/++
$(H3 ASDF and JSON Serialization)

For aggregate types the order of the (de)serialization is the folowing:
    1. All public fields of `alias ? this` that are not hidden by members of `this` (recursively).
    2. All public fields of `this`.
    3. All public properties of `alias ? this` that are not hidden by members of `this` (recursively).
    4. All public properties of `this`.

Publicly imports `mir.serde` from the `mir-algorithm` package.
+/
module asdf.serialization;

import asdf.jsonparser: assumePure;
import mir.algebraic: isVariant;
import mir.reflection;
import std.range.primitives: isOutputRange;
public import mir.serde;

///
pure
unittest
{
    import asdf;
    import std.bigint;
    import std.datetime;
    import mir.conv;

    enum E : char
    {
        a,
        b,
        c,
    }

    static class C
    {
        private double _foo;
    pure:
        this()
        {
            _foo = 4;
        }

        double foo() const @property
        {
            return _foo + 10;
        }

        void foo(double d) @property
        {
            _foo = d - 10;
        }
    }

    import mir.timestamp: Timestamp;

    static struct S
    {
        static int staticNotSeialised = 5;
        enum int enumsNotSeialised = 3;

        @serdeProxy!Timestamp
        DateTime time;

        C object;

        string[E] map;

        @serdeKeys("bar_common", "bar")
        string bar;
    }

    enum json = `{"time":"2016-03-04T00:00:00-00:00","object":{"foo":14.0},"map":{"a":"A"},"bar_common":"escaped chars = '\\', '\"', '\t', '\r', '\n'"}`;
    auto value = S(
        DateTime(2016, 3, 4),
        new C,
        [E.a : "A"],
        "escaped chars = '\\', '\"', '\t', '\r', '\n'");
    import mir.test: should;
    serializeToJson(cast(const)value).should == json; // check serialization of const data
    serializeToAsdf(value).to!string.should == json;
    deserialize!S(json).serializeToJson.should == json;
}

/// `finalizeSerialization` method
unittest
{
    import asdf;

    static struct S
    {
        string a;
        int b;

        void finalizeSerialization(Serializer)(ref Serializer serializer)
        {
            serializer.putKey("c");
            serializer.putValue(100);
        }
    }
    assert(S("bar", 3).serializeToJson == `{"a":"bar","b":3,"c":100}`);
}

/// `finalizeDeserialization` method
pure unittest
{
    import asdf;

    static struct S
    {
        string a;
        int b;

        @serdeIgnoreIn
        double sum;

        void finalizeDeserialization(Asdf data) pure
        {
            auto r = data["c", "d"];
            auto a = r["e"].get(0.0);
            auto b = r["g"].get(0.0);
            sum = a + b;
        }

        void serdeFinalize() pure
        {
            sum *= 2;
        }
    }
    assert(`{"a":"bar","b":3,"c":{"d":{"e":6,"g":7}}}`.deserialize!S == S("bar", 3, 26));
}

/// A user may define setter and/or getter properties.
unittest
{
    import asdf;
    import mir.conv: to;

    static struct S
    {
        @serdeIgnore string str;
    pure:
        string a() @property
        {
            return str;
        }

        void b(int s) @property
        {
            str = s.to!string;
        }
    }

    assert(S("str").serializeToJson == `{"a":"str"}`);
    assert(`{"b":123}`.deserialize!S.str == "123");
}

/// Support for custom nullable types (types that has a bool property `isNull`,
/// non-void property `get` returning payload and void property `nullify` that
/// makes nullable type to null value)
unittest
{
    import asdf;

    static struct MyNullable
    {
        long value;

        @property
        isNull() const
        {
            return value == 0;
        }

        @property
        get()
        {
            return value;
        }

        @property
        nullify()
        {
            value = 0;
        }

        auto opAssign(long value)
        {
            this.value = value;
        }
    }

    static struct Foo
    {
        MyNullable my_nullable;
        string field;

        bool opEquals()(auto ref const(typeof(this)) rhs)
        {
            if (my_nullable.isNull && rhs.my_nullable.isNull)
                return field == rhs.field;

            if (my_nullable.isNull != rhs.my_nullable.isNull)
                return false;

            return my_nullable == rhs.my_nullable &&
                         field == rhs.field;
        }
    }

    Foo foo;
    foo.field = "it's a foo";

    assert (serializeToJson(foo) == `{"my_nullable":null,"field":"it's a foo"}`);

    foo.my_nullable = 200;

    assert (deserialize!Foo(`{"my_nullable":200,"field":"it's a foo"}`) == Foo(MyNullable(200), "it's a foo"));

    import std.typecons : Nullable;

    static struct Bar
    {
        Nullable!long nullable;
        string field;

        bool opEquals()(auto ref const(typeof(this)) rhs)
        {
            if (nullable.isNull && rhs.nullable.isNull)
                return field == rhs.field;

            if (nullable.isNull != rhs.nullable.isNull)
                return false;

            return nullable == rhs.nullable &&
                         field == rhs.field;
        }
    }

    Bar bar;
    bar.field = "it's a bar";

    assert (serializeToJson(bar) == `{"nullable":null,"field":"it's a bar"}`);

    bar.nullable = 777;
    assert (deserialize!Bar(`{"nullable":777,"field":"it's a bar"}`) == Bar(Nullable!long(777), "it's a bar"));

    static struct S
    {
        long i;

        SerdeException deserializeFromAsdf(Asdf data)
        {
            if (auto exc = deserializeValue(data, i))
                return exc;
            return null;
        }
    }

    static struct T
    {
        // import std.typecons: Nullable;
        import mir.algebraic: Nullable;
        Nullable!S test;
    }
    T t = deserialize!T(`{ "test": 5 }`);
    assert(t.test.i == 5);
}


// unittest
// {
//     Asdf[string] map;

//     map["num"] = serializeToAsdf(124);
//     map["str"] = serializeToAsdf("value");
    
//     import std.stdio;
//     map.serializeToJson.writeln();
// }

/// Support for floating point nan and (partial) infinity
unittest
{
    import mir.conv: to;
    import asdf;

    static struct Foo
    {
        float f;

        bool opEquals()(auto ref const(typeof(this)) rhs)
        {
            import std.math : isNaN, approxEqual;

            if (f.isNaN && rhs.f.isNaN)
                return true;

            return approxEqual(f, rhs.f);
        }
    }

    // test for Not a Number
    assert (serializeToJson(Foo()).to!string == `{"f":"nan"}`);
    assert (serializeToAsdf(Foo()).to!string == `{"f":"nan"}`);

    assert (deserialize!Foo(`{"f":null}`)  == Foo());
    assert (deserialize!Foo(`{"f":"nan"}`) == Foo());

    assert (serializeToJson(Foo(1f/0f)).to!string == `{"f":"inf"}`);
    assert (serializeToAsdf(Foo(1f/0f)).to!string == `{"f":"inf"}`);
    assert (deserialize!Foo(`{"f":"inf"}`)  == Foo( float.infinity));
    assert (deserialize!Foo(`{"f":"-inf"}`) == Foo(-float.infinity));

    assert (serializeToJson(Foo(-1f/0f)).to!string == `{"f":"-inf"}`);
    assert (serializeToAsdf(Foo(-1f/0f)).to!string == `{"f":"-inf"}`);
    assert (deserialize!Foo(`{"f":"-inf"}`) == Foo(-float.infinity));
}

import asdf.asdf;
import mir.conv;
import std.bigint: BigInt;
import std.format: FormatSpec, formatValue;
import std.functional;
import std.meta;
import std.range.primitives;
import std.traits;
import std.utf;

deprecated("use mir.serde: SerdeException instead")
alias DeserializationException = SerdeException;

private SerdeException unexpectedKind(string msg = "Unexpected ASDF kind")(ubyte kind)
    @safe pure nothrow @nogc
{
    import mir.conv: to;
    static immutable exc(Asdf.Kind kind) = new SerdeException(msg ~ " " ~ kind.to!string);

    switch (kind)
    {
        foreach (member; EnumMembers!(Asdf.Kind))
        {case member:
            return exc!member;
        }
        default:
            static immutable ret = new SerdeException("Wrong encoding of ASDF kind");
            return ret;
    }
}

/// JSON serialization function.
string serializeToJson(V)(auto ref V value)
{
    return serializeToJsonPretty!""(value);
}

///
unittest
{
    import asdf;

    struct S
    {
        string foo;
        uint bar;
    }

    assert(serializeToJson(S("str", 4)) == `{"foo":"str","bar":4}`);
}


/// JSON serialization function with pretty formatting.
string serializeToJsonPretty(string sep = "\t", V)(auto ref V value)
{
    import std.array: appender;
    import std.functional: forward;

    auto app = appender!(string);
    serializeToJsonPretty!sep(forward!value, app);
    return app.data;
}

///
unittest
{
    import asdf;

    static struct S { int a; }
    assert(S(4).serializeToJsonPretty == "{\n\t\"a\": 4\n}");
}

/// JSON serialization function with pretty formatting and custom output range.
void serializeToJsonPretty(string sep = "\t", V, O)(auto ref V value, ref O output)
    if(isOutputRange!(O, const(char)[]))
{
    import std.range.primitives: put;
    auto ser = jsonSerializer!sep((const(char)[] chars) => put(output, chars));
    ser.serializeValue(value);
    ser.flush;
}


