module yadg::parser;

import yadg::lexer;
import std::collections::list;
import std::io;

faultdef INVALID_AST;

enum AstType
{
	AST_DOCUMENT,
	AST_STMT,

	AST_ALIAS,
	AST_CONST,
	AST_ENUM,
	AST_FAULTDEF,
	AST_CALL,
	AST_MACRO,
	AST_MODULE,
	AST_STRUCT,

	AST_ATTR,
	AST_CALLEE,
	AST_TYPE,
	AST_BRACE,
	AST_PAREN,
	AST_COMMENT,
	AST_SCOPE
}

alias AstList = List{ AstNode* };
alias StringList = List{ String };

struct AstNode (Printable)
{
	AstType type;
	union
	{
		struct document
		{
			AstList stmts;
		}
		// struct module_node
		// {
		// 	AstNode* comment;
		// 	AstNode* module_stmt;
		// }
		struct stmt
		{
			AstNode* comment;
			AstNode* node;
		}
		struct module_stmt
		{
			AstNode*  scope;
			AstList   attrs;
		}
		struct alias_node
		{
			AstNode* lvalue;
			AstList  attrs;
			AstNode* rvalue;
		}
		struct const_node
		{
			String   const_name;
			AstNode* type;
			AstList  attrs;
			AstList  expression;
		}
		struct enum_node
		{
			String   enum_name;
			AstList  attrs;
			AstNode* backing_type;
			AstNode* paren;
			AstNode* brace;
		}
		struct faultdef_node
		{
			StringList faults;
		}
		struct call
		{
			AstNode* type;
			AstNode* callee;
			AstNode* paren;
			AstList  attrs;
		}
		struct callee
		{
			String   receiver;
			String   call_name;
		}
		struct struct_node
		{
			String   struct_name;
			AstList  attrs;
			AstNode* backing_type;
			AstNode* paren;
			AstNode* brace;
			AstList  methods;
		}
		struct attr
		{
			String     name;
			AstNode*   paren;
		}
		struct comment
		{
			String str;
			usz    endln;
		}
		struct scope
		{
			String   scope_name;
			AstNode *next;
		}
		String str; // type, braces, paren, scope
	}
}

fn usz? AstNode.to_format(&self, Formatter* f) @dynamic
{
	usz n;
	if (self == null)
	{
		n += f.printf("AstNode[null]\n")!;
	}
	else
	{
		n += f.printf("AstNode[%d]\n", self.type)!;
	}
	// TODO: Later
        //
	// switch (self.type)
	// {
	// 	case AST_DOCUMENT:
	// 		foreach (child : self.document.modules) n += f.printf("%s\n", child)!;
        //
	// 	case AST_MODULE:
	// 		n += f.printf("## ")!;
	// 		foreach (i, path : self.mod.path)
	// 		{
	// 			n += f.printf("%s%s", (i > 0 ? "::" : ""), path)!;
	// 		}
	// 		foreach (attr : self.mod.attr)
	// 		{
	// 			n += f.printf(" %s", attr)!;
	// 		}
	// 		n += f.printf("\n\n")!;
	// 		if (self.comment.len) n += f.printf("%s\n", self.comment)!;
        //
	// 		foreach (global : self.mod.globals) io::printf("%s\n", global);
	// 		foreach (call : self.mod.calls) io::printf("%s\n", call);
	// 		foreach (block : self.mod.blocks) io::printf("%s\n", block);
        //
	// 	case AST_GLOBAL:
	// 		n += f.printf("### %s", self.glob.name)!;
	// 		n += f.printf("\n\n")!;
	// 		if (self.comment.len) n += f.printf("%s\n\n", self.comment)!;
	// 		n += f.printf("```\n")!;
	// 		foreach (i, decl : self.glob.decls)
	// 		{
	// 			n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
	// 		}
	// 		n += f.printf("\n")!;
	// 		n += f.printf("```\n")!;
	// 		foreach (method : self.glob.methods) io::printfn("\n%s", method);
        //
	// 	case AST_BLOCK:
	// 		n += f.printf("### %s", self.block.name)!;
	// 		n += f.printf("\n\n")!;
	// 		if (self.comment.len) n += f.printf("%s\n", self.comment)!;
	// 		n += f.printf("```\n")!;
	// 		foreach (i, decl : self.block.decls)
	// 		{
	// 			n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
	// 		}
	// 		n += f.printf("\n")!;
	// 		n += f.printf("%s", self.block.brace)!;
	// 		n += f.printf("\n")!;
	// 		n += f.printf("```\n")!;
	// 		foreach (method : self.block.methods) io::printfn("\n%s", method);
        //
	// 	case AST_CALL:
	// 		if (self.call.receiver.len)
	// 		{
	// 			n += f.printf("### %s.%s", self.call.receiver, self.call.name)!;
	// 		}
	// 		else
	// 		{
	// 			n += f.printf("### %s", self.call.name)!;
	// 		}
	// 		n += f.printf("\n\n")!;
	// 		if (self.comment.len) n += f.printf("%s\n", self.comment)!;
	// 		n += f.printf("```\n")!;
	// 		foreach (i, decl : self.call.decls)
	// 		{
	// 			n += f.printf("%s%s", (i > 0 ? " " : ""), decl)!;
	// 		}
	// 		n += f.printf("\n")!;
	// 		n += f.printf("```\n")!;
        //
	// 	case AST_ATTRIBUTE:
	// 		n += f.printf("%s", self.attr.name)!;
	// 		if (self.attr.paren)
	// 		{
	// 			n += f.printf("%s", self.attr.paren)!;
	// 		}
        //
	// 	case AST_PAREN:
	// 		n += f.print(self.term)!;
        //
	// 	case AST_BRACE:
	// 		n += f.print(self.term)!;
	// }

	return n;
}

