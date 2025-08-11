module yadg::lexer;

import std::io;
import std::collections::list;
import std::ascii;

faultdef INVALID_CHAR;

enum TokenType : ushort (String symbol)
{
	// Operators
	TILDE     = "~",
	QUESTION  = "?",
	EMPTYOPT  = "??",
	XOR       = "^",
	EXCLAM    = "!",
	UNWRAP    = "!!",
	PIPE      = "|",
	AMP       = "&",
	AND       = "&&",
	OR        = "||",
	PLUS      = "+",
	MINUS     = "-",
	STAR      = "*",
	DIV       = "/",
	MODULUS   = "%",
	RSHIFT    = ">>",
	LSHIFT    = "<<",
	ASSIGN	  = "=",

	// Punctuation
	SEMICOLON = ";",
	COLON	  = ":",
	SCOPE	  = "::",
	COMMA	  = ",",
	DOT	  = ".",

	// Structure
	LBRACE    = "{",
	LPAREN    = "(",
	LBRACK	  = "[",
	RBRACE    = "}",
	RPAREN    = ")",
	RBRACK	  = "]",
	ARROW     = "=>",

	// Comparison
	EQUAL	  = "==",
	LESS      = "<",
	LESSEQ    = "<=",
	GREATER   = ">",
	GREATEREQ = ">=",

	// Comments and Contracts
	CONTRACT  = "",  // <* *>
	LNCOMM    = "",    // Line comment //
	BLCOMM    = "",    // Block comment /* */

	// Identifiers and Strings
	IDENT     = "",	   // Identifiers (`module`, `fn`, `macro`, etc. )
	STRING    = "",    // "..", '..', `..`

	// Keywords
	ATTRIBUTE = "", // @
	FUNC      = "", // fn
	MACRO     = "", // macro
	MODULE    = "", // module
	IMPORT    = "", // import
	CONST     = "", // const
	ALIAS     = "", // alias
	TYPEDEF   = "", // typedef
	ENUM      = "", // enum
	STRUCT    = "", // struct
	BITSTRUCT = "", // bitstruct
	FAULTDEF  = "", // faultdef
	IF        = "", // if
	ELSE      = "", // else
	WHILE     = "", // while
	FOR       = "", // for
	FOREACH   = "", // foreach
	FOREACHR  = "", // foreachr

	EOF       = "EOF",
}

struct Token (Printable)
{
	TokenType  type;
	String     text;
	LexerRange range;
	Allocator  allocator;
}

fn usz? Token.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.printf("%s ", self.range)!;
	if (n < 9) n += f.printf("%*c", 9 - n, ' ')!;
	n += f.printf("[%s]", self.type)!;
	if (n < 20) n += f.printf("%*c", 20 - n, ' ')!;
	if (self.text.len)
	{
		@pool() {
			n += f.printf(" %s", self.text.trim().tescape(true))!;
		};
	}

	return n;
}


fn void Token.free(&self)
{
	if (!self.allocator) return;
	self.text.free(self.allocator);
	*self = {};
}

struct LexerRange (Printable)
{
	LexerPosition start;
	LexerPosition end;
}

fn usz? LexerRange.to_format(&self, Formatter *f) @dynamic
{
	if (self.start.ln == self.end.ln)
	{
		return f.printf("L%d", self.start.ln)!;
	}
	else
	{
		return f.printf("L%d-%d", self.start.ln, self.end.ln)!;
	}
}

struct LexerPosition
{
	usz ln, col;
}
fn LexerRange LexerPosition.sub(&self, LexerPosition start) @operator(-) => { start, *self };

alias CharList = List { char };

struct Lexer
{
	Allocator allocator;
	InStream f;
	usz ln, col;
	bool eof;

	LexerPosition token_start;

	CharList buf;
}

fn LexerPosition Lexer.pos(&self) => { self.ln, self.col };

fn Lexer* Lexer.init(&self, Allocator allocator, InStream input)
{
	*self = { .allocator = allocator, .f = input,
		.ln = 1, .col = 1, .eof = false };
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
	if (self.buf.len()) return self.buf.pop_first();

	char c = self.f.read_byte()!;

	self.col++;

	if (is_lf(c))
	{
		self.ln++;
		self.col = 1;
	}

	return c;
}

fn char? Lexer.peek(&self)
{
	if (self.buf.len()) return self.buf.first();
	char c = self.advance()!;
	self.buf.push(c);
	return c;
}

<*
 Emit token from lexer.
*>
fn Token Lexer.emit_token(&self, TokenType type, String text = "")
{
	Token tok = {
		.type  = type,
		.text  = text,
		.range = self.pos() - self.token_start,
		.allocator = self.allocator
	};
	return tok;
}

<*
 Lex the next token.
*>
fn Token? Lexer.next(&self)
{
	Token? tok = self._next();
	if (catch err = tok)
	{
		if (err == io::EOF)
		{
			self.eof = true;
			return self.emit_token(EOF);
		}
		return err?;
	}
	return tok;
}

