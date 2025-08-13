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
	// AST_STRUCT,
	AST_BLOCK_DECL, // enum, bitstruct
	AST_BLOCK, // enum, bitstruct
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
		struct struct_node {
			String   name;
			AstList  attr;
			AstNode* paren;
		}
		struct block {
			StringList decls;
			AstNode*   block;
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

		// case AST_STRUCT:
		// 	n += f.printf("### %s", self.struct_node.name)!;
		// 	n += f.printf("\n\n")!;
		// 	if (self.comment.len) n += f.printf("%s\n\n", self.comment)!;
		// 	n += f.printf("```\n")!;
		// 	n += f.printf("struct %s", self.struct_node.name)!;
		// 	foreach (attr : self.struct_node.attr) n += f.printf(" %s", attr)!;
		// 	if (self.struct_node.paren) n += f.printf(" %s", self.struct_node.paren)!;
		// 	n += f.printf("\n")!;
		// 	n += f.printf("```\n")!;

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
			case MACRO:
				// TODO self.parse_call()!;
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

// struct Name [attr(..) ..] [(..)] {..}
// fn AstNode*? struct_node(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_STRUCT;
//
// 	node.struct_node.attr.init(allocator);
// 	node.assign_comment(allocator, parser);
//
// 	if (!parser.expect(TokenType.STRUCT)!) return INVALID_AST?;
//
// 	if (parser.peek().type != TokenType.IDENT) return INVALID_AST?;
// 	node.struct_node.name = parser.advance()!.lexeme().copy(allocator);
//
// 	while (parser.peek().type == TokenType.ATTRIBUTE)
// 	{
// 		node.struct_node.attr.push(attr(allocator, parser)!);
// 	}
//
// 	if (parser.peek().type == TokenType.PAREN)
// 	{
// 		node.struct_node.paren = paren(allocator, parser)!;
// 	}
//
// 	return node;
// }

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

/*
Parser needs the following:

bool Parser.expect(TokenType)
Expression() -- is terminated by semicolon
	module IDENT [SCOPE IDENT] [ATTRIBUTE ..] SEMICOLON
	const IDENT ASSIGN [fn, xxx]

Module() -- handle module  until semicolon;
Const() -- handle const until semicolon;
Struct() -- handle block
	struct IDENT [LPAREN IDENT RPARENT] [ATTRIBUTE [ [LPAREN] IDENT [RPAREN] ] ]
	LCURLY
		IDENT* SEMICOLON [LNCOMM]
	RCURLY

*/