/// ASDF serialization function
Asdf serializeToAsdf(V)(auto ref V value, size_t initialLength = 32)
{
    auto ser = asdfSerializer(initialLength);
    ser.serializeValue(value);
    ser.flush;
    return ser.app.result;
}

///
unittest
{
    import asdf;
    import mir.conv: to;

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
    static if (is(V == class)) value = new V;
    if (auto exc = deserializeValue(data, value))
        throw exc;
    return value;
}

/// ditto
V deserialize(V)(in char[] str)
{
    import asdf.jsonparser: parseJson;
    import std.range: only;
    return str.parseJson.deserialize!V;
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

/// Proxy for members
unittest
{
    struct S
    {
        // const(char)[] doesn't reallocate ASDF data.
        @serdeProxy!(const(char)[])
        uint bar;
    }

    auto json = `{"bar":"4"}`;
    assert(serializeToJson(S(4)) == json);
    assert(deserialize!S(json) == S(4));
}

version(unittest) private
{
    @serdeProxy!ProxyE
    enum E
    {
        none,
        bar,
    }

    // const(char)[] doesn't reallocate ASDF data.
    @serdeProxy!(const(char)[])
    struct ProxyE
    {
        E e;

        this(E e)
        {
            this.e = e;
        }

        this(in char[] str)
        {
            switch(str)
            {
                case "NONE":
                case "NA":
                case "N/A":
                    e = E.none;
                    break;
                case "BAR":
                case "BR":
                    e = E.bar;
                    break;
                default:
                    throw new Exception("Unknown: " ~ cast(string)str);
            }
        }

        string toString() const
        {
            if (e == E.none)
                return "NONE";
            else
                return "BAR";
        }

        E opCast(T : E)()
        {
            return e;
        }
    }

    unittest
    {
        assert(serializeToJson(E.bar) == `"BAR"`);
        assert(`"N/A"`.deserialize!E == E.none);
        assert(`"NA"`.deserialize!E == E.none);
    }
}

///
pure unittest
{
    static struct S
    {
        @serdeKeys("b", "a")
        string s;
    }
    assert(`{"a":"d"}`.deserialize!S.serializeToJson == `{"b":"d"}`);
}

///
pure unittest
{
    static struct S
    {
        @serdeKeys("a")
        @serdeKeyOut("s")
        string s;
    }
    assert(`{"a":"d"}`.deserialize!S.serializeToJson == `{"s":"d"}`);
}

///
pure unittest
{
    import std.exception;
    struct S
    {
        string field;
    }
    assert(`{"field":"val"}`.deserialize!S.field == "val");
    assertThrown(`{"other":"val"}`.deserialize!S);
}

///
unittest
{
    import asdf;

    static struct S
    {
        @serdeKeyOut("a")
        string s;
    }
    assert(`{"s":"d"}`.deserialize!S.serializeToJson == `{"a":"d"}`);
}

///
unittest
{
    import asdf;

    static struct S
    {
        @serdeIgnore
        string s;
    }
    assert(`{"s":"d"}`.deserialize!S.s == null);
    assert(S("d").serializeToJson == `{}`);
}

///
unittest
{
    import asdf;

    static struct Decor
    {
        int candles; // 0
        float fluff = float.infinity; // inf 
    }
    
    static struct Cake
    {
        @serdeIgnoreDefault
        string name = "Chocolate Cake";
        int slices = 8;
        float flavor = 1;
        @serdeIgnoreDefault
        Decor dec = Decor(20); // { 20, inf }
    }
    
    assert(Cake("Normal Cake").serializeToJson == `{"name":"Normal Cake","slices":8,"flavor":1.0}`);
    auto cake = Cake.init;
    cake.dec = Decor.init;
    assert(cake.serializeToJson == `{"slices":8,"flavor":1.0,"dec":{"candles":0,"fluff":"inf"}}`);
    assert(cake.dec.serializeToJson == `{"candles":0,"fluff":"inf"}`);
    
    static struct A
    {
        @serdeIgnoreDefault
        string str = "Banana";
        int i = 1;
    }
    assert(A.init.serializeToJson == `{"i":1}`);
    
    static struct S
    {
        @serdeIgnoreDefault
        A a;
    }
    assert(S.init.serializeToJson == `{}`);
    assert(S(A("Berry")).serializeToJson == `{"a":{"str":"Berry","i":1}}`);
    
    static struct D
    {
        S s;
    }
    assert(D.init.serializeToJson == `{"s":{}}`);
    assert(D(S(A("Berry"))).serializeToJson == `{"s":{"a":{"str":"Berry","i":1}}}`);
    assert(D(S(A(null, 0))).serializeToJson == `{"s":{"a":{"str":null,"i":0}}}`);
    
    static struct F
    {
        D d;
    }
    assert(F.init.serializeToJson == `{"d":{"s":{}}}`);
}

///
unittest
{
    import asdf;

    static struct S
    {
        @serdeIgnoreIn
        string s;
    }
    assert(`{"s":"d"}`.deserialize!S.s == null);
    assert(S("d").serializeToJson == `{"s":"d"}`);
}

///
unittest
{
    static struct S
    {
        @serdeIgnoreOut
        string s;
    }
    assert(`{"s":"d"}`.deserialize!S.s == "d");
    assert(S("d").serializeToJson == `{}`);
}

///
unittest
{
    import asdf;

    static struct S
    {
        @serdeIgnoreOutIf!`a < 0`
        int a;
    }

    assert(serializeToJson(S(3)) == `{"a":3}`, serializeToJson(S(3)));
    assert(serializeToJson(S(-3)) == `{}`);
}

///
unittest
{
    import asdf;

    import std.uuid;

    static struct S
    {
        @serdeScoped
        @serdeProxy!string
        UUID id;
    }
    assert(`{"id":"8AB3060E-2cba-4f23-b74c-b52db3bdfb46"}`.deserialize!S.id
                == UUID("8AB3060E-2cba-4f23-b74c-b52db3bdfb46"));
}

/// Proxy type for array of algebraics
unittest
{
    import asdf;
    import mir.algebraic: Variant;

    static struct ObjectA
    {
        string name;
    }
    static struct ObjectB
    {
        double value;
    }

    alias MyObject = Variant!(ObjectA, ObjectB);

    static struct MyObjectArrayProxy
    {
        MyObject[] array;

        this(MyObject[] array) @safe pure nothrow @nogc
        {
            this.array = array;
        }

        T opCast(T : MyObject[])()
        {
            return array;
        }

        void serialize(S)(ref S serializer) const
        {
            auto state = serializer.listBegin;
            foreach (ref e; array)
            {
                serializer.elemBegin();
                // mir.algebraic has builtin support for serialization.
                // For other algebraic libraies one can use thier visitor handlers.
                serializeValue(serializer, e);
            }
            serializer.listEnd(state);
        }

        auto deserializeFromAsdf(Asdf asdfData)
        {
            import asdf : deserializeValue;
            import std.traits : EnumMembers;

            foreach (e; asdfData.byElement)
            {
                if (e["name"] != Asdf.init)
                {
                    array ~= MyObject(deserialize!ObjectA(e));
                }
                else
                {
                    array ~= MyObject(deserialize!ObjectB(e));
                }
            }

            return SerdeException.init;
        }
    }

    static struct SomeObject
    {
        @serdeProxy!MyObjectArrayProxy MyObject[] objects;
    }

    string data = q{{"objects":[{"name":"test"},{"value":1.5}]}};

    auto value = data.deserialize!SomeObject;
    assert (value.serializeToJson == data);
}

///
unittest
{
    import asdf;

    import std.range;
    import std.uuid;

    static struct S
    {
        private int count;
        @serdeLikeList
        auto numbers() @property // uses `foreach`
        {
            return iota(count);
        }

        @serdeLikeList
        @serdeProxy!string // input element type of
        @serdeIgnoreOut
        Appender!(string[]) strings; //`put` method is used
    }

    assert(S(5).serializeToJson == `{"numbers":[0,1,2,3,4]}`);
    assert(`{"strings":["a","b"]}`.deserialize!S.strings.data == ["a","b"]);
}

///
unittest
{
    import asdf;

    static struct M
    {
        private int sum;

        // opApply is used for serialization
        int opApply(int delegate(in char[] key, int val) pure dg) pure
        {
            if(auto r = dg("a", 1)) return r;
            if(auto r = dg("b", 2)) return r;
            if(auto r = dg("c", 3)) return r;
            return 0;
        }

        // opIndexAssign for deserialization
        void opIndexAssign(int val, string key) pure
        {
            sum += val;
        }
    }

    static struct S
    {
        @serdeLikeStruct
        @serdeProxy!int
        M obj;
    }

    assert(S.init.serializeToJson == `{"obj":{"a":1,"b":2,"c":3}}`);
    assert(`{"obj":{"a":1,"b":2,"c":9}}`.deserialize!S.obj.sum == 12);
}

///
unittest
{
    import asdf;
    import std.range;
    import std.algorithm;
    import std.conv;

    static struct S
    {
        @serdeTransformIn!"a += 2"
        @serdeTransformOut!(a =>"str".repeat.take(a).joiner("_").to!string)
        int a;
    }

    auto s = deserialize!S(`{"a":3}`);
    assert(s.a == 5);
    assert(serializeToJson(s) == `{"a":"str_str_str_str_str"}`);
}

/// JSON serialization back-end
struct JsonSerializer(string sep, Dg)
{
    import asdf.jsonbuffer;

    static if(sep.length)
    {
        private size_t deep;

        private void putSpace()
        {
            for(auto k = deep; k; k--)
            {
                static if(sep.length == 1)
                {
                    sink.put(sep[0]);
                }
                else
                {
                    sink.put!sep;
                }
            }
        }
    }


    /// JSON string buffer
    JsonBuffer!Dg sink;

    ///
    this(Dg sink)
    {
        this.sink = JsonBuffer!Dg(sink);
    }

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
        {
            static if(sep.length)
            {
                sink.put!",\n";
            }
            else
            {
                sink.put(',');
            }
        }
    }

    /// Serialization primitives
    uint structBegin(size_t length = 0)
    {
        static if(sep.length)
        {
            deep++;
            sink.put!"{\n";
        }
        else
        {
            sink.put('{');
        }
        return popState;
    }

    ///ditto
    void structEnd(uint state)
    {
        static if(sep.length)
        {
            deep--;
            sink.put('\n');
            putSpace;
        }
        sink.put('}');
        pushState(state);
    }

    ///ditto
    uint listBegin(size_t length = 0)
    {
        static if(sep.length)
        {
            deep++;
            sink.put!"[\n";
        }
        else
        {
            sink.put('[');
        }
        return popState;
    }

    ///ditto
    void listEnd(uint state)
    {
        static if(sep.length)
        {
            deep--;
            sink.put('\n');
            putSpace;
        }
        sink.put(']');
        pushState(state);
    }

    ///ditto
    void putEscapedKey(in char[] key)
    {
        incState;
        static if(sep.length)
        {
            putSpace;
        }
        sink.put('\"');
        sink.putSmallEscaped(key);
        static if(sep.length)
        {
            sink.put!"\": ";
        }
        else
        {
            sink.put!"\":";
        }
    }

    ///ditto
    void putKey(in char[] key)
    {
        incState;
        static if(sep.length)
        {
            putSpace;
        }
        sink.put('\"');
        sink.put(key);
        static if(sep.length)
        {
            sink.put!"\": ";
        }
        else
        {
            sink.put!"\":";
        }
    }

    ///ditto
    void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init)
    {
        auto f = &sink.putSmallEscaped;
        static if (isNumeric!Num)
        {
            static struct S
            {
                typeof(f) fun;
                auto put(scope const(char)[] str)
                {
                    fun(str);
                }
            }
            auto app = S(f);
            if (fmt == FormatSpec!char.init)
            {
                import mir.format: print;
                print(app, num);
                return;
            }
        }
        assumePure((typeof(f) fun) => formatValue(fun, num, fmt))(f);
    }

    ///ditto
    void putValue(typeof(null))
    {
        sink.put!"null";
    }

    ///ditto
    import mir.timestamp: Timestamp;
    void putValue(Timestamp timestamp)
    {
        import mir.format: stringBuf, getData;
        putValue(stringBuf() << timestamp << getData);
    }

    ///ditto
    void putValue(bool b)
    {
        if(b)
            sink.put!"true";
        else
            sink.put!"false";
    }

    ///ditto
    void putValue(in char[] str)
    {
        sink.put('\"');
        sink.put(str);
        sink.put('\"');
    }

    ///ditto
    void putValue(Num)(Num num)
        if (isNumeric!Num && !is(Num == enum))
    {
        putNumberValue(num);
    }

    ///ditto
    void elemBegin()
    {
        incState;
        static if(sep.length)
        {
            putSpace;
        }
    }

    ///ditto
    void flush()
    {
        sink.flush;
    }

    deprecated("Use structBegin instead") alias objectBegin = structBegin;
    deprecated("Use structEnd instead") alias objectEnd = structEnd;
    deprecated("Use listBegin instead") alias arrayBegin = listBegin;
    deprecated("Use listEnd instead") alias arrayEnd = listEnd;
}

