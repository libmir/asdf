module asdf.serialization;

import std.traits;
import std.meta;
import std.range.primitives;
import std.functional;
import std.conv;
import std.utf;
import std.format: FormatSpec, formatValue, singleSpec;
import std.bigint: BigInt;
import asdf.asdf;

///
class DeserializationException: AsdfException
{
	///
	ubyte kind;

	///
	string func;

	///
	this(
		ubyte kind,
		string msg = "Unexpected ASDF kind",
		string func = __PRETTY_FUNCTION__,
		string file = __FILE__,
		size_t line = __LINE__,
		Throwable next = null) pure nothrow @nogc @safe 
	{
		this.kind = kind;
		this.func = func;
		super(msg, file, line, next);
	}
}

/// JSON serialization function
string serializeToJson(V)(auto ref V value)
{
	import std.array;
	auto ser = jsonSerializer(appender!string);
	ser.serializeValue(value);
	return ser.app.data;
}

///
unittest
{
	struct S
	{
		string foo;
		uint bar;
	}

	assert(serializeToJson(S("str", 4)) == `{"foo":"str","bar":4}`);
}

/// ASDF serialization function
Asdf serializeToAsdf(V)(auto ref V value, size_t initialLength = 32)
{
	import std.array;
	auto ser = asdfSerializer(initialLength);
	ser.serializeValue(value);
	return ser.app.result;
}

///
unittest
{
	struct S
	{
		string foo;
		uint bar;
	}

	assert(serializeToAsdf(S("str", 4)).to!string == `{"foo":"str","bar":4}`);
}


/// Deserialization function
V deserialize(V)(Asdf data)
{
	V value;
	deserializeValue(data, value);
	return value;
}

/// ditto
V deserialize(V)(string str)
{
	import asdf.jsonparser: parseJson;
	import std.range: only;
	return (cast(const(ubyte)[]) str).only.parseJson(str.length + 32).deserialize!V;
}

///
unittest
{
	struct S
	{
		string foo;
		uint bar;
	}

	assert(deserialize!S(`{"foo":"str","bar":4}`) == S("str", 4));
}


/// Serialization proxy for aggregation types
struct serializationProxy(T){}

///
unittest
{
	struct S
	{
		@serializationProxy!string
		uint bar;
	}

	auto json = `{"bar":"4"}`;
	assert(serializeToJson(S(4)) == json);
	assert(deserialize!S(json) == S(4));
}

/// Main serialization attribute type
struct Serialization
{
	/// string list
	string[] args;
}

/// Returns Serialization with the `args` list.
Serialization serialization(string[] args...)
{
	return Serialization(args.dup);
}

/// JSON serialization back-end
struct JsonSerializer(Buffer)
	if (isOutputRange!(Buffer, char))
{
	/// String buffer
	Buffer app;

	private uint state;

	private void pushState(uint state)
	{
		this.state = state;
	}

	private uint popState()
	{
		auto ret = state;
		state = 0;
		return ret;
	}

	private void incState()
	{
		if(state++)
			app.put(',');
	}

	/// Serialization primitives
	uint objectBegin()
	{
		app.put('{');
		return popState;
	}

	///ditto
	void objectEnd(uint state)
	{
		app.put('}');
		pushState(state);
	}

	///ditto
	uint arrayBegin()
	{
		app.put('[');
		return popState;
	}

	///ditto
	void arrayEnd(uint state)
	{
		app.put(']');
		pushState(state);
	}

	///ditto
	void putEscapedKey(in char[] key)
	{
		incState;
		app.put('\"');
		app.put(key);
		app.put('\"');
		app.put(':');
	}

	///ditto
	void putKey(in char[] key)
	{
		incState;
		app.put('\"');
		app.putCommonString(key);
		app.put('\"');
		app.put(':');
	}

	///ditto
	void putEscapedStringValue(in char[] str)
	{
		app.put('\"');
		app.put(str);
		app.put('\"');
	}

	///ditto
	void putEscapedStringElem(in char[] str)
	{
		incState;
		putEscapedStringValue(str);
	}

	///ditto
	void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		app.formatValue(num, fmt);
	}

	///ditto
	void putValue(typeof(null))
	{
		app.put("null");
	}

	///ditto
	void putValue(bool b)
	{
		app.put(b ? "true" : "false");
	}

	///ditto
	void putValue(in char[] str)
	{
		app.put('\"');
		app.putCommonString(str);
		app.put('\"');
	}

	///ditto
	void putValue(Num)(Num num)
		if (isNumeric!Num)
	{
		putNumberValue(num);
	}

	///ditto
	void elemBegin()
	{
		incState;
	}
}

