#ifndef Starfield3D_H
#define Starfield3D_H


//***************************************
//* Simple 3D starfield			   		*
//*								   		*
//* (C) 2020-2026 by Stefan Kubsch      *
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
		struct StarStruct3D* const s = &Stars3D[i];

		s->z -= 15;

		if (s->z <= 0)
		{
			s->z = 800;
		}

		const WORD x = s->x / s->z + SCREENWIDTHMID;
		const WORD y = s->y / s->z + SCREENHEIGHTMID;

		if ((UWORD)x < SCREENWIDTH && y > UPPERBORDERLINE && y < LOWERBORDERLINE)
		{
			lwmf_SetPixel(x, y, (s->z >> 8) + 1, (long*)RenderPort.BitMap->Planes[0]);
		}
	}
}


#endif /* Starfield3D_H */