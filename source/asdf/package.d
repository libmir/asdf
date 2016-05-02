/++
$(H2 ASDF Package)

Publicly imports $(SUBMODULE asdf) and $(SUBMODULE jsonparser).

Copyright: Tamedia Digital, 2016

Authors: Ilya Yaroshenko

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf;

///
unittest
{
	void filterByLine()
	{
		import std.conv;
		import std.stdio;
		import std.format;
		auto values = File("lines.jsonl").byChunk(4096).parseJsonByLine(4096);
		size_t len, count;
		FormatSpec!char fmt;
		auto wr = stdout.lockingTextWriter;
		foreach(val; values)
		{
			len += val.data.length;
			if(val.getValue(["key"]) == "value")
			{
				count++;
				wr.formatValue(val, fmt);
				wr.put("\n");
			}
		}
	}
}

public import asdf.asdf;
public import asdf.jsonparser;