/// Create JSON serialization back-end
auto jsonSerializer(Appender)(auto ref Appender appender)
{
	return JsonSerializer!Appender(appender);
}

///
unittest
{
	import std.array;
	import std.bigint;

	auto ser = jsonSerializer(appender!string);
	auto state0 = ser.objectBegin;

		ser.putEscapedKey("null");
		ser.putValue(null);
	
		ser.putEscapedKey("array");
		auto state1 = ser.arrayBegin();
			ser.elemBegin; ser.putValue(null);
			ser.elemBegin; ser.putValue(123);
			ser.elemBegin; ser.putNumberValue(12300000.123, singleSpec("%.10e"));
			ser.elemBegin; ser.putValue("\t");
			ser.elemBegin; ser.putValue("\r");
			ser.elemBegin; ser.putValue("\n");
			ser.elemBegin; ser.putNumberValue(BigInt("1234567890"));
		ser.arrayEnd(state1);
	
	ser.objectEnd(state0);

	assert(ser.app.data == `{"null":null,"array":[null,123,1.2300000123e+07,"\t","\r","\n",1234567890]}`);
}

/// ASDF serialization back-end
struct AsdfSerializer
{
	/// Output buffer
	OutputArray app;

	import asdf.outputarray;
	import asdf.asdf;
	private uint state;

	/// Serialization primitives
	size_t objectBegin()
	{
		app.put1(Asdf.Kind.object);
		return app.skip(4);
	}

	///ditto
	void objectEnd(size_t state)
	{
		app.put4(cast(uint)(app.shift - state - 4), state);
	}

	///ditto
	size_t arrayBegin()
	{
		app.put1(Asdf.Kind.array);
		return app.skip(4);
	}

	///ditto
	void arrayEnd(size_t state)
	{
		app.put4(cast(uint)(app.shift - state - 4), state);
	}

	///ditto
	void putEscapedKey(in char[] key)
	{
		assert(key.length < ubyte.max);
		app.put1(cast(ubyte) key.length);
		app.put(key);
	}

	///ditto
	void putKey(in char[] key)
	{
		auto sh = app.skip(1);
		app.putCommonString(key);
		app.put1(cast(ubyte)(app.shift - sh - 1), sh);
	}

	///ditto
	void putEscapedStringValue(in char[] str)
	{
		app.put1(Asdf.Kind.string);
		app.put4(cast(uint)str.length);
		app.put(str);
	}

	///ditto
	void putEscapedStringElem(in char[] str)
	{
		putEscapedStringValue(str);
	}

	///ditto
	void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
	{
		app.put1(Asdf.Kind.number);
		auto sh = app.skip(1);
		(&app).formatValue(num, fmt);
		app.put1(cast(ubyte)(app.shift - sh - 1), sh);
	}

	///ditto
	void putValue(typeof(null))
	{
		with(Asdf.Kind) app.put1(null_);
	}

	///ditto
	void putValue(bool b)
	{
		with(Asdf.Kind) app.put1(b ? true_ : false_);
	}

	///ditto
	void putValue(in char[] str)
	{
		app.put1(Asdf.Kind.string);
		auto sh = app.skip(4);
		app.putCommonString(str);
		app.put4(cast(uint)(app.shift - sh - 4), sh);
	}

	///ditto
	void putValue(Num)(Num num)
		if (isNumeric!Num)
	{
		putNumberValue(num);
	}

	///ditto
	void elemBegin()
	{
	}
}

/// Create ASDF serialization back-end
auto asdfSerializer(size_t initialLength = 32)
{
	import asdf.outputarray;
	return AsdfSerializer(OutputArray(initialLength));
}