fn AstNode*? document(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_DOCUMENT;
	node.document.stmts.init(allocator);

	AstNode* stmt_node;
	while (!parser.expect(EOF)!)
	{
		stmt_node = stmt(allocator, parser)!;
		if (stmt_node.stmt.node == null && stmt_node.stmt.comment == null) continue; // TODO: free stmt node when discarded
		node.document.stmts.push(stmt_node);
	}

	return node;
}

fn AstNode*? stmt(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_STMT;

	node.stmt.comment = comment(allocator, parser)!;

	switch(parser.peek().type)
	{
		case ALIAS:    node.stmt.node = alias_stmt(allocator, parser)!;
		case FUNC:     node.stmt.node = call(allocator, parser)!;
		// case CONST:
		// case ENUM:
		case FAULTDEF: node.stmt.node = faultdef_stmt(allocator, parser)!;
		// case MACRO:    node.stmt.node = macro_stmt(allocator, parser)!;
		case MODULE:   node.stmt.node = module_stmt(allocator, parser)!;
		// case STRUCT:
		default:
	}

	return node;
}

fn AstNode*? comment(Allocator allocator, YadgParser *parser)
{
	Token comment, tok;
	while LOOP: (true)
	{
		tok = parser.peek();
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
		parser.advance()!;
	}

	if (comment.type != CONTRACT) return null;
	if (parser.peek().range.start.ln - comment.range.end.ln > 1) return null;

	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_COMMENT;
	node.comment.str = comment.lexeme().trim().replace(allocator, "\n", " ");
	node.comment.endln = comment.range.end.ln;
	return node;
}

fn AstNode*? module_stmt(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_MODULE;
	node.module_stmt.attrs.init(allocator);

	if (!parser.expect(MODULE)!)
	{
		parser.report_error("exepected a 'module' token");
		return INVALID_AST?;
	}

	node.module_stmt.scope = scope(allocator, parser)!;

	while (parser.peek().type == ATTRIBUTE)
	{
		node.module_stmt.attrs.push(attr(allocator, parser)!);
	}

	if (!parser.expect(SEMICOLON)!)
	{
		parser.report_error("module_stmt: semicolon expected?");
		return INVALID_AST?;
	}

	return node;
}

fn AstNode*? scope(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_SCOPE;

	if (parser.peek().type != IDENT)
	{
		parser.report_error("scope: exepect IDENT");
		return INVALID_AST?;
	}
	node.scope.scope_name = parser.advance()!.lexeme().copy(allocator);

	if (parser.peek().type == SCOPE)
	{
		parser.advance()!; // Consume "::"
		node.scope.next = scope(allocator, parser)!;
	}

	return node;
}

fn AstNode*? attr(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_ATTR;

	if (parser.peek().type != ATTRIBUTE)
	{
		parser.report_error("expect ATTRIBUTE token");
		return INVALID_AST?;
	}

	node.attr.name = parser.advance()!.lexeme().copy(allocator);

	if (parser.peek().type == PAREN)
	{
		node.attr.paren = paren(allocator, parser)!;
	}

	return node;
}

