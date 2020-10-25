#ifndef Starfield3D_H
#define Starfield3D_H


//**********************************
//* Simple 3D starfield			   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

BOOL Init_3DStarfield(void);
void Cleanup_3DStarfield(void);
void Draw_3DStarfield(void);

struct StarStruct3D
{
    int x;
    int y;
    int z;
} *Stars3D;

int NumberOf3DStars;

BOOL Init_3DStarfield(void)
{
	// Use more stars, if a fast CPU is available...
	NumberOf3DStars = FastCPUFlag ? 200 : 50;

	if (!(Stars3D = AllocVec(sizeof(struct StarStruct3D) * NumberOf3DStars, MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

    for (int i = 0; i < NumberOf3DStars; ++i) 
    {
        Stars3D[i].x = (lwmf_XorShift32() % WIDTH - (WIDTH >> 1)) << 8;
        Stars3D[i].y = (lwmf_XorShift32() % HEIGHT - (HEIGHT >> 1)) << 8;
        Stars3D[i].z = lwmf_XorShift32() % 800;
    }

	return TRUE;
}

void Cleanup_3DStarfield(void)
{
	if (Stars3D)
	{
		FreeVec(Stars3D);
	}
}

void Draw_3DStarfield(void)
{
	RenderPort.Mask = 0x03;
	
	const int WidthMid = WIDTH >> 1;
	const int HeightMid = HEIGHT >> 1;

	for (int i = 0; i < NumberOf3DStars; ++i)
	{
		Stars3D[i].z -= 15;
	
		if (Stars3D[i].z <= 0) 
		{
			Stars3D[i].z = 800;
		}
		
		const int x = Stars3D[i].x / Stars3D[i].z + WidthMid;
		const int y = Stars3D[i].y / Stars3D[i].z + HeightMid;
		
		if ((unsigned int)x < WIDTH && y > UPPERBORDERLINE && y < LOWERBORDERLINE)
		{
			SetAPen(&RenderPort, Stars3D[i].z / 300 + 1);
			WritePixel(&RenderPort, x, y);
		}
	}

	RenderPort.Mask = -1;
}


#endif /* Starfield3D_H */