///
unittest
{
	import std.bigint;

	auto ser = asdfSerializer();
	auto state0 = ser.objectBegin;

		ser.putEscapedKey("null");
		ser.putValue(null);
	
		ser.putKey("array");
		auto state1 = ser.arrayBegin();
			ser.elemBegin; ser.putValue(null);
			ser.elemBegin; ser.putValue(123);
			ser.elemBegin; ser.putNumberValue(12300000.123, singleSpec("%.10e"));
			ser.elemBegin; ser.putValue("\t");
			ser.elemBegin; ser.putValue("\r");
			ser.elemBegin; ser.putValue("\n");
			ser.elemBegin; ser.putNumberValue(BigInt("1234567890"));
		ser.arrayEnd(state1);
	
	ser.objectEnd(state0);

	assert(ser.app.result.to!string == `{"null":null,"array":[null,123,1.2300000123e+07,"\t","\r","\n",1234567890]}`);
}

/// `null` value serialization
void serializeValue(S)(ref S serializer, typeof(null))
{
	serializer.putValue(null);
}

///
unittest
{
	assert(serializeToJson(null) == `null`);
}

/// Number serialization
void serializeValue(S, V)(ref S serializer, in V value, FormatSpec!char fmt = FormatSpec!char.init)
	if(isNumeric!V || is(V == BigInt))
{
	serializer.putNumberValue(value, fmt);
}

///
unittest
{
	assert(serializeToJson(BigInt(123)) == `123`);
}

/// Boolean serialization
void serializeValue(S)(ref S serializer, bool value)
{
	serializer.putValue(value);
}

///
unittest
{
	assert(serializeToJson(true) == `true`);
}

/// String serialization
void serializeValue(S)(ref S serializer, in char[] value)
{
	if(value is null)
	{
		serializer.putValue(null);
		return;
	}
	serializer.putValue(value);
}

///
unittest
{
	assert(serializeToJson("\t \" \\") == `"\t \" \\"`);
}

/// Array serialization
void serializeValue(S, T)(ref S serializer, T[] value)
	if(!isSomeChar!T)
{
	if(value is null)
	{
		serializer.putValue(null);
		return;
	}
	auto state = serializer.arrayBegin();
	foreach (ref elem; value)
	{
		serializer.elemBegin;
		serializer.serializeValue(elem);
	}
	serializer.arrayEnd(state);
}

///
unittest
{
	uint[2] ar = [1, 2];
	assert(serializeToJson(ar) == `[1,2]`);
	assert(serializeToJson(ar[]) == `[1,2]`);
	assert(serializeToJson(ar[0 .. 0]) == `[]`);
	assert(serializeToJson((uint[]).init) == `null`);
}

/// String-value associative array serialization
void serializeValue(S, T)(ref S serializer, auto ref T[string] value)
{
	if(value is null)
	{
		serializer.putValue(null);
		return;
	}
	auto state = serializer.objectBegin();
	foreach (key, ref val; value)
	{
		serializer.putKey(key);
		serializer.putValue(val);
	}
	serializer.objectEnd(state);
}

///
unittest
{
	uint[string] ar = ["a" : 1];
	assert(serializeToJson(ar) == `{"a":1}`);
	ar.clear;
	assert(serializeToJson(ar) == `{}`);
	assert(serializeToJson((uint[string]).init) == `null`);
}

/// Enumeration-value associative array serialization
void serializeValue(S, T, K)(ref S serializer, auto ref T[K] value)
	if(is(K == enum))
{
	if(value is null)
	{
		serializer.putValue(null);
		return;
	}
	auto state = serializer.objectBegin();
	foreach (key, ref val; value)
	{
		serializer.putEscapedKey(key.to!string);
		serializer.putValue(val);
	}
	serializer.objectEnd(state);
}

///
unittest
{
	enum E { a, b }
	uint[E] ar = [E.a : 1];
	assert(serializeToJson(ar) == `{"a":1}`);
	ar.clear;
	assert(serializeToJson(ar) == `{}`);
	assert(serializeToJson((uint[string]).init) == `null`);
}

