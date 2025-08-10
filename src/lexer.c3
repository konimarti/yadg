module yadg::lexer;

import std::io;
import std::collections::list;
import std::ascii;

faultdef INVALID_CHAR;

enum TokenType
{
	TERNARY,   // ?
	CHTHROW,   // ??
	NOT,       // !
	RETHROW,   // !!
	OR,        // ||
	AMP,       // &
	AND,       // &&
	PLUS,      // +
	MINUS,     // -
	STAR,      // *
	ATTR,      // @
	SEMI,	   // ;
	COLON,	   // :
	COMMA,	   // ,
	PERIOD,	   // .
	BRACE,     // { }
	PAREN,     // (
	BRACK,	   // [ ]
	EQUAL,	   // =
	ARROW,     // =>
	LESS,      // <
	LESSEQ,    // <=
	CNTRCT,    // <* *>
	LNCOMM,    // Line comment \\
	BLCOMM,    // Block comment /* */
	IDENT,	   // Identifiers (`module`, `fn`, `macro`, etc. )
	FUNC,
	MACRO,
	EOF
}

struct Token
{
	TokenType type;
	String    text;
}

alias CharList = List { char };

struct Lexer
{
	Allocator allocator;
	InStream f;
	usz ln, col;
	usz n;
	bool eof;

	CharList buf;
}

fn Lexer* Lexer.init(&self, Allocator allocator, InStream input)
{
	*self = { .allocator = allocator, .f = input,
		.ln = 1, .col = 1, .n = 0, .eof = false };
	self.buf.init(allocator);
	return self;
}

fn void Lexer.free(&self)
{
	if (!self.allocator) return;
	self.buf.free();
	*self = {};
}


fn void Lexer.report_error(&self, String msg)
{
	io::eprintfn("LEXER ERROR at Ln: %d, Col: %d -- %s", self.ln, self.col, msg);
}

fn bool is_lf(char c) @inline => c == '\n';
fn bool is_ws(char c) @inline => @ok(" \t\r\n".index_of_char(c));

fn char? Lexer.advance(&self)
{
	char? c;

	if (self.buf.len()) return self.buf.pop_first();

	c = self.f.read_byte()!;
	if (catch err = c)
	{
		if (err == io::EOF)
		{
			self.eof = true;
			return 0;
		}
		return err?;
	}

	self.n++;
	self.col++;

	if (is_lf(c))
	{
		self.ln++;
		self.col = 1;
	}

	// io::printfn("advance: '%c'", c);

	return c;
}

fn char? Lexer.peek(&self)
{
	char c;

	if (self.buf.len()) return self.buf.first();

	if (self.eof) return 0;

	c = self.advance()!;
	self.buf.push(c);
	return c;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self) => @pool()
{
	char c;

	self.skip_whitespace()!;

	c = self.peek()!;

	switch (c)
	{
		case '@': self.advance()!; return { .type = ATTR };
		case ';': self.advance()!; return { .type = SEMI };
		case ':': self.advance()!; return { .type = COLON };
		case ',': self.advance()!; return { .type = COMMA };
		case '.': self.advance()!; return { .type = PERIOD };
		case '+': self.advance()!; return { .type = PLUS };
		case '-': self.advance()!; return { .type = MINUS };
		case '*': self.advance()!; return { .type = STAR };
		case '!':
			self.advance()!; // Consuem '!'
			if (self.peek()! == '!')
			{
				self.advance()!; // Consume '!'
				return { .type = RETHROW };
			}
			else
			{
				return { .type = NOT };
			};
		case '?':
			self.advance()!; // Consuem '?'
			if (self.peek()! == '?')
			{
				self.advance()!; // Consume '?'
				return { .type = CHTHROW };
			}
			else
			{
				return { .type = TERNARY };
			};
		case '|':
			self.advance()!; // Consuem '|'
			if (self.peek()! == '|')
			{
				self.advance()!; // Consume '|'
				return { .type = OR };
			}
			else
			{
				self.report_error(string::tformat("error after | with char: '%c'", self.peek()!));
				return INVALID_CHAR?;
			};
		case '&':
			self.advance()!; // Consuem '&'
			if (self.peek()! == '&')
			{
				self.advance()!; // Consume '&'
				return { .type = AND };
			}
			else
			{
				return { .type = AMP };
			};
		case '=':
			self.advance()!;
			TokenType type = EQUAL;
			if (self.peek()! == '>')
			{
				self.advance()!;
				type = ARROW;
			}
			return { .type = type };
		case '{': return self.scan_brace()!;
		case '(': return self.scan_paren()!;
		case '[': return self.scan_brack()!;
		case '/': return self.scan_comment()!;
		case '<': return self.scan_contract()!;
		default:
			if (ascii::is_alnum(c)) return self.scan_ident()!;
			self.report_error(string::tformat("encountered invalid char: '%c'", c));
			return INVALID_CHAR?;
	}
}

fn void? Lexer.skip_whitespace(&self)
{
	char c;
	while ((c = self.peek()!) && is_ws(c)) self.advance()!;
}

fn Token? Lexer.scan_brace(&self) => @pool()
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '{'

	// TODO: handle {} nesting (track the depth) and escaped \} in strings
	while ((c = self.peek()!) && c != '}') text.append_char(self.advance()!);

	self.advance()!; // Consume '}'

	return { .type = BRACE, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_paren(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '('

	// TODO: handle () nesting (track the depth) and escaped \) in strings
	while ((c = self.peek()!) && c != ')') text.append_char(self.advance()!);

	self.advance()!; // Consume ')'

	return { .type = PAREN, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_brack(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '['

	// TODO: handle [] nesting (track the depth) and escaped \] in strings
	while ((c = self.peek()!) && c != ']') text.append_char(self.advance()!);

	self.advance()!; // Consume ']'

	return { .type = BRACK, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_comment(&self)
{
	self.advance()!; // consume '/'

	switch (self.peek()!)
	{
		case '/': self.advance()!; return self.scan_line_comment()!;// Line comment
		case '*': self.advance()!; return self.scan_block_comment()!; // Block comment
		default: return self.next()!; // TODO: Continue lexing?
	}
}

fn Token? Lexer.scan_line_comment(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (c != '\n' && c != '\r')) text.append_char(self.advance()!);
	return { .type = LNCOMM, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_block_comment(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while LOOP: (c = self.peek()!)
	{
		if (c == '*')
		{
			self.advance()!; // Consume '*';
			if (self.peek()! == '/')
			{
				self.advance()!; // Consume '/';
				break LOOP;
			}
			text.append_char('*');
			continue;
		}
		text.append_char(self.advance()!);
	}
	return { .type = BLCOMM, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_contract(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '<';

	if (self.peek()! == '=')
	{
		self.advance()!;
		return { .type = LESSEQ };
	}
	if (self.peek()! != '*')
	{
		return { .type = LESS };
	}

	self.advance()!; // Consume '*';

	while LOOP: (c = self.peek()!)
	{
		if (c == '*')
		{
			self.advance()!; // Consume '*';
			if (self.peek()! == '>')
			{
				self.advance()!; // Consume '>'
				break LOOP;
			}
			text.append_char('*');
			continue;
		}
		text.append_char(self.advance()!);
	}
	return { .type = BLCOMM, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.scan_ident(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (ascii::is_alnum(c) || c == '_')) text.append_char(self.advance()!);

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		case "fn":    return { .type = FUNC, .text = str };
		case "macro": return { .type = MACRO, .text = str };
		default:      return { .type = IDENT, .text = str };
	}
}









