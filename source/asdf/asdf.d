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
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @nogc @safe 
	{
		super(msg, file, line, next);
	}
}

struct Asdf
{
	ubyte[] data;

	void toString(Dg)(scope Dg sink)
	{
		enforce!AsdfException(data.length);
		auto t = data[0];
		switch(t)
		{
			case 0x00:
				enforce!AsdfException(data.length == 1);
				sink("null");
				break;
			case 0x01:
				enforce!AsdfException(data.length == 1);
				sink("true");
				break;
			case 0x02:
				enforce!AsdfException(data.length == 1);
				sink("false");
				break;
			case 0x03:
				enforce!AsdfException(data.length > 1);
				size_t length = data[1];
				enforce!AsdfException(data.length == length + 2);
				sink(cast(string) data[2 .. $]);
				break;
			case 0x05:
				enforce!AsdfException(data.length == length4 + 5);
				sink("\"");
				sink(cast(string) data[5 .. $]);
				sink("\"");
				break;
			case 0x09:
				auto elems = byElement;
				if(byElement.empty)
				{
					sink("[]");
					break;
				}
				sink("[");
				elems.front.toString(sink);
				elems.popFront;
				foreach(e; elems)
				{
					sink(",");
					e.toString(sink);
				}
				sink("]");
				break;
			case 0x0A:
				auto pairs = byKeyValue;
				if(byKeyValue.empty)
				{
					sink("{}");
					break;
				}
				sink("{\"");
				sink(pairs.front.key);
				sink("\":");
				pairs.front.value.toString(sink);
				pairs.popFront;
				foreach(e; pairs)
				{
					sink(",\"");
					sink(e.key);
					sink("\":");
					e.value.toString(sink);
				}
				sink("}");
				break;
			default:
				enforce!AsdfException(0);
		}
	}

	bool opEquals(typeof(null)) const
	{
		return data.length == 1 && data[0] == 0;
	}

	bool opEquals(bool boolean) const
	{
		return data.length == 1 && (data[0] == 0x01 && boolean || data[0] == 0x02 && !boolean);
	}

	bool opEquals(in char[] str) const
	{
		return data.length >= 5 && data[0] == 0x05 && data[5 .. 5 + length4] == cast(const(ubyte)[]) str;
	}

	auto byElement()
	{
		enforce!AsdfException(length4 == data.length - 5);
		enforce!AsdfException(data[0] == 0x09);
		static struct Range
		{
			private ubyte[] _data;
			private Asdf _front;

			void popFront()
			{
				while(!_data.empty)
				{
					uint c = cast(ubyte) _data.front;
					switch(c)
					{
						case 0x00:
						case 0x01:
						case 0x02:
							_front = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case 0x03:
							enforce!AsdfException(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce!AsdfException(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							enforce!AsdfException(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce!AsdfException(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce!AsdfException(0);
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
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	auto byKeyValue()
	{
		enforce!AsdfException(length4 == data.length - 5);
		enforce!AsdfException(data[0] == 0x0A);
		static struct Range
		{
			private ubyte[] _data;
			private Tuple!(const(char)[], "key", Asdf, "value") _front;

			void popFront()
			{
				while(!_data.empty)
				{
					enforce!AsdfException(_data.length > 1);
					size_t l = cast(ubyte) _data[0];
					_data.popFront;
					enforce!AsdfException(_data.length >= l);
					_front.key = cast(const(char)[])_data[0 .. l];
					_data.popFrontExactly(l);
					uint c = cast(ubyte) _data.front;
					switch(c)
					{
						case 0x00:
						case 0x01:
						case 0x02:
							_front.value = Asdf(_data[0 .. 1]);
							_data.popFront;
							return;
						case 0x03:
							enforce!AsdfException(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce!AsdfException(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							enforce!AsdfException(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce!AsdfException(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce!AsdfException(_data.length >= 5);
							size_t len = Asdf(_data).length4 + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce!AsdfException(0);
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
		auto ret = Range(data[5 .. $]);
		if(ret._data.length)
			ret.popFront;
		return ret;
	}

	private size_t length1() const @property
	{
		enforce!AsdfException(data.length >= 2);
		return data[1];
	}

	private size_t length4() const @property
	{
		enforce!AsdfException(data.length >= 5);
		version(X86_Any)
			return (cast(uint[1])cast(ubyte[4])data[1 .. 5])[0];
		else
			static assert(0, "not implemented.");
	}
}

Asdf getValue(Asdf asdf, in char[][] keys)
{
	import std.algorithm.iteration: splitter;
	if(asdf.data.empty)
		return Asdf.init;
	L: foreach(key; keys)
	{
		if(asdf.data[0] != 0x0A)
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
