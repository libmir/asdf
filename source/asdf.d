import std.meta;
import std.exception;
import std.range.primitives;
import std.typecons;

//import core.simd;

//version(LDC)
//{
//	import ldc.gccbuiltins_x86;
//}


//version(LDC)
//{
//	version(SSE42)
//	{
//		version = LDC_SSE42;
//	}
//}

version(X86)
	version = GeneralUnaligned;

//static __gshared immutable whiteSpacesSet0 = " \t\r\n\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable whiteSpacesSet1 = " \t\r\0\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable numberSet = "0123456789Ee+-.\0";
//static __gshared immutable digitSet = "0123456789\0";

//static __gshared immutable nullSeq = "null\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable trueSeq = "true\0\0\0\0\0\0\0\0\0\0\0\0";
//static __gshared immutable falseSeq = "false\0\0\0\0\0\0\0\0\0\0\0";

private template Iota(size_t i, size_t j)
{
    static assert(i <= j, "Iota: i should be less than or equal to j");
    static if (i == j)
        alias Iota = AliasSeq!();
    else
        alias Iota = AliasSeq!(i, Iota!(i + 1, j));
}

auto parseAsdfByLine(Chunks)(Chunks chunks, size_t initLength)
{
	static struct LineValue
	{
		private AsdfParser!(false, Chunks) asdf;
		private bool _empty, _nextEmpty;

		void popFront()
		{
			assert(!empty);
			if(_nextEmpty)
			{
				_empty = true;
				return;
			}
			asdf.oa.shift = 0;
			auto length = asdf.readValue;
			if(length > 0)
			{
				auto t = asdf.skipSpaces;
				if(t != '\n' && t != 0)
					length = -t;
				else if(t == 0)
				{
					_nextEmpty = true;
					return;
				}
			}
			if(length <= 0)
			{
				length = -length;
				asdf.oa.shift = 0;
				while(length != '\n' && length != 0)
				{
					length = asdf.pop;
				}
			}
			_nextEmpty = length ? asdf.refresh : 0;
		}

		auto front() @property
		{
			assert(!empty);
			return asdf.oa.result;
		}

		bool empty()
		{
			return _empty;
		}
	}
	LineValue ret; 
	if(chunks.empty)
	{
		ret._empty = ret._nextEmpty = true;
	}
	else
	{
		ret = LineValue(AsdfParser!(false, Chunks)(chunks.front, chunks, OutputArray(initLength)));
		ret.popFront;
	}
	return ret;
}

unittest
{
	import std.stdio;
	auto values = File("test.json").byChunk(4096).parseAsdfByLine(4096);
	foreach(val; values)
	{
		//writefln(" ^^ %s", val.length);
	}
}

auto parseAsdf(bool includingN = true, Chunks)(Chunks chunks, const(ubyte)[] front, size_t initLength)
{
	import std.format: format;
	auto c = AsdfParser!(includingN, Chunks)(front, chunks, OutputArray(initLength));
	auto r = c.readValue;
	if(r == 0)
		throw new Exception("Unexpected end of input");
	if(r < 0)
		throw new Exception("Unexpected character \\x%02X : %s".format(-r, cast(char)-r));
	return c.oa.result;
}

auto parseAsdf(bool includingN = true, Chunks)(Chunks chunks, size_t initLength)
{
	return parseAsdf!(includingN, Chunks)(chunks, chunks.front, initLength);
}

