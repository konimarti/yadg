module yadg::parser;

import std::io;
import yadg::lexer;

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
		case AST_TRANSLATION_UNIT:
			foreach (top_level : node.translation_unit.top_level_stmts)
			{
				n += self.visit(top_level)!;
			}

		case AST_TOP_LEVEL:
			n += write_token(f, prefix, node.top_level.comment)!;
			n += write_token(f, prefix, node.top_level.opt_extern)!;
			n += self.visit(node.top_level.decl)!;

		case AST_MODULE:
			n += write_token_list(f, prefix, node._module.path_ident)!;
			n += write_token(f, prefix, node._module.module_params)!;
			foreach (attr : node._module.opt_attributes) n += self.visit(attr)!;

		case AST_FAULT_DECLARATION:
			foreach (top_level : node.translation_unit.top_level_stmts)
			{
				n += self.visit(top_level)!;
			}

		case AST_FAULTS:
			n += write_token(f, prefix, node.faults.const_ident)!;
			foreach (attr : node.faults.opt_attributes) n += self.visit(attr)!;

		case AST_ATTRIBUTE:
			n += write_token(f, prefix, node._attribute.attribute_name)!;
			n += write_token(f, prefix, node._attribute.attribute_param)!;

		default:
			n += f.printf("%s<not implemented yet in printer>\n", prefix)!;
	}

	// Closing the paren
	n += f.print(prefix)!;
	n += f.printf(")\n")!;

	return n;
}

fn usz? write_token(Formatter *f, String prefix, Token tok) @inline
{
	if (tok.type == EMPTY) return 0;
	return f.printf("%s%s\n", prefix, tok)!;
}

fn usz? write_token_list(Formatter *f, String prefix, TokenList list) @inline
{
	return f.printf("%s%s\n", prefix, list)!;
}