fn AstNode*? paren(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_PAREN;

	if (parser.peek().type != TokenType.PAREN)
	{
		parser.report_error("expect PAREN block ( .. ) ");
		return INVALID_AST?;
	}

	node.str = parser.advance()!.lexeme().copy(allocator);

	return node;
}

fn AstNode*? alias_stmt(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_ALIAS;
	node.alias_node.attrs.init(allocator);

	if (!parser.expect(ALIAS)!)
	{
		parser.report_error("exepected an 'alias' token");
		return INVALID_AST?;
	}

	if (parser.peek().type != IDENT)
	{
		parser.report_error("exepected an 'IDENT' token");
	}

	node.alias_node.lvalue = type(allocator, parser)!;

	while (parser.peek().type == ATTRIBUTE)
	{
		node.alias_node.attrs.push(attr(allocator, parser)!);
	}

	if (!parser.expect(ASSIGN)!)
	{
		parser.report_error("expected an 'ASSIGN' token?");
		return INVALID_AST?;
	}

	// Rvalue could  be a type, module or function call.
	// e.g. alias OnceFn = fn void();
	// e.g. alias l = module std::collection::list;
	switch (parser.peek().type)
	{
		case FUNC:   node.alias_node.rvalue = call(allocator, parser)!;
		case MODULE: node.alias_node.rvalue = module_stmt(allocator, parser)!;
		default:     node.alias_node.rvalue = type(allocator, parser)!;
	}

	if (!parser.expect(SEMICOLON)!)
	{
		parser.report_error("expected a ';' token?");
		return INVALID_AST?;
	}

	return node;
}

fn AstNode*? faultdef_stmt(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_FAULTDEF;
	node.faultdef_node.faults.init(allocator);

	if (!parser.expect(FAULTDEF)!)
	{
		parser.report_error("exepected an 'FAULTDEF' token");
		return INVALID_AST?;
	}

	while LOOP: (true)
	{
		switch (parser.peek().type)
		{
			case IDENT:
				String f = parser.advance()!.lexeme().copy(allocator);
				node.faultdef_node.faults.push(f);
			case LCOMMENT:
			case BCOMMENT:
			case COMMA:
				parser.advance()!;
			default:
				break LOOP;
		}
	}

	if (!parser.expect(SEMICOLON)!)
	{
		parser.report_error("expected a ';' token?");
		return INVALID_AST?;
	}

	return node;
}

fn AstNode*? type(Allocator allocator, YadgParser *parser) => @pool()
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_TYPE;

	DString sb = dstring::temp("");

	// TODO: handle inline prefix, e.g. inline Char16*
	//
	// type = [ "inline" ] ( KEYWORD | IDENT ["::" IDENT ])  [ "*" | "?" | "[..]" | "{..}" ]

	Token tok = parser.peek();
	if (tok.type == KEYWORD && tok.lexeme() == "inline")
	{
		sb.append_chars(parser.advance()!.lexeme());
		sb.append_char(' ');
	}

	switch (parser.peek().type)
	{
		case KEYWORD:
			sb.append_chars(parser.advance()!.lexeme());
		case IDENT:
			@pool() {
				AstNode* ptr = scope(tmem, parser)!;
				while (ptr != null)
				{
					sb.append_chars(ptr.scope.scope_name);
					if (ptr.scope.next) sb.append_chars("::");
					ptr = ptr.scope.next;
				}
			};
		default:
			parser.report_error("invalid token for type");
			return INVALID_AST?;
	}

	while LOOP: (parser.peek().type != EOF)
	{
		switch (parser.peek().type)
		{
			case STAR:
			case QUESTION:
			case BRACK:
			case BRACE:
				sb.append_chars(parser.advance()!.lexeme());
			default:
				break LOOP;
		}
	}

	node.str = sb.copy_str(allocator);

	return node;
}

fn AstNode*? call(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_CALL;
	node.call.attrs.init(allocator);

	if (!parser.expect(FUNC)!)
	{
		parser.report_error("expected a 'FUNC' token");
		return INVALID_AST?;
	}

	node.call.type   = type(allocator, parser)!;
	node.call.callee = callee(allocator, parser)!;
	node.call.paren  = paren(allocator, parser)!;

	while (parser.peek().type == ATTRIBUTE)
	{
		node.call.attrs.push(attr(allocator, parser)!);
	}

	switch (parser.peek().type)
	{
		case ARROW:
			while (parser.peek().type != SEMICOLON) parser.advance()!;
			parser.advance()!; // Consume ';'
		case BRACE:
			parser.advance()!; // Consume '{..}' or ';'
		case SEMICOLON:
			break;
		default:
			parser.report_error("invalid function call termination");
			return INVALID_AST?;
	}

	return node;
}

