/**
* Contains the garbage collector configuration.
*
* Copyright: Copyright Digital Mars 2014
* License:   $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
*/

module gc.config;

import core.stdc.stdlib;
import core.stdc.stdio;
import core.stdc.ctype;
import core.stdc.string;
import core.vararg;

nothrow @nogc:
extern extern(C) string[] rt_args();

extern extern(C) __gshared bool rt_envvars_enabled;
extern extern(C) __gshared bool rt_cmdline_enabled;
extern extern(C) __gshared string[] rt_options;

struct Config
{
    bool disable;            // start disabled
    byte profile;            // enable profiling with summary when terminating program
    bool precise;            // enable precise scanning
    bool concurrent;         // enable concurrent collection

    size_t initReserve;      // initial reserve (MB)
    size_t minPoolSize = 1;  // initial and minimum pool size (MB)
    size_t maxPoolSize = 64; // maximum pool size (MB)
    size_t incPoolSize = 3;  // pool size increment (MB)
    float heapSizeFactor = 2.0; // heap size to used memory ratio

@nogc nothrow:

    bool initialize()
    {
        import core.internal.traits : externDFunc;

        alias rt_configCallBack = string delegate(string) @nogc nothrow;
        alias fn_configOption = string function(string opt, scope rt_configCallBack dg, bool reverse) @nogc nothrow;

        alias rt_configOption = externDFunc!("rt.config.rt_configOption", fn_configOption);

        string parse(string opt) @nogc nothrow
        {
            if (!parseOptions(opt))
                return "err";
            return null; // continue processing
        }
        string s = rt_configOption("gcopt", &parse, true);
        return s is null;
    }

    void help()
    {
        string s = "GC options are specified as white space separated assignments:
    disable:0|1    - start disabled (%d)
    profile:0|1    - enable profiling with summary when terminating program (%d)
    precise:0|1    - enable precise scanning (not implemented yet)
    concurrent:0|1 - enable concurrent collection (not implemented yet)

    initReserve:N  - initial memory to reserve in MB (%lld)
    minPoolSize:N  - initial and minimum pool size in MB (%lld)
    maxPoolSize:N  - maximum pool size in MB (%lld)
    incPoolSize:N  - pool size increment MB (%lld)
    heapSizeFactor:N - targeted heap size to used memory ratio (%f)
";
        printf(s.ptr, disable, profile, cast(long)initReserve, cast(long)minPoolSize,
               cast(long)maxPoolSize, cast(long)incPoolSize, heapSizeFactor);
    }

    bool parseOptions(const(char)[] opt)
    {
        opt = skip!isspace(opt);
        while (opt.length)
        {
            auto tail = find!(c => c == ':' || c == '=')(opt);
            auto name = opt[0 .. $ - tail.length];
            if (tail.length <= 1)
                return optError("Missing argument for", name);
            tail = tail[1 .. $];

            switch (name)
            {
            case "help": help(); break;

            foreach (field; __traits(allMembers, Config))
            {
                static if (!is(typeof(__traits(getMember, this, field)) == function))
                {
                case field:
                    if (!parse(name, tail, __traits(getMember, this, field)))
                        return false;
                    break;
                }
            }
            break;

            default:
                return optError("Unknown", name);
            }
            opt = skip!isspace(tail);
        }
        return true;
    }
}

private:

bool optError(in char[] msg, in char[] name)
{
    version (unittest) if (inUnittest) return false;

    fprintf(stderr, "%.*s GC option '%.*s'.\n",
            cast(int)msg.length, msg.ptr,
            cast(int)name.length, name.ptr);
    return false;
}

inout(char)[] skip(alias pred)(inout(char)[] str)
{
    return find!(c => !pred(c))(str);
}

inout(char)[] find(alias pred)(inout(char)[] str)
{
    foreach (i; 0 .. str.length)
        if (pred(str[i])) return str[i .. $];
    return null;
}

bool parse(T:size_t)(const(char)[] optname, ref const(char)[] str, ref T res)
in { assert(str.length); }
body
{
    size_t i, v;
    for (; i < str.length && isdigit(str[i]); ++i)
        v = 10 * v + str[i] - '0';

    if (!i)
        return parseError("a number", optname, str);
    str = str[i .. $];
    res = v;
    return true;
}

bool parse(T:bool)(const(char)[] optname, ref const(char)[] str, ref T res)
in { assert(str.length); }
body
{
    if (str[0] == '1' || str[0] == 'y' || str[0] == 'Y')
        res = true;
    else if (str[0] == '0' || str[0] == 'n' || str[0] == 'N')
        res = false;
    else
        return parseError("'0/n/N' or '1/y/Y'", optname, str);
    str = str[1 .. $];
    return true;
}

bool parse(T:float)(const(char)[] optname, ref const(char)[] str, ref T res)
in { assert(str.length); }
body
{
    // % uint f %n \0
    char[1 + 10 + 1 + 2 + 1] fmt=void;
    // specify max-width
    immutable n = snprintf(fmt.ptr, fmt.length, "%%%uf%%n", cast(uint)str.length);
    assert(n > 4 && n < fmt.length);

    int nscanned;
    if (sscanf(str.ptr, fmt.ptr, &res, &nscanned) < 1)
        return parseError("a float", optname, str);
    str = str[nscanned .. $];
    return true;
}

bool parseError(in char[] exp, in char[] opt, in char[] got)
{
    version (unittest) if (inUnittest) return false;

    fprintf(stderr, "Expecting %.*s as argument for GC option '%.*s', got '%.*s' instead.\n",
            cast(int)exp.length, exp.ptr,
            cast(int)opt.length, opt.ptr,
            cast(int)got.length, got.ptr);
    return false;
}

size_t min(size_t a, size_t b) { return a <= b ? a : b; }

version (unittest) __gshared bool inUnittest;

unittest
{
    inUnittest = true;
    scope (exit) inUnittest = false;

    Config conf;
    assert(!conf.parseOptions("profile"));
    assert(!conf.parseOptions("profile:"));
    assert(!conf.parseOptions("profile:5"));
    assert(conf.parseOptions("profile:y") && conf.profile);
    assert(conf.parseOptions("profile:n") && !conf.profile);
    assert(conf.parseOptions("profile:Y") && conf.profile);
    assert(conf.parseOptions("profile:N") && !conf.profile);
    assert(conf.parseOptions("profile:1") && conf.profile);
    assert(conf.parseOptions("profile:0") && !conf.profile);

    assert(conf.parseOptions("profile=y") && conf.profile);
    assert(conf.parseOptions("profile=n") && !conf.profile);

    assert(conf.parseOptions("profile:1 minPoolSize:16"));
    assert(conf.profile);
    assert(conf.minPoolSize == 16);

    assert(conf.parseOptions("heapSizeFactor:3.1"));
    assert(conf.heapSizeFactor == 3.1f);
    assert(conf.parseOptions("heapSizeFactor:3.1234567890 profile:0"));
    assert(conf.heapSizeFactor > 3.123f);
    assert(!conf.profile);
    assert(!conf.parseOptions("heapSizeFactor:3.0.2.5"));
    assert(conf.parseOptions("heapSizeFactor:2"));
    assert(conf.heapSizeFactor == 2.0f);

    assert(!conf.parseOptions("initReserve:foo"));
    assert(!conf.parseOptions("initReserve:y"));
    assert(!conf.parseOptions("initReserve:20.5"));
}
