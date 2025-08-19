module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST;

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
}

alias AstList = List{ AstNode* };
alias TokenList = List{ Token };

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
			Token    comment;
			AstNode* decl;
		}
		struct _module
		{
			TokenList path_ident;
			Token     module_params;
			AstList   opt_attributes;
		}
		struct _attribute
		{
			Token attribute_name;
			Token attribute_param;
		}
		struct fault_declaration
		{
			AstList faults;
		}
		struct faults
		{
			Token   const_ident;
			AstList opt_attributes;
		}
		struct struct_declaration
		{
			Token   type_ident;
			Token   opt_interface_impl; // paren
			AstList opt_attributes;
			Token   struct_body; // brace
		}
		struct enum_declaration
		{
			Token    type_ident;
			Token    opt_interface_impl; // paren
			AstNode* enum_spec;
			AstList  opt_attributes;
			Token    enum_list; // brace
		}
		struct enum_spec
		{
			TokenList base_type_no_generics; // base_type_no_user_defined / TYPE_IDENT / { IDENT SCOPE } TYPE_IDENT
			Token     enum_params; // paren
		}
		struct bitstruct_declaration
		{
			Token     type_ident;
			Token     opt_interface_impl; // paren
			TokenList type_no_generics; // base_type_no_generics / type_no_generics type_suffix
			AstList   opt_attributes;
			Token     bitstruct_body; // brace
		}
		struct interface_declaration
		{
			AstNode*  interface_declaration_name;
			Token     interface_body; // brace
		}
		struct interface_declaration_name
		{
			Token     type_ident;
			TokenList interface_parents;
		}
		struct func_definition
		{
			AstNode* func_header;
			Token    fn_parameter_list; // paren
			AstList  opt_attributes;
		}
		struct func_header
		{
			TokenList optional_type;
			TokenList type;
			Token func_macro_name;
		}
		AstNode* child; // inline, extern
	}
}

fn AstNode*? YadgParser.translation_unit(&self)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_TRANSLATION_UNIT;
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
	Token tok_comm;
	AstNode *tl;

	if (try c = self.comment())
	{
		tok_comm = c;
	}

	if (self.expect(EXTERN)!)
	{
		return self._extern(self.top_level()!);
	}

	while LOOP: (self.peek().type != EOF && tl == null)
	{
		switch(self.peek().type)
		{
			case MODULE:    tl = self._module()!;
			case FAULTDEF:  tl = self.fault_declaration()!;
			case UNION:
			case STRUCT:    tl = self.struct_declaration()!;
			case ENUM:      tl = self.enum_declaration()!;
			case BITSTRUCT: tl = self.bitstruct_declaration()!;
			case INTERFACE: tl = self.interface_declaration()!;
			case FUNC:      tl = self.func_definition()!;
			// case ALIAS:    node.top_level.decl = self.alias_stmt()!;
			// case TYPEDEF:  node.top_level.decl = self.alias_stmt()!;
			// case MACRO:    node.top_level.decl = self.call()!;
			// case CONST:
			// case BITSTRUCT:
			default: self.synchronize()!; return self.top_level()!;
		}
	}

	if (!tl) return null;

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_TOP_LEVEL;
	node.top_level.decl = tl;
	node.top_level.comment = tok_comm;
	return node;
}