fn Token? Lexer._next(&self) @private => @pool()
{
	if (self.eof) return self.emit_token(EOF);

	char c;

	self.scan_whitespace()!;

	self.token_start = self.pos();

	c = self.peek()!;

	switch (c)
	{
		case '@': self.advance()!; return self.emit_token(ATTRIBUTE);
		case ';': self.advance()!; return self.emit_token(SEMICOLON);
		case ',': self.advance()!; return self.emit_token(COMMA);
		case '.': self.advance()!; return self.emit_token(DOT);
		case '+': self.advance()!; return self.emit_token(PLUS);
		case '-': self.advance()!; return self.emit_token(MINUS);
		case '*': self.advance()!; return self.emit_token(STAR);
		case '%': self.advance()!; return self.emit_token(MODULUS);
		case '~': self.advance()!; return self.emit_token(TILDE);
		case '^': self.advance()!; return self.emit_token(XOR);
		case ':':
			self.advance()!; // Consuem ':'
			TokenType type = COMMA;
			if (self.peek()! == ':')
			{
				self.advance()!; // Consume ':'
				type = SCOPE;
			}
			return self.emit_token(type);
		case '!':
			self.advance()!; // Consuem '!'
			TokenType type = EXCLAM;
			if (self.peek()! == '!')
			{
				self.advance()!; // Consume '!'
				type = UNWRAP;
			}
			return self.emit_token(type);
		case '?':
			self.advance()!; // Consuem '?'
			TokenType type = QUESTION;
			if (self.peek()! == '?')
			{
				self.advance()!; // Consume '?'
				type = EMPTYOPT;
			}
			return self.emit_token(type);
		case '|':
			self.advance()!; // Consume '|'
			TokenType type = PIPE;
			if (self.peek()! == '|')
			{
				self.advance()!; // Consume '|'
				type = OR;
			}
			return self.emit_token(type);
		case '&':
			self.advance()!; // Consuem '&'
			TokenType type = AMP;
			if (self.peek()! == '&')
			{
				self.advance()!; // Consume '&'
				type = AND;
			}
			return self.emit_token(type);
		case '=':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '>': self.advance()!; type = ARROW;
				case '=': self.advance()!; type = EQUAL;
				default : type = ASSIGN;
			}
			return self.emit_token(type);
		case '>':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '>': self.advance()!; type = RSHIFT;
				case '=': self.advance()!; type = GREATEREQ;
				default : type = GREATER;
			}
			return self.emit_token(type);
		case '{': self.advance()!; return self.emit_token(LBRACE);
		case '(': self.advance()!; return self.emit_token(LPAREN);
		case '[': self.advance()!; return self.emit_token(LBRACK);
		case '}': self.advance()!; return self.emit_token(RBRACE);
		case ')': self.advance()!; return self.emit_token(RPAREN);
		case ']': self.advance()!; return self.emit_token(RBRACK);
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

<*
 @require open.len > 0
 @require close.len > 0
*>
fn String? Lexer.scan_surround(&self, int depth, String open, String close) => @pool()
{
	DString buf = dstring::temp();

	usz i;
	char c;
	while LOOP: ((c = self.peek()!))
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
				buf.append_chars(str);
				str.free(self.allocator);
				continue;
			case open[0]:
				for (i = 0; i < open.len && self.peek()! == open[i]; i++)
				{
					buf.append_char(self.advance()!);
				}
				if (i == open.len)
				{
					depth++;
				}
				continue;
			case close[0]:
				for (i = 0; i < close.len && self.peek()! == close[i]; i++)
				{
					buf.append_char(self.advance()!);
				}
				if (i == close.len)
				{
					if (--depth == 0) break LOOP;
				}
				continue;
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

fn Token? Lexer.lex_string(&self) => self.emit_token(STRING, self.scan_string()!);
// fn Token? Lexer.lex_brace(&self)  => self.emit_token(BRACE, self.scan_surround(0, "{", "}")!);
// fn Token? Lexer.lex_paren(&self)  => self.emit_token(PAREN, self.scan_surround(0, "(", ")")!);
// fn Token? Lexer.lex_brack(&self)  => self.emit_token(BRACK, self.scan_surround(0, "[", "]")!);

fn Token? Lexer.lex_comment(&self)
{
	self.advance()!; // consume '/'

	switch (self.peek()!)
	{
		case '/': self.advance()!; return self.emit_token(LNCOMM, self.scan_line_comment()!);
		case '*': self.advance()!; return self.emit_token(BLCOMM, self.scan_block_comment()!);
		default: return self.emit_token(DIV);
	}
}

fn String? Lexer.scan_line_comment(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (c != '\n' && c != '\r')) text.append_char(self.advance()!);
	return text.str_view().copy(self.allocator);
}

fn String? Lexer.scan_block_comment(&self) => self.scan_surround(1, "/*", "*/")!;

fn Token? Lexer.lex_contract(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '<';

	if (self.peek()! == '<')
	{
		self.advance()!;
		return self.emit_token(LSHIFT);
	}
	if (self.peek()! == '=')
	{
		self.advance()!;
		return self.emit_token(LESSEQ);
	}
	if (self.peek()! != '*')
	{
		return self.emit_token(LESS);
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
	return self.emit_token(CONTRACT, text.str_view().copy(self.allocator));
}

fn Token? Lexer.lex_ident(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && is_ident(c)) text.append_char(self.advance()!);

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		// Keywords
		case "fn":        return self.emit_token(FUNC, str);
		case "macro":     return self.emit_token(MACRO, str);
		case "module":    return self.emit_token(MODULE, str);
		case "import":    return self.emit_token(IMPORT, str);
		case "const":     return self.emit_token(CONST, str);
		case "alias":     return self.emit_token(ALIAS, str);
		case "typedef":   return self.emit_token(TYPEDEF, str);
		case "enum":      return self.emit_token(ENUM, str);
		case "struct":    return self.emit_token(STRUCT, str);
		case "bitstruct": return self.emit_token(BITSTRUCT, str);
		case "faultdef":  return self.emit_token(FAULTDEF, str);
		case "if":        return self.emit_token(IF, str);
		case "else":      return self.emit_token(ELSE, str);
		case "while":     return self.emit_token(WHILE, str);
		case "for":       return self.emit_token(FOR, str);
		case "foreach":   return self.emit_token(FOREACH, str);
		case "foreach_r": return self.emit_token(FOREACHR, str);
		default:          return self.emit_token(IDENT, str);
	}
}









