module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST, INVALID_TYPE;

enum AstType
{
	AST_TRANSLATION_UNIT,
	AST_TOP_LEVEL,
	AST_MODULE,
	AST_ATTRIBUTE,
	AST_FAULT_DECLARATION,
	AST_FAULTS,
	AST_STRUCT_DECLARATION,
	AST_ENUM_DECLARATION,
	AST_ENUM_SPEC,
	AST_BITSTRUCT_DECLARATION,
	AST_INTERFACE_DECLARATION,
	AST_INTERFACE_DECLARATION_NAME,
	AST_INLINE,
	AST_EXTERN,
	AST_CONST,
	AST_FUNC_DEFINITION,
	AST_FUNC_HEADER,
	AST_MACRO_DECLARATION,
	AST_DISTINCT_DECLARATION,

	// NEW
	AST_FUNC_TYPEDEF,
	AST_ALIAS_DEFINE_IDENT,
	AST_ALIAS_TYPE_IDENT,
	AST_ATTRIBUTE_DEF,

	AST_TYPE, // TokenList list
	AST_PATH, // TokenList list
	AST_OPT_ATTRIBUTES, // AstList alist
}

alias AstList = List{ AstNode* };
alias TokenList = List{ Token* };

struct AstNode (Printable)
{
	AstType type;
	union
	{
		struct translation_unit
		{
			AstList top_level_stmts;
		}
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
			Token* attribute_name;
			Token* attribute_param;
		}
		struct fault_declaration
		{
			AstList faults;
		}
		struct faults
		{
			Token*   const_ident;
			AstNode* opt_attributes;
		}
		struct struct_declaration
		{
			Token*   type_ident;
			Token*   opt_interface_impl; // paren
			AstNode* opt_attributes;
			Token*   struct_body; // brace
		}
		struct enum_declaration
		{
			Token*   type_ident;
			Token*   opt_interface_impl; // paren
			AstNode* enum_spec;
			AstNode* opt_attributes;
			Token*   enum_list; // brace
		}
		struct enum_spec
		{
			AstNode* base_type_no_generics; // base_type_no_user_defined / TYPE_IDENT / { IDENT SCOPE } TYPE_IDENT
			Token*   enum_params; // paren
		}
		struct bitstruct_declaration
		{
			Token*   type_ident;
			Token*   opt_interface_impl; // paren
			AstNode* type_no_generics; // base_type_no_generics / type_no_generics type_suffix
			AstNode* opt_attributes;
			Token*   bitstruct_body; // brace
		}
		struct interface_declaration
		{
			AstNode*  interface_declaration_name;
			Token*    interface_body; // brace
		}
		struct interface_declaration_name
		{
			Token*    type_ident;
			TokenList interface_parents;
		}
		struct distinct_declaration
		{
			Token*   type_ident;
			Token*   opt_interface_impl; // paren
			AstNode* opt_attributes;
			bool     opt_inline;
			AstNode* type;
		}
		struct func_definition
		{
			AstNode* func_header;
			Token*   fn_parameter_list; // paren
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
			Token*   fn_parameter_list; // paren
		}
		struct macro_declaration
		{
			AstNode* macro_header;
			Token*   macro_params; // paren
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
			Token*   opt_parameters;	// paren
			AstNode* opt_attributes;
			AstList  attribute_comma_list; 	// comma is optional
		}

		AstNode*  child; // inline, extern
		TokenList list;  // type, optional_type
		AstList   alist; // opt_attributes
	}
}

fn AstNode* YadgParser.make_node(&self, AstType type)
{
	AstNode *node = allocator::new(self.allocator, AstNode);
	node.type = type;
	self.nodes.push(node);
	return node;
}

fn void free_tok(Token* tok)
{
	if (tok) tok.free();
}
fn void free_ast(AstNode* n)
{
	if (n) n.free();
}
fn void free_tok_list(TokenList* l)
{
	foreach (n : l) free_tok(n);
	l.free();
}
fn void free_ast_list(AstList* l)
{
	foreach (n : l) free_ast(n);
	l.free();
}

