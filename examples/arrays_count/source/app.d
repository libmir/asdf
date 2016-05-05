import std.algorithm;
import std.range;
import std.stdio;
import asdf;

void main()
{
	foreach(a;
		File("input.jsonl")
		.byChunk(4096)
		.parseJsonByLine(4096)
		.map!(a => a.getValue(["colors"]))
		.filter!(a => a.data.length))
	{
		auto elems = a.byElement;
		auto count = elems.save.count;
		if(count < 2)
			writefln(`{"num_cols": %s}`, count);
		else
			writefln(`{"num_cols": %s, "fav_color": %s}`, count, elems.dropExactly(1).front);
	}
}
