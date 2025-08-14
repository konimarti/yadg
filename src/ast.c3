module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST;

enum AstType
{
	AST_DOCUMENT,
	AST_MODULE,
	AST_BLOCK,
	AST_CALL,
	AST_GLOBAL,
	AST_ATTRIBUTE,
	AST_BRACE,
	AST_PAREN
}

alias AstList = List{ AstNode* };
alias StringList = List{ String };

struct AstNode (Printable)
{
	AstType type;
	union
	{
		struct document
		{
			AstList modules;
		}
		struct mod
		{
			StringList path;
			AstList    attr;
			String     name; // last part of path
			/*
			TODO: Submodules: i.e. archive::zip, archive::reader

				 archive
				    |
				+---+---+
				|       |
			      Reader   Zip

			*/
			AstList    submodules;

			// Children
			AstList    globals;
			AstList    calls;
			AstList    blocks;
		}
		struct block
		{
			String     name;
			StringList decls;
			AstNode*   brace;
			AstList    methods;
		}
		struct call
		{
		        String     name;
			String     receiver; // Receiver.method
			StringList decls;
		}
		struct glob
		{
			String     name;
			StringList decls;
			AstList    methods;  // typedef can have methods
		}
		struct attr
		{
			String     name;
			AstNode*   paren;
		}
		String     term;
	}
	String comment;
}

fn AstNode*? document(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_DOCUMENT;
	node.document.modules.init(allocator);

	Token tok;
	while LOOP: (true)
	{
		tok = parser.peek();
		switch(tok.type)
		{
			case CONTRACT:
			case LCOMMENT:
			case BCOMMENT:
				parser.last_comment.free();
				parser.last_comment = { tok.range.end.ln, format_comment(tmem, tok.lexeme()), tmem };
			case MODULE:
				node.document.modules.push(module_node(allocator, parser)!);
				continue;
			case STRUCT:
			case ENUM:
			case BITSTRUCT:
			case FAULTDEF:
				AstNode *current_module = node.document.modules.last()!;
				current_module.mod.blocks.push(block(allocator, parser)!);
				continue;
			case ALIAS:
			case TYPEDEF:
			case CONST:
				AstNode *current_module = node.document.modules.last()!;
				current_module.mod.globals.push(global(allocator, parser)!);
				continue;
			case FUNC:
			case MACRO:
				AstNode *current_module = node.document.modules.last()!;
				current_module.mod.calls.push(fncall(allocator, parser)!);
				continue;
			case EOF:
				break LOOP;
			default:
				// Ingore and continue
		}
		parser.advance()!;
	}

	// TODO: sort modules, calls, globs, etc.

	// Match receivers with receiver methods per module
	foreach (mod : node.document.modules)
	{
		match_receivers(mod)!;
	}

	return node;
}


fn usz? AstNode.to_format(&self, Formatter* f) @dynamic
{
	usz n;

	switch (self.type)
	{
		case AST_DOCUMENT:
			foreach (child : self.document.modules) n += f.printf("%s\n", child)!;

		case AST_MODULE:
			n += f.printf("## ")!;
			foreach (i, path : self.mod.path)
			{
				n += f.printf("%s%s", (i > 0 ? "::" : ""), path)!;
			}
			foreach (attr : self.mod.attr)
			{
				n += f.printf(" %s", attr)!;
			}
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n", self.comment)!;

			foreach (global : self.mod.globals) io::printf("%s\n", global);
			foreach (call : self.mod.calls) io::printf("%s\n", call);
			foreach (block : self.mod.blocks) io::printf("%s\n", block);

		case AST_GLOBAL:
			n += f.printf("### %s", self.glob.name)!;
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n\n", self.comment)!;
			n += f.printf("```\n")!;
			foreach (i, decl : self.glob.decls)
			{
				n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
			}
			n += f.printf("\n")!;
			n += f.printf("```\n")!;
			foreach (method : self.glob.methods) io::printfn("\n%s", method);

		case AST_BLOCK:
			n += f.printf("### %s", self.block.name)!;
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n", self.comment)!;
			n += f.printf("```\n")!;
			foreach (i, decl : self.block.decls)
			{
				n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
			}
			n += f.printf("\n")!;
			n += f.printf("%s", self.block.brace)!;
			n += f.printf("\n")!;
			n += f.printf("```\n")!;
			foreach (method : self.block.methods) io::printfn("\n%s", method);

		case AST_CALL:
			if (self.call.receiver.len)
			{
				n += f.printf("### %s.%s", self.call.receiver, self.call.name)!;
			}
			else
			{
				n += f.printf("### %s", self.call.name)!;
			}
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n", self.comment)!;
			n += f.printf("```\n")!;
			foreach (i, decl : self.call.decls)
			{
				n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
			}
			n += f.printf("\n")!;
			n += f.printf("```\n")!;

		case AST_ATTRIBUTE:
			n += f.printf("%s", self.attr.name)!;
			if (self.attr.paren)
			{
				n += f.printf("%s", self.attr.paren)!;
			}

		case AST_PAREN:
			n += f.print(self.term)!;

		case AST_BRACE:
			n += f.print(self.term)!;
	}

	return n;
}

fn void AstNode.assign_comment(&self, Allocator allocator, YadgParser *parser)
{
	self.comment = parser.find_comment().copy(allocator) ?? "";
}

