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
	assert(false);
}
