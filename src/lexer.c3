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
	XOR,
	BANG,
	PLUS,
	MINUS,
	STAR,
	DIV,
	MOD,
	QUESTION,	// ?
	OPTELSE, 	// ??
	ELVIS, 		// ?:
	BANGBANG,	// !!
	BUILTIN, 	// $$

	// Assignment
	ASSIGN,
	SHR_ASSIGN,	//>>=
	SHL_ASSIGN,	//<<=
	ADD_ASSIGN,	//+=
	SUB_ASSIGN,	//-=
	MUL_ASSIGN,	//*=
	DIV_ASSIGN,	///=
	MOD_ASSIGN,	//%=
	AND_ASSIGN,	//&=
	XOR_ASSIGN,	//^=
	OR_ASSIGN,	//|=

	// Comparison
	AND,
	OR,
	LESS,
	GREATER,
	SHR_OP,		//>>
	SHL_OP,		//<<
	INC_OP,		//++
	DEC_OP,		//--
	AND_OP,		//&&
	OR_OP,		//||
	LE_OP,		//<=
	GE_OP,		//>=
	EQ_OP,		//==
	NE_OP,		//!=
	CT_AND_OP,
	CT_OR_OP,
	CT_CONCAT_OP,

	// Punctuation
	SEMICOLON,
	COLON,
	SCOPE,
	COMMA,
	DOT,
	DOTDOT,
	ELLIPSIS,

	// Structure
	// LBRACE,
	// RBRACE,
	// LBRACK,
	// RBRACK,
	LPAREN,
	RPAREN,
	// PAREN, // ()
	BRACE, // {}
	BRACK, // []
	IMPLIES, // =>


	// Comments and Contracts
	CONTRACT,  // <* *>
	LCOMMENT,  // Line comment //
	BCOMMENT,  // Block comment /* */

	// Identifiers and Strings
	STRING,
	NUMBER,
	IDENT,
	TYPE_IDENT,
	CONST_IDENT,
	AT_IDENT,
	AT_TYPE_IDENT,
	AT_CONST_IDENT,
	HASH_IDENT,
	HASH_TYPE_IDENT,
	HASH_CONST_IDENT,

	// Keywords

	ALIAS,
	ASM,
	ASSERT,
	ATTRDEF,
	BITSTRUCT,
	CONST,
	ENUM,
	FAULTDEF,
	FUNC,
	IMPORT,
	INTERFACE,
	MACRO,
	MODULE,
	STRUCT,
	UNION,
	TYPEDEF,

	BREAK,
	CASE,
	CATCH,
	CONTINUE,
	DEFAULT,
	DEFER,
	DO,
	ELSE,
	EXTERN,
	FALSE,
	FOR,
	FOREACH,
	FOREACH_R,
	IF,
	INLINE,
	NEXTCASE,
	NUL,
	RETURN,
	STATIC,
	SWITCH,
	TLOCAL,
	TRUE,
	TRY,
	VAR,
	WHILE,

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

	CT_ALIGNOF,
	CT_ASSERT,
	CT_ASSIGNABLE,
	CT_CASE,
	CT_DEFAULT,
	CT_DEFINED,
	CT_ECHO,
	CT_ELSE,
	CT_ENDFOR,
	CT_ENDFOREACH,
	CT_ENDIF,
	CT_ENDSWITCH,
	CT_ERROR,
	CT_EVAL,
	CT_EVALTYPE,
	CT_EXEC,
	CT_EXTNAMEOF,
	CT_FEATURE,
	CT_FOR,
	CT_FOREACH,
	CT_IF,
	CT_IS_CONST,
	CT_INCLUDE,
	CT_NAMEOF,
	CT_OFFSETOF,
	CT_QNAMEOF,
	CT_SIZEOF,
	CT_STRINGIFY,
	CT_SWITCH,
	CT_TYPEFROM,
	CT_TYPEOF,
	CT_VAARG,
	CT_VACONST,
	CT_VACOUNT,
	CT_VAEXPR,
	CT_VAREF,
	CT_VASPLAT,
	CT_VATYPE,

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
alias TokenPtrList = List{ Token* };

struct Lexer
{
	Allocator allocator;
	InStream f;
	usz ln, col;
	bool eof;

	LexerPosition token_start;

