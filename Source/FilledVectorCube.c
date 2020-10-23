//**********************************************************************
//* Simple filled vector cube demo for Amiga with at least OS 3.0      *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 FilledVectorCube.c -o FilledVectorCube -lmieee -lamiga      *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

#include <math.h>

// Include our own header files
#include "lwmf/lwmf.h"

//
// Screen settings
//

const ULONG WIDTH = 320;
const ULONG HEIGHT = 256;

// Our timing/fps limit is targeted at 25fps
// If you want to use 50fps instead, calc 1000000 / 50
// If you want to use 20fps instead, calc 1000000 / 20 - I guess, you got it...
// Is used in function "DoubleBuffering()"
const int FPSLIMIT = (1000000 / 25);

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Extra Halfbrite mode)
const int NUMBEROFBITPLANES = 3;

// ...and here which colors we want to use
UWORD ColorTable[] = 
{ 
	0x003,
	0xFFF,
	0x0A0,
	0x0B0,
	0x0C0,
	0x0D0,
	0x0E0,
	0x0F0
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL InitDemo();
void DrawDemo();

struct IntPointStruct
{
	int x;
	int y;
};

struct OrderPair
{
	int first;
	float second;
};

struct CubeFaceStruct
{
	int p0;
	int p1;
	int p2;
	int p3;
} CubeFaces[] = { {0,1,3,2}, {4,0,2,6}, {5,4,6,7}, {1,5,7,3}, {0,1,5,4}, {2,3,7,6} };

struct CubeStruct
{
	struct OrderPair Order[6];
	struct IntPointStruct Cube[8];
} CubePreCalc[90];

int CubeSinTabY[64];
int CubeSinTabX[64];

BOOL InitDemo()
{
	//
	// Init Vector cube
	//

	struct VertexStruct
	{
		float x;
		float y;
		float z;
	} CubeDef[8] = { { -50.0f, -50.0f, -50.0f }, { -50.0f, -50.0f, 50.0f }, { -50.0f, 50.0f, -50.0f }, { -50.0f, 50.0f, 50.0f }, { 50.0f, -50.0f, -50.0f }, { 50.0f, -50.0f, 50.0f }, { 50.0f, 50.0f, -50.0f }, { 50.0f, 50.0f, 50.0f } };

	const float CosA = cos(0.04f);
    const float SinA = sin(0.04f);

	// Create two sintabs for a lissajous figure
	for (int i = 0; i < 64; ++i)
	{
		CubeSinTabY[i] = (int)(sin(0.2f * i) * 30.0f);
		CubeSinTabX[i] = (int)(sin(0.1f * i) * 60.0f);
	}

	for (int Pre = 0; Pre < 90; ++Pre)
	{
		for (int i = 0; i < 8; ++i)
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
			CubePreCalc[Pre].Cube[i].x = (WIDTH >> 1) + (int)CubeDef[i].x;
			CubePreCalc[Pre].Cube[i].y = (HEIGHT >> 1) + (int)CubeDef[i].y;
		}

		// selection-sort of depth/faces
		for (int i = 0; i < 6; ++i)
		{
			CubePreCalc[Pre].Order[i].second = (CubeDef[CubeFaces[i].p0].z + CubeDef[CubeFaces[i].p1].z + CubeDef[CubeFaces[i].p2].z + CubeDef[CubeFaces[i].p3].z) * 0.25f;
			CubePreCalc[Pre].Order[i].first = i;
		}

		for (int i = 0; i < 5; ++i)
		{
			int Min = i;

			for (int j = i + 1; j <= 5; ++j)
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

	return TRUE;
}

void DrawDemo()
{
	// Clear background
	SetRast(&RenderPort, 0);

	//
	// Vector Cube
	//

	const int CubeFacesColors[] = { 2, 3, 4, 5, 6, 7 };
	static int VCCount = 0;
	static int CubeSinTabCount = 0;

	// Since we see only the three faces on top, we only need to render these (3, 4 and 5)
	for (int i = 3; i < 6; ++i)
	{
		SetAPen(&RenderPort, CubeFacesColors[CubePreCalc[VCCount].Order[i].first]);

		AreaMove(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].x + CubeSinTabX[CubeSinTabCount], CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].y + CubeSinTabY[CubeSinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].x + CubeSinTabX[CubeSinTabCount], CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].y + CubeSinTabY[CubeSinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].x + CubeSinTabX[CubeSinTabCount], CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].y + CubeSinTabY[CubeSinTabCount]);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].x + CubeSinTabX[CubeSinTabCount], CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].y + CubeSinTabY[CubeSinTabCount]);

		AreaEnd(&RenderPort);
	}

	if (++VCCount >= 90)
	{
		VCCount = 0;
	}

	if (++CubeSinTabCount >= 63)
	{
		CubeSinTabCount = 0;
	}
}

int main()
{
    // Load libraries
    // Exit with SEVERE Error (20) if something goes wrong
	if (!lwmf_LoadLibraries())
    {
        return 20;
    }

	// Check which CPU is used in your Amiga (or UAE...)
	lwmf_CheckCPU();

	// Gain control over the OS
	lwmf_TakeOverOS();
	
	// Setup screen
	const int NumberOfColors = sizeof(ColorTable) / sizeof(*ColorTable);

	if (!lwmf_CreateScreen(WIDTH, HEIGHT, NUMBEROFBITPLANES, ColorTable, NumberOfColors))
    {
        return 20;
    }

    // Init the RenderPort (=Rastport)
	// We need to init some buffers for Area operations
	// Since our demo part draws some cube surfaces which are made out of 4 vertices, we choose 5 (4 + 1 for safety)
	if (!lwmf_CreateRastPort(5, 130, 130, 0))
	{
		return 20;
	}

	//
	// Init stuff for demo if needed
	//

	// Init vector cube
	if (!InitDemo())
	{
		return 20;
	}

    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
	if (!lwmf_DoubleBuffering(DrawDemo, FPSLIMIT, TRUE))
	{
		return 20;
	}

	// Cleanup everything
	lwmf_CleanupAll();
	return 0;
}