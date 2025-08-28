module yadg::parser;

import yadg::lexer;

<*

*>
fn AstNode*? YadgParser.attribute_param_list(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	while (self.peek() != EOF && self.peek() != RPAREN)
	{
		TokenType type = self.peek();
		switch
		{
			case type == BRACK:
				node.ast_list.push(self.new_token(self.advance()!));
				if (self.peek() == ASSIGN)
				{
					node.ast_list.push(self.new_token(self.advance()!));
				}
				continue;
			case type == AND:
				node.ast_list.push(self.new_token(self.advance()!));
				if (self.peek() == BRACK)
				{
					node.ast_list.push(self.new_token(self.advance()!));
				}
				continue;

			case assignment_op(type):
			case mult_op(type):
			case additive_op(type):
			case bit_op(type):
			case shift_op(type):
			case relational_op(type):
				node.ast_list.push(self.new_token(self.advance()!));
			default:
				node.ast_list.push(self.constant_expr()!);
		}
		if (!self.expect(COMMA)!) break;
	}

	return node;
}

<*
opt_interface_impl
	: '(' interfaces ')'
	| '(' ')'
	| empty
	;
*>
fn AstNode*? YadgParser.opt_interface_impl(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (!self.expect(LPAREN)!)
	{
		self.report_error("opt_interface_impl: expected 'LPAREN' token");
		return INVALID_AST?;
	}

	while (self.peek() != EOF && self.peek() != RPAREN && self.peek() == TYPE_IDENT)
	{
		node.ast_list.push(self._interface()!);
		if (self.expect(COMMA)!) continue;
	}

	if (!self.expect(RPAREN)!)
	{
		self.report_error("opt_interface_impl: expected 'RPAREN' token");
		return INVALID_AST?;
	}

	return node;
}

import std::io;
<*
interfaces
	: TYPE_IDENT opt_generic_parameters
	| interfaces ',' TYPE_IDENT opt_generic_parameters
	;
*>
fn AstNode*? YadgParser._interface(&self)
{
	AstNode* node = self.make_node(AST_INTERFACE);
	defer catch node.free();

	if (self.peek() != TYPE_IDENT)
	{
		self.report_error("interface: expected 'TYPE_IDENT' token");
		return INVALID_AST?;
	}
	node._interface.type_ident = self.advance()!;

	if (self.peek() == BRACE)
	{
		node._interface.opt_generic_parameters = self.advance()!;
	}

	return node;
}

<*
enum_params
	: enum_param_decl
	| enum_params ',' enum_param_decl

enum_param_decl
	: type IDENT
	| INLINE type IDENT
	;
*>
fn AstNode*? YadgParser.enum_params(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (!self.expect(LPAREN)!)
	{
		self.report_error("enum_params: expected 'LPAREN' token");
		return INVALID_AST?;
	}

	while (self.peek() != EOF && self.peek() != RPAREN)
	{
		node.ast_list.push(self.enum_param_decl()!);
		if (self.expect(COMMA)!) continue;
	}

	if (!self.expect(RPAREN)!)
	{
		self.report_error("enum_params: expected 'RPAREN' token");
		return INVALID_AST?;
	}

	return node;
}

<*
enum_param_decl
	: type IDENT
	| INLINE type IDENT
	;
*>
fn AstNode*? YadgParser.enum_param_decl(&self)
{
	AstNode* node = self.make_node(AST_ENUM_PARAM_DECL);
	defer catch node.free();

	if (self.expect(INLINE)!)
	{
		return self._inline(self.enum_param_decl()!);
	}
	node.enum_param_decl.type = self.type()!;
	if (self.peek() != IDENT)
	{
		self.report_error("enum_param_decl: expected 'IDENT' token");
		return INVALID_AST?;
	}
	node.enum_param_decl.ident = self.advance()!;
	return node;
}

<*
fn_parameter_list
	: '(' parameters ')'
	| '(' ')'
	;

parameters
	: parameter_default
	| parameters ',' parameter_default
	| parameters ','
	;