	CharList buf;
	TokenPtrList emitted;
}

fn LexerPosition Lexer.pos(&self) => { self.ln, self.col };

fn Lexer* Lexer.init(&self, Allocator allocator, InStream input)
{
	*self = { .allocator = allocator, .f = input,
		.ln = 1, .col = 1, .eof = false };
	self.buf.init(allocator);
	self.emitted.init(allocator);
	return self;
}

fn void Lexer.free(&self)
{
	if (!self.allocator) return;
	self.buf.free();
	foreach (emit : self.emitted) if (emit) allocator::free(self.allocator, emit);
	self.emitted.free();
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
			case c >= 'A' && c <= 'Z': if (!nocaps) caps++;
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
fn Token* Lexer.emit_token(&self, TokenType type, String text = "")
{
	Token* tok = allocator::new(self.allocator, Token);
	tok.type  = type;
	tok.text  = text;
	tok.range = self.pos() - self.token_start;
	tok.allocator = text.len ? self.allocator : null;
	self.emitted.push(tok);
	return tok;
}

<*
 Lex the next token.
*>
fn Token*? Lexer.next(&self)
{
	Token*? tok = self._next();
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

fn Token*? Lexer._next(&self) @private => @pool()
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
		case '~': self.advance()!; return self.emit_token(TILDE);
		case '^':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '=': self.advance()!; type = XOR_ASSIGN;
				default: type = XOR;
			}
			return self.emit_token(type);
		case '*':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '=': self.advance()!; type = MUL_ASSIGN;
				default: type = STAR;
			}
			return self.emit_token(type);
		case '%':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '=': self.advance()!; type = MOD_ASSIGN;
				default: type = MOD;
			}
			return self.emit_token(type);
		case '.':
			self.advance()!;
			TokenType type = DOT;
			if (self.peek()! == '.')
			{
				self.advance()!;
				type = DOTDOT;
				if (self.peek()! == '.')
				{
					self.advance()!;
					type = ELLIPSIS;
				}
			}
			return self.emit_token(type);
		case '+':
			self.advance()!; // Consume '+'
			if (is_digit(self.peek()!))
			{
				self.pushback(c);
				return self.lex_number()!;
			}
			TokenType type;
			switch (self.peek()!)
			{
				case '+':
					self.advance()!; type = INC_OP;
					if (self.peek()! == '+')
					{
						self.advance()!; type = CT_CONCAT_OP;
					}
				case '=': self.advance()!; type = ADD_ASSIGN;
				default: type = PLUS;
			}
			return self.emit_token(type);
		case '-':
			self.advance()!; // Consume '-'
			if (is_digit(self.peek()!))
			{
				self.pushback(c);
				return self.lex_number()!;
			}
			TokenType type;
			switch (self.peek()!)
			{
				case '-': self.advance()!; type = DEC_OP;
				case '=': self.advance()!; type = SUB_ASSIGN;
				default: type = MINUS;
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
			self.advance()!; // Consuem '?'
			TokenType type;
			switch (self.peek()!)
			{
				case '!': self.advance()!; type = BANGBANG;
				case '=': self.advance()!; type = NE_OP;
				default: type = BANG;
			}
			return self.emit_token(type);
		case '?':
			self.advance()!; // Consuem '?'
			TokenType type;
			switch (self.peek()!)
			{
				case '?': self.advance()!; type = OPTELSE;
				case ':': self.advance()!; type = ELVIS;
				default: type = QUESTION;
			}
			return self.emit_token(type);
		case '|':
			self.advance()!; // Consuem '|'
			TokenType type;
			switch (self.peek()!)
			{
				case '|':
					self.advance()!; type = OR_OP;
					if (self.peek()! == '|')
					{
						self.advance()!;
						type = CT_OR_OP;
					}
				case '=': self.advance()!; type = OR_ASSIGN;
				default: type = OR;
			}
			return self.emit_token(type);
		case '&':
			self.advance()!; // Consuem '&'
			TokenType type;
			switch (self.peek()!)
			{
				case '&':
					self.advance()!; type = AND_OP;
					if (self.peek()! == '&')
					{
						self.advance()!;
						type = CT_AND_OP;
					}
				case '=': self.advance()!; type = AND_ASSIGN;
				default: type = AND;
			}
			return self.emit_token(type);
		case '=':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '>': self.advance()!; type = IMPLIES;
				case '=': self.advance()!; type = EQ_OP;
				default : type = ASSIGN;
			}
			return self.emit_token(type);
		case '>':
			self.advance()!;
			TokenType type;
			switch (self.peek()!)
			{
				case '>':
					self.advance()!; type = SHR_OP;
					if (self.peek()! == '=')
					{
						self.advance()!; type = SHR_ASSIGN;
					}
				case '=': self.advance()!; type = GE_OP;
				default : type = GREATER;
			}
			return self.emit_token(type);

		// case '{': self.advance()!; return self.emit_token(LBRACE);
		// case '[': self.advance()!; return self.emit_token(LBRACK);
		//       '[<' --> LVEC
		// case '}': self.advance()!; return self.emit_token(RBRACE);
		// case ']': self.advance()!; return self.emit_token(RBRACK);
		//       '>]' --> RVEC
		case '{': return self.lex_brace();
		case '[': return self.lex_brack();
		// case '(': return self.lex_paren();
		case '(': self.advance()!; return self.emit_token(LPAREN);
		case ')': self.advance()!; return self.emit_token(RPAREN);

		// Don't emit line or block comments, only scan them.
		//case '/': return self.lex_comment()!;
		case '/':
			self.advance()!; // consume '/'
			switch (self.peek()!)
			{
				case '/':
					self.advance()!;
					@pool() {
						self.scan_line_comment(tmem)!;
					};
					return self._next();
				case '*':
					self.advance()!;
					@pool() {
						self.scan_block_comment(tmem)!;
					};
					return self._next();;
				case '=': self.advance()!; return self.emit_token(DIV_ASSIGN);
				default: return self.emit_token(DIV);
			}

		case '<': return self.lex_contract()!;
		case '$': return self.lex_compile_time()!;
		case '#': return self.lex_hash_ident()!;
		case '@': return self.lex_attribute();
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
fn String? Lexer.scan_surround(&self, int depth, String open, String close, Allocator allocator) => @pool()
{
	DString buf = dstring::temp();

	usz i;
	char c;
	while LOOP: ((c = self.peek()!))
	{
		switch (c)
		{
			case '/':
				buf.append_char(self.advance()!); // Consume '/'
				switch (self.peek()!)
				{
					case '/':
						buf.append_char(self.advance()!); // Consume '/'
						buf.append_chars(self.scan_line_comment(tmem)!);
					case '*':
						buf.append_char(self.advance()!); // Consume '*'
						buf.append_chars(self.scan_block_comment(tmem)!);
						buf.append_chars("*/");
				}
				continue;

			case '"' :
			case '`':
			case '\'':
				buf.append_chars(self.scan_string(tmem)!);
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

	return buf.str_view().copy(allocator);
}

fn String? Lexer.scan_string(&self, Allocator allocator)
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

	return buf.str_view().copy(allocator);
}

fn Token*? Lexer.lex_string(&self) => self.emit_token(STRING, self.scan_string(self.allocator)!);
fn Token*? Lexer.lex_brace(&self)  => self.emit_token(BRACE, self.scan_surround(0, "{", "}", self.allocator)!);
// fn Token*? Lexer.lex_paren(&self)  => self.emit_token(PAREN, self.scan_surround(0, "(", ")", self.allocator)!);
fn Token*? Lexer.lex_brack(&self)  => self.emit_token(BRACK, self.scan_surround(0, "[", "]", self.allocator)!);

fn Token*? Lexer.lex_comment(&self)
{
	self.advance()!; // consume '/'

	switch (self.peek()!)
	{
		case '/': self.advance()!; return self.emit_token(LCOMMENT, self.scan_line_comment(self.allocator)!);
		case '*': self.advance()!; return self.emit_token(BCOMMENT, self.scan_block_comment(self.allocator)!);
		default: return self.emit_token(DIV);
	}
}

fn String? Lexer.scan_line_comment(&self, Allocator allocator) => @pool()
{
	char c;
	DString text = dstring::temp();
	while ((c = self.peek()!) && (c != '\n' && c != '\r')) text.append_char(self.advance()!);
	return text.str_view().copy(allocator);
}

fn String? Lexer.scan_block_comment(&self, Allocator allocator) => self.scan_surround(1, "/*", "*/", allocator)!;

fn Token*? Lexer.lex_contract(&self)
{
	char c;
	DString text = dstring::temp();

	self.advance()!; // Consume '<';

	TokenType type = EMPTY;
	switch (self.peek()!)
	{
		case '*': self.advance()!; type = CONTRACT;
		case '<':
			self.advance()!; type = SHL_OP;
			if (self.peek()! == '=')
			{
				self.advance()!; type = SHL_ASSIGN;
			}
		case '=': self.advance()!; type = LE_OP;
		default: type = LESS;
	}

	if (type != CONTRACT) return self.emit_token(type);

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

fn Token*? Lexer.lex_attribute(&self) => @pool()
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
		case STR_CONST:  type = AT_CONST_IDENT;
		default: return NOT_FOUND?;
	}
	return self.emit_token(type, str);
}

