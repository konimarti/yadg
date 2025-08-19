module yadg::lexer;

import std::io;
import std::collections::list;
import std::ascii;

faultdef INVALID_CHAR;

enum TokenType : ushort
{
	EMPTY,

	// Operators
	TILDE,
	QUESTION,
	EMPTYOPT,
	XOR,
	BANG,
	BANGBANG,
	AND,
	ANDAND,
	OR,
	OROR,
	PLUS,
	MINUS,
	STAR,
	DIV,
	MODULUS,
	RSHIFT,
	LSHIFT,
	ASSIGN,

	// Punctuation
	SEMICOLON,
	COLON,
	SCOPE,
	COMMA,
	DOT,

	// Structure
	// LBRACE,
	// LPAREN,
	// LBRACK,
	// RBRACE,
	// RPAREN,
	// RBRACK,
	BRACE, // {}
	PAREN, // ()
	BRACK, // []
	ARROW,

	// Comparison
	EQUAL,
	LESS,
	LESSEQ,
	GREATER,
	GREATEREQ,

	// Comments and Contracts
	CONTRACT,  // <* *>
	LCOMMENT,  // Line comment //
	BCOMMENT,  // Block comment /* */

	// Identifiers and Strings
	IDENT,
	STRING,
	NUMBER,
	AT_IDENT,
	AT_TYPE_IDENT,
	CONST_IDENT,
	TYPE_IDENT,

	// Keywords
	EXTERN,
	INLINE,
	STRUCT,
	UNION,
	ENUM,

	ALIAS,
	BITSTRUCT,
	CONST,
	FAULTDEF,
	FUNC,
	IMPORT,
	MACRO,
	MODULE,
	TYPEDEF,

	KEYWORD,

	// Base Types (base_type_no_generic)
	VOID,
	BOOL,
	CHAR,
	ICHAR,
	SHORT,
	USHORT,
	INT,
	UINT,
	LONG,
	ULONG,
	INT128,
	UINT128,
	FLOAT,
	DOUBLE,
	FLOAT16,
	BFLOAT16,
	FLOAT128,
	IPTR,
	UPTR,
	ISZ,
	USZ,
	FAULT,
	ANY,
	TYPEID,
	CT_CONST_IDENT, // ${CONST}
	CT_TYPE_IDENT,  // ${TYPE}
	CT_IDENT,       // ${IDENT}
	CT_TYPEOF,      // $typeof
	CT_TYPEFROM,    // $typefrom (..)
	CT_VATYPE,      // $vatype [..]
	CT_EVALTYPE,    // $evaltype (..)

	EOF,
}

struct Token (Printable)
{
	TokenType  type;
	String     text;
	LexerRange range;
	Allocator  allocator;
}

fn String Token.lexeme(&self)
{
	return self.text.trim("\t\r\n");
}

fn usz? Token.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	// n += f.printf("%s ", self.range)!;
	// if (n < 9) n += f.printf("%*c", 9 - n, ' ')!;
	n += f.printf("<%s>", self.type)!;
	// if (n < 20) n += f.printf("%*c", 20 - n, ' ')!;
	if (self.text.len)
	{
		@pool() {
			n += f.printf(" %s", self.lexeme().tescape(true))!;
		};
	}

	return n;
}


