/++
Json Parser

Copyright: Tamedia Digital, 2016-2017

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

version(X86_64)
    version = X86_Any;
else
version(X86)
    version = X86_Any;

/++
Parses json value
Params:
    chunks = input range composed of elements type of `const(ubyte)[]`.
        `chunks` can use the same buffer for each chunk.
    initLength = initial output buffer length. Minimal value equals 32.
Returns:
    ASDF value
+/
Asdf parseJson(
    Flag!"includingNewLine" includingNewLine = Yes.includingNewLine,
    Flag!"spaces" spaces = Yes.spaces,
    Chunks)
    (Chunks chunks, size_t initLength = 32)
    if(is(ElementType!Chunks : const(ubyte)[]))
{
    import std.format: format;
    import std.conv: ConvException;
    enum assumeValid = false;
    enum zeroTerminated = false;
    import std.experimental.allocator.gc_allocator;
    auto parser = JsonParserNew!(includingNewLine, spaces, assumeValid, zeroTerminated, shared GCAllocator, Chunks)(GCAllocator.instance, chunks);
    auto err = parser.parse;
    return Asdf(parser.result);
}

///
unittest
{
    import std.range: chunks;
    auto text = cast(const ubyte[])`true `;
    auto ch = text.chunks(3);
    import std.stdio;
    assert(ch.parseJson(32).data == [1]);
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
    Flag!"spaces" spaces = Yes.spaces, 
    Flag!"assumeValid" assumeValid = No.assumeValid,
    Flag!"zeroTerminated" zeroTerminated = No.zeroTerminated,
    Allocator,
    )
    (in char[] str, Allocator allocator)
{
    auto parser = JsonParserNew!(includingNewLine, spaces, assumeValid, zeroTerminated, Allocator, const(char)[])(allocator, str);
    parser.parse();
    return Asdf(parser.result);
}

