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

fn void test_translation_unit() @test
{
	String input = `
	<* this is a comment *>
	module foo::bar @if(env::LINUX);

	// no comment for this one
	module foo::bar @if(!env::LINUX);

	// no comment for this one
	module foo::bar {KEY, VALUE} @if(!env::LINUX);
	`;
	run_parser(input)!!;
}

fn void test_faultdef() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a faultdef comment *>
	faultdef INVALID_AST_TEST,
		INVALID_ELSE_TEST @local, // valid comment
		INVALID_MORE_TEST; /* block comt */
	`;
	run_parser(input)!!;
}

fn void test_struct_declaration() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a struct comment *>
	struct TestStruct (Printable) @local
	{
		// some content which is currently neither lexed nor parsed
	}

	<* this is a union comment *>
	union SomeUnion (OutStream) @local
	{
		// some content which is currently neither lexed nor parsed
	}
	`;
	run_parser(input)!!;
}

fn void test_enum_declaration() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a enum comment *>
	enum TestStruct (Printable) : inline $typefrom(Something) @local
	{
		// some content which is currently neither lexed nor parsed
	}

	<* this is another enum comment *>
	enum SomeUnion (OutStream) : path::to::Type (String s, int x)
	{
		// some content which is currently neither lexed nor parsed
	}
	`;
	run_parser(input)!!;
}

fn void test_bitstruct_declaration() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a bitstruct comment *>
	bitstruct TestStruct (Printable) : uint[<4>] @local
	{
		// some content which is currently neither lexed nor parsed
	}

	<* this is another bitstruct comment *>
	bitstruct SomeUnion : path::to::Type
	{
		// some content which is currently neither lexed nor parsed
	}
	`;
	run_parser(input)!!;
}

fn void test_interface_declaration() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* this is a interface comment *>
	interface TestStruct
	{
		// some content which is currently neither lexed nor parsed
	}

	<* this is another interface comment *>
	interface SomeUnion : Printable, OutStream
	{
		// some content which is currently neither lexed nor parsed
	}
	`;
	run_parser(input)!!;
}

fn void test_func_definition() @test
{
	String input = `
	module foo::bar @if(!env::LINUX);
	<* Method 'add' on Mystruct with an optional, generic return type *>
	fn MyType{int, float}? MyStruct.add(&self, int hello) => self.value;
	<* Method 'add2' with an optional, generic return type *>
	fn MyType{int, float}? MyStruct.add(&self, int hello)
	{
		// function body
	}
	<* fn_add *>
	fn int fn_add(int a, int b) @local
	{
	}

	fn void*[] capture_current(void*[] buffer) {}

	module std::math::nolibc @if(env::NO_LIBC || $feature(C3_MATH));
	fn float logf(float x) @extern("logf")
	{
		return 0.0;
	}
	`;
	run_parser(input)!!;
}

//
// fn void test_typedef() @test
// {
// 	String input = `
// 	module foo::bar @if(!env::LINUX);
// 	<* typedef comment 1 *>
// 	typedef Char16** = uint[<3>];
// 	<* typedef comment 1 *>
// 	typedef WString = inline Char16*;
// 	`;
// 	run_parser(input)!!;
// 	assert(false);
// }
// fn void test_alias() @test
// {
// 	String input = `
// 	<* this is a comment *>
// 	module foo::bar @if(env::LINUX);
// 	fn Char16[<*>]? Adder.sum(int a, int b) => a + b;
//
// 	module foo::bar @if(!env::LINUX);
// 	alias Char16** = uint[<3>];
// 	alias WString = inline Char16*;
// 	alias OnceFn = fn void();
// 	alias PathList = List { Path };
// 	alias Matrix2 = math::Matrix2x2{float};
// 	`;
// 	run_parser(input)!!;
// }
//
// fn void test_macro() @test
// {
// 	String input = `
// 	module foo::bar::macro_test;
//
// 	<* macro without return type *>
// 	macro fn_add(#a, #b)
// 	{
// 		return $$stringify(#a, #b);
// 	}
//
// 	<* macro with return type *>
// 	macro int fn_add_2(#a, #b) => $$stringify(#a, #b);
// 	`;
// 	run_parser(input)!!;
// }
