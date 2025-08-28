module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST, INVALID_TYPE, INVALID_PATH, NO_ATTRIBUTE;

enum AstType
{
	AST_TRANSLATION_UNIT,
	AST_OPT_ATTRIBUTES,
	AST_TOP_LEVEL,
	AST_MODULE,
	AST_ATTRIBUTE,
	AST_FAULT_DECL,
	AST_FAULTS,
	AST_STRUCT_DECL,
	AST_ENUM_DECL,
	AST_ENUM_SPEC,
	AST_BITSTRUCT_DECL,
	AST_INTERFACE_DECL,
	AST_INTERFACE_DECL_NAME,
	AST_INLINE,
	AST_EXTERN,
	AST_CONST,
	AST_TLOCAL,
	AST_BUILTIN,
	AST_FUNC_DEFINITION,
	AST_FUNC_HEADER,
	AST_FUNC_TYPEDEF,
	AST_MACRO_DECL,
	AST_DISTINCT_DECL,
	AST_ALIAS_DEFINE_IDENT,
	AST_ALIAS_TYPE_IDENT,
	AST_ATTRIBUTE_DEF,
	AST_GLOBAL_DECL,
	AST_CONST_DECL,

	AST_PATH, // TokenList list
	AST_TYPE, // TokenList list

	// -- Expression parsing

	AST_PAREN,
	AST_INTERFACE,
	AST_ENUM_PARAM_DECL,
	AST_TERNARY,

	AST_LITERAL,
	AST_UNARY,
	AST_BINARY,
	AST_CALL,
	AST_LAMBDA,
	AST_LIST,
	AST_TOKEN,
	AST_PARAMETER,
	AST_ARG,
}

alias AstList = List{ AstNode* };
alias TokenList = List{ Token* };

struct AstNode (Printable)
{
	AstType type;
	union
	{
		struct top_level
		{
			Token*   comment;
			AstNode* decl;
		}
		struct _module
		{
			AstNode* path_ident;
			Token*   module_params;
			AstNode* opt_attributes;
		}
		struct _attribute
		{
			AstNode* attribute_name;
			AstNode* attribute_param;
		}
		struct faults
		{
			Token*   const_ident;
			AstNode* opt_attributes;
		}
		struct struct_decl
		{
			Token*   type_ident;
			AstNode* opt_interface_impl;	// paren
			AstNode* opt_attributes;
			Token*   struct_body;		// brace
		}
		struct enum_decl
		{
			Token*   type_ident;
			AstNode* opt_interface_impl;	// paren
			AstNode* enum_spec;
			AstNode* opt_attributes;
			Token*   enum_list;		// brace
		}
		struct enum_spec
		{
			AstNode* base_type_no_generics;	// base_type_no_user_defined / TYPE_IDENT / { IDENT SCOPE } TYPE_IDENT
			AstNode* enum_params;		// paren
		}
		struct enum_param_decl
		{
			AstNode* type;
			Token*   ident;
		}
		struct bitstruct_decl
		{
			Token*   type_ident;
			AstNode* opt_interface_impl;	// paren
			AstNode* type_no_generics;	// base_type_no_generics / type_no_generics type_suffix
			AstNode* opt_attributes;
			Token*   bitstruct_body;	// brace
		}
		struct interface_decl
		{
			AstNode*  interface_decl_name;
			Token*    interface_body;	// brace
		}
		struct interface_decl_name
		{
			Token*    type_ident;
			TokenList interface_parents;
		}
		struct _interface
		{
			Token*  type_ident;	// brace
			Token*  opt_generic_parameters;
		}
		struct distinct_decl
		{
			Token*   type_ident;
			AstNode* opt_interface_impl;	// paren
			AstNode* opt_attributes;
			bool     opt_inline;
			AstNode* type;
		}
		struct func_definition
		{
			AstNode* func_header;
			AstNode* fn_parameter_list;	// paren
			AstNode* opt_attributes;
		}
		struct func_header
		{
			AstNode* optional_type;
			AstNode* type;
			Token*   func_macro_name;
		}
		struct func_typedef
		{
			AstNode* optional_type;
			AstNode* fn_parameter_list;	// paren
		}
		struct macro_decl
		{
			AstNode* macro_header;
			AstNode* macro_params;		// paren
			AstNode* opt_attributes;
		}
		struct alias_define
		{
			Token*   define_ident; 		// either an IDENT, CONST_IDENT, or AT_IDENT
			AstNode* opt_attributes;
			AstNode* path; 			// either an path_ident, path_const, or path_at_ident
			Token*   opt_generic_params; 	// brace
		}
		struct alias_type
		{
			Token*   type_ident;
			AstNode* opt_attributes;
			AstNode* typedef_type; 		// func_typedef / type
			AstNode* opt_attributes_rhs;
		}
		struct attr_def
		{
			Token*   at_type_ident;
			AstNode* opt_parameters;	// paren
			AstNode* opt_attributes;
			AstList  attribute_comma_list; 	// comma is optional
		}
		struct global_decl
		{
			AstNode*  optional_type;
			TokenList idents;		// covers 'multi_decl'
			AstNode*  opt_attributes;
			AstNode*  expr;
		}
		struct const_decl
		{
			AstNode* optional_type;
			Token*   const_ident;		// covers 'multi_decl'
			AstNode* opt_attributes;
			AstNode* expr;
		}

		AstNode*  child;			// inline, extern
		TokenList tok_list;			// type, optional_type
		AstList   ast_list;			// opt_attributes

		// Expression parsing
		struct binary
		{
			AstNode* left;
			Token*   op;
			AstNode* right;
		}
		struct unary
		{
			AstNode*   op;
			AstNode* right;
		}
		struct lambda
		{
			AstNode* maybe_opt_type;
			AstNode* fn_param_list;
			AstNode* opt_attributes;
		}
		struct ternary
		{
			AstNode* condition;
			AstNode* consequent;
			AstNode* alternative;
		}
		Token*    literal;
	}
}

fn AstNode* YadgParser.make_node(&self, AstType type)
{
	io::printfn("-- %s", type);
	AstNode *node = allocator::new(self.allocator, AstNode);
	node.type = type;
	self.nodes.push(node);
	return node;
}

fn void free_tok(Token* tok) @local
{
	if (tok) tok.free();
}
fn void free_ast(AstNode* n) @local
{
	if (n) n.free();
}
fn void free_tok_list(TokenList* l) @local
{
	foreach (n : l) free_tok(n);
	l.free();
}
fn void free_ast_list(AstList* l) @local
{
	foreach (n : l) free_ast(n);
	l.free();
}