// module ident[::ident] [attr(..) ..] ;
fn AstNode*? module_node(Allocator allocator, YadgParser *parser)
{
	String lexeme;

	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_MODULE;

	node.mod.path.init(allocator);
	node.mod.attr.init(allocator);
	node.mod.submodules.init(allocator);

	node.mod.globals.init(allocator);
	node.mod.calls.init(allocator);
	node.mod.blocks.init(allocator);

	node.assign_comment(allocator, parser);

	if (!parser.expect(TokenType.MODULE)!) return INVALID_AST?;

	while (parser.peek().type == TokenType.IDENT)
	{
		lexeme = parser.advance()!.lexeme().copy(allocator);
		node.mod.path.push(lexeme);
		node.mod.name = lexeme; // Eventually the last element will stick
		if (!parser.expect(TokenType.SCOPE)!) break;
	}

	while (parser.peek().type == TokenType.ATTRIBUTE)
	{
		node.mod.attr.push(attr(allocator, parser)!);
	}

	if (!parser.expect(TokenType.SEMICOLON)!) return INVALID_AST?;

	return node;
}

// [ alias | typedef | const ] terms .. ;
fn AstNode*? global(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_GLOBAL;
	node.glob.decls.init(allocator);
	node.glob.methods.init(allocator);
	node.assign_comment(allocator, parser);

	usz i = 0;
	while (parser.peek().type != TokenType.SEMICOLON)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.glob.decls.push(lexeme);
		if (i == 1) node.glob.name = lexeme;
		i++;
	}

	return node;
}

// [ enum  | bitstruct ] Name : ["const"] ["inline"] $BackingType [attr(..) ..] [(..)] {..}
fn AstNode*? block(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_BLOCK;

	node.block.decls.init(allocator);
	node.block.methods.init(allocator);
	node.assign_comment(allocator, parser);

	usz i = 0;
	while (parser.peek().type != TokenType.BRACE)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.block.decls.push(lexeme);
		if (i == 1) node.block.name = lexeme;
		i++;
	}

	node.block.brace = brace(allocator, parser)!;

	return node;
}

alias TokenList = List { Token };

//  fn $ReturnType [Receiver.] Call "(" .. ")" [Attr..]  ( "{" .. "}" | ";" )
//  macro [$ReturnType] [Receiver.] Call "(" .. ")" [Attr..]  ( "{" .. "}" | ";" )
fn AstNode*? fncall(Allocator allocator, YadgParser *parser)
{
	String lexeme;

	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_CALL;

	node.call.decls.init(allocator);
	node.assign_comment(allocator, parser);

	@pool()
	{
		TokenList tlist;
		tlist.tinit();

		Token tok = parser.peek();
		while (tok.type != TokenType.PAREN)
		{
			if (tok.type == TokenType.EOF) return INVALID_AST?;
			tlist.push(parser.advance()!);
			tok = parser.peek();
		}

		node.call.name = tlist.pop()!.lexeme().copy(allocator);
		if (tlist.last()!.type == TokenType.DOT)
		{
			(void)tlist.pop(); // Pop DOT
			node.call.receiver = tlist.pop()!.lexeme().copy(allocator);
		}

		foreach (decl : tlist)
		{
			node.call.decls.push(decl.lexeme().copy(allocator));
		}

		String tmp = node.call.name;
		if (node.call.receiver.len)
		{
			tmp = string::format(allocator, "%s.%s", node.call.receiver, node.call.name);
		}
		node.call.decls.push(tmp);
	};

	while (parser.peek().type != TokenType.BRACE && parser.peek().type != TokenType.SEMICOLON)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		lexeme = parser.advance()!.lexeme().copy(allocator);
		node.call.decls.push(lexeme);
	}

	return node;
}

fn AstNode*? attr(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_ATTRIBUTE;

	node.attr.name = parser.advance()!.lexeme().copy(allocator);
	if (parser.peek().type == PAREN)
	{
		node.attr.paren = paren(allocator, parser)!;
	}

	return node;
}

fn AstNode*? paren(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_PAREN;

	if (parser.peek().type != TokenType.PAREN)
	{
		return INVALID_AST?;
	}

	node.term = parser.advance()!.lexeme().copy(allocator);

	return node;
}

fn AstNode*? brace(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_BRACE;

	if (parser.peek().type != TokenType.BRACE)
	{
		return INVALID_AST?;
	}

	node.term = format_braces(allocator, parser.advance()!.lexeme());

	return node;
}

fn String format_braces(Allocator allocator, String str) => @pool()
{
	DString builder = dstring::temp("{\n");
	foreach (i, ln : str.trim("{} \n\r\t").tsplit("\n"))
	{
		builder.appendf("    %s\n", ln.trim());
	}
	builder.append_chars("}");

	return builder.copy_str(allocator);
}

fn String format_comment(Allocator allocator, String str) => @pool()
{
	DString builder = dstring::temp("");
	foreach (i, ln : str.trim().tsplit("\n"))
	{
		builder.appendf("> %s\n", ln.trim());
	}

	return builder.copy_str(allocator);
}

fn void? match_receivers(AstNode *mod) => @pool()
{
	String receiver;
	AstList calls;
	calls.tinit();
	// Loop over calls and determine if it is a method
	foreach (call_node : mod.mod.calls)
	{
		receiver = call_node.call.receiver;
		if (!receiver.len)
		{
			// No receiver
			calls.push(call_node);
			continue;
		}

		// Yes. we have a receiver.
		bool found = false;
		foreach (block_node : mod.mod.blocks)
		{
			if (block_node.block.name == receiver)
			{
				block_node.block.methods.push(call_node);
				found = true;
				break;
			}
		}
		if (found) break;
		foreach (global_node : mod.mod.globals)
		{
			if (global_node.glob.name == receiver)
			{
				global_node.glob.methods.push(call_node);
				found = true;
				break;
			}
		}
		if (!found) calls.push(call_node);
	}

	// Restore calls that have no receiver
	mod.mod.calls.clear();
	mod.mod.calls.add_all(&calls);
}
