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
import std.typecons;
import asdf.asdf;
import asdf.outputarray;
import std.meta;


version(LDC)
{
    static if (__traits(targetHasFeature, "sse4.2"))
    {
        import core.simd;
        import asdf.simd;
        import ldc.gccbuiltins_x86;
        pragma(msg, "Info: SSE4.2 instructions are used for ASDF.");
        version = SSE42;
    }
    else
    {
        pragma(msg, "Info: SSE4.2 instructions are not used for ASDF.");
    }
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
Parses JSON value in each line from a Range of buffers.
Note: Invalid lines generate an empty ASDF value.
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
            _nextEmpty = length ? !asdf.setFrontRange : 0;
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

/++
Parses JSON value in each line within a string.
Note: most probably you do not want this but operate directly on a buffer!
Note: Invalid lines generate an empty ASDF value.
Params:
    text = string or const(char)[]
    initLength = initial output buffer length. Minimal value equals 32.
Returns:
    Input range composed of ASDF values. Each value uses the same internal buffer.
+/
auto parseJsonByLine(
    Flag!"spaces" spaces = Yes.spaces, size_t initLength = 32)
    (in const(char)[] text)
{
    import std.range: only;
    return (cast(const(ubyte[]))text).only.parseJsonByLine!spaces(initLength);
}

unittest
{
    import std.conv;
    import std.algorithm : map;
    import std.range : array;
    string text =  "\t " ~ `{"key": "a"}` ~ "\r\r\n" ~ `{"key2": "b"}`;
    auto values = text.parseJsonByLine();
    assert( values.front["key"] == "a");
    values.popFront;
    assert( values.front["key2"] == "b");
    values.popFront;
}

version(LDC)
{
    public import ldc.intrinsics: _expect = llvm_expect;
}
else
{
    T _expect(T)(T val, T expected_val) if (__traits(isIntegral, T))
    {
        return val;
    }
}

enum AsdfErrorCode
{
    success,
    unexpectedEnd,
    unexpectedValue,
}

private __gshared immutable ubyte[256] parseFlags = [
 // 0 1 2 3 4 5 6 7   8 9 A B C D E F
    0,0,0,0,0,0,0,0,  0,6,6,0,0,6,0,0, // 0
    0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0, // 1
    3,1,0,1,1,1,1,1,  1,1,1,9,1,9,9,1, // 2
    9,9,9,9,9,9,9,9,  9,1,1,1,1,1,1,1, // 3

    1,1,1,1,1,9,1,1,  1,1,1,1,1,1,1,1, // 4
    1,1,1,1,1,1,1,1,  1,1,1,1,0,1,1,1, // 5
    1,1,1,1,1,9,1,1,  1,1,1,1,1,1,1,1, // 6
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1, // 7

    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,

    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
    1,1,1,1,1,1,1,1,  1,1,1,1,1,1,1,1,
];

pragma(inline, true)
bool isPlainJsonCharacter(size_t c)
{
    return (parseFlags[c] & 1) != 0;
}

pragma(inline, true)
bool isJsonWhitespace(size_t c)
{
    return (parseFlags[c] & 2) != 0;
}

pragma(inline, true)
bool isJsonLineWhitespace(size_t c)
{
    return (parseFlags[c] & 4) != 0;
}

pragma(inline, true)
bool isJsonNumber(size_t c)
{
    return (parseFlags[c] & 8) != 0;
}

package struct JsonParserNew(bool includingNewLine, bool hasSpaces, bool assumeValid, bool zeroTerminated, Allocator, Input = const(char)[])
{

    // align(64) ubyte[1024 * 4 + 64] buffer = void;
    // align(64) ubyte[64] payload = void;
    ubyte[] data;
    size_t shift;
    Allocator* allocator;
    Input input;

    enum bool chunked = !is(Input : const(char)[]);

    this(ref Allocator allocator, Input input)
    {
        this.input = input;
        this.allocator = &allocator;
    }

    enum State
    {
        unexpected,
        vObject,
        vArray,
        vNumber,
        vString,
        vFalse,
        vNull,
        vTrue,
        vValue,
    }


    State state;
    size_t length;
    bool unfinished;

    AsdfErrorCode parse()
    {
        const(ubyte)* strPtr;
        const(ubyte)* strEnd;
        static if (chunked)
        {
            static assert(0);
        }
        else
        {
            strPtr = cast(const(ubyte)*) input.ptr;
            strEnd = cast(const(ubyte)*) input.ptr + input.length;
        }
        data = cast(ubyte[])allocator.allocate((strEnd - strPtr) * 6);
        import std.stdio;
        writeln(data.length);
        auto dataPtr = data.ptr;

        bool prepareInput()
        {
        prepareInputCheck:
            if (_expect(strEnd == strPtr, false))
            {
                static if (chunked)
                {
                    if (input.empty)
                    {
                        return false;
                    }
                    auto str = input.front;
                    input.popFront;
                    strPtr = str.ptr;
                    strEnd = std.ptr + str.length;
                    goto prepareInputCheck;
                }
                else
                {
                    return false;
                }
            }
            return true;
        }

        static if (hasSpaces)
        void skipSpaces()
        {
            pragma(inline, false);
            auto ptr = strPtr;
            for(;;)
            {
                if (_expect(ptr == strEnd, false))
                {
                    static if (chunked)
                    {
                        if (input.empty)
                        {
                            strPtr = ptr;
                            return;
                        }
                        auto str = input.front;
                        input.popFront;
                        strPtr = str.ptr;
                        strEnd = std.ptr + str.length;
                        continue;
                    }
                    else
                    {
                        strPtr = ptr;
                        return;
                    }
                }
                
                static if (includingNewLine)
                    alias isWhite = isJsonWhitespace;
                else
                    alias isWhite = isJsonLineWhitespace;
                if (isWhite(ptr[0]))
                {
                    ptr++;
                    continue;
                }
                strPtr = ptr;
                return;
            }
        }

        int readUnicode(out dchar d)
        {
            foreach(i; 0..4)
            {
                if (!prepareInput)
                    return 1;
                uint c = strPtr[0];
                switch(c)
                {
                    case '0': .. case '9':
                        c = c - '0';
                        break;
                    case 'a': .. case 'f':
                        c = c - 'a' + 10;
                        break;
                    case 'A': .. case 'F':
                        c = c - 'A' + 10;
                        break;
                    default:
                        return -1;
                }
                strPtr += 1;
                d <<= 4;
                d ^= c;
            }
            return 0;
        }

        int writeUnicode()
        {
            dchar d;
            if (auto r = (readUnicode(d)))
                return r;
            if (_expect(0xD800 <= d && d <= 0xDFFF, false))
            {
                if (d >= 0xDC00)
                    return -1;
                if (!prepareInput)
                    return 1;
                if (strPtr[0] != '\\')
                    return -1;
                if (!prepareInput)
                    return 1;
                if (strPtr[0] != 'u')
                    return -1;
                d = (d & 0x3FF) << 10;
                dchar trailing;
                if (auto r = (readUnicode(trailing)))
                    return r;
                if (!(0xDC00 <= trailing && trailing <= 0xDFFF))
                    return false;
                d |= trailing & 0x3FF;
                d += 0x10000;
            }
            if (0xFDD0 <= d && d <= 0xFDEF)
                return true; // TODO: review
            if (((~0xFFFF & d) >> 0x10) <= 0x10 && (0xFFFF & d) >= 0xFFFE)
                return true; // TODO: review 
            encodeUTF8(d, dataPtr);
            return true;
        }
    
        size_t[32] stack = void;
        size_t stackIndex = -1;
        ubyte* stringAndNumberShift = void;

        typeof(return) retCode;
        // auto ptr = data.ptr + dataLength;
        // State curr = void;
        // State afterSpace = void;
        // State next = State.end;
        // static if (hasSpaces)
        // {
        // 	auto next = State.value;
        // 	enum start = State.spaces;
        // }
        // else
        // {
        // 	State next = end;
        // 	enum start = State.value;
        // }
        size_t len;
        bool currIsKey = void;
        goto value;
        switch (state)
        {
        default: assert(0);
        next:
            if (stackIndex == -1)
                goto ret;
            {
                const stackValue = stack[stackIndex];
                const isObject = stackValue & 1;
                if (isObject)
                {
                    assert(0);
                }
                else
                {
                    assert(0);
                }
            }
        value:
            static if (hasSpaces)
            {
                skipSpaces;
                if (_expect(strPtr == strEnd, false))
                    goto vValue_unexpectedEnd;
            }

            switch(*strPtr)
            {
            stringValue:
            case '"':
                currIsKey = false;
                *dataPtr++ = Asdf.Kind.string;
                stringAndNumberShift = dataPtr;
                // reserve 4 byte for the length
                dataPtr += 4;
                goto string;
            case '-':
            case '0':
            ..
            case '9': {
                *dataPtr++ = Asdf.Kind.number;
                stringAndNumberShift = dataPtr;
                // reserve 1 byte for the length
                dataPtr++;
                // write the first character
                *dataPtr++ = *strPtr++;
                for(;;)
                {
                    if (!prepareInput)
                        goto number_found0;

                    while(zeroTerminated || strEnd > strPtr + 4)
                    {
                        char c0 = strPtr[0]; dataPtr += 4;     if (!isJsonNumber(c0)) goto number_found0;
                        char c1 = strPtr[1]; dataPtr[-4] = c0; if (!isJsonNumber(c1)) goto number_found1;
                        char c2 = strPtr[2]; dataPtr[-3] = c1; if (!isJsonNumber(c2)) goto number_found2;
                        char c3 = strPtr[3]; dataPtr[-2] = c2; if (!isJsonNumber(c3)) goto number_found3;
                        strPtr += 4;         dataPtr[-1] = c3;
                    }
                    static if (!zeroTerminated)
                    {
                        while(strEnd > strPtr)
                        {
                            char c0 = strPtr[0]; if (!isJsonNumber(c0)) goto number_found0; dataPtr[0] = c0;
                            strPtr += 1;
                            dataPtr += 1;
                        }
                    }
                }
                number_found3: dataPtr++; strPtr++;
                number_found2: dataPtr++; strPtr++;
                number_found1: dataPtr++; strPtr++;
                    dataPtr -= 4;
                number_found0:

                auto numberLength = dataPtr - stringAndNumberShift - 1;
                writeln("numberLength = ", numberLength);
                if (numberLength > 256)
                    goto vNull_unexpectedValue; // TODO: replace proper error
                *stringAndNumberShift = cast(ubyte) numberLength;
                goto next;
            }
            case '[': 
                break;

            foreach (name; AliasSeq!("false", "null", "true"))
            {
            case name[0]:
                    writeln(name);
                    if (_expect(strEnd - strPtr >= name.length, true))
                    {
                        static if (!assumeValid)
                        {
                            char[name.length - 1] c = void;
                            import std.range: iota;
                            foreach (i; aliasSeqOf!(iota(1, name.length)))
                                c[i - 1] = strPtr[i];
                            foreach (i; aliasSeqOf!(iota(1, name.length)))
                            {
                                if (c[i - 1] != name[i])
                                {
                                    writeln("sss");
                                    static if (name == "true")
                                        goto vTrue_unexpectedValue;
                                    else
                                    static if (name == "false")
                                        goto vFalse_unexpectedValue;
                                    else
                                        goto vNull_unexpectedValue;
                                }
                            }
                        }
                    // writeln(name, "2---");
                        static if (name == "null")
                            *dataPtr++ = Asdf.Kind.null_;
                        else
                        static if (name == "false")
                            *dataPtr++ = Asdf.Kind.false_;
                        else
                            *dataPtr++ = Asdf.Kind.true_;
                        strPtr += name.length;
                        goto next;
                    }
                    else
                    {
                        static if (chunked)
                        {
                            strPtr += 1;
                            foreach (i; 1 .. name.length)
                            {
                                while (strPtr == strEnd)
                                {
                                    if (_expect(input.empty, false))
                                        goto FNT_unexpectedEnd;
                                    str = input.front;
                                    input.popFront;
                                }
                                static if (!assumeValid)
                                {
                                    if (_expect(str[0] != name[i], false))
                                    {
                                        state = vFalse0 + i;
                                        goto ret;
                                    }
                                }
                                strPtr += 1;
                            }
                            goto next;
                    FNT_unexpectedEnd:
                        }
                        static if (name == "true")
                            goto vTrue_unexpectedEnd;
                        else
                        static if (name == "false")
                            goto vFalse_unexpectedEnd;
                        else
                            goto vNull_unexpectedEnd;
                    }
            }

            case '{':
                assert(0);
            default :
                assert(0);
            }

        // key:
        // 	currIsKey = true;
        // 	stringAndNumberShift = shift;
        // 	shift += 1;
        // 	goto string;

        string:
            assert(*strPtr == '"');
            strPtr += 1;

            // version(SSE42)
            // {
            // }
            // else
            {
                StringLoop: for(;;)
                {
                    if (!prepareInput)
                        goto vString_unexpectedEnd;

                    while(zeroTerminated || strEnd > strPtr + 4)
                    {
                        char c0 = strPtr[0]; dataPtr += 4;    if (!isPlainJsonCharacter(c0)) goto string_found0;
                        char c1 = strPtr[1]; dataPtr[-4] = c0; if (!isPlainJsonCharacter(c1)) goto string_found1;
                        char c2 = strPtr[2]; dataPtr[-3] = c1; if (!isPlainJsonCharacter(c2)) goto string_found2;
                        char c3 = strPtr[3]; dataPtr[-2] = c2; if (!isPlainJsonCharacter(c3)) goto string_found3;
                        strPtr += 4;         dataPtr[-1] = c3;
                    }
                    static if (!zeroTerminated)
                    {
                        while(strEnd > strPtr)
                        {
                            char c0 = strPtr[0]; if (!isPlainJsonCharacter(c0)) goto string_found0; dataPtr[0] = c0;
                            strPtr += 1;
                            dataPtr += 1;
                        }
                    }
                }
            string_found3: dataPtr++; strPtr++;
            string_found2: dataPtr++; strPtr++;
            string_found1: dataPtr++; strPtr++;
                dataPtr -= 4;
            string_found0:
                uint c = strPtr[0];
                if (c == '\"')
                {
                    strPtr += 1;
                    if (currIsKey)
                    {
                        // TODO
                    }
                    else
                    {
                        auto stringLength = dataPtr - stringAndNumberShift - 4;
                        writeln("stringLength = ", stringLength);
                        if (stringLength > 256)
                            goto vNull_unexpectedValue; // TODO: replace proper error
                        version(X86_64)
                            *cast(uint*)stringAndNumberShift = cast(uint) stringLength;
                        else
                            static assert(0);
                        goto next;
                    }
                }
                if (c == '\\')
                {
                    strPtr += 1;
                    if (!prepareInput)
                        goto vString_unexpectedEnd;
                    c = strPtr[0];
                    strPtr += 1;
                    switch(c)
                    {
                        case '/' :           goto backSlashReplace;
                        case '\"':           goto backSlashReplace;
                        case '\\':           goto backSlashReplace;
                        case 'b' : c = '\b'; goto backSlashReplace;
                        case 'f' : c = '\f'; goto backSlashReplace;
                        case 'n' : c = '\n'; goto backSlashReplace;
                        case 'r' : c = '\r'; goto backSlashReplace;
                        case 't' : c = '\t'; goto backSlashReplace;
                        backSlashReplace:
                            *dataPtr++ = cast(ubyte) c;
                            goto StringLoop;
                        case 'u' :
                            auto wur = writeUnicode();
                            if (wur == 0)
                                goto StringLoop;
                            if (wur == 1)
                                goto vString_unexpectedEnd;
                            assert (wur == -1);
                            goto vString_unexpectedValue;
                        default: goto vString_unexpectedValue;
                    }
                }
                goto vString_unexpectedValue;
            }
        }
    ret:
        data = data[0 .. dataPtr - data.ptr];
        return retCode;
    unexpectedEnd: retCode = AsdfErrorCode.unexpectedEnd; goto ret;
    unexpectedValue: retCode = AsdfErrorCode.unexpectedValue; goto ret;

    vValue_unexpectedEnd : state = State.vValue ; goto unexpectedEnd;
    vString_unexpectedEnd: state = State.vString; goto unexpectedEnd;
    vArray_unexpectedEnd : state = State.vArray ; goto unexpectedEnd;
    vObject_unexpectedEnd: state = State.vObject; goto unexpectedEnd;

    vString_unexpectedValue: state = State.vString; goto unexpectedValue;
    vArray_unexpectedValue : state = State.vArray ; goto unexpectedValue;
    vObject_unexpectedValue: state = State.vObject; goto unexpectedValue;

    vTrue_unexpectedEnd : state = State.vTrue ; goto unexpectedEnd;
    vFalse_unexpectedEnd: state = State.vFalse; goto unexpectedEnd;
    vNull_unexpectedEnd : state = State.vNull ; goto unexpectedEnd;
    vTrue_unexpectedValue : state = State.vTrue ; goto unexpectedValue;
    vFalse_unexpectedValue: state = State.vFalse; goto unexpectedValue;
    vNull_unexpectedValue : state = State.vNull ; goto unexpectedValue;

    }
}

Asdf parseJsonNew(string str)
{
    import std.experimental.allocator;
    import std.experimental.allocator.gc_allocator;
    // (bool includingNewLine, bool hasSpaces, bool assumeValid, bool zeroTerminated, Allocator, Input = const(char)[])
    auto parser = JsonParserNew!(true, true, false, false, shared GCAllocator, const(char)[])(GCAllocator.instance, str);
    parser.parse();
    return Asdf(parser.data);
}

unittest
{
    import std.stdio;
    import std.conv;
    // auto True = parseJsonNew("true");
    // writeln(True.data);

    assert(parseJsonNew(`   true`).to!string == `true`);
    assert(parseJsonNew(`    null `).to!string == `null`);
    assert(parseJsonNew(`false  `).to!string == `false`);
    assert(parseJsonNew(`4`).to!string == `4`);
    assert(parseJsonNew(`   4121231.23e-12321 `).to!string == `4121231.23e-12321`);
    assert(parseJsonNew(`"asdfgr"`).to!string == `"asdfgr"`);
}

void encodeUTF8(dchar c, ref ubyte* ptr)
{   
    if (c < 0x80)
    {
        ptr[0] = cast(ubyte) (c);
        ptr += 1;
    }
    else
    if (c < 0x800)
    {
        ptr[0] = cast(ubyte) (0xC0 | (c >> 6));
        ptr[1] = cast(ubyte) (0x80 | (c & 0x3F));
        ptr += 2;
    }
    else
    if (c < 0x10000)
    {
        ptr[0] = cast(ubyte) (0xE0 | (c >> 12));
        ptr[1] = cast(ubyte) (0x80 | ((c >> 6) & 0x3F));
        ptr[2] = cast(ubyte) (0x80 | (c & 0x3F));
        ptr += 3;
    }
    else
    {
        assert(c < 0x200000);
        ptr[0] = cast(ubyte) (0xF0 | (c >> 18));
        ptr[1] = cast(ubyte) (0x80 | ((c >> 12) & 0x3F));
        ptr[2] = cast(ubyte) (0x80 | ((c >> 6) & 0x3F));
        ptr[3] = cast(ubyte) (0x80 | (c & 0x3F));
        ptr += 4;
    }
}


package struct JsonParser(bool includingNewLine, bool spaces, Chunks)
{
    const(ubyte)[] r;
    Chunks chunks;
    OutputArray oa;

    /++
    Update the front array ``r` if it is empty.
    Return `false` on unexpected end of input.
    +/
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
                            switch(d.length)
                            {
                                default   : goto case;
                                case 0xE+1: str1.array[0xE] = d[0xE]; goto case;
                                case 0xD+1: str1.array[0xD] = d[0xD]; goto case;
                                case 0xC+1: str1.array[0xC] = d[0xC]; goto case;
                                case 0xB+1: str1.array[0xB] = d[0xB]; goto case;
                                case 0xA+1: str1.array[0xA] = d[0xA]; goto case;
                                case 0x9+1: str1.array[0x9] = d[0x9]; goto case;
                                case 0x8+1: str1.array[0x8] = d[0x8]; goto case;
                                case 0x7+1: str1.array[0x7] = d[0x7]; goto case;
                                case 0x6+1: str1.array[0x6] = d[0x6]; goto case;
                                case 0x5+1: str1.array[0x5] = d[0x5]; goto case;
                                case 0x4+1: str1.array[0x4] = d[0x4]; goto case;
                                case 0x3+1: str1.array[0x3] = d[0x3]; goto case;
                                case 0x2+1: str1.array[0x2] = d[0x2]; goto case;
                                case 0x1+1: str1.array[0x1] = d[0x1]; goto case;
                                case 0x0+1: str1.array[0x0] = d[0x0]; goto case;
                                case 0x0  : break;
                            }

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

    private dchar readUnicodeImpl()
    {
        dchar d = '\0';
        foreach(i; 0..4)
        {
            int c = pop;
            switch(c)
            {
                case '0': .. case '9':
                    c = c - '0';
                    break;
                case 'a': .. case 'f':
                    c = c - 'a' + 10;
                    break;
                case 'A': .. case 'F':
                    c = c - 'A' + 10;
                    break;
                default: return -c;
            }
            d <<= 4;
            d ^= c;
        }
        return d;
    }

    /++
    Encodes `XXXX` to the UTF-8 buffer`, where `XXXX` expected to be hexadecimal character.
    Returns: `1` on success.
    +/
    private int readUnicode()
    {
        char[4] buf = void;
        dchar data = readUnicodeImpl;
        if(0xD800 <= data && data <= 0xDFFF)
        {
            import std.exception: enforce;
            enum msg = "Invalid surrogate UTF-16 sequence.";
            enforce(pop == '\\', msg);
            enforce(pop == 'u', msg);
            enforce(data < 0xDC00, msg);
            data = (data & 0x3FF) << 10;
            dchar trailing = readUnicodeImpl;
            enforce(0xDC00 <= trailing && trailing <= 0xDFFF);
            data |= trailing & 0x3FF;
            data += 0x10000;
        }
        if (0xFDD0 <= data && data <= 0xFDEF)
            return 0;
        if (((~0xFFFF & data) >> 0x10) <= 0x10 && (0xFFFF & data) >= 0xFFFE)
            return 0;
        import std.utf: encode;
        size_t len = buf.encode(data);
        foreach(ch; buf[0 .. len])
        {
            oa.put1(ch);
        }
        return cast(int)len;
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
                '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'];
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
                        switch(d.length)
                        {
                            default   : goto case;
                            case 0xE+1: str1.array[0xE] = d[0xE]; goto case;
                            case 0xD+1: str1.array[0xD] = d[0xD]; goto case;
                            case 0xC+1: str1.array[0xC] = d[0xC]; goto case;
                            case 0xB+1: str1.array[0xB] = d[0xB]; goto case;
                            case 0xA+1: str1.array[0xA] = d[0xA]; goto case;
                            case 0x9+1: str1.array[0x9] = d[0x9]; goto case;
                            case 0x8+1: str1.array[0x8] = d[0x8]; goto case;
                            case 0x7+1: str1.array[0x7] = d[0x7]; goto case;
                            case 0x6+1: str1.array[0x6] = d[0x6]; goto case;
                            case 0x5+1: str1.array[0x5] = d[0x5]; goto case;
                            case 0x4+1: str1.array[0x4] = d[0x4]; goto case;
                            case 0x3+1: str1.array[0x3] = d[0x3]; goto case;
                            case 0x2+1: str1.array[0x2] = d[0x2]; goto case;
                            case 0x1+1: str1.array[0x1] = d[0x1]; goto case;
                            case 0x0+1: str1.array[0x0] = d[0x0]; goto case;
                            case 0x0  : break;
                        }

                        storeUnaligned!ubyte16(str1, ptr + shift);

                        size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x04);

                        if(ecx == 16)
                        {
                            shift += d.length;
                            len += d.length;
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
                        case 'u' :
                            c = readUnicode();
                            if(c >= 0)
                            {
                                len += c - 1;
                                continue;
                            }
                            goto default;
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
                if(c < ' ')
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
                        case 'u' :
                            c = readUnicode();
                            if(c >= 0)
                            {
                                len += c;
                                continue;
                            }
                            return -c;
                        default: return -c;
                    }
                }
                oa.put1(cast(ubyte)c);
                len++;
            }
        }
    }

    unittest
    {
        import std.string;
        import std.range;
        static immutable str = `"1234567890qwertyuiopasdfghjklzxcvbnm"`;
        auto data = Asdf(str[1..$-1]);
        assert(data == parseJson(str));
        foreach(i; 1 .. str.length)
            assert(data == parseJson(str.representation.chunks(i)));
    }

    unittest
    {
        import std.string;
        import std.range;
        static immutable str = `"\t\r\f\b\"\\\/\t\r\f\b\"\\\/\t\r\f\b\"\\\/\t\r\f\b\"\\\/"`;
        auto data = Asdf("\t\r\f\b\"\\/\t\r\f\b\"\\/\t\r\f\b\"\\/\t\r\f\b\"\\/");
        assert(data == parseJson(str));
        foreach(i; 1 .. str.length)
            assert(data == parseJson(str.representation.chunks(i)));
    }

    unittest
    {
        import std.string;
        import std.range;
        static immutable str = `"\u0026"`;
        auto data = Asdf("&");
        assert(data == parseJson(str));
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
                {
                    oa.put1(cast(ubyte)len, s);
                    return len + 2;
                }
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
                        switch(d.length)
                        {
                            default   : goto case;
                            case 0xE+1: str1.array[0xE] = d[0xE]; goto case;
                            case 0xD+1: str1.array[0xD] = d[0xD]; goto case;
                            case 0xC+1: str1.array[0xC] = d[0xC]; goto case;
                            case 0xB+1: str1.array[0xB] = d[0xB]; goto case;
                            case 0xA+1: str1.array[0xA] = d[0xA]; goto case;
                            case 0x9+1: str1.array[0x9] = d[0x9]; goto case;
                            case 0x8+1: str1.array[0x8] = d[0x8]; goto case;
                            case 0x7+1: str1.array[0x7] = d[0x7]; goto case;
                            case 0x6+1: str1.array[0x6] = d[0x6]; goto case;
                            case 0x5+1: str1.array[0x5] = d[0x5]; goto case;
                            case 0x4+1: str1.array[0x4] = d[0x4]; goto case;
                            case 0x3+1: str1.array[0x3] = d[0x3]; goto case;
                            case 0x2+1: str1.array[0x2] = d[0x2]; goto case;
                            case 0x1+1: str1.array[0x1] = d[0x1]; goto case;
                            case 0x0+1: str1.array[0x0] = d[0x0]; goto case;
                            case 0x0  : break;
                        }
                        storeUnaligned!ubyte16(str1, ptr + shift);
                        size_t ecx = __builtin_ia32_pcmpistri128(str2, str1, 0x10);
                        shift += ecx;
                        len += ecx;
                        r = d[ecx .. $];
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

    unittest
    {
        import std.string;
        import std.range;
        import std.conv;
        static immutable str = `941763918276349812734691287354912873459128635412037501236410234567123847512983745126`;
        assert(str == parseJson(str).to!string);
        foreach(i; 1 .. str.length)
            assert(str == parseJson(str.representation.chunks(i)).to!string);
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

unittest
{
    auto asdf = "[\"\u007F\"]".parseJson;
}

unittest
{
    auto f = `"\uD801\uDC37"`.parseJson;
    assert(f == "\"\U00010437\"".parseJson);
}
