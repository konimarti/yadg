module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

struct YadgParser
{
	Lexer        lexer;
	Token        next_token;
	Token        last_comment;
	OutStream    output;
	String       path_prefix;
	Allocator    allocator;
}

fn YadgParser* YadgParser.init(&self, Allocator allocator, OutStream output, String prefix = "")
{
	*self = {
		.output      = output,
		.path_prefix = prefix,
		.allocator   = allocator
	};
	return self;
}

fn void YadgParser.free(&self)
{
	if (!self.allocator) return;
	self.last_comment.free();
	*self = {};
}

<*
 AstNode is allocated with the parser's allocator and must be freed by the
 caller of this function.
*>
fn AstNode*? YadgParser.parse(&self, InStream file) => @pool()
{
	// Lexer uses the same token as the parser; the returned AstNode must
	// be freed by the caller.
	self.lexer.init(self.allocator, file);

	// Set next_token
	self.next_token = self.lexer.next()!;

	AstNode *doc = self.translation_unit()!;

	// Release unused resources
	self.last_comment = {};
	self.next_token = {};

	return doc;
}

fn Token? YadgParser.find_comment(&self)
{
	if (self.peek().range.start.ln - self.last_comment.range.end.ln < 2)
	{
		return self.last_comment;
	}
	return NOT_FOUND?;
}

fn void YadgParser.report_error(&self, String err_msg)
{
	io::eprintfn("PARSER ERROR at Ln: %d, Col: %d -- %s [next token: %s]",
		self.lexer.ln, self.lexer.col, err_msg, self.next_token);
}

// Synchroinze discards token until the next semicolon or {..} block
fn void? YadgParser.synchronize(&self)
{
	while LOOP: (true)
	{
		switch (self.peek().type)
		{
			case SEMICOLON:
			case BRACE:
				self.advance()!;
				io::printfn("stop synchro: next tok now: %s", self.peek());
				nextcase EOF;
			case EOF:
				break LOOP;
			default:
				io::printfn("synchronize: discard %s", self.peek());
				self.advance()!;
		}
	}
}

// Return next token that will be consumed next.
fn Token YadgParser.peek(&self) => self.next_token;

// Consume current token and return it.
fn Token? YadgParser.advance(&self)
{
	Token consumed = self.next_token;
	io::printfn("Token consumed: %s", consumed);
	self.next_token = self.lexer.next()!;
	return consumed;
}

// If next token is tok, then advance and return true; otherwise, return false.
fn bool? YadgParser.expect(&self, TokenType type)
{
	if (self.peek().type == type)
	{
		self.advance()!;
		return true;
	}
	return false;
}