fn Token*? Lexer.lex_number(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	int i = 0;
	while ((c = self.peek()!) && (is_digit(c) || c == '-' ||
		(i > 0 && (c == '.' || c == 'e' || c == 'E'|| c == '+' ||
			c == 'b' || c == 'B' || c == 'x' || c == 'X' ||
			c == 'o' || c == 'O' || c == 'p' || c == 'P' ||
			c == 'u' || c == 'U' || c == 'l' || c == 'L' ||
			c == 'i' || c == 'f' || c == 'd' || c == '_'))))
	{
		text.append_char(self.advance()!);
		i++;
	}
	String str = text.str_view().copy(self.allocator);
	return self.emit_token(NUMBER, str);
}

fn Token*? Lexer.lex_ident(&self) => @pool()
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
		case "alias":     return self.emit_token(ALIAS, str);
		case "any":       return self.emit_token(ANY, str);
		case "asm":       return self.emit_token(ASM, str);
		case "assert":    return self.emit_token(ASSERT, str);
		case "attrdef":   return self.emit_token(ATTRDEF, str);
		case "bitstruct": return self.emit_token(BITSTRUCT, str);
		case "const":     return self.emit_token(CONST, str);
		case "enum":      return self.emit_token(ENUM, str);
		case "faultdef":  return self.emit_token(FAULTDEF, str);
		case "fn":        return self.emit_token(FUNC, str);
		case "import":    return self.emit_token(IMPORT, str);
		case "interface": return self.emit_token(INTERFACE, str);
		case "macro":     return self.emit_token(MACRO, str);
		case "module":    return self.emit_token(MODULE, str);
		case "typedef":   return self.emit_token(TYPEDEF, str);
		case "struct":    return self.emit_token(STRUCT, str);
		case "union":     return self.emit_token(UNION, str);

		// Explicit Keywords
		case "break":     return self.emit_token(BREAK, str);
		case "case":      return self.emit_token(CASE, str);
		case "catch":     return self.emit_token(CATCH, str);
		case "continue":  return self.emit_token(CONTINUE, str);
		case "default":   return self.emit_token(DEFAULT, str);
		case "defer":     return self.emit_token(DEFER, str);
		case "do":        return self.emit_token(DO, str);
		case "else":      return self.emit_token(ELSE, str);
		case "false":     return self.emit_token(FALSE, str);
		case "for":       return self.emit_token(FOR, str);
		case "foreach":   return self.emit_token(FOREACH, str);
		case "foreach_r": return self.emit_token(FOREACH_R, str);
		case "if":        return self.emit_token(IF, str);
		case "nextcase":  return self.emit_token(NEXTCASE, str);
		case "null":      return self.emit_token(NUL, str);
		case "return":    return self.emit_token(RETURN, str);
		case "static":    return self.emit_token(STATIC, str);
		case "switch":    return self.emit_token(SWITCH, str);
		case "true":      return self.emit_token(TRUE, str);
		case "try":       return self.emit_token(TRY, str);
		case "var":       return self.emit_token(VAR, str);
		case "while":     return self.emit_token(WHILE, str);

		case "extern":    return self.emit_token(EXTERN, str);
		case "inline":    return self.emit_token(INLINE, str);
		case "tlocal":    return self.emit_token(TLOCAL, str);

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
	assert(classify("aaBb") == STR_IDENT);
}


