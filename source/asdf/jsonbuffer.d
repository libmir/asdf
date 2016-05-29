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
		foreach(chunk; str.representation.chunks(256))
		{
			if(chunk.length + length > buffer.length)
				flush;
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

	/+
	Sends to `sink` remaining data.
	+/
	void flush()
	{
		sink(buffer[0 .. length]);
		length = 0;
	}
}
