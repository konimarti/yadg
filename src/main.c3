module yadg;
import std::io;

import yadg::lexer;

fn int main(String[] args)
{
	String file = `
	module app;

	import std::io;

	// Max is a maximum number
	const MAX = 10;

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
					YadgReport report;
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
	}

	return 0;
}

struct YadgReport (Printable)
{
	usz pass;
	usz nfiles;
	usz ndirs;
}

fn usz? YadgReport.to_format(&self, Formatter *f) @dynamic
{
	usz n;
	n += f.print ("\nYADG Report\n")!;
	n += f.print ("-----------\n")!;
	n += f.printf("Directories scanned: %d\n", self.ndirs)!;
	n += f.printf("Files scanned      : %d\n", self.nfiles)!;
	n += f.printf("Files passed       : %d\n", self.pass)!;
	if (self.nfiles) n += f.printf("Pass Ratio         : %d %%\n", (100 * self.pass) / self.nfiles)!;
	return n;
}

fn bool? yadg_update_report(Path path, bool is_dir, void* data)
{
	YadgReport *report = (YadgReport*)data;
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

	Token? tok;
	while TOKEN_SCAN: (1)
	{
		tok = lexer.next();
		if (catch err = tok)
		{
			if (err == io::EOF)
			{
				io::printn("EOF.");
				break TOKEN_SCAN;
			}
			return err?;
		}
		io::printn(tok);
		// io::printf("Token [%9s]", tok.type);
		// if (tok.text.len) io::printf(": %s", tok.text.trim());
		// io::printn("");
	}
}
