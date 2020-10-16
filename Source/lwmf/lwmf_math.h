#ifndef LWMF_MATH_H
#define LWMF_MATH_H

// Simple random number generator based on XorShift
// https://en.wikipedia.org/wiki/Xorshift
ULONG lwmf_XorShift32(void)
{
	static ULONG Seed = 7;

	Seed ^= Seed << 13;
	Seed ^= Seed >> 17;
	return Seed ^= Seed << 5;
}


#endif /* LWMF_MATH_H */