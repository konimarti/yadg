module yadg::parser;

import std::io;

fn void? output_stream_fn(void *data, char c)
{
	OutStream *stream = data;
	return (*stream).write_byte(c);
}

struct AstPrinter
{
	OutStream out;
	Formatter f;
	usz depth;
}

fn AstPrinter* AstPrinter.init(&self, OutStream out = io::stdout())
{
	self.out = out;
	self.f.init(&output_stream_fn, &self.out);
	return self;
}

fn usz? AstPrinter.visit(&self, AstNode* node) => @pool()
{
	if (node == null) return 0;

	self.depth++;
	defer { self.depth--; };

	usz n;
	Formatter *f = &self.f;

	DString tmp = dstring::temp();
	tmp.append_repeat('\t', self.depth-1);
	String prefix = tmp.str_view();

	n += f.print(prefix)!;
	n += f.printf("(%s\n", node.type)!;

	switch (node.type)
	{
		case AST_DOCUMENT:
			foreach (stmt : node.document.stmts)
			{
				n += self.visit(stmt)!;
			}

		case AST_STMT:
			n += self.visit(node.stmt.comment)!;
			n += self.visit(node.stmt.node)!;

		case AST_MODULE:
			n += self.visit(node.module_stmt.scope)!;
			foreach (attr : node.module_stmt.attrs) n += self.visit(attr)!;

		case AST_ALIAS:
			n += self.visit(node.alias_node.lvalue)!;
			foreach (attr : node.alias_node.attrs) n += self.visit(attr)!;
			n += self.visit(node.alias_node.rvalue)!;

		case AST_MACRO:
		case AST_CALL:
			n += self.visit(node.call.type)!;
			n += self.visit(node.call.callee)!;
			n += self.visit(node.call.paren)!;

		case AST_CALLEE:
			n += f.print(prefix)!;
			if (node.callee.receiver.len)
			{
				n += f.printf("%s.", node.callee.receiver)!;
			}
			n += f.printf("%s\n", node.callee.call_name)!;

		case AST_FAULTDEF:
			foreach (fault_str : node.faultdef_node.faults)
			{
				n += f.print(prefix)!;
				n += f.printf("%s\n", fault_str)!;
			}

		case AST_ATTR:
			n += f.print(prefix)!;
			n += f.printf("%s\n", node.attr.name)!;
			if (node.attr.paren) n += self.visit(node.attr.paren)!;

		case AST_COMMENT:
			if (node.comment.str.len)
			{
				n += f.print(prefix)!;
				n += f.printf("[Ln: %d] %s\n", node.comment.endln, node.comment.str)!;
			}
			else
			{
				n += f.print(prefix)!;
				n += f.printf("<none>\n")!;
			}

		case AST_SCOPE:
			n += f.print(prefix)!;
			n += f.printf("%s\n", node.scope.scope_name)!;
			if (node.scope.next) n += self.visit(node.scope.next)!;

		case AST_TYPE:
		case AST_PAREN:
		case AST_BRACE:
			n += f.print(prefix)!;
			n += f.printf("%s\n", node.str)!;


		default:
			n += f.print("<not implemented yet in printer>\n")!;
	}

	// Closing the paren
	n += f.print(prefix)!;
	n += f.printf(")\n")!;

	return n;
}