*>
fn AstNode*? YadgParser.fn_parameter_list(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (!self.expect(LPAREN)!)
	{
		self.report_error("fn_parameter_list: expected 'LPAREN' token");
		return INVALID_AST?;
	}

	node.ast_list.push(self.parameters()!);

	if (!self.expect(RPAREN)!)
	{
		self.report_error("fn_parameter_list: expected 'RPAREN' token");
		return INVALID_AST?;
	}

	return node;
}

<*
parameters
	: parameter_default
	| parameters ',' parameter_default
	| parameters ','
	;
*>
fn AstNode*? YadgParser.parameters(&self)
{
	AstNode* node = self.make_node(AST_LIST);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	while (self.peek() != EOF && self.peek() != RPAREN && self.peek() != SEMICOLON)
	{
		node.ast_list.push(self.parameter_default()!);
		if (self.expect(COMMA)!) continue;
	}

	return node;
}

<*
parameter_default
	: parameter
	| parameter '=' expr
	| parameter '=' type
	;

parameter
	: type IDENT opt_attributes
	| type ELLIPSIS IDENT opt_attributes
	| type ELLIPSIS CT_IDENT
	| type CT_IDENT
	| type ELLIPSIS opt_attributes
	| type HASH_IDENT opt_attributes
	| type '&' IDENT opt_attributes
	| type opt_attributes
	| '&' IDENT opt_attributes
	| HASH_IDENT opt_attributes
	| ELLIPSIS
	| IDENT opt_attributes
	| IDENT ELLIPSIS opt_attributes
	| CT_IDENT
	| CT_IDENT ELLIPSIS
	;

*>
fn AstNode*? YadgParser.parameter_default(&self)
{
	AstNode* node = self.make_node(AST_PARAMETER);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (try type = self.type())
	{
		node.ast_list.push(type);
	}

	switch (self.peek())
	{
		case COMMA:  return node;
		case RPAREN: return node;
		case AND:
			// '&' IDENT opt_attributes
			node.ast_list.push(self.new_token(self.advance()!));
			nextcase IDENT;
		case IDENT:
			// IDENT opt_attributes
			// IDENT ELLIPSIS opt_attributes
			node.ast_list.push(self.new_literal(self.advance()!));
			if (self.peek() == ELLIPSIS)
			{
				node.ast_list.push(self.new_token(self.advance()!));
			}
			node.ast_list.push(self.opt_attributes()!);

		case HASH_IDENT:
			// HASH_IDENT opt_attributes
			node.ast_list.push(self.new_literal(self.advance()!));
			node.ast_list.push(self.opt_attributes()!);
		case ELLIPSIS:
			node.ast_list.push(self.new_token(self.advance()!));
			if (self.peek() == IDENT)
			{
				node.ast_list.push(self.new_literal(self.advance()!));
				node.ast_list.push(self.opt_attributes()!);
			} else if (self.peek() == CT_IDENT)
			{
				node.ast_list.push(self.new_literal(self.advance()!));
			}
			node.ast_list.push(self.opt_attributes()!);
		case CT_IDENT:
			// CT_IDENT
			// CT_IDENT ELLIPSIS
			node.ast_list.push(self.new_literal(self.advance()!));
			if (self.peek() == ELLIPSIS)
			{
				node.ast_list.push(self.new_token(self.advance()!));
			}
		default:
			self.report_error("parameter_default: unknown token");
			return INVALID_AST?;
	}

	if (self.peek() == ASSIGN)
	{
		node.ast_list.push(self.new_token(self.advance()!)); // Consume '='

		// Now handle type or expr
		if (try type = self.type())
		{
			node.ast_list.push(type);
		}
		else
		{
			node.ast_list.push(self.expr()!);
		}
	}

	return node;
}

<*
macro_params
	: parameters
	| parameters ';' trailing_block_param
	| ';' trailing_block_param
	| empty
	;

trailing_block_param
	: AT_IDENT
	| AT_IDENT '(' ')'
	| AT_IDENT '(' parameters ')'
	;

