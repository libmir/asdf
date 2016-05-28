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
	Puts key/number
	+/
	void putSmallEscaped(in char[] str)
	{
		assert(str.length <= ubyte.max);
		size_t newLength = length + str.length;
		if(newLength > buffer.length)
		{
			sink(buffer[0 .. length]);
			length = 0;
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
		import std.string: representation;
		foreach(char e; str.representation)
		{
			if(e < ' ')
			{
				put('\\');
				switch(e)
				{
					case '\b': put('b'); continue;
					case '\f': put('f'); continue;
					case '\n': put('n'); continue;
					case '\r': put('r'); continue;
					case '\t': put('t'); continue;
					default:
						import std.utf: UTFException;
						import std.format: format;
						throw new UTFException(format("unexpected char \\x%X", e));
				}
			}
			if(e == '\\')
			{
				put('\\');
				put('\\');
				continue;
			}
			if(e == '\"')
			{
				put('\\');
				put('\"');
				continue;
			}
			put(e);
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
