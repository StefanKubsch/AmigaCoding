#ifndef Starfield2D_H
#define Starfield2D_H


//**********************************
//* Simple 2D starfield     	   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

BOOL Init_2DStarfield(void);
void Cleanup_2DStarfield(void);
void Draw_2DStarfield(void);

struct StarStruct2D
{
    UWORD x;
    UWORD y;
    UWORD z;
} *Stars2D;

UWORD NumberOf2DStars;

BOOL Init_2DStarfield(void)
{
	// Use more stars, if a fast CPU is available...
	NumberOf2DStars = FastCPUFlag ? 200 : 100;

	if (!(Stars2D = AllocVec(sizeof(struct StarStruct2D) * NumberOf2DStars, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

    for (UWORD i = 0; i < NumberOf2DStars; ++i) 
    {
        Stars2D[i].x = lwmf_Random() % WIDTH;
        Stars2D[i].y = lwmf_Random() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
        Stars2D[i].z = lwmf_Random() % 3 + 1;
    }

	return TRUE;
}

void Cleanup_2DStarfield(void)
{
	if (Stars2D)
	{
		FreeVec(Stars2D);
	}
}

void Draw_2DStarfield(void)
{
	for (UWORD i = 0; i < NumberOf2DStars; ++i)
	{
		Stars2D[i].x += Stars2D[i].z << 1;
	
		if (Stars2D[i].x >= WIDTH) 
		{
			Stars2D[i].x = 0;
		}
		
		SetAPen(&RenderPort, Stars2D[i].z + 1);
		WritePixel(&RenderPort, Stars2D[i].x, Stars2D[i].y);
	}
}


#endif /* Starfield2D_H */