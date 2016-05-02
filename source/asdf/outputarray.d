module asdf.outputarray;

import asdf.asdf;

version(X86)
	version = X86_Any;

version(X86_64)
	version = X86_Any;

version(X86_Any)
	version = GeneralUnaligned;

package struct OutputArray
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
