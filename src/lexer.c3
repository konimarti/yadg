module yadg::lexer;

import std::io;
import std::collections::list;
import std::ascii;

faultdef INVALID_CHAR;

enum TokenType
{
	TILDE,     // ~
	XOR,       // ^
	QUESTION,  // ?
	EMPTYOPT,  // ??
	EXCLAM,    // !
	UNWRAP,    // !!
	PIPE,      // |
	OR,        // ||
	AMP,       // &
	AND,       // &&
	PLUS,      // +
	MINUS,     // -
	STAR,      // *
	DIV,       // /
	MODULUS,   // %
	ATTRIBUTE, // @
	SEMICOLON, // ;
	COLON,	   // :
	SCOPE,	   // ::
	COMMA,	   // ,
	DOT,	   // .
	BRACE,     // { }
	PAREN,     // (
	BRACK,	   // [ ]
	ASSIGN,	   // =
	EQUAL,	   // ==
	ARROW,     // =>
	LESS,      // <
	LESSEQ,    // <=
	GREATER,   // >
	GREATEREQ, // >=
	RSHIFT,    // >>
	LSHIFT,    // <<
	CONTRACT,    // <* *>
	LNCOMM,    // Line comment //
	BLCOMM,    // Block comment /* */
	IDENT,	   // Identifiers (`module`, `fn`, `macro`, etc. )
	STRING,    // "..", '..', `..`
	FUNC,
	MACRO,
	MODULE,
	CONST,
	ALIAS,
	ENUM,
	STRUCT,
	FAULTDEF,
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
fn bool is_ident(char c) @inline => ascii::is_alnum(c) || c == '_' || c == '$' || c == '#';

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

	self.scan_whitespace()!;

	c = self.peek()!;

	switch (c)
	{
		case '@': self.advance()!; return { .type = ATTRIBUTE };
		case ';': self.advance()!; return { .type = SEMICOLON };
		case ',': self.advance()!; return { .type = COMMA };
		case '.': self.advance()!; return { .type = DOT };
		case '+': self.advance()!; return { .type = PLUS };
		case '-': self.advance()!; return { .type = MINUS };
		case '*': self.advance()!; return { .type = STAR };
		case '%': self.advance()!; return { .type = MODULUS };
		case '~': self.advance()!; return { .type = TILDE };
		case '^': self.advance()!; return { .type = XOR };
		case ':':
			self.advance()!; // Consuem ':'
			if (self.peek()! == ':')
			{
				self.advance()!; // Consume ':'
				return { .type = SCOPE };
			}
			else
			{
				return { .type = COMMA };
			};
		case '!':
			self.advance()!; // Consuem '!'
			if (self.peek()! == '!')
			{
				self.advance()!; // Consume '!'
				return { .type = UNWRAP };
			}
			else
			{
				return { .type = EXCLAM };
			};
		case '?':
			self.advance()!; // Consuem '?'
			if (self.peek()! == '?')
			{
				self.advance()!; // Consume '?'
				return { .type = EMPTYOPT };
			}
			else
			{
				return { .type = QUESTION };
			};
		case '|':
			self.advance()!; // Consume '|'
			if (self.peek()! == '|')
			{
				self.advance()!; // Consume '|'
				return { .type = OR };
			}
			else
			{
				return { .type = PIPE };
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
			TokenType type;
			switch (self.peek()!)
			{
				case '>': self.advance()!; type = ARROW;
				case '=': self.advance()!; type = EQUAL;
				default : type = ASSIGN;
			}
			return { .type = type };
		case '>':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '>': self.advance()!; type = RSHIFT;
				case '=': self.advance()!; type = GREATEREQ;
				default : type = GREATER;
			}
			return { .type = type };
		case '{': return self.lex_brace()!;
		case '(': return self.lex_paren()!;
		case '[': return self.lex_brack()!;
		case '/': return self.lex_comment()!;
		case '<': return self.lex_contract()!;
		case '"':
		case '\'':
		case '`':
			return self.lex_string()!;
		default:
			if (is_ident(c)) return self.lex_ident()!;
			self.report_error(string::tformat("encountered invalid char: '%c'", c));
			return INVALID_CHAR?;
	}
}

fn void? Lexer.scan_whitespace(&self)
{
	char c;
	while ((c = self.peek()!) && is_ws(c)) self.advance()!;
}

