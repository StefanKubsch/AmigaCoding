#ifndef Starfield2D_H
#define Starfield2D_H


//***************************************
//* Simple 2D starfield     	   		*
//*								   		*
//* (C) 2020-2026 by Stefan Kubsch      *
//***************************************

struct StarStruct2D
{
	UWORD x;
	UBYTE y;
	UBYTE z;
} Stars2D[200];

void Init_2DStarfield(void)
{
	for (UBYTE i = 0; i < 200; ++i)
	{
		Stars2D[i].x = lwmf_Random() % SCREENWIDTH;
		Stars2D[i].y = lwmf_Random() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
		Stars2D[i].z = lwmf_Random() % 3 + 1;
	}
}

void Draw_2DStarfield(void)
{
	long* const Target = (long*)RenderPort.BitMap->Planes[0];

	for (UBYTE i = 0; i < 200; ++i)
	{
		struct StarStruct2D* const s = &Stars2D[i];

		s->x += s->z << 1;

		if (s->x >= SCREENWIDTH)
		{
			s->x = 0;
			s->y = lwmf_Random() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
			s->z = lwmf_Random() % 3 + 1;
		}

		lwmf_SetPixel(s->x, s->y, s->z, Target);
	}
}


#endif /* Starfield2D_H */