module asdf.jsonparser;

import asdf.outputarray;

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

package struct AsdfParser(bool includingN = true, Chunks)
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