/++
Creates JSON serialization back-end.
Use `sep` equal to `"\t"` or `"    "` for pretty formatting.
+/
auto jsonSerializer(string sep = "", Dg)(scope Dg sink)
{
    return JsonSerializer!(sep, Dg)(sink);
}

///
unittest
{
    import asdf;

    import std.array;
    import std.bigint;
    import std.format: singleSpec;

    auto app = appender!string;
    auto ser = jsonSerializer(&app.put!(const(char)[]));
    auto state0 = ser.structBegin;

        ser.putEscapedKey("null");
        ser.putValue(null);

        ser.putEscapedKey("array");
        auto state1 = ser.listBegin();
            ser.elemBegin; ser.putValue(null);
            ser.elemBegin; ser.putValue(123);
            ser.elemBegin; ser.putNumberValue(12300000.123, singleSpec("%.10e"));
            ser.elemBegin; ser.putValue("\t");
            ser.elemBegin; ser.putValue("\r");
            ser.elemBegin; ser.putValue("\n");
            ser.elemBegin; ser.putNumberValue(BigInt("1234567890"));
        ser.listEnd(state1);

    ser.structEnd(state0);
    ser.flush;

    assert(app.data == `{"null":null,"array":[null,123,1.2300000123e+07,"\t","\r","\n",1234567890]}`);
}

unittest
{
    import std.array;
    import std.bigint;
    import std.format: singleSpec;

    auto app = appender!string;
    auto ser = jsonSerializer!"    "(&app.put!(const(char)[]));
    auto state0 = ser.structBegin;

        ser.putEscapedKey("null");
        ser.putValue(null);

        ser.putEscapedKey("array");
        auto state1 = ser.listBegin();
            ser.elemBegin; ser.putValue(null);
            ser.elemBegin; ser.putValue(123);
            ser.elemBegin; ser.putNumberValue(12300000.123, singleSpec("%.10e"));
            ser.elemBegin; ser.putValue("\t");
            ser.elemBegin; ser.putValue("\r");
            ser.elemBegin; ser.putValue("\n");
            ser.elemBegin; ser.putNumberValue(BigInt("1234567890"));
        ser.listEnd(state1);

    ser.structEnd(state0);
    ser.flush;

    assert(app.data ==
`{
    "null": null,
    "array": [
        null,
        123,
        1.2300000123e+07,
        "\t",
        "\r",
        "\n",
        1234567890
    ]
}`);
}

/// ASDF serialization back-end
struct AsdfSerializer
{
    /// Output buffer
    OutputArray app;

    import asdf.outputarray;
    import asdf.asdf;
    private uint state;

pure:

    /// Serialization primitives
    size_t structBegin(size_t length = 0)
    {
        app.put1(Asdf.Kind.object);
        return app.skip(4);
    }

    ///ditto
    void structEnd(size_t state)
    {
        app.put4(cast(uint)(app.shift - state - 4), state);
    }

    ///ditto
    size_t listBegin(size_t length = 0)
    {
        app.put1(Asdf.Kind.array);
        return app.skip(4);
    }

    ///ditto
    void listEnd(size_t state)
    {
        app.put4(cast(uint)(app.shift - state - 4), state);
    }

    ///ditto
    alias putEscapedKey = putKey;

    ///ditto
    void putKey(in char[] key)
    {
        auto sh = app.skip(1);
        app.put(key);
        app.put1(cast(ubyte)(app.shift - sh - 1), sh);
    }