fn Token? YadgParser.comment(&self)
{
	Token comment, tok;
	while LOOP: (true)
	{
		tok = self.peek();
		switch(tok.type)
		{
			case LCOMMENT:
			case BCOMMENT:
				break; // switch
			case CONTRACT:
				comment = tok;
			default:
				break LOOP;
		}
		self.advance()!;
	}

	if (comment.type != CONTRACT && self.peek().range.start.ln - comment.range.end.ln > 1)
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

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_MODULE;
	node._module.path_ident.init(self.allocator);
	node._module.opt_attributes.init(self.allocator);

	// path_ident
	self.path_ident(&node._module.path_ident)!;

	if (self.peek().type == BRACE)
	{
		node._module.module_params = self.advance()!;
	}

	self.opt_attributes(&node._module.opt_attributes)!;

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
fn void? YadgParser.path(&self, TokenList *list)
{
	// path_ident
	while (self.peek().type != EOF && self.peek().type == IDENT)
	{
		list.push(self.advance()!);
		if (self.expect(SCOPE)!) continue;
	}
}

<*
path_ident
	: path IDENT
	| IDENT
	;
*>
fn void? YadgParser.path_ident(&self, TokenList *list) => self.path(list);

// opt_attributes
fn void? YadgParser.opt_attributes(&self, AstList *list)
{
	AstNode *ptr;
	while ((ptr = self._attribute()!) && ptr) list.push(ptr);
}

<*
 Returns an Attribute node or null if no attribute was found.
*>
fn AstNode*? YadgParser._attribute(&self)
{
	if (self.peek().type != AT_IDENT && self.peek().type != AT_TYPE_IDENT)
	{
		return null;
	}

	Token name = self.advance()!;

	Token param;
	if (self.peek().type == PAREN)
	{
		param = self.advance()!;
	}

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_ATTRIBUTE;
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

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_FAULT_DECLARATION;
	node.fault_declaration.faults.init(self.allocator);

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

	if (self.peek().type != CONST_IDENT) return null;

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_FAULTS;
	node.faults.const_ident = self.advance()!;

	(void)self.comment();

	node.faults.opt_attributes.init(self.allocator);
	self.opt_attributes(&node.faults.opt_attributes)!;

	(void)self.comment();

	return node;
}

fn AstNode*? YadgParser.struct_declaration(&self)
{
	if (!self.expect(STRUCT)! && !self.expect(UNION)!)
	{
		self.report_error("struct_declaration: expected a 'STRUCT' or 'UNION' token");
		return INVALID_AST?;
	}

	if (self.peek().type != TYPE_IDENT)
	{
		self.report_error("struct_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_STRUCT_DECLARATION;
	node.struct_declaration.opt_attributes.init(self.allocator);

	node.struct_declaration.type_ident = self.advance()!;

	if (self.peek().type == PAREN)
	{
		node.struct_declaration.opt_interface_impl = self.advance()!;
	}

	self.opt_attributes(&node.struct_declaration.opt_attributes)!;

	if (self.peek().type != BRACE)
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

	if (self.peek().type != TYPE_IDENT)
	{
		self.report_error("enum_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_ENUM_DECLARATION;
	node.enum_declaration.opt_attributes.init(self.allocator);
	defer catch { node.enum_declaration.opt_attributes.free(); allocator::free(self.allocator, node); }

	// TYPE_IDENT
	node.enum_declaration.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek().type == PAREN)
	{
		node.enum_declaration.opt_interface_impl = self.advance()!;
	}

	// enum_spec
	if (self.expect(COLON)!)
	{
		node.enum_declaration.enum_spec = self.enum_spec()!;
	}

	self.opt_attributes(&node.enum_declaration.opt_attributes)!;

	if (self.peek().type != BRACE)
	{
		self.report_error("enum_declaration: expected the enum_list (a 'BRACE' token)");
		return INVALID_AST?;
	}
	node.enum_declaration.enum_list = self.advance()!;

	return node;
}

fn AstNode* YadgParser._inline(&self, AstNode* child)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_INLINE;
	node.child = child;
	return node;
}

fn AstNode* YadgParser._extern(&self, AstNode* child)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_EXTERN;
	node.child = child;
	return node;
}

fn AstNode* YadgParser._const(&self, AstNode* child)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_CONST;
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

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_ENUM_SPEC;
	node.enum_spec.base_type_no_generics.init(self.allocator);
	defer catch { node.enum_spec.base_type_no_generics.free(); allocator::free(self.allocator, node); }

	// base_type_no_generics
	self.type(&node.enum_spec.base_type_no_generics, false, false)!;

	// enum_params
	if (self.peek().type == PAREN)
	{
		node.enum_spec.enum_params = self.advance()!;
	}

	return node;
}

fn bool is_base_type_no_generics(Token tok)
{
	switch (tok.type)
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

	if (self.peek().type != TYPE_IDENT)
	{
		self.report_error("bitstruct_declaration: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_BITSTRUCT_DECLARATION;
	node.bitstruct_declaration.type_no_generics.init(self.allocator);
	node.bitstruct_declaration.opt_attributes.init(self.allocator);
	defer catch {
		node.bitstruct_declaration.type_no_generics.free();
		node.bitstruct_declaration.opt_attributes.free();
		allocator::free(self.allocator, node);
	}

	// TYPE_IDENT
	node.bitstruct_declaration.type_ident = self.advance()!;

	// opt_interface_impl
	if (self.peek().type == PAREN)
	{
		node.bitstruct_declaration.opt_interface_impl = self.advance()!;
	}

	if (!self.expect(COLON)!)
	{
		self.report_error("bitstruct_declaration: expected a 'COLON' token");
		return INVALID_AST?;
	}

	// type_no_generics
	self.type(&node.bitstruct_declaration.type_no_generics)!;

	self.opt_attributes(&node.bitstruct_declaration.opt_attributes)!;

	if (self.peek().type != BRACE)
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

 @param [&inout] list : "Pointer to a TokenList"
*>
fn void? YadgParser.type(&self, TokenList* list, bool type_suffix = true, bool generic_params = false)
{
	//  base_type_no_generics
	Token tok = self.peek();
	switch
	{
		case is_base_type_no_generics(tok):
		case tok.type == TYPE_IDENT:
			list.push(self.advance()!);
			switch (tok.type)
			{
				case CT_TYPEOF:
				case CT_TYPEFROM:
				case CT_VATYPE:
				case CT_EVALTYPE:
					list.push(self.advance()!);
				default:
			}
		case tok.type == IDENT:
			// { IDENT SCOPE } TYPE_IDENT
			self.path(list)!;
			if (self.peek().type != TYPE_IDENT)
			{
				self.report_error("type: expected a 'TYPE_IDENT' token");
				return INVALID_AST?;
			}
			list.push(self.advance()!);
	}

	//  opt_generics_param
	if (generic_params)
	{
		if (self.peek().type == BRACE) list.push(self.advance()!);
	}

	//  type_suffix
	if (type_suffix)
	{
		while TYPE_SUFFIX: (self.peek().type != EOF)
		{
			switch (self.peek().type)
			{
				case STAR:
				case BRACK:
					list.push(self.advance()!);
					continue;
				default:
					break TYPE_SUFFIX;
			}
		}
	}
}

<*
optional_type
	: type
	| type '?'
	;
*>
fn void? YadgParser.optional_type(&self, TokenList* list)
{
	self.type(list, true, true)!;
	if (self.peek().type == QUESTION)
	{
		list.push(self.advance()!);
	}
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

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_INTERFACE_DECLARATION;
	node.interface_declaration.interface_declaration_name = self.interface_declaration_name()!;
	defer catch allocator::free(self.allocator, node);

	if (self.peek().type != BRACE)
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
	if (self.peek().type != TYPE_IDENT)
	{
		self.report_error("interface_declaration_name: expected a 'TYPE_IDENT' token");
		return INVALID_AST?;
	}

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_INTERFACE_DECLARATION_NAME;
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
		while (self.peek().type != EOF && self.peek().type == TYPE_IDENT)
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

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_FUNC_DEFINITION;
	node.func_definition.opt_attributes.init(self.allocator);
	defer catch {
		node.func_definition.opt_attributes.free();
		allocator::free(self.allocator, node);
	}

	node.func_definition.func_header = self.func_header()!;

	if (self.peek().type != PAREN)
	{
		self.report_error("func_definition: expected 'fn_parameter_list' (a 'PAREN' token)");
		return INVALID_AST?;
	}
	node.func_definition.fn_parameter_list = self.advance()!;

	self.opt_attributes(&node.func_definition.opt_attributes)!;

	// Handle 'macro_func_body'
	switch (self.peek().type)
	{
		case SEMICOLON: // func_definition_decl
		case BRACE:     // Regular func/macro body
			self.advance()!;
		case IMPLIES:
			while (self.peek().type != EOF && self.peek().type != SEMICOLON)
			{
				self.advance()!;
			}
		case EOF:
			break;
		default:
			self.report_error("func_definition: expected a macro/func body");
			return INVALID_AST?;
	}

	return node;
}


fn AstNode*? YadgParser.func_header(&self)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_FUNC_HEADER;
	node.func_header.optional_type.init(self.allocator);
	node.func_header.type.init(self.allocator);
	defer catch {
		node.func_header.optional_type.free();
		node.func_header.type.free();
		allocator::free(self.allocator, node);
	}
	self.optional_type(&node.func_header.optional_type)!;

	if (self.peek().type == IDENT || self.peek().type == AT_IDENT)
	{
		node.func_header.func_macro_name = self.advance()!;
		if (self.expect(SCOPE)!)
		{
			// Oops. We read a 'path'
			node.func_header.type.push(node.func_header.func_macro_name);
			self.type(&node.func_header.type, true, true)!;
		}
	}
	else
	{
		self.type(&node.func_header.type, true, true)!;
	}

	if (self.expect(DOT)!)
	{
		node.func_header.func_macro_name = self.advance()!;
	}

	return node;
}