fn String? Lexer.scan_surround(&self, int depth, char open, char close) => @pool()
{
	DString buf = dstring::temp();

	char c;
	while LOOP: ((c = self.peek()!) && depth > 0)
	{
		switch (c)
		{
			case '/':
				buf.append_char(c); // Consume '/'
				switch (self.peek()!)
				{
					case '/':
						buf.append_char(self.advance()!); // Consume '/'
						buf.append_chars(self.scan_line_comment()!);
					case '*':
						buf.append_char(self.advance()!); // Consume '*'
						buf.append_chars(self.scan_block_comment()!);
						buf.append_chars("*/");
				}
				continue;

			case '"' :
			case '`':
			case '\'':
				String str = self.scan_string()!;
				buf.append_char(c);
				buf.append_chars(str);
				buf.append_char(c);
				str.free(self.allocator);
				continue;
			case open:
				depth++;
			case close:
				if (--depth == 0) break LOOP;
		}
		buf.append_char(self.advance()!);
	}

	return buf.str_view().copy(self.allocator);
}

fn String? Lexer.scan_string(&self)
{
	DString buf = dstring::temp();

	char c = self.peek()!;
	switch (c)
	{
		case '"' :
			buf.append_char(self.advance()!); // Consume '"'
			while ((c = self.peek()!) && c != '"')
			{
				if (c == '\\') buf.append_char(self.advance()!); // Consume '/'
				buf.append_char(self.advance()!);
			}
			buf.append_char(self.advance()!); // Consume '"'
		case '`' :
		case '\'':
			char quote = c;
			buf.append_char(self.advance()!); // Consume '`' or '\''
			while((c = self.peek()!) && c != quote)
			{
				buf.append_char(self.advance()!);
			}
			buf.append_char(self.advance()!); // Consume '`' or '\''
	}

	return buf.str_view().copy(self.allocator);
}

fn Token? Lexer.lex_string(&self)
{
	return { .type = STRING, .text = self.scan_string()!};
}

fn Token? Lexer.lex_brace(&self)
{
	self.advance()!; // Consume '{'
	String text = self.scan_surround(1, '{', '}')!;
	self.advance()!; // Consume '}'
	return { .type = BRACE, .text = text};
}

fn Token? Lexer.lex_paren(&self)
{
	self.advance()!; // Consume '('
	String text = self.scan_surround(1, '(', ')')!;
	self.advance()!; // Consume ')'
	return { .type = PAREN, .text = text};
}

fn Token? Lexer.lex_brack(&self)
{
	self.advance()!; // Consume '['
	String text = self.scan_surround(1, '[', ']')!;
	self.advance()!; // Consume ']'
	return { .type = BRACK, .text = text};
}

fn Token? Lexer.lex_comment(&self)
{
	self.advance()!; // consume '/'

	switch (self.peek()!)
	{
		case '/': self.advance()!; return { .type = LNCOMM, .text = self.scan_line_comment()!};
		case '*': self.advance()!; return { .type = BLCOMM, .text = self.scan_block_comment()!};
		default: return { .type = DIV };
	}
}

fn String? Lexer.scan_line_comment(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (c != '\n' && c != '\r')) text.append_char(self.advance()!);
	return text.str_view().copy(self.allocator);
}

fn String? Lexer.scan_block_comment(&self) => @pool()
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
	return text.str_view().copy(self.allocator);
}

fn Token? Lexer.lex_contract(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '<';

	if (self.peek()! == '<')
	{
		self.advance()!;
		return { .type = LSHIFT };
	}
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
	return { .type = CONTRACT, .text = text.str_view().copy(self.allocator) };
}

fn Token? Lexer.lex_ident(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && is_ident(c)) text.append_char(self.advance()!);

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		case "fn":       return { .type = FUNC, .text = str };
		case "macro":    return { .type = MACRO, .text = str };
		case "module":   return { .type = MODULE, .text = str };
		case "const":    return { .type = CONST, .text = str };
		case "alias":    return { .type = ALIAS, .text = str };
		case "enum":     return { .type = ENUM, .text = str };
		case "struct":   return { .type = STRUCT, .text = str };
		case "faultdef": return { .type = FAULTDEF, .text = str };
		default:         return { .type = IDENT, .text = str };
	}
}