fn Token*? Lexer.lex_compile_time(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	if (self.peek()! != '$')
	{
		self.report_error("expected '$'");
		return INVALID_CHAR?;
	}
	text.append_char(self.advance()!); // Consume '$'
	while ((c = self.peek()!) && (is_ident(c) || c == '$'))
	{
		text.append_char(self.advance()!);
	}

	String str = text.str_view().copy(self.allocator);
	switch (str)
	{
		// Compile time
		case "$alignof":    return self.emit_token(CT_ALIGNOF, str);
		case "$assert":     return self.emit_token(CT_ASSERT, str);
		case "$assignable": return self.emit_token(CT_ASSIGNABLE, str);
		case "$case":       return self.emit_token(CT_CASE, str);
		case "$default":    return self.emit_token(CT_DEFAULT, str);
		case "$defined":    return self.emit_token(CT_DEFINED, str);
		case "$echo":       return self.emit_token(CT_ECHO, str);
		case "$else":       return self.emit_token(CT_ELSE, str);
		case "$endfor":     return self.emit_token(CT_ENDFOR, str);
		case "$endforeach": return self.emit_token(CT_ENDFOREACH, str);
		case "$endif":      return self.emit_token(CT_ENDIF, str);
		case "$endswitch":  return self.emit_token(CT_ENDSWITCH, str);
		case "$error":      return self.emit_token(CT_ERROR, str);
		case "$eval":       return self.emit_token(CT_EVAL, str);
		case "$evaltype":   return self.emit_token(CT_EVALTYPE, str);
		case "$exec":       return self.emit_token(CT_EXEC, str);
		case "$extnameof":  return self.emit_token(CT_EXTNAMEOF, str);
		case "$feature":    return self.emit_token(CT_FEATURE, str);
		case "$for":        return self.emit_token(CT_FOR, str);
		case "$foreach":    return self.emit_token(CT_FOREACH, str);
		case "$if":         return self.emit_token(CT_IF, str);
		case "$is_const":   return self.emit_token(CT_IS_CONST, str);
		case "$include":    return self.emit_token(CT_INCLUDE, str);
		case "$nameof":     return self.emit_token(CT_NAMEOF, str);
		case "$offsetof":   return self.emit_token(CT_OFFSETOF, str);
		case "$qnameof":    return self.emit_token(CT_QNAMEOF, str);
		case "$sizeof":     return self.emit_token(CT_SIZEOF, str);
		case "$stringify":  return self.emit_token(CT_STRINGIFY, str);
		case "$switch":     return self.emit_token(CT_SWITCH, str);
		case "$typefrom":   return self.emit_token(CT_TYPEFROM, str);
		case "$typeof":     return self.emit_token(CT_TYPEOF, str);
		case "$vaarg":      return self.emit_token(CT_VAARG, str);
		case "$vaconst":    return self.emit_token(CT_VACONST, str);
		case "$vacount":    return self.emit_token(CT_VACOUNT, str);
		case "$vaexpr":     return self.emit_token(CT_VAEXPR, str);
		case "$varef":      return self.emit_token(CT_VAREF, str);
		case "$vasplat":    return self.emit_token(CT_VASPLAT, str);
		case "$vatype":     return self.emit_token(CT_VATYPE, str);

		default:
			TokenType type;
			switch(classify(str))
			{
				case STR_CONST: type = CT_CONST_IDENT;
				case STR_TYPE:  type = CT_TYPE_IDENT;
				case STR_IDENT: type = CT_IDENT;
				default:        return INVALID_CHAR?;
			}
			return self.emit_token(type, str);
	}
}


fn Token*? Lexer.lex_hash_ident(&self) => @pool()
{
	char c;
	DString text = dstring::temp();
	if (self.peek()! != '#')
	{
		self.report_error("expected '#'");
		return INVALID_CHAR?;
	}
	text.append_char(self.advance()!); // Consume '#'
	while ((c = self.peek()!) && (is_ident(c) || c == '#'))
	{
		text.append_char(self.advance()!);
	}

	String str = text.str_view().copy(self.allocator);

	TokenType type;
	switch(classify(str))
	{
		case STR_CONST: type = HASH_CONST_IDENT;
		case STR_TYPE:  type = HASH_TYPE_IDENT;
		case STR_IDENT: type = HASH_IDENT;
		default:        return INVALID_CHAR?;
	}
	return self.emit_token(type, str);
}




