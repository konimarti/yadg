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
		struct fault_declaration
		{
			AstList faults;
		}
		struct faults
		{
			Token   const_ident;
			AstList opt_attributes;
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
		if (top_level)
		{
			node.translation_unit.top_level_stmts.push(top_level);
		}
	}

	return node;
}

fn AstNode*? YadgParser.top_level(&self)
{
	Token tok_comm, tok_ext;
	AstNode *tl;

	if (try c = self.comment())
	{
		tok_comm = c;
	}

	if (self.peek().type == EXTERN)
	{
		tok_ext = self.advance()!;
	}

	while LOOP: (self.peek().type != EOF && tl == null)
	{
		switch(self.peek().type)
		{
			case MODULE:   tl = self._module()!;
			case FAULTDEF: tl = self.fault_declaration()!;
			// case ALIAS:    node.top_level.decl = self.alias_stmt()!;
			// case TYPEDEF:  node.top_level.decl = self.alias_stmt()!;
			// case FUNC:     node.top_level.decl = self.call()!;
			// case MACRO:    node.top_level.decl = self.call()!;
			// case CONST:
			// case ENUM:
			// case BITSTRUCT:
			// case STRUCT:
			default: self.synchronize()!; continue;
		}
	}

	if (!tl) return null;

	AstNode* node = allocator::new(self.allocator, AstNode);
	node.type = AST_TOP_LEVEL;
	node.top_level.decl = tl;
	node.top_level.comment = tok_comm;
	node.top_level.opt_extern = tok_ext;
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

	self.opt_attributes(&node._module.opt_attributes)!;

	if (!self.expect(SEMICOLON)!)
	{
		self.report_error("_module: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

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
