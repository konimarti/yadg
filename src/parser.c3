module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

struct Comment
{
	usz       end_ln; // Comment ends at lineno
	String    comment;
	Allocator allocator;
}

fn void Comment.free(&self)
{
	if (!self.allocator) return;
	self.comment.free(self.allocator);
}

struct YadgParser
{
	Lexer        lexer;
	Token        next_token;
	Comment      last_comment;
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

fn AstNode*? YadgParser.parse(&self, InStream file) => @pool()
{
	// Lexer is with temporary allocator; no need to free tokens
	self.lexer = *(Lexer){}.init(tmem, file);
	defer self.lexer.free();
	self.next_token = self.lexer.next()!;

	AstNode *doc = document(self.allocator, self)!;

	// Release unused resources
	self.last_comment.free();
	self.last_comment = {};
	self.next_token = {};
	self.lexer = {};

	return doc;
}

fn String? YadgParser.find_comment(&self)
{
	if (self.peek().range.start.ln - self.last_comment.end_ln < 2)
	{
		return self.last_comment.comment;
	}
	return NOT_FOUND?;
}

// Return next token that will be consumed next.
fn Token YadgParser.peek(&self) => self.next_token;

// Consume current token and return it.
fn Token? YadgParser.advance(&self)
{
	Token consumed = self.next_token;
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