fn void AstNode.free(&self)
{
	switch (self.type)
	{
		case AST_FAULT_DECL:
		case AST_OPT_ATTRIBUTES:
		case AST_TRANSLATION_UNIT:
			free_ast_list(&self.ast_list);

		case AST_TOP_LEVEL:
			free_tok(self.top_level.comment);
			free_ast(self.top_level.decl);

		case AST_MODULE:
			free_ast(self._module.path_ident);
			free_tok(self._module.module_params);
			free_ast(self._module.opt_attributes);

		case AST_ATTRIBUTE:
			free_ast(self._attribute.attribute_name);
			free_ast(self._attribute.attribute_param);

		case AST_FAULTS:
			free_tok(self.faults.const_ident);
			free_ast(self.faults.opt_attributes);

		case AST_STRUCT_DECL:
			free_tok(self.struct_decl.type_ident);
			free_ast(self.struct_decl.opt_interface_impl);
			free_ast(self.struct_decl.opt_attributes);
			free_tok(self.struct_decl.struct_body);

		case AST_ENUM_DECL:
			free_tok(self.enum_decl.type_ident);
			free_ast(self.enum_decl.opt_interface_impl);
			free_ast(self.enum_decl.enum_spec);
			free_ast(self.enum_decl.opt_attributes);
			free_tok(self.enum_decl.enum_list);

		case AST_ENUM_SPEC:
			free_ast(self.enum_spec.base_type_no_generics);
			free_ast(self.enum_spec.enum_params);

		case AST_ENUM_PARAM_DECL:
			free_ast(self.enum_param_decl.type);
			free_tok(self.enum_param_decl.ident);

		case AST_BITSTRUCT_DECL:
			free_tok(self.bitstruct_decl.type_ident);
			free_ast(self.bitstruct_decl.opt_interface_impl);
			free_ast(self.bitstruct_decl.type_no_generics);
			free_ast(self.bitstruct_decl.opt_attributes);
			free_tok(self.bitstruct_decl.bitstruct_body);

		case AST_INTERFACE_DECL:
			free_ast(self.interface_decl.interface_decl_name);
			free_tok(self.interface_decl.interface_body);

		case AST_INTERFACE_DECL_NAME:
			free_tok(self.interface_decl_name.type_ident);
			free_tok_list(&self.interface_decl_name.interface_parents);

		case AST_DISTINCT_DECL:
			free_tok(self.distinct_decl.type_ident);
			free_ast(self.distinct_decl.opt_interface_impl);
			free_ast(self.distinct_decl.opt_attributes);
			free_ast(self.distinct_decl.type);

		case AST_FUNC_DEFINITION:
			free_ast(self.func_definition.func_header);
			free_ast(self.func_definition.fn_parameter_list);
			free_ast(self.func_definition.opt_attributes);

		case AST_FUNC_HEADER:
			free_ast(self.func_header.optional_type);
			free_ast(self.func_header.type);
			free_tok(self.func_header.func_macro_name);

		case AST_MACRO_DECL:
			free_ast(self.macro_decl.macro_header);
			free_ast(self.macro_decl.macro_params);
			free_ast(self.macro_decl.opt_attributes);

		case AST_FUNC_TYPEDEF:
			free_ast(self.func_typedef.optional_type);
			free_ast(self.func_typedef.fn_parameter_list);

		case AST_ALIAS_DEFINE_IDENT:
			free_tok(self.alias_define.define_ident);
			free_ast(self.alias_define.opt_attributes);
			free_ast(self.alias_define.path);
			free_tok(self.alias_define.opt_generic_params);

		case AST_ALIAS_TYPE_IDENT:
			free_tok(self.alias_type.type_ident);
			free_ast(self.alias_type.opt_attributes);
			free_ast(self.alias_type.typedef_type);
			free_ast(self.alias_type.opt_attributes_rhs);

		case AST_ATTRIBUTE_DEF:
			free_tok(self.attr_def.at_type_ident);
			free_ast(self.attr_def.opt_parameters);
			free_ast(self.attr_def.opt_attributes);
			free_ast_list(&self.attr_def.attribute_comma_list);

		case AST_GLOBAL_DECL:
			free_ast(self.global_decl.optional_type);
			free_tok_list(&self.global_decl.idents);
			free_ast(self.global_decl.opt_attributes);
			free_ast(self.global_decl.expr);

		case AST_CONST_DECL:
			free_ast(self.const_decl.optional_type);
			free_tok(self.const_decl.const_ident);
			free_ast(self.const_decl.opt_attributes);
			free_ast(self.const_decl.expr);

		case AST_INTERFACE:
			free_tok(self._interface.type_ident);
			free_tok(self._interface.opt_generic_parameters);

		case AST_BUILTIN:
		case AST_CONST:
		case AST_EXTERN:
		case AST_INLINE:
		case AST_TLOCAL:
			free_ast(self.child);

		// -- EXPRESSION

		case AST_PATH:
		case AST_TYPE:
			free_tok_list(&self.tok_list);

		case AST_ARG:
		case AST_LIST:
		case AST_PARAMETER:
		case AST_PAREN:
			free_ast_list(&self.ast_list);

		case AST_LITERAL:
		case AST_TOKEN:
			free_tok(self.literal);

		case AST_CALL:
		case AST_UNARY:
			free_ast(self.unary.op);
			free_ast(self.unary.right);

		case AST_BINARY:
			free_ast(self.binary.left);
			free_tok(self.binary.op);
			free_ast(self.binary.right);

		case AST_LAMBDA:
			free_ast(self.lambda.maybe_opt_type);
			free_ast(self.lambda.fn_param_list);
			free_ast(self.lambda.opt_attributes);

		case AST_TERNARY:
			free_ast(self.ternary.condition);
			free_ast(self.ternary.consequent);
			free_ast(self.ternary.alternative);
	}
}

fn AstNode*? YadgParser.translation_unit(&self)
{
	AstNode* node = self.make_node(AST_TRANSLATION_UNIT);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	AstNode*? top_level_stmt;
	while (!self.expect(EOF)!)
	{
		top_level_stmt = self.top_level();
		if (catch err = top_level_stmt)
		{
			@pool() {
			self.report_error(string::tformat("translation unit error: %s", err));
			};
			self.synchronize()!;
			continue;
		}
		node.ast_list.push(top_level_stmt);
	}

	return node;
}

fn AstNode*? YadgParser.top_level(&self)
{
	Token* tok_comment;
	AstNode *top;

	if (try c = self.comment())
	{
		tok_comment = c;
	}
	defer catch {
		free_tok(tok_comment);
		free_ast(top);
	};

	if (self.expect(EXTERN)!)
	{
		return self._extern(self.top_level()!);
	}

	while LOOP: (self.peek() != EOF && top == null)
	{
		switch(self.peek())
		{
			case MODULE:    top = self._module()!;
			case FAULTDEF:  top = self.fault_decl()!;
			case UNION:
			case STRUCT:    top = self.struct_decl()!;
			case ENUM:      top = self.enum_decl()!;
			case BITSTRUCT: top = self.bitstruct_decl()!;
			case INTERFACE: top = self.interface_decl()!;
			case FUNC:      top = self.func_definition()!;
			case MACRO:     top = self.macro_decl()!;
			case TYPEDEF:   top = self.distinct_decl()!;
			case ATTRDEF:
			case ALIAS:     top = self.define_decl()!;
			case CONST:     top = self.const_decl()!;
			case CT_IDENT:
			case IMPORT:
				self.synchronize()!;
				return self.top_level()!;
			default:
				top = self.global_decl()!;
		}
	}

	if (!top) {
		if (tok_comment) tok_comment.free();
		io::printfn("top_level returned null; token=%s", self.peek());
		return null;
	}

	AstNode* node = self.make_node(AST_TOP_LEVEL);
	node.top_level.decl = top;
	node.top_level.comment = tok_comment;
	return node;
}

fn Token*? YadgParser.comment(&self)
{
	Token* comment, tok;
	while LOOP: (true)
	{
		switch(self.peek())
		{
			case LCOMMENT:
			case BCOMMENT:
				tok = self.advance()!;
				if (tok) tok.free();
			case CONTRACT:
				if (comment) comment.free();
				comment = self.advance()!;
			default:
				break LOOP;
		}
	}

	Token* next = self.advance()!;
	defer self.push_back(next);
	if (comment && comment.type != CONTRACT && next.range.start.ln - comment.range.end.ln > 1)
	{
		comment.free();
		return NOT_FOUND?;
	}

	return comment;
}

<*
module
	: MODULE path_ident opt_attributes ';'
	| MODULE path_ident '{' module_params '}' opt_attributes ';'
	;
