#ifndef FilledVectorCube_H
#define FilledVectorCube_H


//****************************************
//* Simple filled vector cube       	 *
//*								    	 *
//* (C) 2020-2021 by Stefan Kubsch       *
//****************************************

#include <math.h>

struct CubeFaceStruct
{
	UBYTE p0;
	UBYTE p1;
	UBYTE p2;
	UBYTE p3;
} CubeFaces[] = { {0,1,3,2}, {4,0,2,6}, {5,4,6,7}, {1,5,7,3}, {0,1,5,4}, {2,3,7,6} };

struct PointStruct
{
	UWORD x;
	UWORD y;
};

struct OrderPair
{
	UBYTE first;
	float second;
};

struct CubeStruct
{
	struct OrderPair Order[6];
	struct PointStruct Cube[8];
} CubePreCalc[90];

UWORD CubeSinTabY[64];
UWORD CubeSinTabX[64];

void Init_FilledVectorCube(void)
{
	struct VertexStruct
	{
		float x;
		float y;
		float z;
	} CubeDef[8] = { { -50.0f, -50.0f, -50.0f }, { -50.0f, -50.0f, 50.0f }, { -50.0f, 50.0f, -50.0f }, { -50.0f, 50.0f, 50.0f }, { 50.0f, -50.0f, -50.0f }, { 50.0f, -50.0f, 50.0f }, { 50.0f, 50.0f, -50.0f }, { 50.0f, 50.0f, 50.0f } };

	// Create two sintabs for a lissajous figure
	for (UBYTE i = 0; i < 64; ++i)
	{
		CubeSinTabX[i] = (UWORD)(sin(0.1f * (float)i) * 60.0f);
		CubeSinTabY[i] = (UWORD)(sin(0.2f * (float)i) * 40.0f);
	}

	const float CosA = cos(0.04f);
	const float SinA = sin(0.04f);

	for (UBYTE Pre = 0; Pre < 90; ++Pre)
	{
		for (UBYTE i = 0; i < 8; ++i)
		{
			// x - rotation
			const float y = CubeDef[i].y;
			CubeDef[i].y = y * CosA - CubeDef[i].z * SinA;

			// y - rotation
			const float z = CubeDef[i].z * CosA + y * SinA;
			CubeDef[i].z = z * CosA + CubeDef[i].x * SinA;

			// z - rotation
			const float x = CubeDef[i].x * CosA - z * SinA;
			CubeDef[i].x = x * CosA - CubeDef[i].y * SinA;
			CubeDef[i].y = CubeDef[i].y * CosA + x * SinA;

			// 2D projection & translate
			CubePreCalc[Pre].Cube[i].x = SCREENWIDTHMID + (UWORD)CubeDef[i].x;
			CubePreCalc[Pre].Cube[i].y = SCREENHEIGHTMID + (UWORD)CubeDef[i].y - 5;
		}

		// selection-sort of depth/faces
		for (UBYTE i = 0; i < 6; ++i)
		{
			CubePreCalc[Pre].Order[i].second = (CubeDef[CubeFaces[i].p0].z + CubeDef[CubeFaces[i].p1].z + CubeDef[CubeFaces[i].p2].z + CubeDef[CubeFaces[i].p3].z) * 0.25f;
			CubePreCalc[Pre].Order[i].first = i;
		}

		for (UBYTE i = 0; i < 5; ++i)
		{
			UBYTE Min = i;

			for (UBYTE j = i + 1; j <= 5; ++j)
			{
				if (CubePreCalc[Pre].Order[j].second < CubePreCalc[Pre].Order[Min].second)
				{
					Min = j;
				}
			}
			
			struct OrderPair Temp = CubePreCalc[Pre].Order[Min];
			CubePreCalc[Pre].Order[Min] = CubePreCalc[Pre].Order[i];
			CubePreCalc[Pre].Order[i] = Temp;
		}
	}
}

void Draw_FilledVectorCube(void)
{
	const UBYTE FaceColors[] = { 1, 2, 3, 4, 5, 6 };
	static UBYTE idx = 0;
	static UBYTE SinTabCount = 0;

	RenderPort.Mask = 0x07;

	// Since we see only the three faces on top, we only need to render these (3, 4 and 5)
	for (UBYTE i = 3; i < 6; ++i)
	{
		SetAPen(&RenderPort, FaceColors[CubePreCalc[idx].Order[i].first]);

		AreaMove(&RenderPort, CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p0].x + CubeSinTabX[SinTabCount], CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p0].y + CubeSinTabY[SinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p1].x + CubeSinTabX[SinTabCount], CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p1].y + CubeSinTabY[SinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p2].x + CubeSinTabX[SinTabCount], CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p2].y + CubeSinTabY[SinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p3].x + CubeSinTabX[SinTabCount], CubePreCalc[idx].Cube[CubeFaces[CubePreCalc[idx].Order[i].first].p3].y + CubeSinTabY[SinTabCount]);

		AreaEnd(&RenderPort);
	}

	if (++idx >= 90)
	{
		idx = 0;
	}

	if (++SinTabCount >= 63)
	{
		SinTabCount = 0;
	}

	RenderPort.Mask = -1;
}


#endif /* FilledVectorCube_H */