fn void AstNode.free(&self)
{
	switch (self.type)
	{
		case AST_TRANSLATION_UNIT:
			free_ast_list(&self.translation_unit.top_level_stmts);

		case AST_TOP_LEVEL:
			free_tok(self.top_level.comment);
			free_ast(self.top_level.decl);

		case AST_MODULE:
			free_ast(self._module.path_ident);
			free_tok(self._module.module_params);
			free_ast(self._module.opt_attributes);

		case AST_ATTRIBUTE:
			free_tok(self._attribute.attribute_name);
			free_tok(self._attribute.attribute_param);

		case AST_FAULT_DECLARATION:
			free_ast_list(&self.translation_unit.top_level_stmts);

		case AST_FAULTS:
			free_tok(self.faults.const_ident);
			free_ast(self.faults.opt_attributes);

		case AST_STRUCT_DECLARATION:
			free_tok(self.struct_declaration.type_ident);
			free_tok(self.struct_declaration.opt_interface_impl);
			free_ast(self.struct_declaration.opt_attributes);
			free_tok(self.struct_declaration.struct_body);

		case AST_ENUM_DECLARATION:
			free_tok(self.enum_declaration.type_ident);
			free_tok(self.enum_declaration.opt_interface_impl);
			free_ast(self.enum_declaration.enum_spec);
			free_ast(self.enum_declaration.opt_attributes);
			free_tok(self.enum_declaration.enum_list);

		case AST_ENUM_SPEC:
			free_ast(self.enum_spec.base_type_no_generics);
			free_tok(self.enum_spec.enum_params);

		case AST_BITSTRUCT_DECLARATION:
			free_tok(self.bitstruct_declaration.type_ident);
			free_tok(self.bitstruct_declaration.opt_interface_impl);
			free_ast(self.bitstruct_declaration.type_no_generics);
			free_ast(self.bitstruct_declaration.opt_attributes);
			free_tok(self.bitstruct_declaration.bitstruct_body);

		case AST_INTERFACE_DECLARATION:
			free_ast(self.interface_declaration.interface_declaration_name);
			free_tok(self.interface_declaration.interface_body);

		case AST_INTERFACE_DECLARATION_NAME:
			free_tok(self.interface_declaration_name.type_ident);
			free_tok_list(&self.interface_declaration_name.interface_parents);

		case AST_DISTINCT_DECLARATION:
			free_tok(self.distinct_declaration.type_ident);
			free_tok(self.distinct_declaration.opt_interface_impl);
			free_ast(self.distinct_declaration.opt_attributes);
			free_ast(self.distinct_declaration.type);

		case AST_FUNC_DEFINITION:
			free_ast(self.func_definition.func_header);
			free_tok(self.func_definition.fn_parameter_list);
			free_ast(self.func_definition.opt_attributes);

		case AST_FUNC_HEADER:
			free_ast(self.func_header.optional_type);
			free_ast(self.func_header.type);
			free_tok(self.func_header.func_macro_name);

		case AST_MACRO_DECLARATION:
			free_ast(self.macro_declaration.macro_header);
			free_tok(self.macro_declaration.macro_params);
			free_ast(self.macro_declaration.opt_attributes);

		case AST_FUNC_TYPEDEF:
			free_ast(self.func_typedef.optional_type);
			free_tok(self.func_typedef.fn_parameter_list);

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
			free_tok(self.attr_def.opt_parameters);
			free_ast(self.attr_def.opt_attributes);
			free_ast_list(&self.attr_def.attribute_comma_list);

		case AST_INLINE:
		case AST_EXTERN:
		case AST_CONST:
			free_ast(self.child);

		case AST_TYPE:
		case AST_PATH:
			free_tok_list(&self.list);

		case AST_OPT_ATTRIBUTES:
			free_ast_list(&self.alist);

	}
}

fn AstNode*? YadgParser.translation_unit(&self)
{
	AstNode* node = self.make_node(AST_TRANSLATION_UNIT);
	node.translation_unit.top_level_stmts.init(self.allocator);

	AstNode* top_level;
	while (!self.expect(EOF)!)
	{
		top_level = self.top_level()!;
		if (top_level)
		{
			node.translation_unit.top_level_stmts.push(top_level);
		}
	}

	return node;
}