    ///ditto
    void putNumberValue(Num)(Num num, FormatSpec!char fmt = FormatSpec!char.init) pure
    {
        app.put1(Asdf.Kind.number);
        auto sh = app.skip(1);
        static if (isNumeric!Num)
        {
            if (fmt == FormatSpec!char.init)
            {
                import mir.format: print;
                print(app, num);
                app.put1(cast(ubyte)(app.shift - sh - 1), sh);
                return;
            }
        }
        assumePure((ref OutputArray app) => formatValue(app, num, fmt))(app);
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
    import mir.timestamp: Timestamp;
    void putValue(Timestamp timestamp)
    {
        import mir.format: stringBuf, getData;
        putValue(stringBuf() << timestamp << getData);
    }

    ///ditto
    void putValue(in char[] str)
    {
        app.put1(Asdf.Kind.string);
        auto sh = app.skip(4);
        app.put(str);
        app.put4(cast(uint)(app.shift - sh - 4), sh);
    }

    ///ditto
    void putValue(Num)(Num num)
        if (isNumeric!Num && !is(Num == enum))
    {
        putNumberValue(num);
    }

    ///
    void putValue(Num)(const Num value)
        if (isNumeric!Num && !is(Num == enum))
    {
        import mir.format: print;
        import mir.internal.utility: isFloatingPoint;

        static if (isFloatingPoint!Num)
        {
            import mir.math.common: fabs;

            if (value.fabs < value.infinity)
                print(app, value);
            else if (value == Num.infinity)
                app.put(`"+inf"`);
            else if (value == -Num.infinity)
                app.put(`"-inf"`);
            else
                app.put(`"nan"`);
        }
        else
            print(app, value);
    }

    ///ditto
    static void elemBegin()
    {
    }

    ///ditto
    static void flush()
    {
    }

    deprecated("Use structBegin instead") alias objectBegin = structBegin;
    deprecated("Use structEnd instead") alias objectEnd = structEnd;
    deprecated("Use listBegin instead") alias arrayBegin = listBegin;
    deprecated("Use listEnd instead") alias arrayEnd = listEnd;
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
    import asdf;
    import mir.conv: to;
    import std.bigint;
    import std.format: singleSpec;

    auto ser = asdfSerializer();
    auto state0 = ser.structBegin;

        ser.putEscapedKey("null");
        ser.putValue(null);

        ser.putKey("array");
        auto state1 = ser.listBegin();
            ser.elemBegin; ser.putValue(null);
            ser.elemBegin; ser.putValue(123);
            ser.elemBegin; ser.putNumberValue(12300000.123, singleSpec("%.10e"));
            ser.elemBegin; ser.putValue("\t");
            ser.elemBegin; ser.putValue("\r");
            ser.elemBegin; ser.putValue("\n");
            ser.elemBegin; ser.putNumberValue(BigInt("1234567890"));
        ser.listEnd(state1);

    ser.structEnd(state0);

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
    import asdf;

    assert(serializeToJson(null) == `null`);
}

/// Number serialization
void serializeValue(S, V)(ref S serializer, in V value, FormatSpec!char fmt = FormatSpec!char.init)
    if((isNumeric!V && !is(V == enum)) || is(V == BigInt))
{
    static if (isFloatingPoint!V)
    {
        import std.math : isNaN, isFinite, signbit;

        if (isFinite(value))
            serializer.putNumberValue(value, fmt);
        else if (value.isNaN)
            serializer.putValue(signbit(value) ? "-nan" : "nan");
        else if (value == V.infinity)
            serializer.putValue("inf");
        else if (value == -V.infinity)
            serializer.putValue("-inf");
    }
    else
        serializer.putNumberValue(value, fmt);
}

///
unittest
{
    import std.bigint;

    assert(serializeToJson(BigInt(123)) == `123`);
    assert(serializeToJson(2.40f) == `2.4`);
    assert(serializeToJson(float.nan) == `"nan"`);
    assert(serializeToJson(float.infinity) == `"inf"`);
    assert(serializeToJson(-float.infinity) == `"-inf"`);
}

/// Boolean serialization
void serializeValue(S, V)(ref S serializer, const V value)
    if (is(V == bool) && !is(V == enum))
{
    serializer.putValue(value);
}

/// Char serialization
void serializeValue(S, V : char)(ref S serializer, const V value)
    if (is(V == char) && !is(V == enum))
{
    auto v = cast(char[1])value;
    serializer.putValue(v[]);
}

///
unittest
{
    assert(serializeToJson(true) == `true`);
}

/// Enum serialization
void serializeValue(S, V)(ref S serializer, in V value)
    if(is(V == enum))
{
    static if (hasUDA!(V, serdeProxy))
    {
        serializer.serializeValue(value.to!(serdeGetProxy!V));
    }
    else
    {
        serializer.putValue(serdeGetKeyOut(value));
    }
}

///
unittest
{
    enum Key { @serdeKeys("FOO", "foo") foo }
    assert(serializeToJson(Key.foo) == `"FOO"`);
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
    auto state = serializer.listBegin();
    foreach (ref elem; value)
    {
        serializer.elemBegin;
        serializer.serializeValue(elem);
    }
    serializer.listEnd(state);
}

/// Input range serialization
void serializeValue(S, R)(ref S serializer, R value)
    if ((isInputRange!R) &&
        !isSomeChar!(ElementType!R) &&
        !isDynamicArray!R &&
        !isStdNullable!R)
{
    auto state = serializer.listBegin();
    foreach (ref elem; value)
    {
        serializer.elemBegin;
        serializer.serializeValue(elem);
    }
    serializer.listEnd(state);
}

/// input range serialization
unittest
{
    import std.algorithm : filter;

    struct Foo
    {
        int i;
    }

    auto ar = [Foo(1), Foo(3), Foo(4), Foo(17)];

    auto filtered1 = ar.filter!"a.i & 1";
    auto filtered2 = ar.filter!"!(a.i & 1)";

    assert(serializeToJson(filtered1) == `[{"i":1},{"i":3},{"i":17}]`);
    assert(serializeToJson(filtered2) == `[{"i":4}]`);
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
    auto state = serializer.structBegin();
    foreach (key, ref val; value)
    {
        serializer.putKey(key);
        serializer.serializeValue(val);
    }
    serializer.structEnd(state);
}

///
unittest
{
    uint[string] ar = ["a" : 1];
    assert(serializeToJson(ar) == `{"a":1}`);
    ar.remove("a");
    assert(serializeToJson(ar) == `{}`);
    assert(serializeToJson((uint[string]).init) == `null`);
}

/// Enumeration-value associative array serialization
void serializeValue(S, V : const T[K], T, K)(ref S serializer, V value)
    if(is(K == enum))
{
    if(value is null)
    {
        serializer.putValue(null);
        return;
    }
    auto state = serializer.structBegin();
    foreach (key, ref val; value)
    {
        serializer.putEscapedKey(key.to!string);
        serializer.putValue(val);
    }
    serializer.structEnd(state);
}

///
unittest
{
    enum E { a, b }
    uint[E] ar = [E.a : 1];
    assert(serializeToJson(ar) == `{"a":1}`);
    ar.remove(E.a);
    assert(serializeToJson(ar) == `{}`);
    assert(serializeToJson((uint[string]).init) == `null`);
}

/// integral typed value associative array serialization
void serializeValue(S,  V : const T[K], T, K)(ref S serializer, V value)
    if((isIntegral!K) && !is(K == enum))
{
    if(value is null)
    {
        serializer.putValue(null);
        return;
    }
    char[40] buffer = void;
    auto state = serializer.structBegin();
    foreach (key, ref val; value)
    {
        import std.format : sformat;
        auto str = sformat(buffer[], "%d", key);
        serializer.putEscapedKey(str);
        .serializeValue(serializer, val);
    }
    serializer.structEnd(state);
}

///
unittest
{
    uint[short] ar = [256 : 1];
    assert(serializeToJson(ar) == `{"256":1}`);
    ar.remove(256);
    assert(serializeToJson(ar) == `{}`);
    assert(serializeToJson((uint[string]).init) == `null`);
    assert(deserialize!(uint[short])(`{"256":1}`) == cast(uint[short]) [256 : 1]);
}

/// Nullable type serialization
void serializeValue(S, N)(ref S serializer, auto ref N value)
    if (isStdNullable!N && !isVariant!N)
{
    if(value.isNull)
    {
        serializer.putValue(null);
        return;
    }
    serializer.serializeValue(value.get);
}

///
unittest
{
    import std.typecons;

    struct Nested
    {
        float f;
    }

    struct T
    {
        string str;
        Nullable!Nested nested;
    }

    T t;
    assert(t.serializeToJson == `{"str":null,"nested":null}`);
    t.str = "txt";
    t.nested = Nested(123);
    assert(t.serializeToJson == `{"str":"txt","nested":{"f":123.0}}`);
}

/// Struct and class type serialization
void serializeValue(S, V)(ref S serializer, auto ref V value)
    if((!isStdNullable!V || isVariant!V) && isAggregateType!V && !is(V : BigInt) && !isInputRange!V)
{
    import mir.timestamp: Timestamp;
    import mir.algebraic : Algebraic;
    import mir.string_map : isStringMap;
    static if(is(V == class) || is(V == interface))
    {
        if(value is null)
        {
            serializer.putValue(null);
            return;
        }
    }

    static if (is(Unqual!V == Timestamp))
    {
        serializer.putValue(value);
    }
    else
    static if (is(Unqual!V == Algebraic!TypeSet, TypeSet...))
    {
        import mir.algebraic: visit;
        value.visit!((auto ref v) {
            alias T = typeof(v);
            static if (isStringMap!T )
            {
                if(v == v.init)
                {
                    auto valState = serializer.structBegin();
                    serializer.structEnd(valState);
                    return;
                }
            }
            else
            static if (isAssociativeArray!T)
            {
                if(v is null)
                {
                    auto valState = serializer.structBegin();
                    serializer.structEnd(valState);
                    return;
                }
            }
            else
            static if (isSomeString!T)
            {
                if(v is null)
                {
                    serializer.putValue("");
                    return;
                }
            }
            else
            static if (isDynamicArray!T)
            {
                if(v is null)
                {
                    auto valState = serializer.listBegin();
                    serializer.listEnd(valState);
                    return;
                }
            }
            .serializeValue(serializer, v);
        });
    }
    else
    static if (isStringMap!V)
    {
        if(value == value.init)
        {
            serializer.putValue(null);
            return;
        }
        auto valState = serializer.structBegin();
        foreach (i, key; value.keys)
        {
            serializer.putKey(key);
            serializer.serializeValue(value.values[i]);
        }
        serializer.structEnd(valState);
        return;
    }
    else
    static if(__traits(hasMember, V, "serialize"))
    {
        value.serialize(serializer);
    }
    else
    static if (hasUDA!(V, serdeProxy))
    {
        serializer.serializeValue(value.to!(serdeGetProxy!V));
    }
    else
    {
        auto state = serializer.structBegin();
        foreach(member; aliasSeqOf!(SerializableMembers!V))
        {{
            enum key = serdeGetKeyOut!(__traits(getMember, value, member));

            static if (key !is null)
            {
                static if (hasUDA!(__traits(getMember, value, member), serdeIgnoreDefault))
                {
                    if (__traits(getMember, value, member) == __traits(getMember, V.init, member))
                        continue;
                }
                
                static if(hasUDA!(__traits(getMember, value, member), serdeIgnoreOutIf))
                {
                    alias pred = serdeGetIgnoreOutIf!(__traits(getMember, value, member));
                    if (pred(__traits(getMember, value, member)))
                        continue;
                }
                static if(hasUDA!(__traits(getMember, value, member), serdeTransformOut))
                {
                    alias f = serdeGetTransformOut!(__traits(getMember, value, member));
                    auto val = f(__traits(getMember, value, member));
                }
                else
                {
                    auto val = __traits(getMember, value, member);
                }

                serializer.putEscapedKey(key);

                static if(hasUDA!(__traits(getMember, value, member), serdeLikeList))
                {
                    alias V = typeof(val);
                    static if(is(V == interface) || is(V == class) || is(V : E[], E))
                    {
                        if(val is null)
                        {
                            serializer.putValue(null);
                            continue;
                        }
                    }
                    auto valState = serializer.listBegin();
                    foreach (ref elem; val)
                    {
                        serializer.elemBegin;
                        serializer.serializeValue(elem);
                    }
                    serializer.listEnd(valState);
                }
                else
                static if(hasUDA!(__traits(getMember, value, member), serdeLikeStruct))
                {
                    static if(is(V == interface) || is(V == class) || is(V : E[T], E, T))
                    {
                        if(val is null)
                        {
                            serializer.putValue(null);
                            continue F;
                        }
                    }
                    auto valState = serializer.structBegin();
                    foreach (key, elem; val)
                    {
                        serializer.putKey(key);
                        serializer.serializeValue(elem);
                    }
                    serializer.structEnd(valState);
                }
                else
                static if(hasUDA!(__traits(getMember, value, member), serdeProxy))
                {
                    serializer.serializeValue(val.to!(serdeGetProxy!(__traits(getMember, value, member))));
                }
                else
                {
                    serializer.serializeValue(val);
                }
            }
        }}
        static if(__traits(hasMember, V, "finalizeSerialization"))
        {
            value.finalizeSerialization(serializer);
        }
        serializer.structEnd(state);
    }
}

/// Alias this support
unittest
{
    struct S
    {
        int u;
    }

    struct C
    {
        int b;
        S s;
        alias s this; 
    }

    assert(C(4, S(3)).serializeToJson == `{"u":3,"b":4}`);
}

/// Custom `serialize`
unittest
{
    import mir.conv: to;

    struct S
    {
        void serialize(S)(ref S serializer) const
        {
            auto state = serializer.structBegin;
            serializer.putEscapedKey("foo");
            serializer.putValue("bar");
            serializer.structEnd(state);
        }
    }
    enum json = `{"foo":"bar"}`;
    assert(serializeToJson(S()) == json);
    assert(serializeToAsdf(S()).to!string == json);
}

/// $(GMREF mir-core, mir, algebraic) support.
unittest
{
    import mir.algebraic: Variant, Nullable, This;
    alias V = Nullable!(double, string, This[], This[string]);
    V v;
    assert(v.serializeToJson == "null", v.serializeToJson);
    v = [V(2), V("str"), V(["key":V(1.0)])];
    assert(v.serializeToJson == `[2.0,"str",{"key":1.0}]`);
}

/// $(GMREF mir-core, mir, algebraic) with manual serialization.
unittest
{
    import asdf.asdf;

    static struct Response
    {
        import mir.algebraic: Variant;

        static union Response_
        {
            double double_;
            immutable(char)[] string;
            Response[] array;
            Response[immutable(char)[]] table;
        }

        alias Union = Variant!Response_;

        Union data;
        alias Tag = Union.Kind;
        // propogates opEquals, opAssign, and other primitives
        alias data this;

        static foreach (T; Union.AllowedTypes)
            this(T v) @safe pure nothrow @nogc { data = v; }

        void serialize(S)(ref S serializer) const
        {
            import asdf: serializeValue;
            import mir.algebraic: visit;

            auto o = serializer.structBegin();
            serializer.putKey("tag");
            serializer.serializeValue(kind);
            serializer.putKey("data");
            data.visit!(
                (double v) => serializer.serializeValue(v), // specialization for double if required
                (const Response[string] v) => serializer.serializeValue(cast(const(Response)[string])v),
                (v) => serializer.serializeValue(v),
            );
            serializer.structEnd(o);
        }

        SerdeException deserializeFromAsdf(Asdf asdfData)
        {
            import asdf : deserializeValue;
            import std.traits : EnumMembers;

            Tag tag;
            if (auto e = asdfData["tag"].deserializeValue(tag))
                return e;
            final switch (tag)
            {
                foreach (m; EnumMembers!Tag)
                {
                    case m: {
                        alias T = Union.AllowedTypes[m];
                        data = T.init;
                        if (auto e = asdfData["data"].deserializeValue(data.trustedGet!T))
                            return e;
                        break;
                    }
                }
            }
            return null;
        }
    }

    Response v = 3.0;
    assert(v.kind == Response.Tag.double_);
    v = "str";
    assert(v == "str");

    import asdf;
    assert(v.serializeToJson == `{"tag":"string","data":"str"}`);
    v = Response.init;
    v = `{"tag":"array","data":[{"tag":"string","data":"S"}]}`.deserialize!Response;
    assert(v.kind == Response.Tag.array);
    assert(v.get!(Response[])[0] == "S");
}

/// Deserialize `null` value
SerdeException deserializeValue(T : typeof(null))(Asdf data, T)
{
    auto kind = data.kind;
    if(kind != Asdf.Kind.null_)
        return unexpectedKind(kind);
    return null;
}

///
unittest
{
    assert(deserializeValue(serializeToAsdf(null), null) is null);
}

/// Deserialize boolean value
SerdeException deserializeValue(T : bool)(Asdf data, ref T value) pure @safe
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case false_:
            value = false;
            return null;
        case true_:
            value = true;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

///
pure unittest
{
    assert(deserialize!bool(serializeToAsdf(true)));
    assert(deserialize!bool(serializeToJson(true)));
}

/++
Deserialize numeric value.

Special_deserialisation_string_values:

$(TABLE
    $(TR $(TD `"+NAN"`))
    $(TR $(TD `"+NaN"`))
    $(TR $(TD `"+nan"`))
    $(TR $(TD `"-NAN"`))
    $(TR $(TD `"-NaN"`))
    $(TR $(TD `"-nan"`))
    $(TR $(TD `"NAN"`))
    $(TR $(TD `"NaN"`))
    $(TR $(TD `"nan"`))
    $(TR $(TD `"+INF"`))
    $(TR $(TD `"+Inf"`))
    $(TR $(TD `"+inf"`))
    $(TR $(TD `"-INF"`))
    $(TR $(TD `"-Inf"`))
    $(TR $(TD `"-inf"`))
    $(TR $(TD `"INF"`))
    $(TR $(TD `"Inf"`))
    $(TR $(TD `"inf"`))
)

+/
SerdeException deserializeValue(V)(Asdf data, ref V value)
    if((isNumeric!V && !is(V == enum)))
{
    auto kind = data.kind;

    static if (isFloatingPoint!V)
    {
        if (kind == Asdf.Kind.null_)
        {
            value = V.nan;
            return null;
        }
        if (kind == Asdf.Kind.string)
        {
            const(char)[] v;
            .deserializeScopedString(data, v);
            switch (v)
            {
                case "+NAN":
                case "+NaN":
                case "+nan":
                case "-NAN":
                case "-NaN":
                case "-nan":
                case "NAN":
                case "NaN":
                case "nan":
                    value = V.nan;
                    return null;
                case "+INF":
                case "+Inf":
                case "+inf":
                case "INF":
                case "Inf":
                case "inf":
                    value = V.infinity;
                    return null;
                case "-INF":
                case "-Inf":
                case "-inf":
                    value = -V.infinity;
                    return null;
                default:
                    import mir.conv : to;
                    value = data.to!V;
                    return null;
            }
        }
    }

    if(kind != Asdf.Kind.number)
        return unexpectedKind(kind);

    static if (isFloatingPoint!V)
    {
        import mir.bignum.internal.dec2float: decimalToFloatImpl;
        import mir.bignum.internal.parse: parseJsonNumberImpl;
        auto result = (cast(string) data.data[2 .. $]).parseJsonNumberImpl;
        if (!result.success)
            throw new Exception("Failed to deserialize number");

        auto fp = decimalToFloatImpl!(Unqual!V)(result.coefficient, result.exponent);
        if (result.sign)
            fp = -fp;
        value = fp;
    }
    else
    {
        value = (cast(string) data.data[2 .. $]).to!V;
    }
    return null;
}

///
unittest
{
    import std.bigint;

    assert(deserialize!ulong (serializeToAsdf(20)) == ulong (20));
    assert(deserialize!ulong (serializeToJson(20)) == ulong (20));
    assert(deserialize!double(serializeToAsdf(20)) == double(20));
    assert(deserialize!double(serializeToJson(20)) == double(20));
    assert(deserialize!BigInt(serializeToAsdf(20)) == BigInt(20));
    assert(deserialize!BigInt(serializeToJson(20)) == BigInt(20));

    assert(deserialize!float (serializeToJson ("2.40")) == float (2.40));
    assert(deserialize!double(serializeToJson ("2.40")) == double(2.40));
    assert(deserialize!double(serializeToAsdf("-2.40")) == double(-2.40));

    import std.math : isNaN, isInfinity;
    assert(deserialize!float (serializeToJson  ("+NaN")).isNaN);
    assert(deserialize!float (serializeToJson  ("INF")).isInfinity);
    assert(deserialize!float (serializeToJson ("-inf")).isInfinity);
}

/// Deserialize enum value
SerdeException deserializeValue(V)(Asdf data, ref V value)
    if(is(V == enum))
{
    static if (hasUDA!(V, serdeProxy))
    {
        serdeGetProxy!V proxy;
        enum S = hasUDA!(value, serdeScoped) && __traits(compiles, .deserializeScopedString(data, proxy));
        alias Fun = Select!(S, .deserializeScopedString, .deserializeValue);
        Fun(data, proxy);
        value = proxy.to!V;
    }
    else
    {
        string s;
        data.deserializeScopedString(s);
        import mir.ndslice.fuse: fuse;
        import mir.array.allocation: array;
        import mir.ndslice.topology: map;
        static immutable allowedKeys = [EnumMembers!V].map!serdeGetKeysIn.array;
        if (!serdeParseEnum(s, value))
            throw new Exception("Unable to deserialize string '" ~ s ~ "' to " ~ V.stringof ~ "Allowed keys:" ~ allowedKeys.stringof);
    }
    return null;
}

///
unittest
{
    @serdeIgnoreCase enum Key { foo }
    assert(deserialize!Key(`"FOO"`) == Key.foo);
    assert(deserialize!Key(serializeToAsdf("foo")) == Key.foo);
}

/++
Deserializes scoped string value.
This function does not allocate a new string and just make a raw cast of ASDF data.
+/
SerdeException deserializeScopedString(V : const(char)[])(Asdf data, ref V value)
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case string:
            value = cast(V) data.data[5 .. $];
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

/++
Deserializes string value.
This function allocates new string.
+/
SerdeException deserializeValue(V)(Asdf data, ref V value)
    if(is(V : const(char)[]) && !isAggregateType!V && !is(V == enum) && !isStdNullable!V)
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case string:
            value = (() @trusted => cast(V) (data.data[5 .. $]).dup)();
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

// issue #94/#95/#97
/// String enums supports only enum keys
unittest
{
    enum SimpleEnum : string
    {
        @serdeKeys("se1", "se1value")
        se1 = "se1value",

        @serdeKeys("se2", "se2value")
        se2 = "se2value",

        @serdeKeys("se3", "se3value")
        se3 = "se3value",
    }

    struct Simple
    {
        SimpleEnum en;
        SimpleEnum ex;
    }

    Simple simple = `{"en":"se2", "ex":"se3value"}`.deserialize!Simple;
    assert(simple.en == SimpleEnum.se2);
    assert(simple.ex == SimpleEnum.se3);
}

/// issue #115
unittest
{
    import asdf;
    import std.typecons;

    struct Example
    {
        @serdeOptional
        Nullable!string field1;
    }

    assert(`{}`.deserialize!Example == Example());
    assert(Example().serializeToJson == `{"field1":null}`);
}

///
unittest
{
    assert(deserialize!string(serializeToJson(null)) is null);
    assert(deserialize!string(serializeToAsdf(null)) is null);
    assert(deserialize!string(serializeToJson("\tbar")) == "\tbar");
    assert(deserialize!string(serializeToAsdf("\"bar")) == "\"bar");
}

/// Deserialize single char
SerdeException deserializeValue(V)(Asdf data, ref V value)
    if (is(V == char) && !is(V == enum))
{
    return deserializeValue(data, *(()@trusted=> cast(char[1]*)&value)());
}

///
unittest
{
    assert(deserialize!char(`"a"`) == 'a');
    assert(deserialize!byte(`-4`) == -4); // regression control
}

/// Deserialize array
SerdeException deserializeValue(V : T[], T)(Asdf data, ref V value)
    if(!isSomeChar!T && !isStaticArray!V)
{
    const kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case array:
            import std.algorithm.searching: count;
            auto elems = data.byElement;
            // create array of properly initialized (by means of ctor) elements
            static if (__traits(compiles, {value = new T[100];}))
            {
                value = new T[elems.save.count];
                foreach(ref e; value)
                {
                    static if(is(T == class)) e = new T;
                    if (auto exc = .deserializeValue(elems.front, e))
                        return exc;
                    elems.popFront;
                }
            }
            else
                static assert(0, "Type `" ~ T.stringof ~ "` should have default value!");
            assert(elems.empty);
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

///
unittest
{
    assert(deserialize!(int[])(serializeToJson(null)) is null);
    assert(deserialize!(int[])(serializeToAsdf(null)) is null);
    assert(deserialize!(int[])(serializeToJson([1, 3, 4])) == [1, 3, 4]);
    assert(deserialize!(int[])(serializeToAsdf([1, 3, 4])) == [1, 3, 4]);
}

/// Deserialize static array
SerdeException deserializeValue(V : T[N], T, size_t N)(Asdf data, ref V value)
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        static if(is(Unqual!T == char))
        {
        case string:
            auto str = cast(immutable(char)[]) data;
            // if source is shorter than destination fill the rest by zeros
            // if source is longer copy only needed part of it
            if (str.length > value.length)
                str = str[0..value.length];
            else
                value[] = '\0';

            import std.algorithm : copy;
            copy(str, value[]);
            return null;
        }
        case array:
            auto elems = data.byElement;
            foreach(ref e; value)
            {
                if(elems.empty)
                    return null;
                if (auto exc = .deserializeValue(elems.front, e))
                    return exc;
                elems.popFront;
            }
            return null;
        case null_:
            return null;
        default:
            return unexpectedKind!("Failed to deserialize value of " ~ V.stringof)(kind);
    }
}