/// Aggregation type serialization
void serializeValue(S, V)(ref S serializer, auto ref V value)
	if(isAggregateType!V && !is(V : BigInt))
{
	static if(is(V == class) || is(V == interface))
	{
		if(value is null)
		{
			serializer.putValue(null);
			return;
		}
	}
	static if(__traits(compiles, value.serialize(serializer)))
	{
		value.serialize(serializer);
	}
	else
	{
		auto state = serializer.objectBegin();
		foreach(member; __traits(allMembers, V))
		{
			static if(__traits(compiles, { __traits(getMember, value, member) = __traits(getMember, value, member); }))
			{
				enum udas = [getUDAs!(__traits(getMember, value, member), Serialization)];
				static if(!ignoreOut(udas))
				{
					enum key = keyOut(S.stringof, member, udas);
					serializer.putEscapedKey(key);
					static if(hasSerializationProxy!(__traits(getMember, value, member)))
					{
						alias Proxy = getSerializationProxy!(__traits(getMember, value, member));
						static if (is(Proxy : const(char)[])
								&& isEscapedOut(S.stringof, member, udas))
						{
							serializer.putEscapedStringValue(__traits(getMember, value, member).to!Proxy);
						}
						else
						{
							serializer.serializeValue(__traits(getMember, value, member).to!Proxy);
						}

					}
					else
					static if(__traits(compiles, serializer.serializeValue(__traits(getMember, value, member))))
					{
						static if (is(typeof(__traits(getMember, value, member)) : const(char)[])
							&& isEscapedOut(S.stringof, member, udas))
						{
							serializer.putEscapedStringValue(__traits(getMember, value, member));
						}
						else
						{
							serializer.serializeValue(__traits(getMember, value, member));
						}
					}
				}
			}
		}
		serializer.objectEnd(state);
	}
}

///
unittest
{
	import std.bigint;
	import std.datetime;
	import std.conv;

	enum E
	{
		a,
		b, 
		c,
	}

	static interface I
	{
		double foo() @property;
		void foo(double) @property;
	}

	static class C : I
	{
		private double _foo;

		this()
		{
			_foo = 4;
		}

		override double foo() @property
		{
			return _foo + 10;
		}

		override void foo(double d) @property
		{
			_foo = d;
		}
	}

	static struct S
	{
		@serializationProxy!string
		@serialization("escaped")
		DateTime time;
		
		I object;

		string[E] map;

		@serialization("keys", "bar_common", "bar")
		string bar = "escaped chars = '\\', '\"', '\t', '\r', '\n'";
		
		@serialization("key-out", "bar_escaped")
		@serialization("escaped")
		string barEscaped = `escaped chars = '\\', '\"', '\t', '\r', '\n'`;
	}

	enum json = `{"time":"2016-Mar-04 00:00:00","object":{"foo":14},"map":{"a":"A"},"bar_common":"escaped chars = '\\', '\"', '\t', '\r', '\n'","bar_escaped":"escaped chars = '\\', '\"', '\t', '\r', '\n'"}`;
	assert(serializeToJson(S(DateTime(2016, 3, 4), new C, [E.a : "A"])) == json);
	assert(serializeToAsdf(S(DateTime(2016, 3, 4), new C, [E.a : "A"])).to!string == json);
}

/// Custom serialization
unittest
{
	struct S
	{
		void serialize(S)(ref S serializer)
		{
			auto state = serializer.objectBegin;
			serializer.putEscapedKey("foo");
			serializer.putEscapedStringValue("bar");
			serializer.objectEnd(state);
		}
	}
	enum json = `{"foo":"bar"}`;
	assert(serializeToJson(S()) == json);
	assert(serializeToAsdf(S()).to!string == json);
}


/// Deserialize `null` value
void deserializeValue(Asdf data, typeof(null))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.null_)
		throw new DeserializationException(kind);
}

/// Deserialize boolean value
void deserializeValue(Asdf data, ref bool value)
{
	auto kind = data.kind;
	with(Asdf.Kind) switch(kind)
	{
		case false_:
			value = false;
			return;
		case true_:
			value = true;
			return;
		default:
			throw new DeserializationException(kind); 
	}
}

/// Deserialize numeric value
void deserializeValue(V)(Asdf data, ref V value)
	if(isNumeric!V || is(V : BigInt))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.number)
		throw new DeserializationException(kind);
	value = (cast(string) data.data[2 .. $]).to!V;
}

/// Deserialize escaped string value
void deserializeEscapedString(V)(Asdf data, ref V value)
	if(is(V : const(char)[]))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.number)
		throw new DeserializationException(kind);
	value = cast(V) data.data[5 .. $].dup;
}

