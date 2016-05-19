module asdf.outputarray;

import asdf.asdf;

package struct OutputArray
{
	import std.experimental.allocator;
	import std.experimental.allocator.gc_allocator;

	ubyte[] data;
	size_t shift;

	auto result()
	{
		return Asdf(data[0 .. shift]);
	}

	this(size_t initialLength)
	{
		assert(initialLength >= 32);
		data = cast(ubyte[]) GCAllocator.instance.allocate(GCAllocator.instance.goodAllocSize(initialLength));
	}

	size_t skip(size_t len)
	{
		auto ret = shift;
		shift += len;
		if(shift > data.length)
			extend;
		return ret;
	}

	void put(in char[] str)
	{
		size_t newShift = shift + str.length;
		if(newShift < data.length)
			extend(str.length);
		data[shift .. newShift] = cast(ubyte[])str;
		//assert(newShift > shift);
		shift = newShift;
	}

	void put1(ubyte b)
	{
		put1(b, shift);
		shift += 1;
	}

	void put(char b)
	{
		put1(cast(ubyte)b);
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
		assert(sh <= data.length);
		if(sh == data.length)
			extend;
		data[sh] = b;
	}

	void put4(uint b, size_t sh)
	{
		immutable newShift = sh + 4;
		if(newShift > data.length)
			extend;

		*cast(uint*) (data.ptr + sh) = b;
	}

	version(SSE42)
	void put16(ubyte16 b, size_t len)
	{
		if(shift + 16 > data.length)
			extend;
		__builtin_ia32_storedqu(data.ptr, b);
		shift += len;
	}

	private void extend(size_t add = 0)
	{
		size_t length = (data.length) * 2 + add;
		void[] t = data;
		GCAllocator.instance.reallocate(t, length);
		data = cast(ubyte[])t;
	}
}