fn void Token.free(&self)
{
	if (!self.allocator) return;
	if (self.text.len) self.text.free(self.allocator);
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
fn bool is_digit(char c) @inline => ascii::is_digit(c);
fn bool is_ident(char c) @inline => ascii::is_alnum(c) || c == '_' || c == '#';

enum IdentType
{
	STR_INVALID,
	STR_CONST,
	STR_TYPE,
	STR_IDENT
}

fn IdentType classify(String s)
{
	usz caps, nocaps, n;
	n = s.len;
	foreach (c : s)
	{
		switch
		{
			case c >= 'a' && c <= 'z': nocaps++;
			case c >= 'A' && c <= 'Z': caps++;
			case c == '_' || c == '$' || c == '#': n--;
		}
	}
	if (n && caps      && nocaps     ) return STR_TYPE;
	if (n && caps      && nocaps == 0) return STR_CONST;
	if (n && caps == 0 && nocaps     ) return STR_IDENT;
	return STR_INVALID;
}

fn char? Lexer.advance(&self)
{
	char c;
	if (self.buf.len())
	{
		c = self.buf.pop_first()!;

		self.col++;

		if (is_lf(c))
		{
			self.ln++;
			self.col = 1;
		}

		return c;
	}

	return self.f.read_byte()!;
}

fn char? Lexer.peek(&self)
{
	if (self.buf.len()) return self.buf.first();
	char c = self.advance()!;
	self.buf.push(c);
	return c;
}

fn void Lexer.pushback(&self, char c) => self.buf.push_front(c);

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
		case ';': self.advance()!; return self.emit_token(SEMICOLON);
		case ',': self.advance()!; return self.emit_token(COMMA);
		case '.': self.advance()!; return self.emit_token(DOT);
		case '+': self.advance()!; return self.emit_token(PLUS);
		case '*': self.advance()!; return self.emit_token(STAR);
		case '%': self.advance()!; return self.emit_token(MODULUS);
		case '~': self.advance()!; return self.emit_token(TILDE);
		case '^': self.advance()!; return self.emit_token(XOR);
		case '-':
			self.advance()!; // Consuem '-'
			TokenType type = MINUS;
			if (is_digit(self.peek()!))
			{
				self.pushback(c);
				return self.lex_number()!;
			}
			return self.emit_token(type);
		case ':':
			self.advance()!; // Consuem ':'
			TokenType type = COLON;
			if (self.peek()! == ':')
			{
				self.advance()!; // Consume ':'
				type = SCOPE;
			}
			return self.emit_token(type);
		case '!':
			self.advance()!; // Consuem '!'
			TokenType type = BANG;
			if (self.peek()! == '!')
			{
				self.advance()!; // Consume '!'
				type = BANGBANG;
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
			TokenType type = OR;
			if (self.peek()! == '|')
			{
				self.advance()!; // Consume '|'
				type = OROR;
			}
			return self.emit_token(type);
		case '&':
			self.advance()!; // Consuem '&'
			TokenType type = AND;
			if (self.peek()! == '&')
			{
				self.advance()!; // Consume '&'
				type = ANDAND;
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

		// case '{': self.advance()!; return self.emit_token(LBRACE);
		// case '(': self.advance()!; return self.emit_token(LPAREN);
		// case '[': self.advance()!; return self.emit_token(LBRACK);
		// case '}': self.advance()!; return self.emit_token(RBRACE);
		// case ')': self.advance()!; return self.emit_token(RPAREN);
		// case ']': self.advance()!; return self.emit_token(RBRACK);
		case '{': return self.lex_brace();
		case '(': return self.lex_paren();
		case '[': return self.lex_brack();

		case '@': return self.lex_attribute();
		case '/': return self.lex_comment()!;
		case '<': return self.lex_contract()!;
		case '$': return self.lex_compile_time()!;
		case '"':
		case '\'':
		case '`':
			return self.lex_string()!;
		default:
			if (is_digit(c)) return self.lex_number()!;
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
fn Token? Lexer.lex_brace(&self)  => self.emit_token(BRACE, self.scan_surround(0, "{", "}")!);
fn Token? Lexer.lex_paren(&self)  => self.emit_token(PAREN, self.scan_surround(0, "(", ")")!);
fn Token? Lexer.lex_brack(&self)  => self.emit_token(BRACK, self.scan_surround(0, "[", "]")!);

fn Token? Lexer.lex_comment(&self)
{
	self.advance()!; // consume '/'

	switch (self.peek()!)
	{
		case '/': self.advance()!; return self.emit_token(LCOMMENT, self.scan_line_comment()!);
		case '*': self.advance()!; return self.emit_token(BCOMMENT, self.scan_block_comment()!);
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

fn Token? Lexer.lex_attribute(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (is_ident(c) || c == '@' ))
	{
		text.append_char(self.advance()!);
	}

	String str = text.str_view().copy(self.allocator);

	TokenType type;
	switch (classify(str[1..]))
	{
		case STR_IDENT: type = AT_IDENT;
		case STR_TYPE:  type = AT_TYPE_IDENT;
		default: return NOT_FOUND?;
	}
	return self.emit_token(type, str);
}

fn Token? Lexer.lex_number(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	int i = 0;
	while ((c = self.peek()!) && (is_digit(c) || c == '-' ||
		(i > 0 && (c == '.' || c == 'e' || c == 'E'||
			c == 'b' || c == 'B' || c == 'x' || c == 'X' ||
			c == 'o' || c == 'O' || c == 'p' || c == 'P' ||
			c == '_'))))
	{
		text.append_char(self.advance()!);
		i++;
	}
	String str = text.str_view().copy(self.allocator);
	return self.emit_token(NUMBER, str);
}

fn Token? Lexer.lex_ident(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	// int i = 0;
	while ((c = self.peek()!) && (is_ident(c)))
	{
		// switch (c)
		// {
			// case '[': text.append_chars(self.scan_surround(0, "[", "]")!);
			// case '<': text.append_chars(self.scan_surround(0, "<", ">")!);
			// default:  text.append_char(self.advance()!);
		// }
		// i++;
		text.append_char(self.advance()!);
	}

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		// Explicit Keywords
		case "fn":        return self.emit_token(FUNC, str);
		case "macro":     return self.emit_token(MACRO, str);
		case "module":    return self.emit_token(MODULE, str);
		case "import":    return self.emit_token(IMPORT, str);
		case "const":     return self.emit_token(CONST, str);
		case "alias":     return self.emit_token(ALIAS, str);
		case "typedef":   return self.emit_token(TYPEDEF, str);
		case "enum":      return self.emit_token(ENUM, str);
		case "struct":    return self.emit_token(STRUCT, str);
		case "union":     return self.emit_token(UNION, str);
		case "bitstruct": return self.emit_token(BITSTRUCT, str);
		case "faultdef":  return self.emit_token(FAULTDEF, str);
		// Explicit Keywords
		case "if":        return self.emit_token(KEYWORD, str);
		case "else":      return self.emit_token(KEYWORD, str);
		case "while":     return self.emit_token(KEYWORD, str);
		case "do":        return self.emit_token(KEYWORD, str);
		case "for":       return self.emit_token(KEYWORD, str);
		case "foreach":   return self.emit_token(KEYWORD, str);
		case "foreach_r": return self.emit_token(KEYWORD, str);
		case "tlocal":    return self.emit_token(KEYWORD, str);
		case "inline":    return self.emit_token(INLINE, str);
		case "extern":    return self.emit_token(EXTERN, str);
		// Base Types
		case "void":      return self.emit_token(VOID, str);
		case "bool":      return self.emit_token(BOOL, str);
		case "char":      return self.emit_token(CHAR, str);
		case "ichar":     return self.emit_token(ICHAR, str);
		case "short":     return self.emit_token(SHORT, str);
		case "ushort":    return self.emit_token(USHORT, str);
		case "int":       return self.emit_token(INT, str);
		case "uint":      return self.emit_token(UINT, str);
		case "long":      return self.emit_token(LONG, str);
		case "ulong":     return self.emit_token(ULONG, str);
		case "int128":    return self.emit_token(INT128, str);
		case "uint128":   return self.emit_token(UINT128, str);
		case "iptr":      return self.emit_token(IPTR, str);
		case "uptr":      return self.emit_token(UPTR, str);
		case "isz":       return self.emit_token(ISZ, str);
		case "usz":       return self.emit_token(USZ, str);
		case "float":     return self.emit_token(FLOAT, str);
		case "double":    return self.emit_token(DOUBLE, str);
		case "float16":   return self.emit_token(FLOAT16, str);
		case "bfloat16":  return self.emit_token(BFLOAT16, str);
		case "float128":  return self.emit_token(FLOAT128, str);
		case "fault":     return self.emit_token(FAULT, str);
		case "any":       return self.emit_token(ANY, str);
		case "typeid":    return self.emit_token(TYPEID, str);

		default:
			TokenType type;
			switch(classify(str))
			{
				case STR_CONST: type = CONST_IDENT;
				case STR_TYPE:  type = TYPE_IDENT;
				case STR_IDENT:
				default: type = IDENT;
			}
			return self.emit_token(type, str);
	}
}

fn void test_classify_str() @test
{
	assert(classify("AABB") == STR_CONST);
	assert(classify("Aabb") == STR_TYPE);
	assert(classify("aabb") == STR_IDENT);
}


fn Token? Lexer.lex_compile_time(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	if (self.peek()! != '$')
	{
		self.report_error("expected '$'");
		return INVALID_CHAR?;
	}
	text.append_char(self.advance()!); // Consume '$'
	while ((c = self.peek()!) && (is_ident(c)))
	{
		text.append_char(self.advance()!);
	}

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		// Compile time
		case "$typeof":   return self.emit_token(CT_TYPEOF, str);
		case "$typefrom": return self.emit_token(CT_TYPEFROM, str);
		case "$vatype":   return self.emit_token(CT_VATYPE, str);
		case "$evaltype": return self.emit_token(CT_EVALTYPE, str);

		default:
			TokenType type;
			switch(classify(str))
			{
				case STR_CONST: type = CT_CONST_IDENT;
				case STR_TYPE:  type = CT_TYPE_IDENT;
				case STR_IDENT: type = CT_IDENT;
				default:        type = EMPTY;
			}
			return self.emit_token(type, str);
	}
}