unittest
{
	import std.conv: to;
	import std.range;
	auto text = cast(const ubyte[])`{"a":[true],"b":false,"c":32323,"dsdsd":{"a":true,"b":false,"c":"32323","d":null,"dsdsd":{}}}`;
	auto asdf = text.chunks(13).parseAsdf(32);
	import std.stdio;
	assert(asdf.getValue(["dsdsd", "d"]) == null);
	assert(asdf.getValue(["dsdsd", "a"]) == true);
	assert(asdf.getValue(["dsdsd", "b"]) == false);
	assert(asdf.getValue(["dsdsd", "c"]) == "32323");
	assert(asdf.to!string == text);
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

struct Asdf
{
	ubyte[] data;

	void toString(Dg)(scope Dg sink)
	{
		enforce(data.length);
		auto t = data[0];
		switch(t)
		{
			case 0x00:
				enforce(data.length == 1);
				sink("null");
				break;
			case 0x01:
				enforce(data.length == 1);
				sink("true");
				break;
			case 0x02:
				enforce(data.length == 1);
				sink("false");
				break;
			case 0x03:
				enforce(data.length > 1);
				size_t length = data[1];
				enforce(data.length == length + 2);
				sink(cast(string) data[2 .. $]);
				break;
			case 0x05:
				enforce(data.length == length4 + 5);
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
				//writefln("`%s`", elems.front.data);
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
				enforce(0);
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
		enforce(length4 == data.length - 5);
		enforce(data[0] == 0x09);
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
							enforce(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce(_data.length >= 5);
							size_t len = (cast(uint[1])cast(ubyte[4])_data[1 .. 5])[0] + 5;
							enforce(_data.length >= len);
							_front = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce(_data.length >= 5);
							size_t len = (cast(uint[1])cast(ubyte[4])_data[1 .. 5])[0] + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce(0);
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
		enforce(length4 == data.length - 5);
		enforce(data[0] == 0x0A);
		static struct Range
		{
			private ubyte[] _data;
			private Tuple!(const(char)[], "key", Asdf, "value") _front;

			void popFront()
			{
				while(!_data.empty)
				{
					enforce(_data.length > 1);
					size_t l = cast(ubyte) _data[0];
					_data.popFront;
					enforce(_data.length >= l);
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
							enforce(_data.length >= 2);
							size_t len = _data[1] + 2;
							enforce(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x05:
						case 0x09:
						case 0x0A:
							enforce(_data.length >= 5);
							size_t len = (cast(uint[1])cast(ubyte[4])_data[1 .. 5])[0] + 5;
							enforce(_data.length >= len);
							_front.value = Asdf(_data[0 .. len]);
							_data = _data[len .. $];
							return;
						case 0x80:
						case 0x81:
						case 0x82:
							_data.popFront;
							continue;
						case 0x83:
							enforce(_data.length >= 2);
							_data.popFrontExactly(_data[1] + 2);
							continue;
						case 0x85:
						case 0x89:
						case 0x8A:
							enforce(_data.length >= 5);
							size_t len = (cast(uint[1])cast(ubyte[4])_data[1 .. 5])[0] + 5;
							_data.popFrontExactly(len);
							continue;
						default:
							enforce(0);
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
		enforce(data.length >= 2);
		return data[1];
	}

	private size_t length4() const @property
	{
		enforce(data.length >= 5);
		return (cast(uint[1])cast(ubyte[4])data[1 .. 5])[0];
	}
}

private struct AsdfParser(bool includingN = true, Chunks)
{
	const(ubyte)[] r;
	Chunks chunks;
	OutputArray oa;

	bool refresh() @property
	{
		if(r.length == 0)
		{
			assert(!chunks.empty);
			chunks.popFront;
			if(chunks.empty)
				return true;
			r = chunks.front;
		}
		return false;
	} 

	int front()
	{
		if(r.length == 0)
		{
			assert(!chunks.empty);
			chunks.popFront;
			if(chunks.empty)
			{
				return 0;  // unexpected end of input
			}
			r = chunks.front;
		}
		return r[0];
	}

	void popFront()
	{
		r = r[1 .. $];
	}

	int pop()
	{
		int ret = front;
		if(ret != 0) popFront;
		return ret;
	}

	int skipSpaces()
	{
		for(;;)
		{
			int c = pop;
			switch(c)
			{
				case  ' ':
				case '\t':
				case '\r':
				static if(includingN)
				{
					case '\n':
				}
					continue;
				default:
					return c;
			}
		}
	}

	sizediff_t readValue()
	{
		int c = skipSpaces;
		switch(c)
		{
			case 'n': return readWord!("ull" , 0x00);
			case 't': return readWord!("rue" , 0x01);
			case 'f': return readWord!("alse", 0x02);
			case '-':
			case '0':
			..
			case '9': return readNumberImpl(cast(ubyte)c);
			case '"': return readStringImpl;
			case '[': return readArrayImpl;
			case '{': return readObjectImpl;
			default :              return -c;
		}
	}

	sizediff_t readStringImpl()
	{
		oa.put1(0x05);
		auto s = oa.skip(4);
		uint len;
		int prev;
		for(;;)
		{
			int c = pop;
			if(c < ' ')
				return -c;
			if(c == '"' && prev != '\\')
			{
				oa.put4(len, s);
				return len + 5;
			}
			prev = c;
			oa.put1(cast(ubyte)c);
			len++;
		}
	}

	sizediff_t readKeyImpl()
	{
		auto s = oa.skip(1);
		uint len;
		int prev;
		for(;;)
		{
			int c = pop;
			if(c < ' ')
				return -c;
			if(c == '"' && prev != '\\')
			{
				oa.put1(cast(ubyte)len, s);
				return len + 1;
			}
			prev = c;
			oa.put1(cast(ubyte)c);
			len++;
		}
	}

	sizediff_t readNumberImpl(ubyte c)
	{
		oa.put1(0x03);
		auto s = oa.skip(1);
		uint len = 1;
		oa.put1(c);
		for(;;)
		{
			uint d = front;
			switch(d)
			{
				case '0':
				..
				case '9':
				case '-':
				case '+':
				case '.':
				case 'e':
				case 'E':
					popFront;
					oa.put1(cast(ubyte)d);
					len++;
					break;
				default :
					oa.put1(cast(ubyte)len, s);
					return len + 2;
			}
		}
	}

	sizediff_t readWord(string word, ubyte t)()
	{
		foreach(i; Iota!(0, word.length))
		{
			auto c = pop;
			if(c != word[i])
				return -c;
		}
		oa.put1(t);
		return 1;
	}

	sizediff_t readArrayImpl()
	{
		oa.put1(0x09);
		auto s = oa.skip(4);
		uint len;
		L: for(;;)
		{
			auto v = readValue;
			if(v <= 0)
			{
				if(-v == ']' && len == 0)
					break;
				return v;
			}
			len += v;

			auto c = skipSpaces;
			switch(c)
			{
				case ',': continue;
				case ']': break L;
				default : return -c;
			}
		}
		oa.put4(len, s);
		return len + 5;
	}

	sizediff_t readObjectImpl()
	{
		oa.put1(0x0A);
		auto s = oa.skip(4);
		uint len;
		L: for(;;)
		{
			auto c = skipSpaces;
			if(c == '"')
			{
				auto v = readKeyImpl;
				if(v <= 0)
				{
					return v;
				}
				len += v;
			}
			else
			if(c == '}' && len == 0)
			{
				break;
			}
			else
			{
				return -c;
			}

			c = skipSpaces;
			if(c != ':')
				return -c;

			auto v = readValue;
			if(v <= 0)
			{
				return v;
			}
			len += v;

			c = skipSpaces;
			switch(c)
			{
				case ',': continue;
				case '}': break L;
				default : return -c;
			}
		}
		oa.put4(len, s);
		return len + 5;
	}
}

struct OutputArray
{
	import std.experimental.allocator;
	import std.experimental.allocator.gc_allocator;

	ubyte[] array;
	size_t shift;

	auto result()
	{
		return Asdf(array[0 .. shift]);
	}

	this(size_t initialLength)
	{
		assert(initialLength >= 32);
		array = cast(ubyte[]) GCAllocator.instance.allocate(GCAllocator.instance.goodAllocSize(initialLength));
	}

	size_t skip(size_t len)
	{
		auto ret = shift;
		shift += len;
		if(shift > array.length)
			extend;
		return ret;
	}

	void put1(ubyte b)
	{
		put1(b, shift);
		shift += 1;
	}

	void put4(uint b)
	{
		put4(b, shift);
		shift += 4;
	}

	version(SSE42)
	void put16(ubyte16 b, size_t len)
	{
		put16(b, len, shift);
	}

	void put1(ubyte b, size_t sh)
	{
		assert(sh <= array.length);
		if(sh == array.length)
			extend;
		array[sh] = b;
	}

	void put4(uint b, size_t sh)
	{
		immutable newShift = sh + 4;
		if(newShift > array.length)
			extend;

		version(GeneralUnaligned)
		{
			*cast(uint*) (array.ptr + sh) = b;
		}
		else
		version(LittleEndian)
		{
			array[sh + 0] = cast(ubyte) (b >> 0x00u);
			array[sh + 1] = cast(ubyte) (b >> 0x08u);
			array[sh + 2] = cast(ubyte) (b >> 0x10u);
			array[sh + 3] = cast(ubyte) (b >> 0x18u);
		}
		else
		{
			array[sh + 0] = cast(ubyte) (b >> 0x18u);
			array[sh + 1] = cast(ubyte) (b >> 0x10u);
			array[sh + 2] = cast(ubyte) (b >> 0x08u);
			array[sh + 3] = cast(ubyte) (b >> 0x00u);
		}
	}

	version(SSE42)
	void put16(ubyte16 b, size_t len)
	{
		if(shift + 16 > array.length)
			extend;
		__builtin_ia32_storedqu(array.ptr, b);
		shift += len;
	}

	private void extend()
	{
		size_t length = array.length * 2;
		void[] t = array;
		GCAllocator.instance.reallocate(t, array.length * 2);
		array = cast(ubyte[])t;
	}
}

version(APP)
void main(string[] args)
{
	import std.datetime;
	import std.conv;
	import std.stdio;
	import std.format;
	auto values = File(args[1]).byChunk(4096).parseAsdfByLine(4096);
	size_t len, count;
	StopWatch sw;
	sw.start;
	{
		FormatSpec!char fmt;
		auto wr = stdout.lockingTextWriter;
		foreach(val; values)
		{
			len += val.data.length;
			if(val.getValue(["dsrc"]) == "20min.ch")
			{
				count++;
				wr.formatValue(val, fmt);
				wr.put("\n");
			}
		}
	}
	sw.stop;
	//writefln("%s bytes of input", len);
	//writefln("%s lines of output", count);
	//writeln(sw.peek.to!Duration);
}
