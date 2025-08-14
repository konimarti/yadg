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

fn AstPrinter* AstPrinter.init(&self)
{
	self.out = io::stdout();
	self.f.init(&output_stream_fn, &self.out);
	return self;
}

fn usz? AstPrinter.visit(&self, AstNode* node) => @pool()
{

	self.depth++;
	defer { self.depth--; };

	usz n;
	Formatter *f = &self.f;

	DString tmp = dstring::temp();
	tmp.append_repeat('\t', self.depth);

	String prefix = tmp.str_view();

	switch (node.type)
	{
		case AST_DOCUMENT:
			foreach (child : node.document.modules)
			{
				n += f.print(prefix)!;
				n += f.printf("(document\n")!;

				n += self.visit(child)!;

				n += f.print(prefix)!;
				n += f.printf(")\n")!;
			}

		case AST_MODULE:
			n += f.print(prefix)!;
			n += f.printf("(module %s\n", node.mod.path.last()!)!;

			foreach (global : node.mod.globals)
			{
				n += self.visit(global)!;
			}

			foreach (call : node.mod.calls)
			{
				n += self.visit(call)!;
			}

			foreach (block : node.mod.blocks)
			{
				n += self.visit(block)!;
			}

			n += f.print(prefix)!;
			n += f.printf(")\n")!;

		case AST_GLOBAL:
			n += f.print(prefix)!;
			n += f.printf("(global %s)\n", node.glob.name)!;

			// foreach (method : node.glob.methods) io::printfn("\n%s", method);

		case AST_BLOCK:
			n += f.print(prefix)!;
			n += f.printf("(block %s", node.block.name)!;
			if (node.block.methods.len())
			{
				n += f.printf("\n")!;
				foreach (method : node.block.methods) n += self.visit(method)!;
				n += f.print(prefix)!;
			}
			n += f.printf(")\n")!;


		case AST_CALL:
			n += f.print(prefix)!;
			n += f.printf("(call ", node.call.name)!;
			if (node.call.receiver.len) n += f.printf("%s.", node.call.receiver)!;
			n += f.printf("%s)\n", node.call.name)!;

		case AST_ATTRIBUTE:
		case AST_PAREN:
		case AST_BRACE:
	}

	return n;
}

