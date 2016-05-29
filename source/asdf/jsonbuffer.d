module asdf.jsonbuffer;

package struct JsonBuffer
{
	void delegate(const(char)[]) sink;
	// current buffer length
	size_t length;

	char[4096] buffer = void;

	/+
	Puts char
	+/
	void put(char c)
	{
		if(length == buffer.length)
		{
			flush;
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
			flush;
			newLength = str.length;
		}
		import asdf.utility;
		// compile time loop
		foreach(i; Iota!(0, str.length))
			buffer[length + i] = str[i];
		length = newLength;
	}

	/+
	Puts key/number
	+/
	void putSmallEscaped(in char[] str)
	{
		assert(str.length <= ubyte.max);
		size_t newLength = length + str.length;
		if(newLength > buffer.length)
		{
			flush;
			newLength = str.length;
		}
		buffer[length .. newLength] = str;
		length = newLength;
	}

	/+
	Puts string
	+/
	void put(in char[] str)
	{
		import std.range: chunks;
		import std.string: representation;
		version(SSE42)
		{
			import core.simd;
			import asdf.simd;
			import ldc.gccbuiltins_x86;

			enum byte16 str2E = [
				'\u0001', '\u001F',
				'\"', '\"',
				'\\', '\\',
				'\u007f', '\u007f',
				'\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			enum byte16 str3E = ['\"', '\\', '\b', '\f', '\n', '\r', '\t', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
			byte16 str2 = str2E;
			byte16 str3 = str3E;
			static immutable emap = ['\"', '\\', 'b', 'f', 'n', 'r', 't'];
			for(auto d = str.representation; d.length;)
			{
				if(length + 17 > buffer.length)
				{
					flush;
				}
				byte16 str1 = void;
				int ecx = void;
				if(d.length >= 16)
				{
					str1 = loadUnaligned!ubyte16(cast(ubyte*) d.ptr);
					storeUnaligned!ubyte16(str1, cast(ubyte*) buffer.ptr + length);
					auto cflag = __builtin_ia32_pcmpistric128(str2, str1, 0x04);
					ecx =        __builtin_ia32_pcmpistri128 (str2, str1, 0x04);
					d = d[ecx .. $];
					length += ecx;
					if(ecx == 16)
						continue;
				}
				else
				{
					str1 ^= str1;
					align(16) byte[16] str1E = void;
					* cast(__vector(byte[16])*) str1E.ptr = str1;
					foreach(i; 0..d.length)
						str1E[i] = d[i];
					str1 = * cast(__vector(byte[16])*) str1E.ptr;
					storeUnaligned!ubyte16(str1, cast(ubyte*) buffer.ptr + length);
					auto cflag = __builtin_ia32_pcmpistric128(str2, str1, 0x04);
					ecx =        __builtin_ia32_pcmpistri128 (str2, str1, 0x04);
					if(!cflag)
					{
						length += d.length;
						break;
					}
					d = d[ecx .. $];
					length += ecx;
				}

				int eax = ecx + 1;
				auto cflag = __builtin_ia32_pcmpestric128(str1, eax, str3, emap.length, 0x00);
				ecx =        __builtin_ia32_pcmpestri128 (str1, eax, str3, emap.length, 0x00);
				if(cflag)
				{
					d = d[1 .. $];
					buffer[length + 0] = '\\';
					buffer[length + 1] = emap[ecx];
					length += 2;
					continue;
				}
				import std.utf: UTFException;
				import std.format: format;
				throw new UTFException(format("unexpected char \\x%X", d[0]));
			}
		}
		else
		{
			foreach(chunk; str.representation.chunks(256))
			{
				if(chunk.length + length + 16 > buffer.length)
				{
					flush;
				}
				auto ptr = buffer.ptr + length;
				foreach(size_t i, char e; chunk)
				{
					if(e < ' ')
					{
						ptr++[i] = '\\';
						length++;
						switch(e)
						{
							case '\b': ptr[i] = 'b'; continue;
							case '\f': ptr[i] = 'f'; continue;
							case '\n': ptr[i] = 'n'; continue;
							case '\r': ptr[i] = 'r'; continue;
							case '\t': ptr[i] = 't'; continue;
							default:
								import std.utf: UTFException;
								import std.format: format;
								throw new UTFException(format("unexpected char \\x%X", e));
						}
					}
					if(e == '\\')
					{
						ptr++[i] = '\\';
						length++;
						ptr[i] = '\\';
						continue;
					}
					if(e == '\"')
					{
						ptr++[i] = '\\';
						length++;
						ptr[i] = '\"';
						continue;
					}
					ptr[i] = e;
				}
				length += chunk.length;
			}
		}
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
