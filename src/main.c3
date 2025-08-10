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
	if (args.len >= 2 && args[1] == "-stdin")
	{
		input = io::stdin();
	}

	Lexer lexer;
	lexer.init(tmem, input);

	Token? tok;
	while LEX: (1)
	{
		tok = lexer.next();
		if (catch err = tok)
		{
			if (err == io::EOF)
			{
				io::printn("EOF");
			}
			else
			{
				io::printn(err);
			}
			break LEX;
		}
		io::printf("Token [%6s]", tok.type);
		if (tok.text.len) io::printf(": %s", tok.text.trim());
		io::printn("");

	}

	return 0;
}
