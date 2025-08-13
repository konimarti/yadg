module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST;

enum AstType
{
	AST_DOCUMENT,
	AST_MODULE,
	AST_GLOBAL,
	AST_BLOCK_DECL, // enum, bitstruct
	AST_BLOCK,
	AST_CALL,
	AST_ATTRIBUTE,
	AST_PAREN
}

alias AstList = List{ AstNode* };
alias StringList = List{ String };

struct AstNode (Printable)
{
	AstType type;
	union
	{
		struct document {
			AstList children;
		}
		struct module_node {
			StringList path;
			AstList    attr;
		}
		struct block {
			StringList decls;
			AstNode*   block;
		}
		struct call {
			String     receiver;
		        String     name;
			StringList decls;
		}
		String     term;
		StringList terms;
	}
	String comment;
}

fn usz? AstNode.to_format(&self, Formatter* f) @dynamic
{
	usz n;

	switch (self.type)
	{
		case AST_DOCUMENT:
			n += f.printf("DOCUMENT START\n\n")!;
			foreach (child : self.document.children) n += f.printf("%s\n", child)!;
			n += f.printf("\nDOCUMENT END\n")!;

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

		case AST_GLOBAL:
			if (self.terms.len() < 2) return INVALID_AST?;
			n += f.printf("### %s", self.terms[1])!;
			n += f.printf("\n\n")!;
			if (self.comment.len) n += f.printf("%s\n\n", self.comment)!;
			n += f.printf("```\n")!;
			foreach (i, term : self.terms)
			{
				n += f.printf("%s%s", (i > 0 ? " " : ""), term)!;
			}
			n += f.printf("\n")!;
			n += f.printf("```\n")!;

		case AST_BLOCK_DECL:
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
			n += f.printf("%s", self.block.block)!;
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

		case AST_BLOCK:
			n += f.print(self.term)!;
	}

	return n;
}

fn AstNode*? document(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_DOCUMENT;
	node.document.children.init(allocator);

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
				node.document.children.push(module_node(allocator, parser)!);
				continue;
			case STRUCT:
			case ENUM:
			case BITSTRUCT:
				node.document.children.push(block_decl(allocator, parser)!);
				continue;
			case ALIAS:
			case TYPEDEF:
			case CONST:
				node.document.children.push(global(allocator, parser)!);
				continue;
			case FUNC:
				node.document.children.push(fncall(allocator, parser)!);
				continue;
			case MACRO:
				// TODO
				break;
			case EOF:
				break LOOP;
			default:
				// Ingore and continue
		}
		parser.advance()!;
	}

	return node;
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
	node.terms.init(allocator);
	node.assign_comment(allocator, parser);

	while (parser.peek().type != TokenType.SEMICOLON)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.terms.push(lexeme);
	}

	return node;
}

// [ enum  | bitstruct ] Name : ["const"] ["inline"] $BackingType [attr(..) ..] [(..)] {..}
fn AstNode*? block_decl(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_BLOCK_DECL;

	node.block.decls.init(allocator);
	node.assign_comment(allocator, parser);

	while (parser.peek().type != TokenType.BRACE)
	{
		if (parser.peek().type == EOF) return INVALID_AST?;
		String lexeme = parser.advance()!.lexeme().copy(allocator);
		node.block.decls.push(lexeme);
	}

	node.block.block = block(allocator, parser)!;

	return node;
}

//  fn $ReturnType [Receiver.] Call "(" .. ")" [Attr..]  ( "{" .. "}" | ";" )
fn AstNode*? fncall(Allocator allocator, YadgParser *parser)
{
	String lexeme, receiver, name;

	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_CALL;

	node.call.decls.init(allocator);
	node.assign_comment(allocator, parser);

	bool is_macro = parser.peek().type == TokeType.MACRO;

	if (parser.peek().type == TokenType.FUNC || is_macro)
	{
		lexeme = parser.advance()!.lexeme().copy(allocator);
		node.call.decls.push(lexeme);
	}
	else
	{
		return INVALID_AST?;
	}

	// Return type
	if (parser.peek().type != TokenType.IDENT)
	{
		return INVALID_AST?;
	}
	node.call.decls.push(parser.advance()!.lexeme().copy(allocator));

	// Receiver or call name
	if (parser.peek().type != TokenType.IDENT)
	{
		io::printfn("Btoken got: %s", parser.peek() );
		return INVALID_AST?;
	}
	name = parser.advance()!.lexeme().copy(allocator);

	if (parser.peek().type == TokenType.DOT)
	{
		receiver = name;
		parser.advance()!; // Consume DOT
		if (parser.peek().type != TokenType.IDENT) return INVALID_AST?;
		name = parser.advance()!.lexeme().copy(allocator);
	}

	// Write to decls
	node.call.name = name;
	if (receiver.len)
	{
		node.call.receiver = receiver;
		node.call.decls.push(string::format(allocator, "%s.%s", receiver, name));
	}
	else
	{
		node.call.decls.push(name);
	}


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

fn AstNode*? block(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_BLOCK;

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
