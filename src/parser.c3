module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

struct YadgParser
{
	Lexer        lexer;
	TokenList    consumed; // keep track of consumed tokens
	TokenList    tokens;
	Token        last_comment;
	Allocator    allocator;
}

fn YadgParser* YadgParser.init(&self, Allocator allocator)
{
	*self = {
		.allocator   = allocator
	};
	self.consumed.init(self.allocator);
	self.tokens.init(self.allocator);
	return self;
}

fn void YadgParser.free(&self)
{
	if (!self.allocator) return;
	self.last_comment.free();
	foreach (tok : self.consumed) tok.free();
	self.consumed.free();
	foreach (tok : self.tokens) tok.free();
	self.tokens.free();
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

	AstNode *doc = self.translation_unit()!;

	// Release unused resources
	self.last_comment.free();
	self.last_comment = {};
	self.lexer.free();

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
		self.lexer.ln, self.lexer.col, err_msg, self.tokens.first() ?? (Token){});
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
fn Token YadgParser.peek(&self)
{
	if (self.tokens.len() == 0)
	{
		if (try tok = self.lexer.next())
		{
			self.tokens.push(tok);
		}
		else
		{
			return (Token){};
		}
	}
	return self.tokens.first()!!;
}

// Consume current token and return it.
fn Token? YadgParser.advance(&self)
{
	Token tok;
	if (self.tokens.len())
	{
		tok = self.tokens.pop_first()!;
	}
	else
	{
		tok = self.lexer.next()!;
	}
	self.consumed.push(tok);
	return tok;
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

fn void YadgParser.push_back(&self, Token tok) => self.tokens.push_front(tok);

