#ifndef Starfield3D_H
#define Starfield3D_H


//**********************************
//* Simple starfield  			   *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

// Needed bitplanes : 2
// Needed colors : 4

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
	NumberOf3DStars = FastCPUFlag ? 300 : 100;

	if (!(Stars3D = AllocVec(sizeof(struct StarStruct3D) * NumberOf3DStars, MEMF_ANY)))
	{
		lwmf_CleanupAll();
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
	// Since we use only bitplane 0 for the starfield, we enable only bitplane 0
	// Bitmap.Planes[0] = Bit 0
	// Bitmap.Planes[1] = Bit 1
	// ...
	// To enable bitplane 0 only set the mask as follows:
	// 00000001 = Hex 0x01
	//
	// You could also use "SetWrMsk(RP, Color)" - but it´s just a macro...

	RenderPort.Mask = 0x03;

	for (int i = 0; i < NumberOf3DStars; ++i)
	{
		Stars3D[i].z -= 15;
	
		if (Stars3D[i].z <= 0) 
		{
			Stars3D[i].z = 800;
		}
		
		const int x = Stars3D[i].x / Stars3D[i].z + WidthMid;
		const int y = Stars3D[i].y / Stars3D[i].z + HeightMid;
		
		if ((unsigned int)x < WIDTH && (unsigned int)y < HEIGHT)
		{
			SetAPen(&RenderPort, Stars3D[i].z / 300 + 1);
			WritePixel(&RenderPort, x, y);
		}
	}

	RenderPort.Mask = -1;
}


#endif /* Starfield3D_H */