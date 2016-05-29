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
import std.typecons;


version(SSE42)
{
	import core.simd;
	import asdf.simd;
	import ldc.gccbuiltins_x86;
}

/++
Parses json value
Params:
	chunks = input range composed of elements type of `const(ubyte)[]`.
		`chunks` can use the same buffer for each chunk.
	initLength = initial output buffer length. Minimal value equals 32.
Returns:
	ASDF value
+/
Asdf parseJson(Flag!"includingNewLine" includingNewLine = Yes.includingNewLine, Flag!"spaces" spaces = Yes.spaces, Chunks)(Chunks chunks, size_t initLength = 32)
	if(is(ElementType!Chunks : const(ubyte)[]))
{
	return parseJson!(includingNewLine, spaces, Chunks)(chunks, chunks.front, initLength);
}

///
unittest
{
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
Asdf parseJson(
	Flag!"includingNewLine" includingNewLine = Yes.includingNewLine,
	Flag!"spaces" spaces = Yes.spaces,
	Chunks)
	(Chunks chunks, const(ubyte)[] front, size_t initLength = 32)
	if(is(ElementType!Chunks : const(ubyte)[]))
{
	import std.format: format;
	import std.conv: ConvException;
	auto c = JsonParser!(includingNewLine, spaces, Chunks)(front, chunks, OutputArray(initLength));
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
	import std.range: chunks;
	auto text = cast(const ubyte[])`true `;
	auto ch = text.chunks(3);
	assert(ch.parseJson(ch.front, 32).data == [1]);
}

/++
Parses json value
Params:
	str = input string
	initLength = initial output buffer length. Minimal value equals 32.
Returns:
	ASDF value
+/
Asdf parseJson(
	Flag!"includingNewLine" includingNewLine = Yes.includingNewLine,
	Flag!"spaces" spaces = Yes.spaces)
	(in char[] str, size_t initLength = 32)
{
	import std.range: only;
	return parseJson!(includingNewLine, spaces)(only(cast(const ubyte[])str), cast(const ubyte[])str, initLength);
}

///
unittest
{
	assert(`{"ak": {"sub": "subval"} }`.parseJson["ak", "sub"] == "subval");
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
auto parseJsonByLine(
	Flag!"spaces" spaces = Yes.spaces,
	Chunks)
	(Chunks chunks, size_t initLength = 32)
{
	static struct ByLineValue
	{
		private JsonParser!(false, spaces, Chunks) asdf;
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
		ret = ByLineValue(JsonParser!(false, spaces, Chunks)(chunks.front, chunks, OutputArray(initLength)));
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

package struct JsonParser(bool includingNewLine, bool spaces, Chunks)
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

	bool setFrontRange()
	{
		if(r.length == 0)
		{
			assert(!chunks.empty);
			chunks.popFront;
			if(chunks.empty)
			{
				return false;  // unexpected end of input
			}
			r = chunks.front;
		}
		return true;
	}

	int front()
	{
		return setFrontRange ? r[0] : 0;
	}

	void popFront()
	{
		r = r[1 .. $];
	}


	int pop()
	{
		if(setFrontRange)
		{
			int ret = r[0];
			r = r[1 .. $];
			return ret;
		}
		else
		{
			return 0;
		}
	}

	// skips `' '`, `'\t'`, `'\r'`, and optinally '\n'.
	int skipSpaces()
	{
		static if(!spaces)
		{
			return pop;
		}
		else
		{
			version(SSE42)
			{
				static if(includingNewLine)
					enum byte16 str2E = [' ', '\t', '\r', '\n', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
				else
					enum byte16 str2E = [' ', '\t', '\r', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
				byte16 str2 = str2E;
				OL: for(;;)
				{
					if(setFrontRange == false)
						return 0;
					auto d = r;
					for(;;)
					{
						if(d.length >= 16)
						{
							byte16 str1 = loadUnaligned!ubyte16(cast(ubyte*) d.ptr);

							size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x10);
							d = d[ecx .. $];
							
							if(ecx == 16)
								continue;

							int c = d[0];
							r = d[1 .. $];
							return c;
						}
						else
						{
							byte16 str1 = void;
							str1 ^= str1;
							align(16) byte[16] str1E = void;
							* cast(__vector(byte[16])*) str1E.ptr = str1;
							foreach(i; 0..d.length)
								str1E[i] = r[i];
							
							str1 = * cast(__vector(byte[16])*) str1E.ptr;

							size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x10);
							r = d = d[ecx .. $];

							if(d.length == 0)
								continue OL;

							int c = d[0];
							r = d[1 .. $];
							return c;
						}
					}
				}
				return 0; // DMD bug workaround
			}
			else
			{
				for(;;)
				{
					int c = pop;
					switch(c)
					{
						case  ' ':
						case '\r':
						case '\t':
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
		}
	}

	// reads any value
	sizediff_t readValue()
	{
		int c = skipSpaces;
		with(Asdf.Kind) switch(c)
		{
			case '"': return readStringImpl;
			case '-':
			case '0':
			..
			case '9': return readNumberImpl(cast(ubyte)c);
			case '[': return readArrayImpl;
			case 'f': return readWord!("alse", false_);
			case 'n': return readWord!("ull" , null_);
			case 't': return readWord!("rue" , true_);
			case '{': return readObjectImpl;
			default : return -c;
		}
	}

	// reads a string
	sizediff_t readStringImpl(bool key = false)()
	{
		static if(key)
		{
			auto s = oa.skip(1);
		}
		else
		{
			oa.put1(Asdf.Kind.string);
			auto s = oa.skip(4);
		}
		size_t len;
		int c = void;
		//int prev;
		version(SSE42)
		{
			enum byte16 str2E = [
				'\u0001', '\u001F',
				'\"', '\"',
				'\\', '\\',
				'\u007f', '\u007f',
				'\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			byte16 str2 = str2E;
			OL: for(;;)
			{
				if(setFrontRange == false)
					return 0;
				auto d = r;
				auto ptr = oa.data.ptr;
				auto datalen = oa.data.length;
				auto shift = oa.shift;
				for(;;)
				{
					if(datalen < shift + 16)
					{
						oa.extend;
						ptr = oa.data.ptr;
						datalen = oa.data.length;
					}
					if(d.length >= 16)
					{
						byte16 str1 = loadUnaligned!ubyte16(cast(ubyte*) d.ptr);
						storeUnaligned!ubyte16(str1, ptr + shift);

						size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x04);
						shift += ecx;
						len += ecx;
						d = d[ecx .. $];
						
						if(ecx == 16)
							continue;

						r = d;
						oa.shift = shift;
						break;
					}
					else
					{
						byte16 str1 = void;
						str1 ^= str1;
						align(16) byte[16] str1E = void;
						* cast(__vector(byte[16])*) str1E.ptr = str1;
						foreach(i; 0..d.length)
							str1E[i] = r[i];
						
						str1 = * cast(__vector(byte[16])*) str1E.ptr;
						storeUnaligned!ubyte16(str1, ptr + shift);

						size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x04);

						if(ecx == 16)
						{
							shift += r.length;
							len += r.length;
							r = null;

							oa.shift = shift;
							continue OL;
						}

						shift += ecx;
						len += ecx;
						r = d[ecx .. $];

						oa.shift = shift;
						break;
					}
				}
				c = r[0];
				r = r[1 .. $];
				if(c == '\"')
				{
					static if(key)
					{
						oa.put1(cast(ubyte)len, s);
						return len + 1;
					}
					else
					{
						oa.put4(cast(uint)len, s);
						return len + 5;
					}
				}
				if(c == '\\')
				{
					c = pop;
					len++;
					switch(c)
					{
						case '/' : oa.put1('/');  continue;
						case '\"': oa.put1('\"'); continue;
						case '\\': oa.put1('\\'); continue;
						case 'b' : oa.put1('\b'); continue;
						case 'f' : oa.put1('\f'); continue;
						case 'n' : oa.put1('\n'); continue;
						case 'r' : oa.put1('\r'); continue;
						case 't' : oa.put1('\t'); continue;
						default  :
					}
				}
				return -c;
			}
			return 0; // DMD bug workaround
		}
		else
		{
			for(;;)
			{
				c = pop;
				if(c == '\"')
				{
					static if(key)
					{
						oa.put1(cast(ubyte)len, s);
						return len + 1;
					}
					else
					{
						oa.put4(cast(uint)len, s);
						return len + 5;
					}
				}
				if(c < ' ' || c == '\u007f')
				{
					return -c;
				}
				if(c == '\\')
				{
					c = pop;
					switch(c)
					{
						case '/' :           break;
						case '\"':           break;
						case '\\':           break;
						case 'b' : c = '\b'; break;
						case 'f' : c = '\f'; break;
						case 'n' : c = '\n'; break;
						case 'r' : c = '\r'; break;
						case 't' : c = '\t'; break;
						default: return -c;
					}
				}
				oa.put1(cast(ubyte)c);
				len++;
			}
		}
	}

	// reads a number
	sizediff_t readNumberImpl(ubyte c)
	{
		oa.put1(Asdf.Kind.number);
		auto s = oa.skip(1);
		uint len = 1;
		oa.put1(c);
		version(SSE42)
		{
			enum byte16 str2E = ['+', '-', '.', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'e', 'E', '\0'];
			byte16 str2 = str2E;
			OL: for(;;)
			{
				if(setFrontRange == false)
					return 0;
				auto d = r;
				auto ptr = oa.data.ptr;
				auto datalen = oa.data.length;
				auto shift = oa.shift;
				for(;;)
				{
					if(datalen < shift + 16)
					{
						oa.extend;
						ptr = oa.data.ptr;
						datalen = oa.data.length;
					}
					if(d.length >= 16)
					{
						byte16 str1 = loadUnaligned!ubyte16(cast(ubyte*) d.ptr);
						storeUnaligned!ubyte16(str1, ptr + shift);

						size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x10);
						shift += ecx;
						len += ecx;
						d = d[ecx .. $];

						if(ecx == 16)
							continue;

						r = d;
						oa.shift = shift;
						oa.put1(cast(ubyte)len, s);
						return len + 2;
					}
					else
					{
						byte16 str1 = void;
						str1 ^= str1;
						align(16) byte[16] str1E = void;
						* cast(__vector(byte[16])*) str1E.ptr = str1;
						foreach(i; 0..d.length)
							str1E[i] = r[i];

						str1 = * cast(__vector(byte[16])*) str1E.ptr;
						storeUnaligned!ubyte16(str1, ptr + shift);

						size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x10);
						shift += ecx;
						len += ecx;
						r = d = d[ecx .. $];
						oa.shift = shift;

						if(ecx == d.length)
							continue OL;

						oa.put1(cast(ubyte)len, s);
						return len + 2;
					}
				}
			}
			return 0; // DMD bug workaround
		}
		else
		{
			for(;;)
			{
				uint d = front;
				switch(d)
				{
					case '+':
					case '-':
					case '.':
					case '0':
					..
					case '9':
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
	}

	// reads `ull`, `rue`, or `alse`
	sizediff_t readWord(string word, ubyte t)()
	{
		oa.put1(t);
		version(SSE42)
		if(r.length >= word.length)
		{
			static if (word == "ull")
			{
				enum byte16 str2E = ['u', 'l', 'l', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			}
			else
			static if (word == "rue")
			{
				enum byte16 str2E = ['r', 'u', 'e', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			}
			else
			static if (word == "alse")
			{
				enum byte16 str2E = ['a', 'l', 's', 'e', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			}
			else
			{
				static assert(0, "'" ~ word ~ "' is not defined for simd operations.");
			}

			byte16 str2 = str2E;
			if(setFrontRange == false)
				return 0;
			auto d = r;
			byte16 str1 = void;
			str1 ^= str1;
			static if(word.length == 3)
			{
				str1.array[0x0] = d[0x0];
				str1.array[0x1] = d[0x1];
				str1.array[0x2] = d[0x2];
			}
			else
			static if(word.length == 4)
			{
				str1.array[0x0] = d[0x0];
				str1.array[0x1] = d[0x1];
				str1.array[0x2] = d[0x2];
				str1.array[0x3] = d[0x3];
			}
			auto cflag = __builtin_ia32_pcmpistric128(str2 , str1, 0x38);
			auto ecx   = __builtin_ia32_pcmpistri128 (str2 , str1, 0x38);
			if(!cflag)
				return -d[ecx];
			assert(ecx == word.length);
			r = d[ecx .. $];
			return 1;
		}
		foreach(i; 0 .. word.length)
		{
			auto c = pop;
			if(c != word[i])
				return -c;
		}
		return 1;
	}

	// reads an array
	sizediff_t readArrayImpl()
	{
		oa.put1(Asdf.Kind.array);
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
		oa.put1(Asdf.Kind.object);
		auto s = oa.skip(4);
		uint len;
		L: for(;;)
		{
			auto c = skipSpaces;
			if(c == '"')
			{
				auto v = readStringImpl!true;
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
