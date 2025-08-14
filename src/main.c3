module yadg;
import std::io;

import yadg::lexer;

fn int main(String[] args)
{
	String file = `
	// This is the app module
	module web::app @if(env::LINUX && env::DARWIN);

	import std::io;

	// Define max precision
	const PRECISION = 1.00e-16;

	alias NewType @local = int;

	<*
	 Struct description

	 @deprecated
	*>
	struct Hello @local (Printable)
	{
		inline   int a;
		String   world;
		int[2]   numbers;
		int[<4>] vec;
	}

	// This is an enum
	enum TokenSomething : uint
	{
		FOO,
		BAR,
	}


	<*
	Contract for macro
	*>
	macro macro_add(a, b) => a + b;

	<*
	Contract for fn
	*>
	fn int fn_add(int a, int b) @local
	{
		/*
		 Block comment.
		*/

		// Line comment.
		return a + b
	}

	<*
	 this is a method for struct Hello
	*>
	fn void? Hello.say_hello(&self)
	{
		io::printfn("hello");
	}

	<*
	 'to_char_start' is a method of struct Hello
	*>
	fn char* Hello.to_char_start(&self, char* str) => str;

	fn void main()
	{
		assert(macro_add(1,2) == fn_add(1,2));
	}
	`;

	InStream input = &&io::wrap_bytes(file);
	if (args.len >= 2)
	{
		switch (args[1])
		{
			case "-":
			case "-stdin":
			case "--stdin":
				scan_tokens(io::stdin())!!;
			case "-p":
			case "--path":
				if (args.len != 3) io::printn("Usage: ./yadg -p <path>");
				@pool()
				{
					YadgLexerReport report;
					path::temp(args[2])!!.walk(&yadg_update_report, &report)!!;
					io::printn(report);
				};
			default:
				scan_tokens(input)!!;
		}
	}
	else
	{
		scan_tokens(input)!!;

		// Parsing step;
		io::printn(" -- YADG PARSER --");
		input.seek(0, Seek.SET)!!;
		@pool()
		{
			YadgParser *parser = (YadgParser){}.init(tmem, io::stdout());
			AstNode* document = parser.parse(input)!!;
			// io::printn(document);
			AstPrinter printer;
			printer.init();
			printer.visit(document)!!;
		};
	}

	return 0;
}

struct YadgLexerReport (Printable)
{
	usz pass;
	usz nfiles;
	usz ndirs;
}

fn usz? YadgLexerReport.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.print ("\nYADG Lexer Report\n")!;
	n += f.print (  "-----------------\n")!;
	n += f.printf("Folders scanned: %d\n", self.ndirs)!;
	n += f.printf("Files scanned  : %d\n", self.nfiles)!;
	n += f.printf("Files passed   : %d\n", self.pass)!;
	if (self.nfiles) n += f.printf("Pass Ratio         : %d %%\n", (100 * self.pass) / self.nfiles)!;
	return n;
}

fn bool? yadg_update_report(Path path, bool is_dir, void* data)
{
	YadgLexerReport *report = (YadgLexerReport*)data;
	if (is_dir)
	{
		report.ndirs++;
	}
	else
	{
		if (!path.has_extension("c3")) return false;

		report.nfiles++;

		File f = file::open_path(path, "r")!;
		defer (void)f.close();

		io::printfn("-- scanning file: %s", path.str_view());
		if (try scan_tokens(&f))
		{
			report.pass++;
		}
		else
		{
			io::eprintfn("-- Failed to scan: %s", path);
		}
	}
	return false; // false means continue the walk.
}

fn void? scan_tokens(InStream input) => @pool()
{
	Lexer lexer;
	lexer.init(tmem, input);

	Token tok;
	while (true)
	{
		tok = lexer.next()!;
		io::printn(tok);
		if (tok.type == EOF) break;
	}
}
