/++
ASDF Representation

Copyright: Tamedia Digital, 2016

Authors: Ilya Yaroshenko

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf.asdf;

import std.exception;
import std.range.primitives;
import std.typecons;

version(X86)
	version = X86_Any;

version(X86_64)
	version = X86_Any;

///
class AsdfException: Exception
{
	///
	this(
		string msg,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

///
class InvalidAsdfException: AsdfException
{
	///
	this(
		uint kind,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @safe 
	{
		import std.conv: text;
		super(text("ASDF values is invalid for kind = ", kind), file, line, next);
	}
}

private void enforceValidAsdf(
		bool condition,
		uint kind,
		string file = __FILE__,
		size_t line = __LINE__)
{
	if(!condition)
		throw new InvalidAsdfException(kind, file, line);
}

///
class EmptyAsdfException: AsdfException
{
	///
	this(
		string msg = "ASDF values is empty",
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

/++
The structure for ASDF manipulation.
+/
struct Asdf
{
	enum Kind : ubyte
	{
		null_  = 0x00,
		true_  = 0x01,
		false_ = 0x02,
		number = 0x03,
		string = 0x05,
		array  = 0x09,
		object = 0x0A,
	}

	/// Returns ASDF Kind
	ubyte kind()
	{
		enforce!EmptyAsdfException(data.length);
		return data[0];
	}

	/++
	Plain ASDF data.
	+/
	ubyte[] data;

	/// Creates ASDF using already allocated data
	this(ubyte[] data)
	{
		this.data = data;
	}

	/// Creates ASDF from a string
	this(in char[] str)
	{
		data = new ubyte[str.length + 5];
		data[0] = Kind.string;
		length4 = str.length;
		data[5 .. $] = cast(const(ubyte)[])str;
	}

	///
	unittest
	{
		assert(Asdf("string") == "string");
		assert(Asdf("string") != "String");
	}

	/// Sets deleted bit on
	void remove()
	{
		if(data.length)
			data[0] |= 0x80;
	}

	///
	unittest
	{
		import std.conv: to;
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
		auto asdfData = text.chunks(13).parseJson(32);
		asdfData.getValue(["inner", "d"]).remove;
		assert(asdfData.to!string == `{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","e":{}}}`);
	}

	///
	void toString(Dg)(scope Dg sink)
	{
		enforce!EmptyAsdfException(data.length);
		auto t = data[0];
		switch(t)
		{
			case Kind.null_:
				enforceValidAsdf(data.length == 1, t);
				sink("null");
				break;
			case Kind.true_:
				enforceValidAsdf(data.length == 1, t);
				sink("true");
				break;
			case Kind.false_:
				enforceValidAsdf(data.length == 1, t);
				sink("false");
				break;
			case Kind.number:
				enforceValidAsdf(data.length > 1, t);
				size_t length = data[1];
				enforceValidAsdf(data.length == length + 2, t);
				sink(cast(string) data[2 .. $]);
				break;
			case Kind.string:
				enforceValidAsdf(data.length >= 5, Kind.object);
				enforceValidAsdf(data.length == length4 + 5, t);
				sink("\"");
				sink(cast(string) data[5 .. $]);
				sink("\"");
				break;
			default:
				// Uses internal buffer for object and arrays.
				// This makes formatting 3-4 times faster.
				static struct Buffer
				{
					Dg sink;
					// current buffer length
					size_t length;

					char[4096] buffer;

					void put(char c)
					{
						if(length == buffer.length)
						{
							sink(buffer[0 .. length]);
							length = 0;
						}
						buffer[length++] = c;
					}

					/+
					Uses compile time loop for values `null`, `true`, `false`
					+/
					void put(string str)()
					{
						size_t newLength = length + str.length;
						if(newLength > buffer.length)
						{
							sink(buffer[0 .. length]);
							length = 0;
							newLength = str.length;
						}
						import asdf.utility;
						// compile time loop
						foreach(i; Iota!(0, str.length))
							buffer[length + i] = str[i];
						length = newLength;
					}

					/+
					Params:
						small = if string length less or equal 255.
							Keys and numbers have small lengths.
						str = string to write
					+/
					void put(bool small = false)(in char[] str)
					{
						size_t newLength = length + str.length;
						if(newLength > buffer.length)
						{
							sink(buffer[0 .. length]);
							length = 0;
							newLength = str.length;
							static if(!small)
							{
								if(str.length > buffer.length)
								{
									sink(str);
									return;
								}
							}
						}
						buffer[length .. newLength] = str;
						length = newLength;
					}

					/+
					Sends to `sink` remaining data.
					+/
					void flush()
					{
						sink(buffer[0 .. length]);
						length = 0;
					}
				}
				scope buffer = Buffer(sink);
				toStringImpl!Buffer(buffer);
				buffer.flush;
		}
	}

	/+
	Internal recursive toString implementation.
	Params:
		sink = output range that accepts `char`, `in char[]` and compile time string `(string str)()`
	+/
	private void toStringImpl(Buffer)(ref Buffer sink)
	{
		enforce!EmptyAsdfException(data.length);
		auto t = data[0];
		switch(t)
		{
			case Kind.null_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"null";
				break;
			case Kind.true_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"true";
				break;
			case Kind.false_:
				enforceValidAsdf(data.length == 1, t);
				sink.put!"false";
				break;
			case Kind.number:
				enforceValidAsdf(data.length > 1, t);
				size_t length = data[1];
				enforceValidAsdf(data.length == length + 2, t);
				sink.put(cast(string) data[2 .. $]);
				break;
			case Kind.string:
				enforceValidAsdf(data.length >= 5, Kind.object);
				enforceValidAsdf(data.length == length4 + 5, t);
				sink.put('"');
				sink.put!true(cast(string) data[5 .. $]);
				sink.put('"');
				break;
			case Kind.array:
				auto elems = byElement;
				if(byElement.empty)
				{
					sink.put!"[]";
					break;
				}
				sink.put('[');
				elems.front.toStringImpl(sink);
				elems.popFront;
				foreach(e; elems)
				{
					sink.put(',');
					e.toStringImpl(sink);
				}
				sink.put(']');
				break;
			case Kind.object:
				auto pairs = byKeyValue;
				if(byKeyValue.empty)
				{
					sink.put!"{}";
					break;
				}
				sink.put!"{\"";
				sink.put!true(pairs.front.key);
				sink.put!"\":";
				pairs.front.value.toStringImpl(sink);
				pairs.popFront;
				foreach(e; pairs)
				{
					sink.put!",\"";
					sink.put!true(e.key);
					sink.put!"\":";
					e.value.toStringImpl(sink);
				}
				sink.put('}');
				break;
			default:
				enforceValidAsdf(0, t);
		}
	}

	///
	unittest
	{
		import std.conv: to;
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData.to!string == text);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(in Asdf rhs) const
	{
		return data == rhs.data;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`null`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == asdfData);
	}

	/++
	`==` operator overloads for `null`
	+/
	bool opEquals(typeof(null)) const
	{
		return data.length == 1 && data[0] == 0;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`null`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == null);
	}

	/++
	`==` operator overloads for `bool`
	+/
	bool opEquals(bool boolean) const
	{
		return data.length == 1 && (data[0] == Kind.true_ && boolean || data[0] == Kind.false_ && !boolean);
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`true`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == true);
		assert(asdfData != false);
	}

	/++
	`==` operator overloads for `string`
	+/
	bool opEquals(in char[] str) const
	{
		return data.length >= 5 && data[0] == Kind.string && data[5 .. 5 + length4] == cast(const(ubyte)[]) str;
	}

	///
	unittest
	{
		import asdf.jsonparser;
		import std.range: chunks;
		auto text = cast(const ubyte[])`"str"`;
		auto asdfData = text.chunks(13).parseJson(32);
		assert(asdfData == "str");
		assert(asdfData != "stR");
	}

	/++
	Returns:
		input range composed of elements of an array.
	+/
	auto byElement()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Asdf _front;

			auto save() @property
			{
				return this;
			}

			void popFront()
			{
				while(!_data.empty)
				{
					uint t = cast(ubyte) _data.front;
					switch(t)
					{
						case Kind.null_:
						case Kind.true_:
						case Kind.false_:
							_front = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							size_t len = _data[1] + 2;
							enforceValidAsdf(_data.length >= len, t);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case Kind.string:
						case Kind.array:
						case Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							enforceValidAsdf(_data.length >= len, t);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80 | Kind.null_:
						case 0x80 | Kind.true_:
						case 0x80 | Kind.false_:
							_data.popFront;
							continue;
						case 0x80 | Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x80 | Kind.string:
						case 0x80 | Kind.array:
						case 0x80 | Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforceValidAsdf(0, t);
					}
				}
				_front = Asdf.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.data.length == 0;
			}
		}
		if(data.empty || data[0] != Kind.array)
			return Range.init;
		enforceValidAsdf(data.length >= 5, Kind.array);
		enforceValidAsdf(length4 == data.length - 5, Kind.array);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/++
	Returns:
		Input range composed of key-value pairs of an object.
		Elements are type of `Tuple!(const(char)[], "key", Asdf, "value")`.
	+/
	auto byKeyValue()
	{
		static struct Range
		{
			private ubyte[] _data;
			private Tuple!(const(char)[], "key", Asdf, "value") _front;

			auto save() @property
			{
				return this;
			}

			void popFront()
			{
				while(!_data.empty)
				{
					enforceValidAsdf(_data.length > 1, Kind.object);
					size_t l = cast(ubyte) _data[0];
					_data.popFront;
					enforceValidAsdf(_data.length >= l, Kind.object);
					_front.key = cast(const(char)[])_data[0 .. l];
					_data.popFrontExactly(l);
					uint t = cast(ubyte) _data.front;
					switch(t)
					{
						case Kind.null_:
						case Kind.true_:
						case Kind.false_:
							_front.value = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							size_t len = _data[1] + 2;
							enforceValidAsdf(_data.length >= len, t);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case Kind.string:
						case Kind.array:
						case Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							enforceValidAsdf(_data.length >= len, t);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80 | Kind.null_:
						case 0x80 | Kind.true_:
						case 0x80 | Kind.false_:
							_data.popFront;
							continue;
						case 0x80 | Kind.number:
							enforceValidAsdf(_data.length >= 2, t);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x80 | Kind.string:
						case 0x80 | Kind.array:
						case 0x80 | Kind.object:
							enforceValidAsdf(_data.length >= 5, t);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforceValidAsdf(0, t);
					}
				}
				_front = _front.init;
			}

			auto front() @property
			{
				assert(!empty);
				return _front;
			}

			bool empty() @property
			{
				return _front.value.data.length == 0;
			}
		}
		if(data.empty || data[0] != Kind.object)
			return Range.init;
		enforceValidAsdf(data.length >= 5, Kind.object);
		enforceValidAsdf(length4 == data.length - 5, Kind.object);
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	/// returns 4-byte length
	private size_t length4() const @property
	{
		assert(data.length >= 5);
		return (cast(uint[1])cast(ubyte[4])data[1 .. 5])[0];
	}

	/// ditto
	void length4(size_t len) const @property
	{
		assert(data.length >= 5);
		assert(len <= uint.max);
		(cast(uint[1])cast(ubyte[4])data[1 .. 5])[0] = cast(uint) len;
	}
}

/++
Searches a value recursively in an ASDF object.

Params:
	asdf = ASDF data
	keys = input range of keys
Returns
	ASDF value if it was found (first win) or ASDF with empty plain data.
+/
Asdf getValue(Range)(Asdf asdf, Range keys)
	if(is(ElementType!Range : const(char)[]))
{
	if(asdf.data.empty)
		return Asdf.init;
	L: foreach(key; keys)
	{
		if(asdf.data[0] != Asdf.Kind.object)
			return Asdf.init;
		foreach(e; asdf.byKeyValue)
		{
			if(e.key == key)
			{
				asdf = e.value;
				continue L;
			}
		}
		return Asdf.init;
	}
	return asdf;
}

///
unittest
{
	import asdf.jsonparser;
	import std.range: chunks;
	auto text = cast(const ubyte[])`{"foo":"bar","inner":{"a":true,"b":false,"c":"32323","d":null,"e":{}}}`;
	auto asdfData = text.chunks(13).parseJson(32);
	assert(asdfData.getValue(["inner", "a"]) == true);
	assert(asdfData.getValue(["inner", "b"]) == false);
	assert(asdfData.getValue(["inner", "c"]) == "32323");
	assert(asdfData.getValue(["inner", "d"]) == null);
}