fn AstNode*? YadgParser.top_level(&self)
{
	Token* tok_comm;
	AstNode *tl;

	if (try c = self.comment())
	{
		tok_comm = c;
	}

	if (self.expect(EXTERN)!)
	{
		return self._extern(self.top_level()!);
	}

	while LOOP: (self.peek() != EOF && tl == null)
	{
		switch(self.peek())
		{
			case MODULE:    tl = self._module()!;
			case FAULTDEF:  tl = self.fault_declaration()!;
			case UNION:
			case STRUCT:    tl = self.struct_declaration()!;
			case ENUM:      tl = self.enum_declaration()!;
			case BITSTRUCT: tl = self.bitstruct_declaration()!;
			case INTERFACE: tl = self.interface_declaration()!;
			case FUNC:      tl = self.func_definition()!;
			case MACRO:     tl = self.macro_declaration()!;
			case TYPEDEF:   tl = self.distinct_declaration()!;
			case ATTRDEF:
			case ALIAS:     tl = self.define_declaration()!;
			// case CONST:
			default: self.synchronize()!; return self.top_level()!;
		}
	}

	if (!tl) return null;

	AstNode* node = self.make_node(AST_TOP_LEVEL);
	node.top_level.decl = tl;
	node.top_level.comment = tok_comm;
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
				break; // switch
			case CONTRACT:
				comment = self.advance()!;
				continue;
			default:
				break LOOP;
		}
		self.advance()!;
	}

	Token* next = self.advance()!;
	defer self.push_back(next);
	if (comment && comment.type != CONTRACT && next.range.start.ln - comment.range.end.ln > 1)
	{
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
*>
fn AstNode*? YadgParser.path(&self, TokenType path_type = IDENT)
{
	AstNode* node = self.make_node(AST_PATH);
	node.list.init(self.allocator);
	defer catch node.list.free();

	// path_ident
	while (self.peek() != EOF && self.peek() == path_type)
	{
		node.list.push(self.advance()!);
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
fn AstNode*? YadgParser.path_ident(&self) => self.path(IDENT);

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

*>
fn AstNode*? YadgParser.opt_attributes(&self)
{
	AstNode* node = self.make_node(AST_OPT_ATTRIBUTES);
	node.alist.init(self.allocator);

	defer catch node.alist.free();

	AstNode *ptr;
	while ((ptr = self._attribute()!) && ptr) node.alist.push(ptr);

	return node;
}

<*
 Returns an Attribute node or null if no attribute was found.
 FIXME: Handle 'path AT_TYPE_IDENT'

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
	if (self.peek() != AT_IDENT && self.peek() != AT_TYPE_IDENT)
	{
		return null;
	}

	Token* name = self.advance()!;

	Token* param;
	if (self.peek() == PAREN)
	{
		param = self.advance()!;
	}

	AstNode* node = self.make_node(AST_ATTRIBUTE);
	node._attribute.attribute_name = name;
	node._attribute.attribute_param = param;
	return node;
}

fn AstNode*? YadgParser.fault_declaration(&self)
{
	if (!self.expect(FAULTDEF)!)
	{
		self.report_error("fault_declaration: expected a 'FAULTDEF' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_FAULT_DECLARATION);
	node.fault_declaration.faults.init(self.allocator);
	defer catch node.fault_declaration.faults.free();

	AstNode *ptr;
	while ((ptr = self.faults()!) && ptr)
	{
		node.fault_declaration.faults.push(ptr);
		if (!self.expect(COMMA)!) break;
	}

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("fault_declaration: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

<*
 Returns an Faults node or null if no attribute was found.
*>
fn AstNode*? YadgParser.faults(&self)
{
	(void)self.comment();

	if (self.peek() != CONST_IDENT) return null;

	AstNode* node = self.make_node(AST_FAULTS);
	node.faults.const_ident = self.advance()!;
	defer catch node.faults.opt_attributes.free();

	node.faults.opt_attributes = self.opt_attributes()!;

	return node;
}

fn AstNode*? YadgParser.struct_declaration(&self)
{
	if (!self.expect(STRUCT)! && !self.expect(UNION)!)
	{
		self.report_error("struct_declaration: expected a 'STRUCT' or 'UNION' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("struct_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_STRUCT_DECLARATION);
	defer catch node.struct_declaration.opt_attributes.free();

	node.struct_declaration.type_ident = self.advance()!;

	if (self.peek() == PAREN)
	{
		node.struct_declaration.opt_interface_impl = self.advance()!;
	}

	node.struct_declaration.opt_attributes = self.opt_attributes()!;

	if (self.peek() != BRACE)
	{
		self.report_error("struct_declaration: expected the struct body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.struct_declaration.struct_body = self.advance()!;

	return node;
}

<*
enum_declaration
	: ENUM TYPE_IDENT opt_interface_impl enum_spec opt_attributes '{' enum_list '}'
	| ENUM TYPE_IDENT opt_interface_impl opt_attributes '{' enum_list '}'
	;
*>
fn AstNode*? YadgParser.enum_declaration(&self)
{
	if (!self.expect(ENUM)!)
	{
		self.report_error("enum_declaration: expected a 'ENUM' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("enum_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_ENUM_DECLARATION);
	defer catch node.enum_declaration.opt_attributes.free();

	// TYPE_IDENT
	node.enum_declaration.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek() == PAREN)
	{
		node.enum_declaration.opt_interface_impl = self.advance()!;
	}

	// enum_spec
	if (self.expect(COLON)!)
	{
		node.enum_declaration.enum_spec = self.enum_spec()!;
	}

	node.enum_declaration.opt_attributes = self.opt_attributes()!;

	if (self.peek() != BRACE)
	{
		self.report_error("enum_declaration: expected the enum_list (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.enum_declaration.enum_list = self.advance()!;

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
	defer catch node.enum_spec.base_type_no_generics.free();

	// base_type_no_generics
	node.enum_spec.base_type_no_generics = self.type(false, false)!;

	// enum_params
	if (self.peek() == PAREN)
	{
		node.enum_spec.enum_params = self.advance()!;
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
bitstruct_declaration
	: BITSTRUCT TYPE_IDENT opt_interface_impl ':' type_no_generics opt_attributes bitstruct_body
	;
*>
fn AstNode*? YadgParser.bitstruct_declaration(&self)
{
	if (!self.expect(BITSTRUCT)!)
	{
		self.report_error("bitstruct_declaration: expected a 'BITSTRUCT' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("bitstruct_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_BITSTRUCT_DECLARATION);
	defer catch {
		node.bitstruct_declaration.type_no_generics.free();
		node.bitstruct_declaration.opt_attributes.free();
	}

	// TYPE_IDENT
	node.bitstruct_declaration.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek() == PAREN)
	{
		node.bitstruct_declaration.opt_interface_impl = self.advance()!;
	}

	if (!self.expect(COLON)!)
	{
		self.report_error("bitstruct_declaration: expected a 'COLON' token");
		return INVALID_AST?;
	}

	// type_no_generics
	node.bitstruct_declaration.type_no_generics = self.type()!;

	node.bitstruct_declaration.opt_attributes = self.opt_attributes()!;

	if (self.peek() != BRACE)
	{
		self.report_error("bitstruct_declaration: expected the bitstruct_body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.bitstruct_declaration.bitstruct_body = self.advance()!;

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
fn AstNode*? YadgParser.type(&self, bool type_suffix = true, bool generic_params = false)
{
	AstNode* node = self.make_node(AST_TYPE);
	node.list.init(self.allocator);

	defer catch {
		while (node.list.len()) self.push_back(node.list.pop()!!);
		node.list.free();
	}

	//  base_type_no_generics
	TokenType tok_type = self.peek();
	switch
	{
		case is_base_type_no_generics(tok_type):
		case tok_type == TYPE_IDENT:
			node.list.push(self.advance()!);
			switch (tok_type)
			{
				case CT_TYPEOF:
				case CT_TYPEFROM:
				case CT_VATYPE:
				case CT_EVALTYPE:
					node.list.push(self.advance()!);
				default:
			}
		case tok_type == IDENT:
			// { IDENT SCOPE } TYPE_IDENT
			AstNode* path = self.path()!;
			foreach (ptok : path.list) node.list.push(ptok);
			path.free();
			if (self.peek() != TYPE_IDENT) return INVALID_TYPE?;
			node.list.push(self.advance()!);
		case tok_type == AT_IDENT:
			return INVALID_TYPE?;
	}

	//  opt_generics_param
	if (generic_params)
	{
		if (self.peek() == BRACE) node.list.push(self.advance()!);
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
					node.list.push(self.advance()!);
					continue;
				default:
					break TYPE_SUFFIX;
			}
		}
	}
	return node;
}

<*
optional_typnode
	: type
	| type '?'
	;
*>
fn AstNode*? YadgParser.optional_type(&self)
{
	AstNode *node = self.type(true, true)!;
	if (self.peek() == QUESTION)
	{
		node.list.push(self.advance()!);
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
	return self.type(true, true)!;
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
	defer catch allocator::free(self.allocator, node);

	node.func_typedef.optional_type = self.optional_type()!;

	if (self.peek() != PAREN)
	{
		self.report_error("func_type: expected a 'PAREN' token as fn_paramter_list");
		return INVALID_AST?;
	}
	node.func_typedef.fn_parameter_list = self.advance()!;

	return node;
}


<*
interface_declaration
	: INTERFACE interface_declaration_name '{' '}'
	| INTERFACE interface_declaration_name '{' interface_body '}'
	;
*>
fn AstNode*? YadgParser.interface_declaration(&self)
{
	if (!self.expect(INTERFACE)!)
	{
		self.report_error("interface_declaration: expected a 'INTERFACE' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_INTERFACE_DECLARATION);
	node.interface_declaration.interface_declaration_name = self.interface_declaration_name()!;
	defer catch allocator::free(self.allocator, node);

	if (self.peek() != BRACE)
	{
		self.report_error("interface_declaration: expected the interface_body (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.interface_declaration.interface_body = self.advance()!;

	return node;
}

<*
interface_declaration_name
	: TYPE_IDENT
	| TYPE_IDENT ':' interface_parents
	;

interface_parents
	: TYPE_IDENT
	| interface_parents ',' TYPE_IDENT
	;

*>
fn AstNode*? YadgParser.interface_declaration_name(&self)
{
	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("interface_declaration_name: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_INTERFACE_DECLARATION_NAME);
	node.interface_declaration_name.type_ident = self.advance()!;
	node.interface_declaration_name.interface_parents.init(self.allocator);
	defer catch {
		node.interface_declaration_name.interface_parents.free();
		allocator::free(self.allocator, node);
	}

	// interface_parents
	if (self.expect(COLON)!)
	{
		// interface_parents as TYPE_IDENT ','
		while (self.peek() != EOF && self.peek() == TYPE_IDENT)
		{
			node.interface_declaration_name.interface_parents.push(self.advance()!);
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
	defer catch {
		node.func_definition.opt_attributes.free();
		allocator::free(self.allocator, node);
	}

	node.func_definition.func_header = self.func_header()!;

	if (self.peek() != PAREN)
	{
		self.report_error("func_definition: expected 'fn_parameter_list' (a 'PAREN' token)");
		return INVALID_AST?;
	}
	node.func_definition.fn_parameter_list = self.advance()!;

	node.func_definition.opt_attributes = self.opt_attributes()!;

	// Handle 'macro_func_body'
	self.macro_func_body()!;

	return node;
}


fn AstNode*? YadgParser.func_header(&self)
{
	AstNode* node = self.make_node(AST_FUNC_HEADER);
	defer catch {
		node.func_header.optional_type.free();
		node.func_header.type.free();
		allocator::free(self.allocator, node);
	}

	// We can have two cases:
	// 	1.) mod::String? trim
	// 	2.) mod::String? mod::Struct.trim

	node.func_header.optional_type = self.optional_type()!;

	AstNode*? type = self.type(true, true);
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


fn AstNode*? YadgParser.macro_declaration(&self)
{
	if (!self.expect(MACRO)!)
	{
		self.report_error("macro_declaration: expected a 'MACRO' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_MACRO_DECLARATION);
	defer catch {
		node.macro_declaration.opt_attributes.free();
		allocator::free(self.allocator, node);
	}

	node.macro_declaration.macro_header = self.macro_header()!;

	if (self.peek() != PAREN)
	{
		self.report_error("macro_declaration: expected 'macro_params' (a 'PAREN' token)");
		return INVALID_AST?;
	}
	node.macro_declaration.macro_params = self.advance()!;

	node.macro_declaration.opt_attributes = self.opt_attributes()!;

	// Handle 'macro_func_body'
	self.macro_func_body()!;

	return node;
}

fn void? YadgParser.macro_func_body(&self)
{
	switch (self.peek())
	{
		case SEMICOLON: // macro_declaration_decl
		case BRACE:     // Regular func/macro body
			self.advance()!;
		case IMPLIES:
			while (self.peek() != EOF && self.peek() != SEMICOLON)
			{
				self.advance()!;
			}
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
	defer catch {
		node.func_header.optional_type.free();
		node.func_header.type.free();
		allocator::free(self.allocator, node);
	}

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

	AstNode*? type = self.type(true, true);
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
distinct_declaration
	: TYPEDEF TYPE_IDENT opt_interface_impl opt_attributes '=' opt_inline type ';'
	;
*>
fn AstNode*? YadgParser.distinct_declaration(&self)
{
	if (!self.expect(TYPEDEF)!)
	{
		self.report_error("distinct_declaration: expected a 'TYPEDEF' token");
		return INVALID_AST?;
	}

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("distinct_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = self.make_node(AST_DISTINCT_DECLARATION);
	defer catch {
		node.distinct_declaration.opt_attributes.free();
		node.distinct_declaration.type.free();
		allocator::free(self.allocator, node);
	}

	node.distinct_declaration.type_ident = self.advance()!;

	if (self.peek() == PAREN)
	{
		node.distinct_declaration.opt_interface_impl = self.advance()!;
	}

	node.distinct_declaration.opt_attributes = self.opt_attributes()!;

	if (!self.expect(ASSIGN)!)
	{
		self.report_error("distinct_declaration: expected a 'ASSIGN' token");
		return INVALID_AST?;
	}

	node.distinct_declaration.opt_inline = self.expect(INLINE)!;
	node.distinct_declaration.type = self.type(true, true)!;

	return node;
}

<*
define_declaration
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
fn AstNode*? YadgParser.define_declaration(&self)
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

				// ..

				return node;
			case TYPE_IDENT:
				// alias_type_ident
				AstNode* node = self.make_node(AST_ALIAS_TYPE_IDENT);

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
					self.report_error("attrdef: expected 'SEMICOLON'");
					return INVALID_AST?;
				}

				return node;
			default:
				self.report_error("define_declaration: invalid type after 'alias'");
				return INVALID_AST?;
		}

	} else if (self.expect(ATTRDEF)!)
	{
		if (self.peek() == AT_TYPE_IDENT)
		{
			// attr_def
			AstNode* node = self.make_node(AST_ATTRIBUTE_DEF);
			node.attr_def.attribute_comma_list.init(self.allocator);
			defer catch node.attr_def.attribute_comma_list.free();

			node.attr_def.at_type_ident = self.advance()!;
			if (self.peek() == PAREN)
			{
				node.attr_def.opt_parameters = self.advance()!;
			}
			node.attr_def.opt_attributes = self.opt_attributes()!;

			if (self.expect(ASSIGN)!)
			{
				AstNode *attr;
				while ((attr = self._attribute()!) && attr)
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
			self.report_error("define_declaration: expected 'AT_TYPE_IDENT' token after 'attrdef'");
			return INVALID_AST?;
		}
	}
	else
	{
		self.report_error("define_declaration: expected either an 'ALIAS' or 'ATTRDEF' token");
		return INVALID_AST?;
	}
}