/// Deserialize string value
void deserializeValue(V)(Asdf data, ref V value)
	if(is(V : const(char)[]))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.string)
		throw new DeserializationException(kind);
	value = cast(V) data.data[5 .. $].dup; // TODO: implement conversion
}

/// Deserialize array
void deserializeValue(V : T[], T)(Asdf data, ref V value)
	if(!isSomeChar!T)
{
	import std.algorithm.searching: count;
	auto kind = data.kind;
	if(kind != Asdf.Kind.array)
		throw new DeserializationException(kind);
	auto elems = data.byElement;
	value = new T[elems.save.count];
	foreach(ref e; value)
	{
		.deserializeValue(elems.front, e);
		elems.popFront;
	}
	assert(elems.empty);
}

/// Deserialize static array
void deserializeValue(V : T[N], T, size_t N)(Asdf data, ref V value)
	if(is(E == enum))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.array)
		throw new DeserializationException(kind);
	auto elems = data.byElement;
	foreach(ref e; value)
	{
		if(elems.empty)
			return;
		.deserializeValue(elems.front, e);
		elems.popFront;
	}
}

/// Deserialize string-value associative array
void deserializeValue(V : T[string], T)(Asdf data, ref V value)
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.object)
		throw new DeserializationException(kind);
	foreach(ref elem; elvalue.byKeyValue)
	{
		T v;
		.deserializeValue(elem.value, v);
		value[elem.key.idup] = v;
		.deserializeValue(elems.front, e);
	}
	assert(elems.empty);
}

/// Deserialize enumeration-value associative array
void deserializeValue(V : T[E], T, E)(Asdf data, ref V value)
	if(is(E == enum))
{
	auto kind = data.kind;
	if(kind != Asdf.Kind.object)
		throw new DeserializationException(kind);
	foreach(ref elem; elvalue.byKeyValue)
	{
		T v;
		.deserializeValue(elem.value, v);
		value[elem.key.to!E] = v;
		.deserializeValue(elems.front, e);
	}
	assert(elems.empty);
}

/// Deserialize aggregate value
void deserializeValue(V)(Asdf data, ref V value)
	if(isAggregateType!V && !is(V : BigInt))
{
	static if(__traits(compiles, {value = V.deserialize(data);}))
	{
		value = V.deserialize(data);
	}
	else
	{
		auto kind = data.kind;
		if(kind != Asdf.Kind.object)
		{
			throw new DeserializationException(kind);
		}
		static if(is(V == class) || is(V == interface))
		{
			if(value is null)
			{
				static if(__traits(compiles, {value = new V;}))
				{
					value = new V;
				}
				else
				{
					throw new DeserializationException(data.kind, "Object / interface must not be null");
				}
			}
		}
		foreach(elem; data.byKeyValue)
		{
			switch(elem.key)
			{
				foreach(member; __traits(allMembers, V))
				{
					static if(__traits(compiles, { __traits(getMember, value, member) = __traits(getMember, value, member); }))
					{
						enum udas = [getUDAs!(__traits(getMember, value, member), Serialization)];
						static if(!ignoreIn(udas))
						{
							enum keys = keysIn(V.stringof, member, udas);
							foreach (key; aliasSeqOf!keys)
							{
				case key:

							}
							alias Type = typeof(__traits(getMember, value, member));
							alias Fun = Select!(isEscapedIn(V.stringof, member, udas), .deserializeEscapedString, .deserializeValue);
							static if(hasSerializationProxy!(__traits(getMember, value, member)))
							{
								alias Proxy = getSerializationProxy!(__traits(getMember, value, member));
						
					Proxy proxy;
					Fun(elem.value, proxy);
					__traits(getMember, value, member) = proxy.to!Type;

							}
							else
							static if(__traits(compiles, {auto ptr = &__traits(getMember, value, member); }))
							{

					Fun(elem.value, __traits(getMember, value, member));

							}
							else
							{

					Type val;
					Fun(elem.value, val);
					__traits(getMember, value, member) = val;

							}

					break;

						}
					}
				}
				default:
			}
		}
	}
}


private enum bool isSerializationProxy(A) = is(A : serializationProxy!T, T);

private enum bool isSerializationProxy(alias a) = false;

