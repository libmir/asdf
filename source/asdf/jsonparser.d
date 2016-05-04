/++
Json Parser

Copyright: Tamedia Digital, 2016

Authors: Ilya Yaroshenko

License: MIT

Macros:
SUBMODULE = $(LINK2 asdf_$1.html, asdf.$1)
SUBREF = $(LINK2 asdf_$1.html#.$2, $(TT $2))$(NBSP)
T2=$(TR $(TDNW $(LREF $1)) $(TD $+))
T4=$(TR $(TDNW $(LREF $1)) $(TD $2) $(TD $3) $(TD $4))
+/
module asdf.jsonparser;

import std.range.primitives;	
import asdf.asdf;
import asdf.outputarray;

/++
Parses json value
Params:
	chunks = input range composed of elements type of `const(ubyte)[]`.
		`chunks` can use the same buffer for each chunk.
	initLength = initial output buffer length. Minimal value equals 32.
Returns:
	ASDF value
+/
Asdf parseJson(bool includingNewLine = true, Chunks)(Chunks chunks, size_t initLength)
	if(is(ElementType!Chunks : const(ubyte)[]))
{
	return parseJson!(includingNewLine, Chunks)(chunks, chunks.front, initLength);
}

///
unittest
{
	import asdf.jsonparser;
	import std.range: chunks;
	auto text = cast(const ubyte[])`true`;
	assert(text.chunks(3).parseJson(32).data == [1]);
}

/++
Params:
	chunks = input range composed of elements type of `const(ubyte)[]`.
		`chunks` can use the same buffer for each chunk.
	front = current front element of `chunks` or its part
	initLength = initial output buffer length. Minimal value equals 32.
Returns:
	ASDF value
+/
Asdf parseJson(bool includingNewLine = true, Chunks)(Chunks chunks, const(ubyte)[] front, size_t initLength)
	if(is(ElementType!Chunks : const(ubyte)[]))
{
	import std.format: format;
	import std.conv: ConvException;
	auto c = JsonParser!(includingNewLine, Chunks)(front, chunks, OutputArray(initLength));
	auto r = c.readValue;
	if(r == 0)
		throw new ConvException("Unexpected end of input");
	if(r < 0)
		throw new ConvException("Unexpected character \\x%02X : %s".format(-r, cast(char)-r));
	return c.oa.result;
}

///
unittest
{
	import asdf.jsonparser;
	import std.range: chunks;
	auto text = cast(const ubyte[])`true `;
	auto ch = text.chunks(3);
	assert(ch.parseJson(ch.front, 32).data == [1]);
}

/++
Parses JSON value in each line.
ASDF value has empty data for invalid lines.
Params:
	chunks = input range composed of elements type of `const(ubyte)[]`.
		`chunks` can use the same buffer for each chunk.
	initLength = initial output buffer length. Minimal value equals 32.
Returns:
	Input range composed of ASDF values. Each value uses the same internal buffer.
+/
auto parseJsonByLine(Chunks)(Chunks chunks, size_t initLength)
{
	static struct ByLineValue
	{
		private JsonParser!(false, Chunks) asdf;
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
	ByLineValue ret; 
	if(chunks.empty)
	{
		ret._empty = ret._nextEmpty = true;
	}
	else
	{
		ret = ByLineValue(JsonParser!(false, Chunks)(chunks.front, chunks, OutputArray(initLength)));
		ret.popFront;
	}
	return ret;
}

///
unittest
{
	import asdf.jsonparser;
	import std.range: chunks;
	auto text = cast(const ubyte[])"\t true \r\r\n false\t";
	auto values = text.chunks(3).parseJsonByLine(32);
	assert(values.front.data == [1]);
	values.popFront;
	assert(values.front.data == [2]);
	values.popFront;
	assert(values.empty);
}

package struct JsonParser(bool includingNewLine = true, Chunks)
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

	// skips `' '`, `'\t'`, `'\r'`, and optinally '\n'.
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
				static if(includingNewLine)
				{
					case '\n':
				}
					continue;
				default:
					return c;
			}
		}
	}

	// reads any value
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

	// reads a string
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

	// reads a key in an object
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

	// reads a number
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

	// reads `null`, `true`, or `false`
	sizediff_t readWord(string word, ubyte t)()
	{
		import asdf.utility;
		foreach(i; Iota!(0, word.length))
		{
			auto c = pop;
			if(c != word[i])
				return -c;
		}
		oa.put1(t);
		return 1;
	}

	// reads an array
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

	// reads an object
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
