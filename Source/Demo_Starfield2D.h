#ifndef Starfield2D_H
#define Starfield2D_H


//**********************************
//* Simple 2D starfield     	   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

struct StarStruct2D
{
	UWORD x;
	UWORD y;
	UWORD z;
} Stars2D[200];

void Init_2DStarfield(void)
{
	for (UWORD i = 0; i < 200; ++i) 
	{
		Stars2D[i].x = lwmf_Random() % SCREENWIDTH;
		Stars2D[i].y = lwmf_Random() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
		Stars2D[i].z = lwmf_Random() % 3 + 1;
	}
}

void Draw_2DStarfield(void)
{
	for (UWORD i = 0; i < 200; ++i)
	{
		Stars2D[i].x += Stars2D[i].z << 1;
	
		if (Stars2D[i].x >= SCREENWIDTH) 
		{
			Stars2D[i].x = 0;
			Stars2D[i].y = lwmf_Random() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
			Stars2D[i].z = lwmf_Random() % 3 + 1;
		}
		
		lwmf_SetPixel(Stars2D[i].x, Stars2D[i].y, Stars2D[i].z, (long*)RenderPort.BitMap->Planes[0]);
	}
}


#endif /* Starfield2D_H */