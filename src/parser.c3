module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

struct YadgParser
{
	Lexer        lexer;
	TokenList    consumed; // keep track of consumed tokens
	TokenList    tokens;
	Token*       last_comment;
	AstList      nodes;
	Allocator    allocator;
}

fn YadgParser* YadgParser.init(&self, Allocator allocator, InStream file)
{
	*self = {
		.allocator   = allocator
	};
	self.lexer.init(self.allocator, file);
	self.consumed.init(self.allocator);
	self.tokens.init(self.allocator);
	self.nodes.init(self.allocator);
	return self;
}

fn void YadgParser.free(&self)
{
	if (!self.allocator) return;

	if (self.last_comment) self.last_comment.free();

	foreach (tok : self.consumed) if (tok) tok.free();
	self.consumed.free();

	foreach (tok : self.tokens) if (tok) tok.free();
	self.tokens.free();

	self.lexer.free();

	foreach (node : self.nodes) if (node) allocator::free(self.allocator, node);
	self.nodes.free();

	*self = {};
}

<*
 AstNode is allocated with the parser's allocator and must be freed by the
 caller of this function.
*>
fn AstNode*? YadgParser.parse(&self) => self.translation_unit()!;

fn void YadgParser.report_error(&self, String err_msg)
{
	io::eprintfn("PARSER ERROR at Ln: %d, Col: %d -- %s [next token: %s]",
		self.lexer.ln, self.lexer.col, err_msg, self.tokens.first()!!);
}

// Synchronize discards token until the next semicolon or {..} block
fn void? YadgParser.synchronize(&self)
{
	while LOOP: (true)
	{
		switch (self.peek())
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
fn TokenType YadgParser.peek(&self)
{
	if (self.tokens.len() == 0)
	{
		if (try tok = self.lexer.next())
		{
			self.tokens.push(tok);
		}
	}
	if (try tok = self.tokens.first() && tok) return tok.type;
	return EMPTY;
}

// Consume current token and return it.
fn Token*? YadgParser.advance(&self)
{
	Token* tok;
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
	if (self.peek() == type)
	{
		self.advance()!;
		return true;
	}
	return false;
}

fn void YadgParser.push_back(&self, Token* tok) => self.tokens.push_front(tok);