*>
fn AstNode*? YadgParser.macro_params(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (!self.expect(LPAREN)!)
	{
		self.report_error("macro_params: expected 'LPAREN' token");
		return INVALID_AST?;
	}

	node.ast_list.push(self.parameters()!);

	// trailing_block_param
	if (self.expect(SEMICOLON)!)
	{
		if (self.peek() == AT_IDENT)
		{
			node.ast_list.push(self.new_literal(self.advance()!));
			if (self.expect(LPAREN)!)
			{
				node.ast_list.push(self.parameters()!);
				if (!self.expect(RPAREN)!)
				{
					self.report_error("macro_params: expected RPAREN after trailing_block_param");
					return INVALID_AST?;
				}
			}
		}
	}

	if (!self.expect(RPAREN)!)
	{
		self.report_error("macro_params: expected 'RPAREN' token");
		return INVALID_AST?;
	}

	return node;
}

<*
call_arg_list
	: opt_arg_list
	| opt_arg_list ';'
	| opt_arg_list ';' parameters

arg_list
	: arg
	| arg_list ',' arg
	| arg_list ','
	;
*>
fn AstNode*? YadgParser.call_arg_list(&self)
{
	AstNode* node = self.make_node(AST_PAREN);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	node.ast_list.push(self.arg_list()!);

	// ';' parameters
	if (self.expect(SEMICOLON)!)
	{
		node.ast_list.push(self.parameters()!);
	}

	return node;
}

<*
arg_list
	: arg
	| arg_list ',' arg
	| arg_list ','
	;

*>
fn AstNode*? YadgParser.arg_list(&self)
{
	AstNode* node = self.make_node(AST_LIST);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	while (self.peek() != EOF && self.peek() != RPAREN && self.peek() != SEMICOLON)
	{
		node.ast_list.push(self.arg()!);
		if (self.expect(COMMA)!) continue;
	}
	return node;
}


<*
arg
	: param_path '=' expr
	| param_path '=' type
	| param_path
	| arg_name ':' expr
	| arg_name ':' type
	| type
	| expr
	| CT_VASPLAT
	| CT_VASPLAT '[' range_expr ']'
	| ELLIPSIS expr
	;

arg_name
	: IDENT
	| CT_TYPE_IDENT
	| HASH_IDENT
	| CT_IDENT
	;

param_path
	: param_path_element
	| param_path param_path_element
	;

param_path_element
	: '[' expr ']'
	| '[' expr DOTDOT expr ']'
	| '.' primary_expr
	;
*>
fn AstNode*? YadgParser.arg(&self)
{
	AstNode* node = self.make_node(AST_ARG);
	node.ast_list.init(self.allocator);
	defer catch node.free();

	if (self.peek() == BRACK || self.peek() == DOT)
	{
		// param_path_element*
		while (self.peek() != EOF && (self.peek() == BRACK || self.peek() == DOT))
		{
			if (self.peek() == DOT)
			{
				// Handle '.' primary_expr
				node.ast_list.push(self.new_token(self.advance()!));
				node.ast_list.push(self.primary_expr()!);
			}
			else
			{
				node.ast_list.push(self.new_token(self.advance()!));
			}
		}
		if (self.peek() != ASSIGN)
		{
			return node;
		}
		node.ast_list.push(self.new_token(self.advance()!)); // Consume '='
		// Now read either an expr or type
	}
	else if (self.peek() == IDENT || self.peek() == CT_TYPE_IDENT || self.peek() == HASH_IDENT || self.peek() == CT_IDENT)
	{
		// arg_name
		Token* tok = self.advance()!;
		if (self.peek() == SCOPE)
		{
			// Opps. This looks like a path. Rewind.
			self.push_back(tok);
		}
		else
		{
			node.ast_list.push(self.new_token(tok));
			if (self.peek() != COLON)
			{
				self.report_error("arg: expected COLON after arg_name");
				return INVALID_AST?;
			}
			node.ast_list.push(self.new_token(self.advance()!)); // Consume ':'
		}
		// Now read either an expr or type
	}
	else if (self.peek() == CT_VASPLAT)
	{
		node.ast_list.push(self.new_token(self.advance()!));
		if (self.peek() == BRACK)
		{
			node.ast_list.push(self.new_token(self.advance()!));
		}
	}
	else if (self.peek() == ELLIPSIS)
	{
		node.ast_list.push(self.new_token(self.advance()!));
		node.ast_list.push(self.expr()!);
	}

	// Now handle type or expr
	if (try type = self.type())
	{
		node.ast_list.push(type);
	}
	else
	{
		node.ast_list.push(self.expr()!);
	}

	return node;
}
