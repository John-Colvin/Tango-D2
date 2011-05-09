/*
 *  Copyright (C) 2004-2005 by Digital Mars, www.digitalmars.com
 *  Written by Walter Bright
 *
 *  This software is provided 'as-is', without any express or implied
 *  warranty. In no event will the authors be held liable for any damages
 *  arising from the use of this software.
 *
 *  Permission is granted to anyone to use this software for any purpose,
 *  including commercial applications, and to alter it and redistribute it
 *  freely, in both source and binary form, subject to the following
 *  restrictions:
 *
 *  o  The origin of this software must not be misrepresented; you must not
 *     claim that you wrote the original software. If you use this software
 *     in a product, an acknowledgment in the product documentation would be
 *     appreciated but is not required.
 *  o  Altered source versions must be plainly marked as such, and must not
 *     be misrepresented as being the original software.
 *  o  This notice may not be removed or altered from any source
 *     distribution.
 */

module rt.compiler.gdc.typeinfo.ti_Adouble;

private import rt.compiler.gdc.typeinfo.ti_double;
private import rt.compiler.util.hash;

// double[]

class TypeInfo_Ad : TypeInfo_Array
{
    override char[] toString() { return "double[]"; }

    override hash_t getHash(in void* p){
        double[] s = *cast(double[]*)p;
        size_t len = s.length;
        auto str = s.ptr;
        return rt_hash_str(str,len*double.sizeof,0); // use rt_hash_block?
    }

    override equals_t equals(in void* p1, in void* p2)
    {
        double[] s1 = *cast(double[]*)p1;
        double[] s2 = *cast(double[]*)p2;
        size_t len = s1.length;

        if (len != s2.length)
            return 0;
        for (size_t u = 0; u < len; u++)
        {
            if (!TypeInfo_d._equals(s1[u], s2[u]))
                return false;
        }
        return true;
    }

    override int compare(in void* p1, in void* p2)
    {
        double[] s1 = *cast(double[]*)p1;
        double[] s2 = *cast(double[]*)p2;
        size_t len = s1.length;

        if (s2.length < len)
            len = s2.length;
        for (size_t u = 0; u < len; u++)
        {
            int c = TypeInfo_d._compare(s1[u], s2[u]);
            if (c)
                return c;
        }
        if (s1.length < s2.length)
            return -1;
        else if (s1.length > s2.length)
            return 1;
        return 0;
    }

    override size_t talign()
    {
        return (double[]).alignof;
    }

    override size_t tsize()
    {
        return (double[]).sizeof;
    }

    override uint flags()
    {
        return 1;
    }

    override TypeInfo next()
    {
        return typeid(double);
    }

    version (X86_64) override int argTypes(out TypeInfo arg1, out TypeInfo arg2)
    {
        return 0;
    }
}

// idouble[]

class TypeInfo_Ap : TypeInfo_Ad
{
    char[] toString() { return "idouble[]"; }

    override TypeInfo next()
    {
        return typeid(idouble);
    }
}
