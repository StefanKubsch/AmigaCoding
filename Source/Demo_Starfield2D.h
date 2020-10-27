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

int NumberOf2DStars;

BOOL Init_2DStarfield(void)
{
	// Use more stars, if a fast CPU is available...
	NumberOf2DStars = FastCPUFlag ? 200 : 100;

	if (!(Stars2D = AllocVec(sizeof(struct StarStruct2D) * NumberOf2DStars, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

    for (int i = 0; i < NumberOf2DStars; ++i) 
    {
        Stars2D[i].x = lwmf_XorShift32() % WIDTH;
        Stars2D[i].y = lwmf_XorShift32() % (LOWERBORDERLINE - UPPERBORDERLINE) + UPPERBORDERLINE;
        Stars2D[i].z = lwmf_XorShift32() % 3 + 1;
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
	for (int i = 0; i < NumberOf2DStars; ++i)
	{
		Stars2D[i].x += Stars2D[i].z << 1;
	
		if (Stars2D[i].x >= WIDTH) 
		{
			Stars2D[i].x = 0;
		}
		
		SetAPen(&RenderPort, Stars2D[i].z + 7);
		WritePixel(&RenderPort, Stars2D[i].x, Stars2D[i].y);
	}
}


#endif /* Starfield2D_H */