///
unittest
{
    assert(deserialize!(int[4])(serializeToJson(null)) == [0, 0, 0, 0]);
    assert(deserialize!(int[4])(serializeToAsdf(null)) == [0, 0, 0, 0]);
    assert(deserialize!(int[4])(serializeToJson([1, 3, 4])) == [1, 3, 4, 0]);
    assert(deserialize!(int[4])(serializeToAsdf([1, 3, 4])) == [1, 3, 4, 0]);
    assert(deserialize!(int[2])(serializeToJson([1, 3, 4])) == [1, 3]);
    assert(deserialize!(int[2])(serializeToAsdf([1, 3, 4])) == [1, 3]);

    assert(deserialize!(char[2])(serializeToAsdf(['a','b'])) == ['a','b']);
    assert(deserialize!(char[2])(serializeToAsdf(['a','\0'])) == ['a','\0']);
    assert(deserialize!(char[2])(serializeToAsdf(['a','\255'])) == ['a','\255']);
    assert(deserialize!(char[2])(serializeToAsdf(['\255'])) == ['\255','\0']);
    assert(deserialize!(char[2])(serializeToAsdf(['\255', '\255', '\255'])) == ['\255','\255']);
}

/// AA with value of aggregate type
unittest
{
    struct Foo
    {

    }

    assert (deserialize!(Foo[int])(serializeToJson([1: Foo()])) == [1:Foo()]);
}

