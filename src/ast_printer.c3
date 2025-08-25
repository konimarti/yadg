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
		case AST_FAULT_DECL:
		case AST_OPT_ATTRIBUTES:
			foreach (ast : node.ast_list)
				n += self.visit(ast)!;

		case AST_TOP_LEVEL:
			n += write_token(f, prefix, node.top_level.comment)!;
			n += self.visit(node.top_level.decl)!;

		case AST_MODULE:
			n += self.visit(node._module.path_ident)!;
			n += write_token(f, prefix, node._module.module_params)!;
			n += self.visit(node._module.opt_attributes)!;

		case AST_FAULTS:
			n += write_token(f, prefix, node.faults.const_ident)!;
			n += self.visit(node.faults.opt_attributes)!;

		case AST_ATTRIBUTE:
			n += self.visit(node._attribute.path_at_type)!;
			n += write_token(f, prefix, node._attribute.attribute_name)!;
			n += write_token(f, prefix, node._attribute.attribute_param)!;

		case AST_STRUCT_DECL:
			n += write_token(f, prefix, node.struct_decl.type_ident)!;
			n += write_token(f, prefix, node.struct_decl.opt_interface_impl)!;
			n += self.visit(node.struct_decl.opt_attributes)!;
			n += write_token(f, prefix, node.struct_decl.struct_body)!;

		case AST_ENUM_DECL:
			n += write_token(f, prefix, node.enum_decl.type_ident)!;
			n += write_token(f, prefix, node.enum_decl.opt_interface_impl)!;
			n += self.visit(node.enum_decl.enum_spec)!;
			n += self.visit(node.enum_decl.opt_attributes)!;
			n += write_token(f, prefix, node.enum_decl.enum_list)!;

		case AST_ENUM_SPEC:
			n += self.visit(node.enum_spec.base_type_no_generics)!;
			n += write_token(f, prefix, node.enum_spec.enum_params)!;

		case AST_BITSTRUCT_DECL:
			n += write_token(f, prefix, node.bitstruct_decl.type_ident)!;
			n += write_token(f, prefix, node.bitstruct_decl.opt_interface_impl)!;
			n += self.visit(node.bitstruct_decl.type_no_generics)!;
			n += self.visit(node.bitstruct_decl.opt_attributes)!;
			n += write_token(f, prefix, node.bitstruct_decl.bitstruct_body)!;

		case AST_INTERFACE_DECL:
			n += self.visit(node.interface_decl.interface_decl_name)!;
			n += write_token(f, prefix, node.interface_decl.interface_body)!;

		case AST_INTERFACE_DECL_NAME:
			n += write_token(f, prefix, node.interface_decl_name.type_ident)!;
			n += write_token_list(f, prefix, node.interface_decl_name.interface_parents)!;

		case AST_FUNC_DEFINITION:
			n += self.visit(node.func_definition.func_header)!;
			n += write_token(f, prefix, node.func_definition.fn_parameter_list)!;
			n += self.visit(node.func_definition.opt_attributes)!;

		case AST_FUNC_HEADER:
			n += self.visit(node.func_header.optional_type)!;
			n += self.visit(node.func_header.type)!;
			n += write_token(f, prefix, node.func_header.func_macro_name)!;

		case AST_MACRO_DECL:
			n += self.visit(node.macro_decl.macro_header)!;
			n += write_token(f, prefix, node.macro_decl.macro_params)!;
			n += self.visit(node.macro_decl.opt_attributes)!;

		case AST_DISTINCT_DECL:
			n += write_token(f, prefix, node.distinct_decl.type_ident)!;
			n += write_token(f, prefix, node.distinct_decl.opt_interface_impl)!;
			n += self.visit(node.distinct_decl.opt_attributes)!;
			if (node.distinct_decl.opt_inline) n += write_string(f, prefix, "INLINE")!;
			n += self.visit(node.distinct_decl.type)!;

		case AST_FUNC_TYPEDEF:
			n += self.visit(node.func_typedef.optional_type)!;
			n += write_token(f, prefix, node.func_typedef.fn_parameter_list)!;

		case AST_ALIAS_DEFINE_IDENT:
			n += write_token(f, prefix, node.alias_define.define_ident)!;
			n += self.visit(node.alias_define.opt_attributes)!;
			n += self.visit(node.alias_define.path)!;
			n += write_token(f, prefix, node.alias_define.opt_generic_params)!;

		case AST_ALIAS_TYPE_IDENT:
			n += write_token(f, prefix, node.alias_type.type_ident)!;
			n += self.visit(node.alias_type.opt_attributes)!;
			n += self.visit(node.alias_type.typedef_type)!;
			n += self.visit(node.alias_type.opt_attributes_rhs)!;

		case AST_ATTRIBUTE_DEF:
			n += write_token(f, prefix, node.attr_def.at_type_ident)!;
			n += write_token(f, prefix, node.attr_def.opt_parameters)!;
			n += self.visit(node.attr_def.opt_attributes)!;
			foreach (attr : node.attr_def.attribute_comma_list)
				n += self.visit(attr)!;

		case AST_GLOBAL_DECL:
			n += self.visit(node.global_decl.optional_type)!;
			n += write_token_list(f, prefix, node.global_decl.idents)!;
			n += self.visit(node.global_decl.opt_attributes)!;
			n += self.visit(node.global_decl.expr)!;

		case AST_CONST_DECL:
			n += self.visit(node.const_decl.optional_type)!;
			n += write_token(f, prefix, node.const_decl.const_ident)!;
			n += self.visit(node.const_decl.opt_attributes)!;
			n += self.visit(node.const_decl.expr)!;

		case AST_INLINE:
		case AST_EXTERN:
		case AST_CONST:
		case AST_TLOCAL:
			n += self.visit(node.child)!;

		case AST_EXPR:
		case AST_TYPE:
		case AST_PATH:
			n += write_token_list(f, prefix, node.tok_list)!;

		default:
			n += f.printf("%s<not implemented yet in printer>\n", prefix)!;
	}

	// Closing the paren
	n += f.print(prefix)!;
	n += f.printf(")\n")!;

	return n;
}

fn usz? write_token(Formatter *f, String prefix, Token *tok) @inline @local
{
	if (!tok || tok.type == EMPTY) return 0;
	return f.printf("%s%s\n", prefix, tok)!;
}

fn usz? write_token_list(Formatter *f, String prefix, TokenList list) @inline @local
{
	if (list.len() == 0) return 0;
	return f.printf("%s%s\n", prefix, list)!;
}

fn usz? write_string(Formatter *f, String prefix, String s) @inline @local
{
	if (s.len == 0) return 0;
	return f.printf("%s%s\n", prefix, s)!;
}
