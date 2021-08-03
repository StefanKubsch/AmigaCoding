#ifndef Starfield3D_H
#define Starfield3D_H


//***************************************
//* Simple 3D starfield			   		*
//*								   		*
//* (C) 2020-2021 by Stefan Kubsch      *
//***************************************

struct StarStruct3D
{
	WORD x;
	WORD y;
	WORD z;
} Stars3D[200];

void Init_3DStarfield(void)
{
	for (UBYTE i = 0; i < 200; ++i)
	{
		Stars3D[i].x = (lwmf_Random() % SCREENWIDTH - SCREENWIDTHMID) << 8;
		Stars3D[i].y = (lwmf_Random() % SCREENHEIGHT - SCREENHEIGHTMID) << 8;
		Stars3D[i].z = lwmf_Random() % 800;
	}
}

void Draw_3DStarfield(void)
{
	for (UBYTE i = 0; i < 200; ++i)
	{
		Stars3D[i].z -= 15;

		if (Stars3D[i].z <= 0)
		{
			Stars3D[i].z = 800;
		}

		const UWORD x = Stars3D[i].x / Stars3D[i].z + SCREENWIDTHMID;
		const UWORD y = Stars3D[i].y / Stars3D[i].z + SCREENHEIGHTMID;

		if (x < SCREENWIDTH && y > UPPERBORDERLINE && y < LOWERBORDERLINE)
		{
			lwmf_SetPixel(x, y, (Stars3D[i].z >> 8) + 1, (long*)RenderPort.BitMap->Planes[0]);
		}
	}
}


#endif /* Starfield3D_H */