/// Deserialize string-value associative array
SerdeException deserializeValue(V : T[string], T)(Asdf data, ref V value)
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case object:
            foreach(elem; data.byKeyValue)
            {
                T v;
                if (auto exc = .deserializeValue(elem.value, v))
                    return exc;
                value[elem.key.idup] = v;
            }
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

///
unittest
{
    assert(deserialize!(int[string])(serializeToJson(null)) is null);
    assert(deserialize!(int[string])(serializeToAsdf(null)) is null);
    assert(deserialize!(int[string])(serializeToJson(["a" : 1, "b" : 2])) == ["a" : 1, "b" : 2]);
    assert(deserialize!(int[string])(serializeToAsdf(["a" : 1, "b" : 2])) == ["a" : 1, "b" : 2]);
}

unittest
{
    int[string] r = ["a" : 1];
    serializeToAsdf(null).deserializeValue(r);
    assert(r is null);
}

/// Deserialize enumeration-value associative array
SerdeException deserializeValue(V : T[E], T, E)(Asdf data, ref V value)
    if(is(E == enum))
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case object:
            foreach(elem; data.byKeyValue)
            {
                T v;
                if (auto exc = .deserializeValue(elem.value, v))
                    return exc;
                value[elem.key.to!E] = v;
            }
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

///
unittest
{
    enum E {a, b}
    assert(deserialize!(int[E])(serializeToJson(null)) is null);
    assert(deserialize!(int[E])(serializeToAsdf(null)) is null);
    assert(deserialize!(int[E])(serializeToJson([E.a : 1, E.b : 2])) == [E.a : 1, E.b : 2]);
    assert(deserialize!(int[E])(serializeToAsdf([E.a : 1, E.b : 2])) == [E.a : 1, E.b : 2]);
}

unittest
{
    enum E {a, b}
    int[E] r = [E.a : 1];
    serializeToAsdf(null).deserializeValue(r);
    assert(r is null);
}

