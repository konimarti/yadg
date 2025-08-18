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

	// -- border --

	AST_STMT,
	AST_ALIAS,
	AST_CONST,
	AST_ENUM,
	AST_FAULTDEF,
	AST_CALL,
	AST_MACRO,
	AST_STRUCT,
	AST_TYPEDEF,

	AST_CALLEE,
	AST_TYPE,
	AST_BRACE,
	AST_PAREN,
	AST_COMMENT,
	AST_SCOPE
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
			Token    opt_extern;
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
		node.translation_unit.top_level_stmts.push(top_level);
	}

	return node;
}

fn AstNode*? YadgParser.top_level(&self)
{
	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_TOP_LEVEL;

	if (try c = self.comment())
	{
		node.top_level.comment = c;
	}

	if (self.peek().type == EXTERN)
	{
		node.top_level.opt_extern = self.advance()!;
	}

	while (self.peek().type != EOF)
	{
		switch(self.peek().type)
		{
			case MODULE:   node.top_level.decl = self._module()!;
			// case ALIAS:    node.top_level.decl = self.alias_stmt()!;
			// case TYPEDEF:  node.top_level.decl = self.alias_stmt()!;
			// case FUNC:     node.top_level.decl = self.call()!;
			// case FAULTDEF: node.top_level.decl = self.faultdef_stmt()!;
			// case MACRO:    node.top_level.decl = self.call()!;
			// case CONST:
			// case ENUM:
			// case BITSTRUCT:
			// case STRUCT:
			default: self.synchronize()!; continue;
		}
	}

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
	while (self.peek().type != EOF && self.peek().type == IDENT)
	{
		node._module.path_ident.push(self.advance()!);
		if (self.expect(SCOPE)!) continue;
	}

	if (self.peek().type == PAREN)
	{
		node._module.module_params = self.advance()!;
	}

	// opt_attributes
	AstNode *ptr;
	while ((ptr = self.opt_attributes()!) && ptr)
	{
		node._module.opt_attributes.push(ptr);
	}

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("_module: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

<*
 Returns an Attribute node or null if no attribute was found.
*>
fn AstNode*? YadgParser.opt_attributes(&self)
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


