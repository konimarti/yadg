module yadg::ast_test;

import yadg::parser;
import std::io;

fn void? run_parser(String input) @private
{
	@pool() {
		AstPrinter printer;
		printer.init(io::stderr());

		YadgParser *parser = (YadgParser){}.init(tmem, io::stdout());
		printer.visit(parser.parse(&&io::wrap_bytes(input))!)!;
	};
}

fn void test_document() @test
{
	String input = `
	<* this is a comment *>
	module foo::bar @if(env::LINUX);
	fn Char16[<*>]? Adder.sum(int a, int b) => a + b;

	module foo::bar @if(!env::LINUX);
	alias Char16** = uint[<3>];
	alias WString = inline Char16*;
	alias OnceFn = fn void();
	alias PathList = List { Path };
	alias Matrix2 = math::Matrix2x2{float};
	`;
	run_parser(input)!!;
}

fn void test_typedef() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* typedef comment 1 *>
	typedef Char16** = uint[<3>];
	<* typedef comment 1 *>
	typedef WString = inline Char16*;
	`;
	run_parser(input)!!;
	assert(false);
}

fn void test_faultdef() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a faultdef comment *>
	faultdef INVALID_AST,
		INVALID_ELSE, // valid comment
		INVALID_MORE; /* block comt */
	`;
	run_parser(input)!!;
}

fn void test_macro() @test
{
	String input = `
	module foo::bar::macro_test;

	<* macro without return type *>
	macro fn_add(#a, #b)
	{
		return $$stringify(#a, #b);
	}

	<* macro with return type *>
	macro int fn_add_2(#a, #b) => $$stringify(#a, #b);
	`;
	run_parser(input)!!;
}