/// Deserialize associative array with integral type key
SerdeException deserializeValue(V : T[K], T, K)(Asdf data, ref V value)
    if((isIntegral!K) && !is(K == enum))
{
    auto kind = data.kind;
    with(Asdf.Kind) switch(kind)
    {
        case object:
            foreach(elem; data.byKeyValue)
            {
                T v;
                if (auto exc = .deserializeValue(elem.value, v))
                    return exc;
                value[elem.key.to!K] = v;
            }
            return null;
        case null_:
            value = null;
            return null;
        default:
            return unexpectedKind(kind);
    }
}

///
unittest
{
    assert(deserialize!(int[int])(serializeToJson(null)) is null);
    assert(deserialize!(int[int])(serializeToAsdf(null)) is null);
    assert(deserialize!(int[int])(serializeToJson([2 : 1, 40 : 2])) == [2 : 1, 40 : 2]);
    assert(deserialize!(int[int])(serializeToAsdf([2 : 1, 40 : 2])) == [2 : 1, 40 : 2]);
}

unittest
{
    int[int] r = [3 : 1];
    serializeToAsdf(null).deserializeValue(r);
    assert(r is null);
}

///
unittest
{
    import std.typecons;

    struct Nested
    {
        float f;
    }

    struct T
    {
        string str;
        Nullable!Nested nested;
        @serdeOptional
        Nullable!bool nval;
    }

    T t;
    assert(deserialize!T(`{"str":null,"nested":null}`) == t);
    t.str = "txt";
    t.nested = Nested(123);
    t.nval = false;
    assert(deserialize!T(`{"str":"txt","nested":{"f":123},"nval":false}`) == t);
}

struct Impl
{
@safe pure @nogc static:

    enum customDeserializeValueMehtodName = "deserializeFromAsdf";

    bool isAnyNull(Asdf data)
    {
        return data.kind == Asdf.Kind.null_;
    }

    bool isObjectNull(Asdf data)
    {
        return data.kind == Asdf.Kind.null_;
    }

    bool isObject(Asdf data)
    {
        return data.kind == Asdf.Kind.object;
    }

    SerdeException unexpectedData(string msg)(Asdf data)
    {
        return unexpectedKind(data.kind);
    }
}

/// Deserialize aggregate value
SerdeException deserializeValue(V)(Asdf data, ref V value)
    if(isAggregateType!V)
{
    import mir.algebraic;
    import mir.string_map;
    import mir.timestamp;
    static if (is(V == Timestamp))
    {
        const(char)[] str;
        if (auto exc = deserializeValue(data, str))
            return exc;
        value = Timestamp(str);
        return null;
    }
    else
    static if (is(V == StringMap!T, T))
    {
        auto kind = data.kind;
        with(Asdf.Kind) switch(kind)
        {
            case object:
                foreach(elem; data.byKeyValue)
                {
                    T v;
                    if (auto exc = .deserializeValue(elem.value, v))
                        return exc;
                    value[elem.key.idup] = v;
                }
                return null;
            case null_:
                value = null;
                return null;
            default:
                return unexpectedKind(kind);
        }
    }
    else
    static if (is(V == Algebraic!TypeSet, TypeSet...))
    {
        import std.meta: anySatisfy, Filter;
        import mir.internal.meta: Contains;
        alias Types = V.AllowedTypes;
        alias contains = Contains!Types;
        import mir.algebraic: isNullable;
        static if (isNullable!V && TypeSet.length == 2)
        {
            if (data.kind == Asdf.Kind.null_)
            {
                value = null;
                return null;
            }

            V.AllowedTypes[1] payload;
            if (auto exc = .deserializeValue(data, payload))
                return exc;
            value = payload;
            return null;
        }
        else
        switch (data.kind)
        {
            static if (contains!(typeof(null)))
            {
                case Asdf.Kind.null_:
                {
                    value = null;
                    return null;
                }
            }

            static if (contains!bool)
            {
                case Asdf.Kind.true_:
                {
                    value = true;
                    return null;
                }
                case Asdf.Kind.false_:
                {
                    value = false;
                    return null;
                }
            }

            static if (contains!string)
            {
                case Asdf.Kind.string:
                {
                    string str;
                    if (auto exc = deserializeValue(data, str))
                        return exc;
                    value = str;
                    return null;
                }
            }

            static if (contains!long || contains!double)
            {
                case Asdf.Kind.number:
                {
                    import mir.bignum.decimal;
                    DecimalExponentKey key;
                    Decimal!256 decimal = void;
                    auto str = (()@trusted => cast(string) data.data[2 .. $])();

                    enum bool allowSpecialValues = false;
                    enum bool allowDotOnBounds = false;
                    enum bool allowDExponent = false;
                    enum bool allowStartingPlus = false;
                    enum bool allowUnderscores = false;
                    enum bool allowLeadingZeros = false;
                    enum bool allowExponent = true;
                    enum bool checkEmpty = false;

                    if (!decimal.fromStringImpl!(
                        char,
                        allowSpecialValues,
                        allowDotOnBounds,
                        allowDExponent,
                        allowStartingPlus,
                        allowUnderscores,
                        allowLeadingZeros,
                        allowExponent,
                        checkEmpty,
                    )(str, key))
                        return new SerdeException("Asdf: can't parse number string: " ~ str);

                    if (key || !contains!long)
                    {
                        static if (contains!double)
                        {
                            value = cast(double) decimal;
                            return null;
                        }
                        else
                        {
                            return new SerdeException("Asdf: can't parse integer string: " ~ str);
                        }
                    }
                    static if (contains!long)
                    {
                        auto bigintView = decimal.coefficient.view;
                        auto ret = cast(long) bigintView;
                        if (ret != bigintView) {
                            return new SerdeException("Asdf: integer overflow");
                        }
                        value = ret;
                    }
                    return null;
                }
            }

            static if (anySatisfy!(templateAnd!(isArray, templateNot!isSomeString), Types))
            {
                case Asdf.Kind.array:
                {
                    alias ArrayTypes = Filter!(templateAnd!(isArray, templateNot!isSomeString), Types);
                    static assert(ArrayTypes.length == 1, ArrayTypes.stringof);
                    ArrayTypes[0] array;
                    if (auto exc = deserializeValue(data, array))
                        return exc;
                    value = array;
                    return null;
                }
            }

            static if (anySatisfy!(isStringMap, Types))
            {
                case Asdf.Kind.object:
                {
                    alias MapTypes = Filter!(isStringMap, Types);
                    static assert(MapTypes.length == 1, MapTypes.stringof);
                    MapTypes[0] object;
                    if (auto exc = deserializeValue(data, object))
                        return exc;
                    value = object;
                    return null;
                }
            }
            else
            static if (anySatisfy!(isAssociativeArray, Types))
            {
                case Asdf.Kind.object:
                {
                    alias AATypes = Filter!(isAssociativeArray, Types);
                    static assert(AATypes.length == 1, AATypes.stringof);
                    AATypes[0] object;
                    if (auto exc = deserializeValue(data, object))
                        return exc;
                    value = object;
                    return null;
                }
            }

            default:
                return unexpectedKind(data.kind);
        }
    }
    else
    static if (is(V == BigInt))
    {
        if (data.kind != Asdf.Kind.number)
            return unexpectedKind(data.kind);
        value = BigInt((()@trusted => cast(string) data.data[2 .. $])());
        return null;
    }
    else
    static if (isStdNullable!V)
    {
        if (data.kind == Asdf.Kind.null_)
        {
            value.nullify;
            return null;
        }

        typeof(value.get) payload;
        if (auto exc = .deserializeValue(data, payload))
            return exc;
        value = payload;
        return null;
    }
    else
    static if (__traits(hasMember, value, "deserializeFromAsdf"))
    {
        return __traits(getMember, value, "deserializeFromAsdf")(data);
    }
    else
    static if (hasUDA!(V, serdeProxy))
    {{
        serdeGetProxy!V proxy;
        enum S = hasUDA!(value, serdeScoped) && __traits(compiles, .deserializeScopedString(data, proxy));
        alias Fun = Select!(S, .deserializeScopedString, .deserializeValue);
        if (auto exc = Fun(data, proxy))
            return exc;
        value = proxy.to!V;
        return null;
    }}
    else
    {
        if (!(data.kind == Asdf.Kind.object))
        {
            static if(__traits(compiles, value = null))
            {
                if (data.kind == Asdf.Kind.null_)
                {
                    value = null;
                    return null;
                }
            }
            return unexpectedKind!("Cann't deserialize " ~ V.stringof ~ ". Unexpected data:")(data.kind);
        }

        static if(is(V == class) || is(V == interface))
        {
            if(value is null)
            {
                static if(__traits(compiles, value = new V))
                {
                    value = new V;
                }
                else
                {
                    return unexpectedKind(data.kind, "Object / interface must be either not null or have a a default constructor.");
                }
            }
        }

        SerdeFlags!V requiredFlags;

        static if (hasUDA!(V, serdeOrderedIn))
        {
            SerdeOrderedDummy!V temporal;
            if (auto exc = .deserializeValue(data, temporal))
                return exc;
            temporal.serdeFinalizeTarget(value, requiredFlags);
        }
        else
        {
            import std.meta: aliasSeqOf;

            alias impl = deserializeValueMemberImpl!(deserializeValue, deserializeScopedString);

            static immutable exc(string member) = new SerdeException("ASDF deserialisation: non-optional member '" ~ member ~ "' in " ~ V.stringof ~ " is missing.");

            static if (hasUDA!(V, serdeRealOrderedIn))
            {
                static foreach(member; serdeFinalProxyDeserializableMembers!V)
                {{
                    enum keys = serdeGetKeysIn!(__traits(getMember, value, member));
                    static if (keys.length)
                    {
                        foreach(elem; data.byKeyValue)
                        {
                            switch(elem.key)
                            {
                                static foreach (key; keys)
                                {
                                case key:
                                }
                                    if (auto mexp = impl!member(elem.value, value, requiredFlags))
                                        return mexp;
                                    break;
                                default:
                            }
                        }
                    }

                    static if (!hasUDA!(__traits(getMember, value, member), serdeOptional))
                        if (!__traits(getMember, requiredFlags, member))
                            return exc!member;
                }}
            }
            else
            {
                foreach(elem; data.byKeyValue)
                {
                    S: switch(elem.key)
                    {
                        static foreach(member; serdeFinalProxyDeserializableMembers!V)
                        {{
                            enum keys = serdeGetKeysIn!(__traits(getMember, value, member));
                            static if (keys.length)
                            {
                                static foreach (key; keys)
                                {
                        case key:
                                }
                            if (auto mexp = impl!member(elem.value, value, requiredFlags))
                                return mexp;
                            break S;
                            }
                        }}
                        default:
                    }
                }

                static foreach(member; __traits(allMembers, SerdeFlags!V))
                    static if (!hasUDA!(__traits(getMember, value, member), serdeOptional))
                        if (!__traits(getMember, requiredFlags, member))
                            return exc!member;
            }
        }

        static if(__traits(hasMember, V, "finalizeDeserialization"))
        {
            value.finalizeDeserialization(data);
        }
        static if(__traits(hasMember, V, "serdeFinalizeWithFlags"))
        {
            value.serdeFinalizeWithFlags(requiredFlags);
        }
        static if(__traits(hasMember, V, "serdeFinalize"))
        {
            value.serdeFinalize();
        }
        return null;
    }
}