fn AstNode*? callee(Allocator allocator, YadgParser *parser)
{
	AstNode* node = allocator::new(allocator, AstNode);
	node.type = AST_CALLEE;

	if (parser.peek().type != IDENT)
	{
		return node; // Return empty
	}
	node.callee.call_name = parser.advance()!.lexeme().copy(allocator);

	if (parser.expect(DOT)!)
	{
		node.callee.receiver = node.callee.call_name;

		if (parser.peek().type != IDENT)
		{
			parser.report_error("callee: expected an 'IDENT' token after 'DOT' token");
			return INVALID_AST?;
		}

		node.callee.call_name = parser.advance()!.lexeme().copy(allocator);
	}

	return node;
}

// fn void AstNode.assign_comment(&self, Allocator allocator, YadgParser *parser)
// {
// 	self.comment = parser.find_comment().copy(allocator) ?? "";
// }
//
// // module ident[::ident] [attr(..) ..] ;
// fn AstNode*? module_node(Allocator allocator, YadgParser *parser)
// {
// 	String lexeme;
//
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_MODULE;
//
// 	node.mod.path.init(allocator);
// 	node.mod.attr.init(allocator);
// 	node.mod.submodules.init(allocator);
//
// 	node.mod.globals.init(allocator);
// 	node.mod.calls.init(allocator);
// 	node.mod.blocks.init(allocator);
//
// 	node.assign_comment(allocator, parser);
//
// 	if (!parser.expect(TokenType.MODULE)!) return INVALID_AST?;
//
// 	while (parser.peek().type == TokenType.IDENT)
// 	{
// 		lexeme = parser.advance()!.lexeme().copy(allocator);
// 		node.mod.path.push(lexeme);
// 		node.mod.name = lexeme; // Eventually the last element will stick
// 		if (!parser.expect(TokenType.SCOPE)!) break;
// 	}
//
// 	while (parser.peek().type == TokenType.ATTRIBUTE)
// 	{
// 		node.mod.attr.push(attr(allocator, parser)!);
// 	}
//
// 	if (!parser.expect(TokenType.SEMICOLON)!) return INVALID_AST?;
//
// 	return node;
// }
//
// // [ alias | typedef | const ] terms .. ;
// fn AstNode*? global(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_GLOBAL;
// 	node.glob.decls.init(allocator);
// 	node.glob.methods.init(allocator);
// 	node.assign_comment(allocator, parser);
//
// 	usz i = 0;
// 	while (parser.peek().type != TokenType.SEMICOLON)
// 	{
// 		if (parser.peek().type == EOF) return INVALID_AST?;
// 		String lexeme = parser.advance()!.lexeme().copy(allocator);
// 		node.glob.decls.push(lexeme);
// 		if (i == 1) node.glob.name = lexeme;
// 		i++;
// 	}
//
// 	return node;
// }
//
// // [ enum  | bitstruct ] Name : ["const"] ["inline"] $BackingType [attr(..) ..] [(..)] {..}
// fn AstNode*? block(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_BLOCK;
//
// 	node.block.decls.init(allocator);
// 	node.block.methods.init(allocator);
// 	node.assign_comment(allocator, parser);
//
// 	usz i = 0;
// 	while (parser.peek().type != TokenType.BRACE)
// 	{
// 		if (parser.peek().type == EOF) return INVALID_AST?;
// 		String lexeme = parser.advance()!.lexeme().copy(allocator);
// 		node.block.decls.push(lexeme);
// 		if (i == 1) node.block.name = lexeme;
// 		i++;
// 	}
//
// 	node.block.brace = brace(allocator, parser)!;
//
// 	return node;
// }
//
// alias TokenList = List { Token };
//
// //  fn $ReturnType [Receiver.] Call "(" .. ")" [Attr..]  ( "{" .. "}" | ";" )
// //  macro [$ReturnType] [Receiver.] Call "(" .. ")" [Attr..]  ( "{" .. "}" | ";" )
// fn AstNode*? fncall(Allocator allocator, YadgParser *parser)
// {
// 	String lexeme;
//
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_CALL;
//
// 	node.call.decls.init(allocator);
// 	node.assign_comment(allocator, parser);
//
// 	@pool()
// 	{
// 		TokenList tlist;
// 		tlist.tinit();
//
// 		Token tok = parser.peek();
// 		while (tok.type != TokenType.PAREN)
// 		{
// 			if (tok.type == TokenType.EOF) return INVALID_AST?;
// 			tlist.push(parser.advance()!);
// 			tok = parser.peek();
// 		}
//
// 		node.call.name = tlist.pop()!.lexeme().copy(allocator);
// 		if (tlist.last()!.type == TokenType.DOT)
// 		{
// 			(void)tlist.pop(); // Pop DOT
// 			node.call.receiver = tlist.pop()!.lexeme().copy(allocator);
// 		}
//
// 		foreach (decl : tlist)
// 		{
// 			node.call.decls.push(decl.lexeme().copy(allocator));
// 		}
//
// 		String tmp = node.call.name;
// 		if (node.call.receiver.len)
// 		{
// 			tmp = string::format(allocator, "%s.%s", node.call.receiver, node.call.name);
// 		}
// 		node.call.decls.push(tmp);
// 	};
//
// 	Token tok = parser.peek();
// 	while (tok.type != TokenType.BRACE && tok.type != TokenType.SEMICOLON && tok.type != TokenType.ARROW)
// 	{
// 		if (tok.type == EOF) return INVALID_AST?;
// 		lexeme = parser.advance()!.lexeme().copy(allocator);
// 		node.call.decls.push(lexeme);
// 		tok = parser.peek();
// 	}
//
// 	return node;
// }
//
// fn AstNode*? attr(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_ATTRIBUTE;
//
// 	node.attr.name = parser.advance()!.lexeme().copy(allocator);
// 	if (parser.peek().type == PAREN)
// 	{
// 		node.attr.paren = paren(allocator, parser)!;
// 	}
//
// 	return node;
// }
//
// fn AstNode*? paren(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_PAREN;
//
// 	if (parser.peek().type != TokenType.PAREN)
// 	{
// 		return INVALID_AST?;
// 	}
//
// 	node.term = parser.advance()!.lexeme().copy(allocator);
//
// 	return node;
// }
//
// fn AstNode*? brace(Allocator allocator, YadgParser *parser)
// {
// 	AstNode* node = allocator::new(allocator, AstNode);
// 	node.type = AST_BRACE;
//
// 	if (parser.peek().type != TokenType.BRACE)
// 	{
// 		return INVALID_AST?;
// 	}
//
// 	node.term = format_braces(allocator, parser.advance()!.lexeme());
//
// 	return node;
// }
//
// fn String format_braces(Allocator allocator, String str) => @pool()
// {
// 	DString builder = dstring::temp("{\n");
// 	foreach (i, ln : str.trim("{} \n\r\t").tsplit("\n"))
// 	{
// 		builder.appendf("    %s\n", ln.trim());
// 	}
// 	builder.append_chars("}");
//
// 	return builder.copy_str(allocator);
// }
//
// fn String format_comment(Allocator allocator, String str) => @pool()
// {
// 	DString builder = dstring::temp("");
// 	foreach (i, ln : str.trim().tsplit("\n"))
// 	{
// 		builder.appendf("> %s\n", ln.trim());
// 	}
//
// 	return builder.copy_str(allocator);
// }
//
// fn void? match_receivers(AstNode *mod) => @pool()
// {
// 	String receiver;
// 	AstList calls;
// 	calls.tinit();
// 	// Loop over calls and determine if it is a method
// 	foreach (call_node : mod.mod.calls)
// 	{
// 		receiver = call_node.call.receiver;
// 		// io::printfn("match_receivers for call '%s' (receiver: %s)", call_node.call.name, receiver);
// 		if (!receiver.len)
// 		{
// 			// No receiver
// 			calls.push(call_node);
// 			continue;
// 		}
//
// 		// Yes. we have a receiver.
// 		bool found = false;
// 		foreach (block_node : mod.mod.blocks)
// 		{
// 			if (block_node.block.name == receiver)
// 			{
// 				// io::printfn("RECEIVER FOUND: '%s' for '%s'", receiver, call_node.call.name);
// 				block_node.block.methods.push(call_node);
// 				found = true;
// 				break;
// 			}
// 		}
// 		foreach (global_node : mod.mod.globals)
// 		{
// 			if (global_node.glob.name == receiver)
// 			{
// 				global_node.glob.methods.push(call_node);
// 				found = true;
// 				break;
// 			}
// 		}
// 		if (!found) calls.push(call_node);
// 	}
//
// 	// Restore calls that have no receiver
// 	mod.mod.calls.clear();
// 	mod.mod.calls.add_all(&calls);
// }
