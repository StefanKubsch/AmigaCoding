#ifndef LWMF_MATH_H
#define LWMF_MATH_H

//
// Global symbols for our assembler functions
//

ULONG lwmf_Random(void);

//
// Functions
//

static UWORD RGB4_Lerp(UWORD c0, UWORD c1, UWORD t, UWORD tmax)
{
	WORD r0, g0, b0;
	WORD r1, g1, b1;
	WORD f;

	if (tmax == 0)
	{
		return c0;
	}

	r0 = (c0 >> 8) & 0xF;
	g0 = (c0 >> 4) & 0xF;
	b0 =  c0       & 0xF;

	r1 = (c1 >> 8) & 0xF;
	g1 = (c1 >> 4) & 0xF;
	b1 =  c1       & 0xF;

	f = (WORD)((t << 8) / tmax);

	return
		((UWORD)(r0 + (((r1 - r0) * f) >> 8)) << 8) |
		((UWORD)(g0 + (((g1 - g0) * f) >> 8)) << 4) |
		((UWORD)(b0 + (((b1 - b0) * f) >> 8)));
}

#endif /* LWMF_MATH_H */