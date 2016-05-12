module asdf.serialization;

import std.traits;
import std.meta;
import std.range.primitives;
import std.conv;
import std.utf;
import std.format: FormatSpec, formatValue, singleSpec;

private void putCommonString(Appender)(auto ref Appender app, in char[] str)
{
	foreach(ref e; str)
	{
		if(e < ' ')
		{
			app.put('\\');
			switch(e)
			{
				case '\t':
					app.put('t');
					continue;
				case '\r':
					app.put('r');
					continue;
				case '\n':
					app.put('n');
					continue;
				default:
					import std.format: format;
					throw new UTFException(format("unexpected char \\x%X", e));
			}
		}
		app.put(e);
	}
}

struct JsonSerializer(Buffer)
	if (isOutputRange!(Buffer, char))
{
	Buffer app;
	//uint level;
	//size_t counter;
	private uint state;

	private void pushState(uint state)
	{
		this.state = state;
	}

	private uint popState()
	{
		auto ret = state;
		state = 0;
		return ret;
	}

	private void incState()
	{
		if(state++)
			app.put(',');
	}

	uint objectBegin()
	{
		app.put('{');
		return popState;
	}

	void objectEnd(uint state)
	{
		app.put('}');
		pushState(state);
	}

	uint arrayBegin()
	{
		app.put('[');
		return popState;
	}

	void arrayEnd(uint state)
	{
		app.put(']');
		pushState(state);
	}

	void putEscapedKey(in char[] key)
	{
		incState;
		app.put('\"');
		app.put(key);
		app.put('\"');
		app.put(':');
	}

	void putKey(in char[] key)
	{
		incState;
		app.put('\"');
		app.putCommonString(key);
		app.put('\"');
		app.put(':');
	}

	void putEscapedStringValue(in char[] str)
	{
		app.put('\"');
		app.put(str);
		app.put('\"');
	}

	void putEscapedStringElem(in char[] str)
	{
		incState;
		putEscapedStringValue(str);
	}

	void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		app.formatValue(num, fmt);
	}

	void putNumberElem(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		incState;
		putNumberValue(num, fmt);
	}

	void putValue(typeof(null))
	{
		app.put("null");
	}

	void putValue(bool b)
	{
		app.put(b ? "true" : "false");
	}

	void putValue(in char[] str)
	{
		app.put('\"');
		app.putCommonString(str);
		app.put('\"');
	}

	void putValue(Num)(Num num)
		if (isNumeric!Num)
	{
		putNumberValue(num);
	}

	void putElem(E)(E e)
	{
		incState;
		putValue(e);
	}
}

auto jsonSerializer(Appender)(auto ref Appender appender)
{
	return JsonSerializer!Appender(appender);
}

unittest
{
	import std.array;
	import std.bigint;

	pragma(msg, isOutputRange!(Appender!(char[]), char).stringof);

	auto ser = jsonSerializer(appender!string);
	auto state0 = ser.objectBegin;

		ser.putEscapedKey("null");
		ser.putValue(null);
	
		ser.putKey("array");
		auto state1 = ser.arrayBegin();
			ser.putElem(null);
			ser.putElem(123);
			ser.putNumberElem(12300000.123, singleSpec("%.10e"));
			ser.putElem("\t");
			ser.putElem("\r");
			ser.putElem("\n");
			ser.putNumberElem(BigInt("1234567890"));
		ser.arrayEnd(state1);
	
	ser.objectEnd(state0);

	import std.stdio;
	assert(ser.app.data == `{"null":null,"array":[null,123,1.2300000123e+07,"\t","\r","\n",1234567890]}`);
}

struct AsdfSerializer
{
	import asdf.outputarray;
	import asdf.asdf;
	OutputArray app;
	//uint level;
	//size_t counter;
	private uint state;

	size_t objectBegin()
	{
		app.put1(Asdf.Kind.object);
		return app.skip(4);
	}

	void objectEnd(size_t state)
	{
		app.put4(cast(uint)(app.shift - state - 4), state);
	}

	size_t arrayBegin()
	{
		app.put1(Asdf.Kind.array);
		return app.skip(4);
	}

	void arrayEnd(size_t state)
	{
		app.put4(cast(uint)(app.shift - state - 4), state);
	}

	void putEscapedKey(in char[] key)
	{
		assert(key.length < ubyte.max);
		app.put1(cast(ubyte) key.length);
		app.put(key);
	}

	void putKey(in char[] key)
	{
		auto sh = app.skip(1);
		app.putCommonString(key);
		app.put1(cast(ubyte)(app.shift - sh - 1), sh);
	}

	void putEscapedStringValue(in char[] str)
	{
		app.put1(Asdf.Kind.string);
		app.put4(cast(uint)str.length);
		app.put(str);
	}

	void putEscapedStringElem(in char[] str)
	{
		putEscapedStringValue(str);
	}

	void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		import std.stdio;
		app.put1(Asdf.Kind.number);
		auto sh = app.skip(1);
		(&app).formatValue(num, fmt);
		app.put1(cast(ubyte)(app.shift - sh - 1), sh);
	}

	void putNumberElem(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		putNumberValue(num, fmt);
	}

	void putValue(typeof(null))
	{
		with(Asdf.Kind) app.put1(null_);
	}

	void putValue(bool b)
	{
		with(Asdf.Kind) app.put1(b ? true_ : false_);
	}

	void putValue(in char[] str)
	{
		app.put1(Asdf.Kind.string);
		auto sh = app.skip(4);
		app.putCommonString(str);
		app.put4(cast(uint)(app.shift - sh - 4), sh);
	}

	void putValue(Num)(Num num)
		if (isNumeric!Num)
	{
		putNumberValue(num);
	}

	void putElem(E)(E e)
	{
		putValue(e);
	}
}

auto asdfSerializer(size_t initialLength = 32)
{
	import asdf.outputarray;
	return AsdfSerializer(OutputArray(initialLength));
}

unittest
{
	import std.bigint;

	auto ser = asdfSerializer();
	auto state0 = ser.objectBegin;

		ser.putEscapedKey("null");
		ser.putValue(null);
	
		ser.putKey("array");
		auto state1 = ser.arrayBegin();
			ser.putElem(null);
			ser.putElem(123);
			ser.putNumberElem(12300000.123, singleSpec("%.10e"));
			ser.putElem("\t");
			ser.putElem("\r");
			ser.putElem("\n");
			ser.putNumberElem(BigInt("1234567890"));
		ser.arrayEnd(state1);
	
	ser.objectEnd(state0);

	import std.stdio;
	assert(ser.app.result.to!string == `{"null":null,"array":[null,123,1.2300000123e+07,"\t","\r","\n",1234567890]}`);
}


auto serialize(S)(S obj)
	if (is(S == class) || is(S == struct))
{

}

