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
    int x;
    int y;
    int z;
} *Stars2D;

int NumberOf2DStars;

BOOL Init_2DStarfield(void)
{
	// Use more stars, if a fast CPU is available...
	NumberOf2DStars = FastCPUFlag ? 100 : 50;

	if (!(Stars2D = AllocVec(sizeof(struct StarStruct2D) * NumberOf2DStars, MEMF_ANY)))
	{
		return FALSE;
	}

    for (int i = 0; i < NumberOf2DStars; ++i) 
    {
        Stars2D[i].x = lwmf_XorShift32() % WIDTH;
        Stars2D[i].y = lwmf_XorShift32() % HEIGHT + UPPERBORDERLINE;
        Stars2D[i].z = lwmf_XorShift32() % 3 + 2;
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
		
		if (Stars2D[i].y < LOWERBORDERLINE)
		{
			SetAPen(&RenderPort, Stars2D[i].z);
			WritePixel(&RenderPort, Stars2D[i].x, Stars2D[i].y);
		}
	}
}


#endif /* Starfield2D_H */