/// StringMap support
unittest
{
    import mir.string_map;
    auto map = `{"b" : 1.0, "a" : 2}`.deserialize!(StringMap!double);
    assert(map.keys == ["b", "a"]);
    assert(map.values == [1.0, 2.0]);
    assert(map.serializeToJson == `{"b":1.0,"a":2.0}`);

}

/// JsonAlgebraic alias support
unittest
{
    import mir.algebraic_alias.json;
    auto value = `{"b" : 1.0, "a" : [1, true, false, null, "str"]}`.deserialize!JsonAlgebraic;
    assert(value.kind == JsonAlgebraic.Kind.object);

    auto object = value.get!(StringMap!JsonAlgebraic);
    assert(object.keys == ["b", "a"]); // sequental order
    assert(object["b"].get!double == 1.0);
    object["b"].get!double += 4;

    auto array = object["a"].get!(JsonAlgebraic[]);
    assert(array[0].get!long == 1);
    array[0].get!long += 10;
    assert(array[1].get!bool == true);
    assert(array[2].get!bool == false);
    assert(array[3].isNull);
    assert(array[3].get!(typeof(null)) is null);
    assert(array[4].get!string == "str");

    assert(value.serializeToJson == `{"b":5.0,"a":[11,true,false,null,"str"]}`);
    value = [JsonAlgebraic[].init.JsonAlgebraic, StringMap!JsonAlgebraic.init.JsonAlgebraic, string.init.JsonAlgebraic];
    // algebraics have type safe serialization instead of null values
    assert(value.serializeToJson == `[[],{},""]`, value.serializeToJson);
}

/++
User defined algebraic types deserialization supports any subset of the following types:

$(UL 
$(LI `typeof(null)`)
$(LI `bool`)
$(LI `long`)
$(LI `double`)
$(LI `string`)
$(LI `AnyType[]`)
$(LI `StringMap!AnyType`)
$(LI `AnyType[string]`)
)

A `StringMap` has has priority over builtin associative arrays.

Serializations works with any algebraic types.

See_also: $(GMREF mir-core, mir,algebraic), $(GMREF mir-algorithm, mir,string_map)
+/
unittest
{
    import mir.algebraic: Nullable, This; // Nullable, Variant, or TaggedVariant
    alias MyJsonAlgebraic = Nullable!(bool, string, double[], This[string]);

    auto value = `{"b" : true, "z" : null, "this" : {"c" : "str", "d" : [1, 2, 3, 4]}}`.deserialize!MyJsonAlgebraic;

    auto object = value.get!(MyJsonAlgebraic[string]);
    assert(object["b"].get!bool == true);
    assert(object["z"].isNull);

    object = object["this"].get!(MyJsonAlgebraic[string]);
    assert(object["c"].get!string == "str");
    assert(object["d"].get!(double[]) == [1.0, 2, 3, 4]);
}

///
unittest
{
    static class Turtle
    {
        string _metadata;
        long id;
        string species;
    }

    auto turtles = `
       [{"_metadata":"xyz123", "id":72, "species":"Galapagos"},
        {"_metadata":"tu144", "id":108, "species":"Snapping"},
        null,
        null,
        {"_metadata":"anew1", "id":9314, "species":"Sea Turtle"}]`
          .deserialize!(Turtle[]);
}

/// Alias this support
unittest
{
    struct S
    {
        int a;
    }

    struct C
    {
        S s;
        alias s this; 
        int b;
    }

    assert(`{"a":3, "b":4}`.deserialize!C == C(S(3), 4));
}


/// `serdeOrderedIn` supprot
unittest
{
    static struct I
    {
        @serdeOptional
        int a;
        int m;
    }

    @serdeOrderedIn
    static struct S
    {
        import mir.small_string;

        SmallString!8 id;

        int acc;

        I inner = I(1000, 0);

    @safe pure nothrow @nogc
    @property:

        void add(int v)
        {
            inner.a += v;
            acc += v;
        }

        void mul(int v)
        {
            inner.m += v;
            acc *= v;
        }
    }

    import mir.reflection;

    auto val = `{"mul":2, "id": "str", "add":5,"acc":100, "inner":{"m": 2000}}`.deserialize!S;
    assert(val.id == "str");
    assert(val.acc == 210);
    assert(val.inner.a == 1005);
    assert(val.inner.m == 2002);
    assert(val.serializeToJson == `{"id":"str","acc":210,"inner":{"a":1005,"m":2002}}`);
}

/// `serdeRealOrderedIn` supprot
unittest
{
    static struct I
    {
        @serdeOptional
        int a;
        int m;
    }

    @serdeRealOrderedIn
    static struct S
    {
        import mir.small_string;

        SmallString!8 id;

        int acc;

        I inner = I(1000, 0);

    @safe pure nothrow @nogc
    @property:

        void add(int v)
        {
            inner.a += v;
            acc += v;
        }

        void mul(int v)
        {
            inner.m += v;
            acc *= v;
        }
    }

    import mir.reflection;

    auto val = `{"mul":2, "id": "str", "add":5,"acc":100, "inner":{"m": 2000}}`.deserialize!S;
    assert(val.id == "str");
    assert(val.acc == 210);
    assert(val.inner.a == 1005);
    assert(val.inner.m == 2002);
    assert(val.serializeToJson == `{"id":"str","acc":210,"inner":{"a":1005,"m":2002}}`);
}

///
unittest
{
    struct A {
        string str;
    }
    struct B {
        A a;
        string serialize() const {
            return asdf.serializeToJson(a);
        }
    }
    assert(B(A("2323")).serialize == `{"str":"2323"}`);
}

private template isNullable(T)
{
    import std.traits : hasMember;

    static if (
        hasMember!(T, "isNull") &&
        is(typeof(__traits(getMember, T, "isNull")) == bool) &&
        hasMember!(T, "get") &&
        !is(typeof(__traits(getMember, T, "get")) == void) &&
        hasMember!(T, "nullify") &&
        is(typeof(__traits(getMember, T, "nullify")) == void)
    )
    {
        enum isNullable = true;
    }
    else
    {
        enum isNullable = false;
    }
}

deprecated("use @serdeIgnoreOut instead")
alias serializationIgnoreOut = serdeIgnoreOut;

deprecated("use @serdeIgnoreIn instead")
alias serializationIgnoreIn = serdeIgnoreIn;

deprecated("use @serdeIgnore instead")
alias serializationIgnore = serdeIgnore;

deprecated("use @serdeKeys instead")
alias serializationKeys = serdeKeys;

deprecated("use @serdeKeys instead")
alias serializationKeyOut = serdeKeyOut;

deprecated("use @serdeIgnoreDefault instead")
alias serializationIgnoreDefault = serdeIgnoreDefault;

deprecated("use @serdeLikeList instead")
alias serializationLikeArray = serdeLikeList;

deprecated("use @serdeLikeStruct instead")
alias serializationLikeObject = serdeLikeStruct;

deprecated("use @serdeProxy instead")
alias serializedAs = serdeProxy;

deprecated("use @serdeIgnoreOutIf instead")
alias serializationIgnoreOutIf = serdeIgnoreOutIf;

deprecated("use @serdeTransformIn instead")
alias serializationTransformIn = serdeTransformIn;

deprecated("use @serdeTransformOut instead")
alias serializationTransformOut = serdeTransformOut;

deprecated("use @serdeScoped instead")
alias serializationScoped = serdeScoped;
