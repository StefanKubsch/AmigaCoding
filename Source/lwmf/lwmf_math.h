#ifndef LWMF_MATH_H
#define LWMF_MATH_H

ULONG lwmf_XorShift32(void);
LONG lwmf_IntPow(LONG Base, LONG Exp);

// Simple random number generator based on XorShift
// https://en.wikipedia.org/wiki/Xorshift
ULONG lwmf_XorShift32(void)
{
	static ULONG Seed = 7;

	Seed ^= Seed << 13;
	Seed ^= Seed >> 17;
	return Seed ^= Seed << 5;
}

LONG lwmf_IntPow(LONG Base, LONG Exp)
{
    LONG Result = 1;

    for (;;)
    {
        if (Exp & 1)
		{
            Result *= Base;
		}

        Exp >>= 1;
        
		if (!Exp)
		{
            break;
		}

        Base *= Base;
    }

    return Result;
}


#endif /* LWMF_MATH_H */