unittest
{
	static assert(isSerializationProxy!(serializationProxy!string));
	static assert(!isSerializationProxy!(string));
}

private alias ProxyList(alias value) = staticMap!(getSerializationProxy, Filter!(isSerializationProxy, __traits(getAttributes, value)));

private template hasSerializationProxy(alias value)
{
	private enum _listLength = ProxyList!(value).length;
	static assert(_listLength <= 1, `Only single serialization proxy is allowed`);
	enum bool hasSerializationProxy = _listLength == 1;
}

unittest
{
	@serializationProxy!string uint bar;
	uint foo;
	static assert(hasSerializationProxy!bar);
	static assert(!hasSerializationProxy!foo);
}

private alias getSerializationProxy(T :  serializationProxy!Proxy, Proxy) = Proxy;

private template getSerializationProxy(alias value)
{
	private alias _list = ProxyList!value;
	static assert(_list.length <= 1, `Only single serialization proxy is allowed`);
	alias getSerializationProxy = _list[0];
}

private bool isEscapedOut(string type, string member, Serialization[] attrs)
{
	import std.algorithm.searching: canFind, find, startsWith, count;
	alias pred = unaryFun!(a =>
		a.args[0] == "escaped"
		||
		a.args[0] == "escaped-out"
		);
	auto c = attrs.count!pred;
	if(c == 0)
		return false;
	if(c == 1)
		return true;
	throw new Exception(type ~ "." ~ member ~
		` : Only single declaration of "escaped" / "escaped-out" serialization attribute is allowed`);
}

private bool isEscapedIn(string type, string member, Serialization[] attrs)
{
	import std.algorithm.searching: canFind, find, startsWith, count;
	alias pred = unaryFun!(a =>
		a.args[0] == "escaped"
		||
		a.args[0] == "escaped-in"
		);
	auto c = attrs.count!pred;
	if(c == 0)
		return false;
	if(c == 1)
		return true;
	throw new Exception(type ~ "." ~ member ~
		` : Only single declaration of "escaped" / "escaped-in" serialization attribute is allowed`);
}

private string keyOut(string type, string member, Serialization[] attrs)
{
	import std.algorithm.searching: canFind, find, startsWith, count;
	alias pred = unaryFun!(a =>
			a.args[0] == "keys"
			||
			a.args[0] == "key-out"
			);
	auto c = attrs.count!pred;
	if(c == 0)
		return member;
	if(c == 1)
		return attrs.find!pred.front.args[1];
	throw new Exception(type ~ "." ~ member ~
		` : Only single declaration of "keys" / "key-out" serialization attribute is allowed`);
}

private string[] keysIn(string type, string member, Serialization[] attrs)
{
	import std.algorithm.searching: canFind, find, startsWith, count;
	alias pred = unaryFun!(a =>
			a.args[0] == "keys"
			||
			a.args[0] == "keys-in"
			);
	auto c = attrs.count!pred;
	if(c == 0)
		return [member];
	if(c == 1)
		return attrs.find!pred.front.args[1 .. $];
	throw new Exception(type ~ "." ~ member ~
		` : Only single declaration of "keys" / "keys-in" serialization attribute is allowed`);
}

private bool ignoreOut(Serialization[] attrs)
{
	import std.algorithm.searching: canFind;
	return attrs.canFind!(a => 
			a.args == ["ignore"]
			||
			a.args == ["ignore-out"]
			);
}

private bool ignoreIn(Serialization[] attrs)
{
	import std.algorithm.searching: canFind;
	return attrs.canFind!(a => 
			a.args == ["ignore"]
			||
			a.args == ["ignore-out"]
			);
}

private void putCommonString(Appender)(auto ref Appender app, in char[] str)
{
	foreach(ref e; str)
	{
		if(e < ' ')
		{
			app.put('\\');
			switch(e)
			{
				case '\t':
					app.put('t');
					continue;
				case '\r':
					app.put('r');
					continue;
				case '\n':
					app.put('n');
					continue;
				default:
					import std.format: format;
					throw new UTFException(format("unexpected char \\x%X", e));
			}
		}
		if(e == '\\')
		{
			app.put('\\');
			app.put('\\');
			continue;
		}
		if(e == '\"')
		{
			app.put('\\');
			app.put('\"');
			continue;
		}
		app.put(e);
	}
}
