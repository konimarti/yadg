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
		struct module_node
		{
			StringList path;
			AstList    attr;

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
			String     receiver; // blocks and typedefs can be receivers
		        String     name;
			StringList decls;
		}
		struct glob
		{
			StringList decls;
			AstList    methods;  // typedef can have methods
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
				AstNode *current_module = node.document.modules.last()!;
				current_module.module_node.blocks.push(block(allocator, parser)!);
				continue;
			case ALIAS:
			case TYPEDEF:
			case CONST:
				AstNode *current_module = node.document.modules.last()!;
				current_module.module_node.globals.push(global(allocator, parser)!);
				continue;
			case FUNC:
			case MACRO:
				AstNode *current_module = node.document.modules.last()!;
				current_module.module_node.calls.push(fncall(allocator, parser)!);
				continue;
			case EOF:
				break LOOP;
			default:
				// Ingore and continue
		}
		parser.advance()!;
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
			foreach (i, path : self.module_node.path)
			{
				n += f.printf("%s%s", (i > 0 ? "::" : ""), path)!;
			}
			foreach (attr : self.module_node.attr)
			{
				n += f.printf(" %s", attr)!;
			}
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n", self.comment)!;

			foreach (global : self.module_node.globals) io::printf("%s\n", global);
			foreach (call : self.module_node.calls) io::printf("%s\n", call);
			foreach (block : self.module_node.blocks) io::printf("%s\n", block);

		case AST_GLOBAL:
			if (self.glob.decls.len() < 2) return INVALID_AST?;
			n += f.printf("### %s", self.glob.decls[1])!;
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n\n", self.comment)!;
			n += f.printf("```\n")!;
			foreach (i, decl : self.glob.decls)
			{
				n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
			}
			n += f.printf("\n")!;
			n += f.printf("```\n")!;

		case AST_BLOCK:
			if (self.block.decls.len() < 2) return INVALID_AST?;
			n += f.printf("### %s", self.block.decls[1])!;
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
			n += f.print(self.term)!;

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
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_MODULE;

	node.module_node.path.init(allocator);
	node.module_node.attr.init(allocator);
	node.module_node.globals.init(allocator);
	node.module_node.calls.init(allocator);
	node.module_node.blocks.init(allocator);
	node.assign_comment(allocator, parser);

	if (!parser.expect(TokenType.MODULE)!) return INVALID_AST?;

	while (parser.peek().type == TokenType.IDENT)
	{
		node.module_node.path.push(parser.advance()!.lexeme().copy(allocator));
		if (!parser.expect(TokenType.SCOPE)!) break;
	}

	while (parser.peek().type == TokenType.ATTRIBUTE)
	{
		node.module_node.attr.push(attr(allocator, parser)!);
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
	node.assign_comment(allocator, parser);

	while (parser.peek().type != TokenType.SEMICOLON)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.glob.decls.push(lexeme);
	}

	return node;
}

// [ enum  | bitstruct ] Name : ["const"] ["inline"] $BackingType [attr(..) ..] [(..)] {..}
fn AstNode*? block(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_BLOCK;

	node.block.decls.init(allocator);
	node.assign_comment(allocator, parser);

	while (parser.peek().type != TokenType.BRACE)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.block.decls.push(lexeme);
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
	node.term = parser.advance()!.lexeme().copy(allocator);
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