/// ditto
Asdf parseJson(
    Flag!"includingNewLine" includingNewLine = Yes.includingNewLine,
    Flag!"spaces" spaces = Yes.spaces, 
    Flag!"assumeValid" assumeValid = No.assumeValid,
    Flag!"zeroTerminated" zeroTerminated = No.zeroTerminated,
    )
    (in char[] str)
{
    import std.experimental.allocator;
    import std.experimental.allocator.gc_allocator;
    auto parser = JsonParserNew!(includingNewLine, spaces, assumeValid, zeroTerminated, shared GCAllocator, const(char)[])(GCAllocator.instance, str);
    parser.parse();
    return Asdf(parser.result);
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
    chunks = input range composed of elements type of `const(ubyte)[]` or string / const(char)[].
        `chunks` can use the same buffer for each chunk.
    initLength = initial output buffer length. Minimal value equals 32.
Returns:
    Input range composed of ASDF values. Each value uses the same internal buffer.
+/
auto parseJsonByLine(
    Flag!"spaces" spaces = Yes.spaces,
    Input)
    (Input input)
{
    import std.experimental.allocator.gc_allocator;
    alias Parser = JsonParserNew!(false, cast(bool)spaces, false, false, shared GCAllocator, Input);
    static struct ByLineValue
    {
        private Parser parser;
        private bool _empty, _nextEmpty;

        void popFront()
        {
            assert(!empty);
            if(_nextEmpty)
            {
                _empty = true;
                return;
            }
            // parser.oa.shift = 0;
            parser.dataLength = 0;
            auto error = parser.parse;
            if(!error)
            {
                auto t = parser.skipSpaces_;
                import std.stdio;
                if(t != '\n' && t != 0)
                {
                    error = AsdfErrorCode.unexpectedValue;
                }
                else
                if(t == 0)
                {
                    _nextEmpty = true;
                    return;
                }
                else
                {
                    parser.skipNewLine;
                    _nextEmpty = false;
                    return;
                }
            }
            parser.skipLine;
            _nextEmpty = parser.prepareInput_;
        }

        auto front() @property
        {
            assert(!empty);
            return Asdf(parser.result);
        }

        bool empty()
        {
            return _empty;
        }
    }
    ByLineValue ret; 
    if(input.empty)
    {
        ret._empty = ret._nextEmpty = true;
    }
    else
    {
        ret = ByLineValue(Parser(GCAllocator.instance, input));
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
    auto values = text.chunks(3).parseJsonByLine;
    assert(values.front.data == [1]);
    values.popFront;
    assert(values.front.data == [2]);
    values.popFront;
    assert(values.empty);
}

///
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
    0,0,0,0,0,0,0,0,  0,6,2,0,0,6,0,0, // 0
    0,0,0,0,0,0,0,0,  0,0,0,0,0,0,0,0, // 1
    7,1,0,1,1,1,1,1,  1,1,1,9,1,9,9,1, // 2
    9,9,9,9,9,9,9,9,  9,9,1,1,1,1,1,1, // 3

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
bool isPlainJsonCharacter()(size_t c)
{
    return (parseFlags[c] & 1) != 0;
}

pragma(inline, true)
bool isJsonWhitespace()(size_t c)
{
    return (parseFlags[c] & 2) != 0;
}

pragma(inline, true)
bool isJsonLineWhitespace()(size_t c)
{
    return (parseFlags[c] & 4) != 0;
}

pragma(inline, true)
bool isJsonNumber()(size_t c)
{
    return (parseFlags[c] & 8) != 0;
}

package struct JsonParserNew(bool includingNewLine, bool hasSpaces, bool assumeValid, bool zeroTerminated, Allocator, Input = const(ubyte)[])
{

    ubyte[] data;
    Allocator* allocator;
    Input input;
    static if (chunked)
        ubyte[] front;
    else
        alias front = input;
    size_t dataLength;

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

    bool prepareInput_()()
    {
        static if (zeroTerminated && !chunked)
            return true;
        else
        {
            static if (chunked)
            {
                if (front.length == 0)
                {
                    if (input.empty)
                        return false;
                    front = cast(typeof(front)) input.front;
                    input.popFront;
                }
            }
            return front.length != 0;
        }
    }

    void skipNewLine()()
    {
        assert(front.length);
        assert(front[0] == '\n');
        front = front[1 .. $];
    }

    char skipSpaces_()()
    {
        for(;;)
        {
            if (prepareInput_ == false)
                return 0;
            static if (includingNewLine)
                alias isWhite = isJsonWhitespace;
            else
                alias isWhite = isJsonLineWhitespace;
            if (isWhite(front[0]))
            {
                front = front[1 .. $];
                continue;
            }
            return front[0];
        }
    }

    bool skipLine()()
    {
        for(;;)
        {
            if (prepareInput_ == false)
                return false;
            auto c = front[0];
            front = front[1 .. $];
            if (c == '\n')
                return true;
        }
    }

    State state;

    auto result()()
    {
        return data[0 .. dataLength];
    }

    pragma(inline, false)
    AsdfErrorCode parse()
    {
        const(ubyte)* strPtr;
        const(ubyte)* strEnd;
        ubyte* dataPtr;
        ubyte* stringAndNumberShift = void;
        import std.stdio;
        static if (chunked)
        {
            bool prepareInput()()
            {
                if (_expect(strEnd == strPtr, false))
                {
                    if (input.empty)
                    {
                        return false;
                    }
                    front = cast(typeof(front)) input.front;
                    input.popFront;
                    if (front.length == 0)
                        return false;
                    strPtr = front.ptr;
                    strEnd = front.ptr + front.length;
                    const dataAddLength = front.length * 6;
                    const dataLength = dataPtr - data.ptr;
                    const dataRequiredLength = dataLength + dataAddLength;
                    if (data.length < dataRequiredLength)
                    {
                        const valueLength = stringAndNumberShift - dataPtr;
                        import std.algorithm.comparison: max;
                        allocator.reallocate(*cast(void[]*)&data, max(data.length * 2, dataRequiredLength));
                        dataPtr = data.ptr + dataLength;
                        stringAndNumberShift = dataPtr + valueLength;
                    }
                }
                return true;
            }
            strPtr = front.ptr;
            strEnd = front.ptr + front.length;
            prepareInput;
        }
        else
        {
            strPtr = cast(const(ubyte)*) input.ptr;
            strEnd = cast(const(ubyte)*) input.ptr + input.length;
            static if (zeroTerminated)
            {
                enum prepareInput = false;
            }
            else
            {
                bool prepareInput()() { return strEnd != strPtr; }
            }
        }
        data = cast(ubyte[])allocator.allocate((strEnd - strPtr) * 6);
        // data[] = 0;
        dataPtr = data.ptr;

        static if (hasSpaces)
        bool skipSpaces()()
        {
            for(;;)
            {
                if (prepareInput == false)
                {
                    return false;
                }
                static if (includingNewLine)
                    alias isWhite = isJsonWhitespace;
                else
                    alias isWhite = isJsonLineWhitespace;
                if (isWhite(strPtr[0]))
                {
                    strPtr++;
                    continue;
                }
                return true;
            }
        }
        else alias skipSpaces = prepareInput;

        int readUnicode(out dchar d)
        {
            d = '\0';
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
                if (*strPtr++ != '\\')
                    return -1;
                if (!prepareInput)
                    return 1;
                if (*strPtr++ != 'u')
                    return -1;
                d = (d & 0x3FF) << 10;
                dchar trailing;
                if (auto r = (readUnicode(trailing)))
                    return r;
                if (!(0xDC00 <= trailing && trailing <= 0xDFFF))
                    return -1;
                d |= trailing & 0x3FF;
                d += 0x10000;
            }
            if (0xFDD0 <= d && d <= 0xFDEF)
                return -1; // TODO: review
            if (((~0xFFFF & d) >> 0x10) <= 0x10 && (0xFFFF & d) >= 0xFFFE)
                return -1; // TODO: review 
            encodeUTF8(d, dataPtr);
            return 0;
        }
    
        size_t[32] stack = void;
        size_t stackIndex = 0;

        typeof(return) retCode;
        bool currIsKey = void;
        size_t stackValue = void;
        goto value;
        switch (state)
        {
        default: assert(0);
        key:
            static if (hasSpaces)
                skipSpaces;
            if (!skipSpaces)
                goto vObject_unexpectedEnd; // TODO
        key_start:
            if (*strPtr != '"')
                goto vObject_unexpectedValue; // TODO
            currIsKey = true;
            stringAndNumberShift = dataPtr;
            // reserve 4 byte for the length
            dataPtr += 1;
            goto string;

        first_object_element:
            static if (hasSpaces)
                skipSpaces;
            if (!prepareInput)
                goto vValue_unexpectedEnd; // TODO
            if (*strPtr != '}')
                goto key_start;
            strPtr++;
            goto structure_end;
        first_array_element:
            static if (hasSpaces)
                skipSpaces;
            if (!prepareInput)
                goto vValue_unexpectedEnd; // TODO
            if (*strPtr != ']')
                goto value_start;
            strPtr++;
            goto structure_end;
        next:
            if (stackIndex == 0)
                goto ret;
            {
                static if (hasSpaces)
                    skipSpaces();
                if (!prepareInput)
                    goto vArray_unexpectedEnd; // TODO: proper error
                stackValue = stack[stackIndex - 1];
                const isObject = stackValue & 1;
                auto v = *strPtr++;
                if (isObject)
                {
                    if (v == ',')
                        goto key;
                    if (v != '}')
                        goto vObject_unexpectedValue;
                }
                else
                {
                    if (v == ',')
                        goto value;
                    if (v != ']')
                        goto vArray_unexpectedValue;
                }
            }
        structure_end: {
            stackValue = stack[--stackIndex];
            const structureShift = stackValue >> 1;
            const structureLengthPtr = data.ptr + structureShift;
            const size_t structureLength = dataPtr - structureLengthPtr - 4;
            if (structureLength > uint.max)
                goto vArray_unexpectedValue; //TODO: proper error
            version(X86_Any)
                *cast(uint*) structureLengthPtr = cast(uint) structureLength;
            else
                static assert(0);
            goto next;
        }
        value:
            if (!skipSpaces)
                goto vValue_unexpectedEnd;
        value_start:
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
                        goto number_found;
                    while(zeroTerminated || strEnd >= strPtr + 4)
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
                            char c0 = strPtr[0]; if (!isJsonNumber(c0)) goto number_found; dataPtr[0] = c0;
                            strPtr += 1;
                            dataPtr += 1;
                        }
                    }
                }
            number_found3: dataPtr++; strPtr++;
            number_found2: dataPtr++; strPtr++;
            number_found1: dataPtr++; strPtr++;
            number_found0: dataPtr -= 4;
            number_found:

                auto numberLength = dataPtr - stringAndNumberShift - 1;
                if (numberLength > ubyte.max)
                    goto vNull_unexpectedValue; // TODO: replace proper error
                *stringAndNumberShift = cast(ubyte) numberLength;
                goto next;
            }
            case '{':
                strPtr++;
                *dataPtr++ = Asdf.Kind.object;
                stack[stackIndex++] = ((dataPtr - data.ptr) << 1) ^ 1;
                dataPtr += 4;
                goto first_object_element;
            case '[':
                strPtr++;
                *dataPtr++ = Asdf.Kind.array;
                stack[stackIndex++] = ((dataPtr - data.ptr) << 1) ^ 0;
                dataPtr += 4;
                goto first_array_element;
            import std.stdio;
            foreach (name; AliasSeq!("false", "null", "true"))
            {
            case name[0]:
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
                        strPtr += 1;
                        foreach (i; 1 .. name.length)
                        {
                            import std.stdio;
                            if (prepareInput == false)
                            {
                                static if (name == "true")
                                    goto vTrue_unexpectedEnd;
                                else
                                static if (name == "false")
                                    goto vFalse_unexpectedEnd;
                                else
                                    goto vNull_unexpectedEnd;
                            }
                            static if (!assumeValid)
                            {
                                if (_expect(strPtr[0] != name[i], false))
                                {
                                    static if (name == "true")
                                        goto vTrue_unexpectedValue;
                                    else
                                    static if (name == "false")
                                        goto vFalse_unexpectedValue;
                                    else
                                        goto vNull_unexpectedValue;
                                }
                            }
                            strPtr++;
                        }
                        static if (name == "null")
                            *dataPtr++ = Asdf.Kind.null_;
                        else
                        static if (name == "false")
                            *dataPtr++ = Asdf.Kind.false_;
                        else
                            *dataPtr++ = Asdf.Kind.true_;
                        goto next;
                    }
            }

            default :
                import std.conv;
                assert(0, strPtr[0].to!string);
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
            StringLoop:
                for(;;)
                {
                    if (!prepareInput)
                        goto vString_unexpectedEnd;

                    while(zeroTerminated || strEnd >= strPtr + 4)
                    {
                        char c0 = strPtr[0]; dataPtr += 4;     if (!isPlainJsonCharacter(c0)) goto string_found0;
                        char c1 = strPtr[1]; dataPtr[-4] = c0; if (!isPlainJsonCharacter(c1)) goto string_found1;
                        char c2 = strPtr[2]; dataPtr[-3] = c1; if (!isPlainJsonCharacter(c2)) goto string_found2;
                        char c3 = strPtr[3]; dataPtr[-2] = c2; if (!isPlainJsonCharacter(c3)) goto string_found3;
                        strPtr += 4;         dataPtr[-1] = c3;
                    }
                    static if (!zeroTerminated)
                    {
                        while(strEnd > strPtr)
                        {
                            char c0 = strPtr[0]; if (!isPlainJsonCharacter(c0)) goto string_found; dataPtr[0] = c0;
                            strPtr += 1;
                            dataPtr += 1;
                        }
                    }
                }
            string_found3: dataPtr++; strPtr++;
            string_found2: dataPtr++; strPtr++;
            string_found1: dataPtr++; strPtr++;
            string_found0: dataPtr -= 4;
            string_found:

                uint c = strPtr[0];
                if (c == '\"')
                {
                    strPtr += 1;
                    if (currIsKey)
                    {
                        auto stringLength = dataPtr - stringAndNumberShift - 1;
                        if (stringLength > ubyte.max)
                            goto vNull_unexpectedValue; // TODO: replace proper error
                        *cast(ubyte*)stringAndNumberShift = cast(ubyte) stringLength;
                        static if (hasSpaces)
                            skipSpaces();
                        if (!prepareInput)
                            goto vArray_unexpectedEnd; // TODO: proper error
                        if (*strPtr != ':')
                            goto vObject_unexpectedValue; // TODO: proper error
                        strPtr++;
                        goto value;
                    }
                    else
                    {
                        auto stringLength = dataPtr - stringAndNumberShift - 4;
                        if (stringLength > uint.max)
                            goto vNull_unexpectedValue; // TODO: replace proper error
                        version(X86_Any)
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
        assert(0);
    ret:
        front = front[cast(typeof(front.ptr)) strPtr - front.ptr .. $];
    ret_error:
        dataLength = dataPtr - data.ptr;
        return retCode;
    unexpectedEnd: retCode = AsdfErrorCode.unexpectedEnd; goto ret_error;
    unexpectedValue: retCode = AsdfErrorCode.unexpectedValue; goto ret_error;

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

unittest
{
    import std.conv;
    auto asdf_data = parseJson(` [ true, 123 , [ false, 123.0 , "123211" ], "3e23e" ] `);
    auto str = asdf_data.to!string;
    auto str2 = `[true,123,[false,123.0,"123211"],"3e23e"]`;
    assert( str == str2);
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
    //    assert(c < 0x200000);
        ptr[0] = cast(ubyte) (0xF0 | (c >> 18));
        ptr[1] = cast(ubyte) (0x80 | ((c >> 12) & 0x3F));
        ptr[2] = cast(ubyte) (0x80 | ((c >> 6) & 0x3F));
        ptr[3] = cast(ubyte) (0x80 | (c & 0x3F));
        ptr += 4;
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

unittest
{
    import std.string;
    import std.range;
    static immutable str = `"1234567890qwertyuiopasdfghjklzxcvbnm"`;
    auto data = Asdf(str[1..$-1]);
    assert(data == parseJson(str));
    import std.stdio;
    foreach(i; 1 .. str.length)
    {
        auto s  = parseJson(str.representation.chunks(i));
        assert(data == s);
    }
}

    import std.stdio;
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

unittest
{
    import std.string;
    import std.range;
    import std.conv;
    static immutable str = `941763918276349812734691287354912873459128635412037501236410234567123847512983745126`;
    assert(str == parseJson(str).to!string);
    foreach(i; 1 .. str.length)
    {
        assert(str == parseJson(str.representation.chunks(i)).to!string);

    }
}