*>
fn AstNode*? YadgParser._module(&self)
{
	if (!self.expect(MODULE)!)
	{
		self.report_error("_module: expected a 'module' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_MODULE);
	defer catch node.free();

	// path_ident
	node._module.path_ident = self.path_ident()!;

	if (self.peek() == BRACE)
	{
		node._module.module_params = self.advance()!;
	}

	node._module.opt_attributes = self.opt_attributes()!;

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("_module: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

<*
path
	: IDENT SCOPE
	| path IDENT SCOPE
	;

Note: This is not exactly like the grammer above but will read a terminal IDENT
as well.
*>
fn AstNode*? YadgParser.path(&self)
{
	AstNode* node = self.make_node(AST_PATH);
	node.tok_list.init(self.allocator);
	defer catch node.free();

	// path_ident
	while (self.peek() != EOF && self.peek() == IDENT)
	{
		node.tok_list.push(self.advance()!);
		if (self.expect(SCOPE)!) continue;
	}

	return node;
}

<*
path_ident
	: path IDENT
	| IDENT
	;
*>
fn AstNode*? YadgParser.path_ident(&self) => self.path();

<*
path_const
	: path CONST_IDENT
	| CONST_IDENT
	;
*>
fn AstNode*? YadgParser.path_const(&self)
{
	AstNode* path = self.path()!;
	defer catch path.free();
	if (self.peek() != CONST_IDENT)
	{
		return INVALID_PATH?;
	}
	path.tok_list.push(self.advance()!);
	return path;
}

<*
path_at_ident
	: path AT_IDENT
	| AT_IDENT
	;
*>
fn AstNode*? YadgParser.path_at_ident(&self)
{
	AstNode* path = self.path()!;
	defer catch path.free();
	if (self.peek() != AT_IDENT)
	{
		return INVALID_PATH?;
	}
	path.tok_list.push(self.advance()!);
	return path;
}

<*
path_at_type_ident
	: path AT_TYPE_IDENT
	| AT_TYPE_IDENT
	;
*>
fn AstNode*? YadgParser.path_at_type_ident(&self)
{
	AstNode* path = self.path()!;
	defer catch path.free();
	if (self.peek() != AT_TYPE_IDENT)
	{
		return INVALID_PATH?;
	}
	path.tok_list.push(self.advance()!);
	return path;
}

<*
opt_attributes
	: attribute_list
	| empty
	;

attribute_list
	: attribute
	| attribute_list attribute
	;

attribute
	: attribute_name
	| attribute_name '(' attribute_param_list ')'
	;

	Return null when no attributes are present;
*>
fn AstNode*? YadgParser.opt_attributes(&self)
{
	if (!is_attribute(self.peek())) return null;

	AstNode* node = self.make_node(AST_OPT_ATTRIBUTES);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	while ATTRIBUTE: (self.peek() != EOF && is_attribute(self.peek()))
	{
		if (try attr = self._attribute())
		{
			node.ast_list.push(attr);
		}
	}
	return node;
}

fn bool is_attribute(TokenType type) @inline
{
	switch (type)
	{
		case AT_IDENT:
		case AT_TYPE_IDENT:
		case IDENT:
			return true;
		default:
			return false;

	}
}

<*
 Returns an Attribute node or NO_ATTRIBUTE? if no attribute was found.

attribute
	: attribute_name
	| attribute_name '(' attribute_param_list ')'
	;

attribute_name
	: AT_IDENT
	| AT_TYPE_IDENT
	| path AT_TYPE_IDENT
	;
*>
fn AstNode*? YadgParser._attribute(&self)
{
	AstNode* node = self.make_node(AST_ATTRIBUTE);
	defer catch node.free();

	if (self.peek() == IDENT)
	{
		node._attribute.attribute_name = self.path_at_type_ident()!;
	}
	else if (self.peek() == AT_IDENT || self.peek() == AT_TYPE_IDENT)
	{
		node._attribute.attribute_name = self.new_literal(self.advance()!);
	}
	else
	{
		return NO_ATTRIBUTE?;
	}

	if (self.expect(LPAREN)!)
	{
		node._attribute.attribute_param = self.attribute_param_list()!;
		if (!self.expect(RPAREN)!)
		{
			self.report_error("attribute: expected RPAREN after attribute_param_list");
			return INVALID_AST?;
		}
	}

	return node;
}

fn AstNode*? YadgParser.fault_decl(&self)
{
	if (!self.expect(FAULTDEF)!)
	{
		self.report_error("fault_decl: expected a 'FAULTDEF' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_FAULT_DECL);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	AstNode *ptr;
	while ((ptr = self.faults()!) && ptr)
	{
		node.ast_list.push(ptr);
		if (!self.expect(COMMA)!) break;
	}

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("fault_decl: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

<*
 Returns an Faults node or null if no attribute was found.
*>
fn AstNode*? YadgParser.faults(&self)
{
	if (self.peek() != CONST_IDENT) return null;

	AstNode* node = self.make_node(AST_FAULTS);
	defer catch node.free();
	node.faults.const_ident = self.advance()!;
	node.faults.opt_attributes = self.opt_attributes()!;
	return node;
}

fn AstNode*? YadgParser.struct_decl(&self)
{
	if (!self.expect(STRUCT)! && !self.expect(UNION)!)
	{
		self.report_error("struct_decl: expected a 'STRUCT' or 'UNION' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("struct_decl: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_STRUCT_DECL);
	defer catch node.free();

	node.struct_decl.type_ident = self.advance()!;

	if (self.peek() == LPAREN)
	{
		node.struct_decl.opt_interface_impl = self.opt_interface_impl()!;
	}

	if (self.peek() == IDENT || self.peek() == AT_IDENT || self.peek() == AT_TYPE_IDENT)
	{
		node.struct_decl.opt_attributes = self.opt_attributes()!;
	}

	if (self.peek() != BRACE)
	{
		self.report_error("struct_decl: expected the struct body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.struct_decl.struct_body = self.advance()!;

	return node;
}

<*
enum_decl
	: ENUM TYPE_IDENT opt_interface_impl enum_spec opt_attributes '{' enum_list '}'
	| ENUM TYPE_IDENT opt_interface_impl opt_attributes '{' enum_list '}'
	;
*>
fn AstNode*? YadgParser.enum_decl(&self)
{
	if (!self.expect(ENUM)!)
	{
		self.report_error("enum_decl: expected a 'ENUM' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("enum_decl: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_ENUM_DECL);
	defer catch node.free();

	// TYPE_IDENT
	node.enum_decl.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek() == LPAREN)
	{
		node.enum_decl.opt_interface_impl = self.opt_interface_impl()!;
	}

	// enum_spec
	if (self.expect(COLON)!)
	{
		node.enum_decl.enum_spec = self.enum_spec()!;
	}

	node.enum_decl.opt_attributes = self.opt_attributes()!;

	if (self.peek() != BRACE)
	{
		self.report_error("enum_decl: expected the enum_list (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.enum_decl.enum_list = self.advance()!;

	return node;
}

fn AstNode* YadgParser._inline(&self, AstNode* child)
{
	AstNode* node = self.make_node(AST_INLINE);
	node.child = child;
	return node;
}

fn AstNode* YadgParser._extern(&self, AstNode* child)
{
	AstNode* node = self.make_node(AST_EXTERN);
	node.child = child;
	return node;
}

fn AstNode* YadgParser._const(&self, AstNode* child)
{
	AstNode* node = self.make_node(AST_CONST);
	node.child = child;
	return node;
}

fn AstNode* YadgParser._tlocal(&self, AstNode* child)
{
	AstNode* node = self.make_node(AST_TLOCAL);
	node.child = child;
	return node;
}

fn AstNode* YadgParser._builtin(&self, AstNode* child)
{
	AstNode* node = self.make_node(AST_BUILTIN);
	node.child = child;
	return node;
}

<*
Colon is already consumed when enum_spec() is called.

enum_spec
	: ':' base_type_no_generics '(' enum_params ')'
	| ':' INLINE base_type_no_generics '(' enum_params ')'
        | ':' base_type_no_generics
        | ':' INLINE base_type_no_generics
        | ':' '(' enum_params ')'
	;

base_type_no_generics
	: base_type_no_user_defined
	| TYPE_IDENT
        | path TYPE_IDENT
	;

path
	: IDENT SCOPE
	| path IDENT SCOPE
	;
*>
fn AstNode*? YadgParser.enum_spec(&self)
{
	if (self.expect(INLINE)!) return self._inline(self.enum_spec());
	if (self.expect(CONST)!) return self._const(self.enum_spec());

	AstNode* node = self.make_node(AST_ENUM_SPEC);
	defer catch node.free();

	// base_type_no_generics
	if (try type = self.base_type_no_generics())
	{
		node.enum_spec.base_type_no_generics = type;
	}

	// enum_params
	if (self.peek() == LPAREN)
	{
		node.enum_spec.enum_params = self.enum_params()!;
	}

	return node;
}

fn bool is_base_type_no_generics(TokenType type)
{
	switch (type)
	{
		case VOID:
		case BOOL:
		case CHAR:
		case ICHAR:
		case SHORT:
		case USHORT:
		case INT:
		case UINT:
		case LONG:
		case ULONG:
		case INT128:
		case UINT128:
		case FLOAT:
		case DOUBLE:
		case FLOAT16:
		case BFLOAT16:
		case FLOAT128:
		case IPTR:
		case UPTR:
		case ISZ:
		case USZ:
		case FAULT:
		case ANY:
		case TYPEID:
		case CT_CONST_IDENT:
		case CT_TYPE_IDENT:
		case CT_IDENT:
		case CT_TYPEOF:
		case CT_TYPEFROM:
		case CT_VATYPE:
		case CT_EVALTYPE:
			return true;
		default:
			return false;
	}
}

<*
bitstruct_decl
	: BITSTRUCT TYPE_IDENT opt_interface_impl ':' type_no_generics opt_attributes bitstruct_body
	;
*>
fn AstNode*? YadgParser.bitstruct_decl(&self)
{
	if (!self.expect(BITSTRUCT)!)
	{
		self.report_error("bitstruct_decl: expected a 'BITSTRUCT' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("bitstruct_decl: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_BITSTRUCT_DECL);
	defer catch node.free();

	// TYPE_IDENT
	node.bitstruct_decl.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek() == LPAREN)
	{
		node.bitstruct_decl.opt_interface_impl = self.opt_interface_impl()!;
	}

	if (!self.expect(COLON)!)
	{
		self.report_error("bitstruct_decl: expected a 'COLON' token");
		return INVALID_AST?;
	}

	// type_no_generics
	node.bitstruct_decl.type_no_generics = self.type_no_generics()!;

	node.bitstruct_decl.opt_attributes = self.opt_attributes()!;

	if (self.peek() != BRACE)
	{
		self.report_error("bitstruct_decl: expected the bitstruct_body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.bitstruct_decl.bitstruct_body = self.advance()!;

	return node;
}

<*
 Parses a 'type_no_generics' as default (type_suffix = true, generic_params = false).

 If 'type_suffix' is false => base_type_no_generics
 If 'generic_params' is true => type (with opt_generic_params)


type
	: base_type
	| type type_suffix;


base_type
	: base_type_no_user_defined
	| TYPE_IDENT opt_generic_parameters
        | path TYPE_IDENT opt_generic_parameters
	;

type_no_generics
	: base_type_no_generics
	| type_no_generics type_suffix
	;

type_suffix
	: '*'
	| '[' constant_expr ']'
        | '[' ']'
        | '[' '*' ']'
        | LVEC constant_expr RVEC
        | LVEC '*' RVEC
        ;
*>
fn AstNode*? YadgParser.parse_type(&self, bool type_suffix = true, bool generic_params = false)
{
	AstNode* node = self.make_node(AST_TYPE);
	node.tok_list.init(self.allocator);

	defer catch {
		while (node.tok_list.len()) self.push_back(node.tok_list.pop()!!);
		node.free();
	}

	//  base_type_no_generics
	TokenType tok_type = self.peek();
	switch
	{
		case is_base_type_no_generics(tok_type):
		case tok_type == TYPE_IDENT:
			node.tok_list.push(self.advance()!);
			switch (tok_type)
			{
				case CT_TYPEOF:
				case CT_TYPEFROM:
				case CT_EVALTYPE:
					// TODO: Hack
					if (self.peek() == LPAREN)
					{
						usz depth = 1;
						node.tok_list.push(self.advance()!); // Consume LPAREN
						while (self.peek() != EOF && depth != 0)
						{
							switch (self.peek())
							{
								case LPAREN: depth++;
								case RPAREN: depth--;
								default: break;
							}
							node.tok_list.push(self.advance()!);
						}
					}

				case CT_VATYPE:
					node.tok_list.push(self.advance()!);
				default:
			}
		case tok_type == IDENT:
			// { IDENT SCOPE } TYPE_IDENT
			AstNode* path = self.path()!;
			while (path.tok_list.len()) node.tok_list.push(path.tok_list.pop()!);
			path.free();
			if (self.peek() != TYPE_IDENT)
			{
				return INVALID_TYPE?;
			}
			node.tok_list.push(self.advance()!);
		// case tok_type == AT_IDENT:
		default:
			return INVALID_TYPE?;
	}

	//  opt_generics_param
	if (generic_params)
	{
		if (self.peek() == BRACE) node.tok_list.push(self.advance()!);
	}

	//  type_suffix
	if (type_suffix)
	{
		while TYPE_SUFFIX: (self.peek() != EOF)
		{
			switch (self.peek())
			{
				case STAR:
				case BRACK:
					node.tok_list.push(self.advance()!);
					continue;
				default:
					break TYPE_SUFFIX;
			}
		}
	}
	return node;
}
fn AstNode*? YadgParser.base_type(&self) => self.parse_type(false, true);
fn AstNode*? YadgParser.type_no_generics(&self) => self.parse_type(true, false);
fn AstNode*? YadgParser.base_type_no_generics(&self) => self.parse_type(false, false);
fn AstNode*? YadgParser.type(&self) => self.parse_type(true, true);

<*
optional_typnode
	: type
	| type '?'
	;
*>
fn AstNode*? YadgParser.optional_type(&self)
{
	AstNode *node = self.type()!;
	if (self.peek() == QUESTION)
	{
		node.tok_list.push(self.advance()!);
	}
	return node;
}

<*
typedef_type
	: func_typedef
	| type
	;

func_typedef
	: FN optional_type fn_parameter_list
	;
*>
fn AstNode*? YadgParser.typedef_type(&self)
{
	if (self.peek() == FUNC) return self.func_type()!;
	return self.type()!;
}

<*
func_typedef
	: FN optional_type fn_parameter_list
	;
*>
fn AstNode*? YadgParser.func_type(&self)
{
	if (!self.expect(FUNC)!)
	{
		self.report_error("func_type: expected a 'FUNC' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_FUNC_TYPEDEF);
	defer catch node.free();

	node.func_typedef.optional_type = self.optional_type()!;

	if (self.peek() != LPAREN)
	{
		self.report_error("func_type: expected a 'LPAREN' token as fn_paramter_list");
		return INVALID_AST?;
	}
	node.func_typedef.fn_parameter_list = self.fn_parameter_list()!;

	return node;
}


<*
interface_decl
	: INTERFACE interface_decl_name '{' '}'
	| INTERFACE interface_decl_name '{' interface_body '}'
	;
*>
fn AstNode*? YadgParser.interface_decl(&self)
{
	if (!self.expect(INTERFACE)!)
	{
		self.report_error("interface_decl: expected a 'INTERFACE' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_INTERFACE_DECL);
	node.interface_decl.interface_decl_name = self.interface_decl_name()!;
	defer catch node.free();

	if (self.peek() != BRACE)
	{
		self.report_error("interface_decl: expected the interface_body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.interface_decl.interface_body = self.advance()!;

	return node;
}

<*
interface_decl_name
	: TYPE_IDENT
	| TYPE_IDENT ':' interface_parents
	;

interface_parents
	: TYPE_IDENT
	| interface_parents ',' TYPE_IDENT
	;

*>
fn AstNode*? YadgParser.interface_decl_name(&self)
{
	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("interface_decl_name: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_INTERFACE_DECL_NAME);
	node.interface_decl_name.interface_parents.init(self.allocator);
	defer catch node.free();

	node.interface_decl_name.type_ident = self.advance()!;

	// interface_parents
	if (self.expect(COLON)!)
	{
		// interface_parents as TYPE_IDENT ','
		while (self.peek() != EOF && self.peek() == TYPE_IDENT)
		{
			node.interface_decl_name.interface_parents.push(self.advance()!);
			if (self.expect(COMMA)!) continue;
		}
	}

	return node;
}

<*
func_definition
	: func_defintion_decl
	| FN func_header fn_parameter_list opt_attributes macro_func_body
	;

func_defintion_decl
	: FN func_header fn_parameter_list opt_attributes ';'
	;
*>
fn AstNode*? YadgParser.func_definition(&self)
{
	if (!self.expect(FUNC)!)
	{
		self.report_error("func_definition: expected a 'FUNC' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_FUNC_DEFINITION);
	defer catch node.free();

	node.func_definition.func_header = self.func_header()!;

	if (self.peek() != LPAREN)
	{
		self.report_error("func_definition: expected 'fn_parameter_list' (a 'LPAREN' token)");
		return INVALID_AST?;
	}
	node.func_definition.fn_parameter_list = self.fn_parameter_list()!;

	node.func_definition.opt_attributes = self.opt_attributes()!;

	// Handle 'macro_func_body'
	self.macro_func_body()!;

	return node;
}


fn AstNode*? YadgParser.func_header(&self)
{
	AstNode* node = self.make_node(AST_FUNC_HEADER);
	defer catch node.free();

	// We can have two cases:
	// 	1.) mod::String? trim
	// 	2.) mod::String? mod::Struct.trim

	node.func_header.optional_type = self.optional_type()!;

	AstNode*? type = self.type();
	if (catch type)
	{
		node.func_header.func_macro_name = self.advance()!;
		return node; // Case 1
	}
	node.func_header.type = type;

	if (self.expect(DOT)!)
	{
		node.func_header.func_macro_name = self.advance()!;
	}
	else
	{
		self.report_error("exepected 'DOT' token?");
		return INVALID_AST?;
	}

	return node; // Case 2
}


fn AstNode*? YadgParser.macro_decl(&self)
{
	if (!self.expect(MACRO)!)
	{
		self.report_error("macro_decl: expected a 'MACRO' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_MACRO_DECL);
	defer catch node.free();

	node.macro_decl.macro_header = self.macro_header()!;

	if (self.peek() != LPAREN)
	{
		self.report_error("macro_decl: expected 'macro_params' (a 'LPAREN' token)");
		return INVALID_AST?;
	}
	node.macro_decl.macro_params = self.macro_params()!;

	node.macro_decl.opt_attributes = self.opt_attributes()!;

	// Handle 'macro_func_body'
	self.macro_func_body()!;

	return node;
}

fn void? YadgParser.macro_func_body(&self)
{
	switch (self.peek())
	{
		case SEMICOLON: // macro_decl_decl
		case BRACE:     // Regular func/macro body
			self.advance()!.free();
		case IMPLIES:
			if (try attr = self.opt_attributes() && attr)
			{
				return self.macro_func_body()!;
			}
			while (self.peek() != EOF && self.peek() != SEMICOLON)
			{
				self.advance()!.free();
			}
			return self.macro_func_body()!;
		case EOF:
			break;
		default:
			self.report_error("macro_func_body: expected a macro/func body");
			return INVALID_AST?;
	}
}

<*
 Similar to func_header but we pass a macro

macro_header
	: func_header
	| type '.' func_macro_name
	| func_macro_name
	;

func_header
	: optional_type type '.' func_macro_name
	| optional_type func_macro_name
	;

*>
fn AstNode*? YadgParser.macro_header(&self)
{
	AstNode* node = self.make_node(AST_FUNC_HEADER);
	defer catch node.free();

	// We can have four cases:
	// 	1.) trim
	// 	2.) mod::String.trim
	// 	3.) mod::String? trim
	// 	4.) mod::String? mod::Struct.trim

	AstNode*? opt_type = self.optional_type();
	if (catch opt_type)
	{
		node.func_header.func_macro_name = self.advance()!;
		return node; // Case 1
	}
	node.func_header.optional_type = opt_type;

	if (self.expect(DOT)!)
	{
		node.func_header.func_macro_name = self.advance()!;
		node.func_header.type = node.func_header.optional_type;
		node.func_header.optional_type = null;
		return node; // Case 2
	}

	AstNode*? type = self.type();
	if (catch type)
	{
		node.func_header.func_macro_name = self.advance()!;
		return node; // Case 3
	}
	node.func_header.type = type;

	if (self.expect(DOT)!)
	{
		node.func_header.func_macro_name = self.advance()!;
	}
	else
	{
		self.report_error("exepected 'DOT' token?");
		return INVALID_AST?;
	}

	return node; // Case 4
}

<*
distinct_decl
	: TYPEDEF TYPE_IDENT opt_interface_impl opt_attributes '=' opt_inline type ';'
	;
*>
fn AstNode*? YadgParser.distinct_decl(&self)
{
	if (!self.expect(TYPEDEF)!)
	{
		self.report_error("distinct_decl: expected a 'TYPEDEF' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("distinct_decl: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_DISTINCT_DECL);
	defer catch node.free();

	node.distinct_decl.type_ident = self.advance()!;

	if (self.peek() == LPAREN)
	{
		node.distinct_decl.opt_interface_impl = self.opt_interface_impl()!;
	}

	node.distinct_decl.opt_attributes = self.opt_attributes()!;

	if (!self.expect(ASSIGN)!)
	{
		self.report_error("distinct_decl: expected a 'ASSIGN' token");
		return INVALID_AST?;
	}

	node.distinct_decl.opt_inline = self.expect(INLINE)!;
	node.distinct_decl.type = self.type()!;

	return node;
}

<*
define_decl
	: ALIAS define_ident ';'
	| ATTRDEF define_attribute ';'
	| ALIAS TYPE_IDENT opt_attributes '=' typedef_type opt_attributes ';'
	;

define_ident
	: IDENT opt_attributes '=' path_ident opt_generic_parameters
	| CONST_IDENT  opt_attributes '=' path_const opt_generic_parameters
	| AT_IDENT opt_attributes '=' path_at_ident opt_generic_parameters
	;

opt_generic_parameters
	: generic_expr
	| empty
	;

generic_expr
	: '{' generic_parameters '}'
	;

define_attribute
	: AT_TYPE_IDENT '(' parameters ')' opt_attributes define_attribute_body
	| AT_TYPE_IDENT opt_attributes define_attribute_body
	;

define_attribute_body
	: empty
	| '=' attribute_comma_list opt_comma
	;

attribute_comma_list
	: attribute
	| attribute_comma_list ',' attribute
	;

opt_comma
	: ','
	| empty
	;
*>
fn AstNode*? YadgParser.define_decl(&self)
{
	if (self.expect(ALIAS)!)
	{
		switch (self.peek())
		{
			case IDENT:
			case CONST_IDENT:
			case AT_IDENT:
				// alias_define_ident
				AstNode* node = self.make_node(AST_ALIAS_DEFINE_IDENT);
				defer catch node.free();

				switch (self.peek())
				{
					case IDENT:
					case CONST_IDENT:
					case AT_IDENT:
						node.alias_define.define_ident = self.advance()!;
					default:
						self.report_error("alias ident: wrong type_ident token");
						return INVALID_AST?;
				}

				node.alias_define.opt_attributes = self.opt_attributes()!;
				if (!self.expect(ASSIGN)!)
				{
					self.report_error("alias ident: expected an 'ASSIGN' token");
					return INVALID_AST?;
				}

				switch (node.alias_define.define_ident.type)
				{
					case IDENT:
						node.alias_define.path = self.path_ident()!;
					case CONST_IDENT:
						node.alias_define.path = self.path_const()!;
					case AT_IDENT:
						node.alias_define.path = self.path_at_ident()!;
					default:
						unreachable("alias ident: invalid path token");
				}

				if (self.peek() == BRACE)
				{
					node.alias_define.opt_generic_params = self.advance()!;
				}

				if (!self.expect(SEMICOLON)!)
				{
					self.report_error("alias ident: expected 'SEMICOLON'");
					return INVALID_AST?;
				}

				return node;
			case TYPE_IDENT:
				// alias_type_ident
				AstNode* node = self.make_node(AST_ALIAS_TYPE_IDENT);
				defer catch node.free();

				node.alias_type.type_ident = self.advance()!;
				node.alias_type.opt_attributes = self.opt_attributes()!;
				if (!self.expect(ASSIGN)!)
				{
					self.report_error("alias TYPE_IDENT: expected an 'ASSIGN' token");
					return INVALID_AST?;
				}
				node.alias_type.typedef_type = self.typedef_type()!;
				node.alias_type.opt_attributes_rhs = self.opt_attributes()!;

				if (!self.expect(SEMICOLON)!)
				{
					self.report_error("alias TYPE_IDENT: expected 'SEMICOLON'");
					return INVALID_AST?;
				}

				return node;
			default:
				self.report_error("define_decl: invalid type after 'alias'");
				return INVALID_AST?;
		}

	} else if (self.expect(ATTRDEF)!)
	{
		if (self.peek() == AT_TYPE_IDENT)
		{
			// attr_def
			AstNode* node = self.make_node(AST_ATTRIBUTE_DEF);
			node.attr_def.attribute_comma_list.init(self.allocator);
			defer catch node.free();

			node.attr_def.at_type_ident = self.advance()!;
			if (self.peek() == LPAREN)
			{
				node.attr_def.opt_parameters = self.fn_parameter_list()!;
			}
			node.attr_def.opt_attributes = self.opt_attributes()!;

			if (self.expect(ASSIGN)!)
			{
				while (try attr = self._attribute())
				{
					node.attr_def.attribute_comma_list.push(attr);
					if (self.expect(COMMA)!) continue;
				}
			}

			if (!self.expect(SEMICOLON)!)
			{
				self.report_error("attrdef: expected 'SEMICOLON'");
				return INVALID_AST?;
			}

			return node;
		}
		else
		{
			self.report_error("define_decl: expected 'AT_TYPE_IDENT' token after 'attrdef'");
			return INVALID_AST?;
		}
	}
	else
	{
		self.report_error("define_decl: expected either an 'ALIAS' or 'ATTRDEF' token");
	 	return INVALID_AST?;
	}
}

<*
global_decl
	: global_storage optional_type IDENT opt_attributes ';'
	| global_storage optional_type IDENT multi_decl opt_attributes ';'
	| global_storage optional_type IDENT opt_attributes '=' expr ';'
	;

global_storage
	: TLOCAL
	| empty
	;

multi_decl
	: ',' IDENT
	| multi_decl ',' IDENT
	;

*>
fn AstNode*? YadgParser.global_decl(&self)
{
	if (self.expect(TLOCAL)!)
	{
		return self._tlocal(self.global_decl()!);
	}

	AstNode* node = self.make_node(AST_GLOBAL_DECL);
	node.global_decl.idents.init(self.allocator);
	defer catch node.free();

	node.global_decl.optional_type = self.optional_type()!;

	while (self.peek() != EOF && self.peek() == IDENT)
	{
		node.global_decl.idents.push(self.advance()!);
		if (self.expect(COMMA)!) continue;
	}

	node.global_decl.opt_attributes = self.opt_attributes()!;

	if (self.expect(ASSIGN)!)
	{
		node.global_decl.expr = self.expr()!;
	}

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("global_decl: expected 'SEMICOLON'");
		return INVALID_AST?;
	}

	return node;
}

<*
const_declaration
	: CONST CONST_IDENT opt_attributes '=' expr ';'
	| CONST optional_type CONST_IDENT opt_attributes '=' expr ';'
	| CONST optional_type CONST_IDENT opt_attributes ';'
	;
*>
fn AstNode*? YadgParser.const_decl(&self)
{
	if (!self.expect(CONST)!)
	{
		self.report_error("const_decl: expected 'CONST'");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_CONST_DECL);
	defer catch node.free();

	if (self.peek() != CONST_IDENT)
	{
		node.global_decl.optional_type = self.optional_type()!;
	}
	node.const_decl.const_ident = self.advance()!;
	node.const_decl.opt_attributes = self.opt_attributes()!;

	if (self.expect(ASSIGN)!)
	{
		node.const_decl.expr = self.expr()!;
	}

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("const_decl: expected 'SEMICOLON'");
		return INVALID_AST?;
	}

	return node;
}

//
// -- Expression parsing
//

fn bool assignment_op(TokenType type)
{
	switch(type)
	{
	case ASSIGN:
	case ADD_ASSIGN:
	case SUB_ASSIGN:
	case MUL_ASSIGN:
	case DIV_ASSIGN:
	case MOD_ASSIGN:
	case SHL_ASSIGN:
	case SHR_ASSIGN:
	case AND_ASSIGN:
	case XOR_ASSIGN:
	case OR_ASSIGN:
		return true;
	default: return false;
	}
}

fn bool relational_op(TokenType type)
{
	switch(type)
	{
	case LESS:
	case GREATER:
	case LE_OP:
	case GE_OP:
	case EQ_OP:
	case NE_OP:
		return true;
	default: return false;
	}
}

fn bool additive_op(TokenType type)
{
	switch(type)
	{
	case PLUS:
	case MINUS:
	case CT_CONCAT_OP:
		return true;
	default: return false;
	}
}

fn bool or_op(TokenType type)
{
	switch(type)
	{
	case OR_OP:
	case CT_OR_OP:
		return true;
	default: return false;
	}
}

fn bool and_op(TokenType type)
{
	switch(type)
	{
	case AND_OP:
	case CT_AND_OP:
		return true;
	default: return false;
	}
}

fn bool bit_op(TokenType type)
{
	switch(type)
	{
	case AND:
	case XOR:
	case OR:
		return true;
	default: return false;
	}
}

fn bool shift_op(TokenType type)
{
	switch(type)
	{
	case SHL_OP:
	case SHR_OP:
		return true;
	default: return false;
	}
}

fn bool mult_op(TokenType type)
{
	switch(type)
	{
	case STAR:
	case DIV:
	case MOD:
		return true;
	default: return false;
	}
}

fn bool unary_op(TokenType type)
{
	switch(type)
	{
	case LPAREN: // TODO: Grammar says: '(' type ')'
	case AND:
	case AND_OP:
	case STAR:
	case PLUS:
	case MINUS:
	case TILDE:
	case BANG:
	case INC_OP:
	case DEC_OP:
		return true;
	default: return false;
	}
}

fn AstNode* YadgParser.new_binary(&self, AstNode* l, Token* op, AstNode* r) @private
{
	AstNode* node = self.make_node(AST_BINARY);
	node.binary.left = l;
	node.binary.op = op;
	node.binary.right = r;
	return node;
}

fn AstNode* YadgParser.new_unary(&self, AstNode* op, AstNode* right) @private
{
	AstNode* node = self.make_node(AST_UNARY);
	node.unary.op = op;
	node.unary.right = right;
	return node;
}

fn AstNode* YadgParser.new_literal(&self, Token* t) @private
{
	AstNode* node = self.make_node(AST_LITERAL);
	node.literal = t;
	return node;
}

fn AstNode* YadgParser.new_token(&self, Token* t) @private
{
	AstNode* node = self.make_node(AST_TOKEN);
	node.literal = t;
	return node;
}

fn AstNode* YadgParser.new_single_entry_paren(&self, AstNode* entry) @private
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	node.ast_list.push(entry);
	return node;
}

fn AstNode* YadgParser.new_call(&self, AstNode* call, AstNode* trailing) @private
{
	AstNode* node = self.make_node(AST_CALL);
	node.unary.op = call;
	node.unary.right = trailing;
	return node;
}

fn AstNode* YadgParser.new_lambda(&self, AstNode* maybe_opt_type, AstNode* fn_param_list, AstNode* opt_attributes) @private
{
	AstNode* node = self.make_node(AST_LAMBDA);
	node.lambda.maybe_opt_type = maybe_opt_type;
	node.lambda.fn_param_list = fn_param_list;
	node.lambda.opt_attributes = opt_attributes;
	return node;
}

fn AstNode* YadgParser.new_ternary(&self, AstNode* condition, AstNode* consequent, AstNode* alternative) @private
{
	AstNode* node = self.make_node(AST_TERNARY);
	node.ternary.condition = condition;
	node.ternary.consequent = consequent;
	node.ternary.alternative = alternative;
	return node;
}

alias OpFn = fn bool(TokenType);
alias ExprFn = fn AstNode*?(YadgParser*);
macro AstNode*? YadgParser.eval_binary_expr(&self, OpFn is_op, ExprFn eval) @private
{
	AstNode* left, right;
	Token* op;
	defer catch {
		free_ast(left);
		free_tok(op);
		free_ast(right);
	}
	left = eval(self)!;
	while (is_op(self.peek()))
	{
		op = self.advance()!;
		right = eval(self)!;
		left = self.new_binary(left, op, right);
	}
	return left;
}

fn AstNode*? YadgParser.expr(&self)
	=> self.assignment_expr()!;

fn AstNode*? YadgParser.assignment_expr(&self)
	=> self.eval_binary_expr(&assignment_op, &YadgParser.ternary_expr);

fn AstNode*? YadgParser.constant_expr(&self) @inline => self.ternary_expr();

fn AstNode*? YadgParser.ternary_expr(&self)
{
	AstNode* expr = self.suffix_expr()!;

	AstNode* consequent, alternative;
	defer catch {
		free_ast(expr);
		free_ast(consequent);
		free_ast(alternative);
	}

	switch (self.peek())
	{
		case CT_TERNARY:
		case QUESTION:
			self.advance()!.free();
			consequent = self.expr()!;
			if (!self.expect(COLON)!)
			{
				self.report_error("ternary_expr: expected COLON");
				return INVALID_AST?;
			}
			alternative = self.ternary_expr()!;
			return self.new_ternary(expr, consequent, alternative);
		case ELVIS:
		case OPTELSE:
			self.advance()!.free(); // Consume ELVIS, OPTELSE
			alternative = self.ternary_expr()!;
			return self.new_ternary(expr, null, alternative);
		case FUNC:
			AstNode* lambda = self.lambda_decl()!;
			self.macro_func_body()!; // Discards the implied body
			return lambda;
		default:
			return expr;
	}
}

fn AstNode*? YadgParser.suffix_expr(&self)
{
	// TODO: handle terminal '?' / '?!'
	return self.or_expr()!;
}

fn AstNode*? YadgParser.or_expr(&self)
	=> self.eval_binary_expr(&or_op, &YadgParser.and_expr);

fn AstNode*? YadgParser.and_expr(&self)
	=> self.eval_binary_expr(&and_op, &YadgParser.relational_expr);

fn AstNode*? YadgParser.relational_expr(&self)
	=> self.eval_binary_expr(&relational_op, &YadgParser.additive_expr);

fn AstNode*? YadgParser.additive_expr(&self)
	=> self.eval_binary_expr(&additive_op, &YadgParser.bit_expr);

fn AstNode*? YadgParser.bit_expr(&self)
	=> self.eval_binary_expr(&bit_op, &YadgParser.shift_expr);

fn AstNode*? YadgParser.shift_expr(&self)
	=> self.eval_binary_expr(&shift_op, &YadgParser.mult_expr);

fn AstNode*? YadgParser.mult_expr(&self)
	=> self.eval_binary_expr(&mult_op, &YadgParser.unary_expr);

fn AstNode*? YadgParser.unary_expr(&self)
{
	if (unary_op(self.peek()))
	{
		Token *tok;
		AstNode*? op;
		if (self.peek() == LPAREN)
		{
			tok = self.advance()!; // Consume '('
			// TODO: Hackish. Better way to see if it is a type?
			op = self.type();
			if (catch op)
			{
				self.push_back(tok);
				return self.call_expr()!;
			}
			if (!self.expect(RPAREN)!)
			{
				// Oops. We have a type but it's not done yet
				// Now we rewind to '(' and call base_expr()

				while (op.tok_list.len()) self.push_back(op.tok_list.pop()!!);
				self.push_back(tok); // Pushback '('
				free_ast(op);
				return self.call_expr();
			}
		}
		else
		{
			op = self.new_token(self.advance()!);
		}
		return self.new_unary(op, self.unary_expr()!);
	}
	return self.call_expr()!;

}

fn AstNode*? YadgParser.call_expr(&self)
{
	AstNode* call = self.primary_expr()!;
	defer catch free_ast(call);
	while CALL_EXPR: (is_call_trailing(self.peek()))
	{
		AstNode* trailing = self.call_trailing()!;
		call = self.new_call(call, trailing);
	}
	return call;
}

fn bool is_call_trailing(TokenType type)
{
	switch (type)
	{
		case LPAREN:
		case DOT:
		case BRACK: // '[' range_loc ']' / '[' range_expr ']'
		case INC_OP:
		case DEC_OP:
		case BANG:
		case BANGBANG:
			return true;
		default:
			return false;
	}
}

<*
 Return a call trailing node or null if no call trailing is found.
*>
fn AstNode*? YadgParser.call_trailing(&self)
{
	switch (self.peek())
	{
		case LPAREN:
			//  call_invocation opt_compound_statement
			// call_invocation : '(' call_arg_list ')' call_inline_attributes

			// call_arg_list
			self.advance()!.free(); // Consume '('
			AstNode* op = self.call_arg_list()!;
			if (!self.expect(RPAREN)!)
			{
				self.report_error("call_trailing: expected RPAREN");
				return INVALID_AST?;
			}

			// call_inline_attributes
			while (self.peek() != EOF && self.peek() == AT_IDENT)
			{
				op = self.new_unary(op, self.new_token(self.advance()!));
			}

			// opt_compound_statement
			if (self.peek() == BRACE)
			{
				op = self.new_unary(op, self.new_token(self.advance()!));
			}
			return op;

		case DOT:
			// '.' access_ident
			AstNode* op = self.new_token(self.advance()!); // Consume '.'
			return self.new_unary(op, self.access_ident()!);

		case BRACK: // '[' range_loc ']'
		case INC_OP:
		case DEC_OP:
		case BANG:
		case BANGBANG:
			return self.new_token(self.advance()!);
		default:
			self.report_error("call_trailing: unhandled token");
			unreachable("call_trailing: unhandled token");
	}
}

fn AstNode*? YadgParser.access_ident(&self)
{
	switch (self.peek())
	{
		case CT_EVAL:
			// CT_EVAL '(' expr ')'
			AstNode* op = self.new_token(self.advance()!); // Consume CT_EVAL
			defer catch free_ast(op);
			if (!self.expect(LPAREN)!)
			{
				self.report_error("access_ident: expected LPAREN");
				return INVALID_AST?;
			}
			op = self.new_unary(op, self.expr()!);
			if (!self.expect(RPAREN)!)
			{
				self.report_error("access_ident: expected RPAREN");
				return INVALID_AST?;
			}
			return op;
		case IDENT:
		case AT_IDENT:
		case HASH_IDENT:
		case TYPEID:
			return self.new_token(self.advance()!);
		default:
			self.report_error("access_ident: unknown token");
			return INVALID_AST?;
	}
}

<*
 Returns null when no match found.
*>
fn AstNode*? YadgParser.primary_expr(&self)
{
	// initializer_list
	if (self.peek() == BRACE) return self.new_token(self.advance()!);
	// base_expr
	AstNode *expr = self.base_expr()!;
	// generic_expr
	if (self.peek() == BRACE)
	{
		// TODO: Handle/store generic parameters, we discard it for now
		self.advance()!.free();
	}
	return expr;
}

<*
@require type == STRING || type == BYTES
*>
fn AstNode*? YadgParser.rollup_token(&self, TokenType type) => @pool()
{
	Token* tok = self.advance()!;
	assert(tok.type == type);

	DString buf = dstring::temp(tok.text);
	while (self.peek() == type)
	{
		Token* next = self.advance()!;
		buf.append_chars(next.text);
		next.free();
	}
	tok.text.free(tok.allocator);
	tok.text = buf.copy_str(tok.allocator);
	return self.new_literal(tok);
}

fn AstNode*? YadgParser.base_expr(&self)
{
       switch (self.peek())
       {
               case STRING:
               case BYTES:
                       return self.rollup_token(self.peek());
               case NUMBER:
               case NUL:
               case TRUE:
               case FALSE:
                       return self.new_literal(self.advance()!);
               default:
                       // base_expr_assignable
                       switch (self.peek())
                       {
                               // ident_expr
                               case IDENT:
			       		AstNode* path = self.path()!;
					if (self.peek() == CONST_IDENT || self.peek() == AT_IDENT)
					{
						path.tok_list.push(self.advance()!);
					}
					return path;

                               case CONST_IDENT:
                               case AT_IDENT:
                               case CT_IDENT:
                               case HASH_IDENT:
                                       return self.new_token(self.advance()!);

			       case LPAREN:
			       		// '(' expr ')'
					self.expect(LPAREN)!;
					AstNode* e = self.expr()!;
					self.expect(RPAREN)!;
					return self.new_single_entry_paren(e);

				case BUILTIN:
					self.advance()!.free();
					switch (self.peek())
					{
						case CONST_IDENT:
						case IDENT:
							return self._builtin(self.new_token(self.advance()!));
						default:
							self.report_error("base_expr: invalid BUILTIN token");
							return INVALID_AST?;
					}

				// TODO: Handle the remaining CT tokens

				case CT_DEFINED:
					AstNode *ct = self.new_token(self.advance()!);
					defer catch free_ast(ct);
					if (!self.expect(LPAREN)!)
					{
						self.report_error("base_expr: expected LPAREN after CT_DEFINED");
						return INVALID_AST?;
					}
					AstNode *paren = self.arg_list()!;
					defer catch free_ast(paren);
					if (!self.expect(RPAREN)!)
					{
						self.report_error("base_expr: expected RPAREN after parsing CT_DEFINED");
						return INVALID_AST?;
					}
					return self.new_unary(ct, paren); // TODO: is unary the right "structure"?

                         	case CT_VACOUNT:
                                       return self.new_token(self.advance()!);

				case CT_FEATURE:
					AstNode *ct = self.new_token(self.advance()!);
					defer catch free_ast(ct);
					if (!self.expect(LPAREN)!)
					{
						self.report_error("base_expr: expected LPAREN after CT_FEATURE");
						return INVALID_AST?;
					}
					if (self.peek() != CONST_IDENT)
					{
						self.report_error("base_expr: expected CONST_IDENT after CT_FEATURE");
						return INVALID_AST?;
					}
					AstNode *const_ident = self.new_single_entry_paren(self.new_token(self.advance()!));
					defer catch free_ast(const_ident);
					if (!self.expect(RPAREN)!)
					{
						self.report_error("base_expr: expected RPAREN after parsing CT_FEATURE");
						return INVALID_AST?;
					}
					return self.new_unary(ct, const_ident); // TODO: is unary the right "structure"?

				// lambda_decl compount_statement
				case FUNC:
					AstNode* call = self.lambda_decl()!;
					defer catch free_ast(call);
					if (!self.expect(BRACE)!)
					{
						self.report_error("base_expr: expected '{'");
						return INVALID_AST?;
					}
					return self.new_call(call, self.new_token(self.advance()!));

                               default:
			       		// type '.' access_ident
			       		// type '.' CONST_IDENT
			       		AstNode* type = self.type() ?? null;
					if (!type)
					{
						self.report_error("base_expr: failed to read a type");
						return INVALID_AST?;
					}
					if (!self.expect(DOT)!)
					{
						self.report_error("base_expr: expected DOT");
						return INVALID_AST?;
					}
					if (self.peek() == CONST_IDENT)
					{
						return self.new_unary(type, self.new_token(self.advance()!));
					}
					return self.new_unary(type, self.access_ident()!);
                       }
       }
}

<*
lambda_decl
	: FN maybe_optional_type fn_parameter_list opt_attributes
	;

maybe_optional_type
	: optional_type
	| empty
	;

*>
fn AstNode*? YadgParser.lambda_decl(&self)
{
	if (!self.expect(FUNC)!)
	{
		self.report_error("lambda_decl: expected FUNC token");
		return INVALID_AST?;
	}

	AstNode* maybe_opt_type;
	AstNode* fn_parameter_list;
	AstNode* opt_attributes;

	defer catch {
		free_ast(maybe_opt_type);
		free_ast(fn_parameter_list);
		free_ast(opt_attributes);
	};

	// maybe_optional_type
	maybe_opt_type = self.optional_type() ?? null;
	fn_parameter_list = self.fn_parameter_list()!;
	opt_attributes = self.opt_attributes()!;

	return self.new_lambda(maybe_opt_type, fn_parameter_list, opt_attributes);
}

