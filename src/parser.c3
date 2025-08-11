module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

struct Comment
{
	usz end_ln; // Comment ends at lineno
	String comment;
}

alias CommentStack = List { Comment };

struct YadgParser
{
	Lexer        lexer;
	Token        next_token;
	OutStream    output;
	String       path_prefix;
	CommentStack stack;
	Allocator    allocator;
}

fn YadgParser* YadgParser.init(&self, Allocator allocator, OutStream output, String prefix = "")
{
	*self = {
		.output      = output,
		.path_prefix = prefix,
		.stack       = *(CommentStack){}.init(allocator),
		.allocator   = allocator
	};
	return self;
}

fn void YadgParser.free(&self)
{
	if (!self.allocator) return;
	self.stack.free();
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
	self.stack.clear();
	self.next_token = {};
	self.lexer = {};

	return doc;
}

fn String? YadgParser.find_adjacent_comment(&self, Allocator allocator, Token current_token)
{
	String comment;
	if (try tok = self.stack.last() && current_token.range.start.ln - tok.end_ln < 2)
	{
		comment = tok.comment.copy(allocator);
		(void)self.stack.pop();
		return comment;
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


