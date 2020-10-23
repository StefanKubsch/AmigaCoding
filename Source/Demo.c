//**********************************************************************
//* Simple combined demo for Amiga with at least OS 3.0    			   *
//*														 			   *
//* Effects: Copper background, 3D starfield, filled vector cube       *
//* and a sine scroller												   *
//*														 			   *
//*                                                      			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Demo.c -o Demo -lmieee -lamiga              			   	   *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

#include <math.h>
#include <string.h>

// Include our own header files
#include "lwmf/lwmf.h"

//
// Screen settings
//

const ULONG WIDTH = 320;
const ULONG HEIGHT = 256;

// Our timing/fps limit is targeted at 20fps
// If you want to use 50fps instead, calc 1000000 / 50
// If you want to use 25fps instead, calc 1000000 / 25 - I guess, you got it...
// Is used in function "DoubleBuffering()"
const int FPSLIMIT = (1000000 / 20);

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Extra Halfbrite mode)
const int NUMBEROFBITPLANES = 4;

// ...and here which colors we want to use
UWORD ColorTable[] = 
{ 
	0x000,
	0xFFF,
	0x878,
	0x989,
	0xA9A,
	0xBAB,
	0xCBC,
	0xDCD,
	0xA0A,
	0xB0B,
	0xC0C,
	0xD0D,
	0xE0E,
	0xF0F
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL LoadCopperList();
BOOL InitDemo();
void CleanupDemo();
void DrawDemo();

BOOL LoadCopperList()
{
	struct UCopList* UserCopperList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_ANY | MEMF_CLEAR);
	
	if (!UserCopperList)
	{
		return FALSE;
	}
	
	const UWORD Colors[] =
	{
		0x0604, 0x0605, 0x0606, 0x0607, 0x0617, 0x0618, 0x0619,	0x0629, 
		0x072A, 0x073B, 0x074B, 0x074C, 0x075D, 0x076E,	0x077E, 0x088F, 
		0x07AF, 0x06CF, 0x05FF, 0x04FB, 0x04F7,	0x03F3, 0x07F2, 0x0BF1, 
		0x0FF0, 0x0FC0, 0x0EA0, 0x0E80,	0x0E60, 0x0D40, 0x0D20, 0x0D00
	};

	// Copper init

	// Number Of Colors * 2 + Init & End + some spare
	UCopperListInit(UserCopperList, 10 + 64);

	// Set mouse pointer to blank sprite
	CMove(UserCopperList, SPR0PTH, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
    CMove(UserCopperList, SPR0PTL, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
	
	for (int i = 0, Temp = HEIGHT >> 5; i < 32; ++i)
	{
		CWait(UserCopperList, i * Temp, 0);
		CBump(UserCopperList);
		// Write Colors[i] to register COLOR00
		CMove(UserCopperList, COLOR00, Colors[i]);
		CBump(UserCopperList);
	}

	// Copper list end
	CWait(UserCopperList, 10000, 255);

	Screen->ViewPort.UCopIns = UserCopperList;
	RethinkDisplay();
	
	return TRUE;
}

struct StarStruct
{
    int x;
    int y;
    int z;
} *Stars;

int NumberOfStars;

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

struct Scrollfont
{
	struct lwmf_Image* FontBitmap;
	char* Text;
	char* CharMap;
	int CharWidth;
	int CharHeight;
	int CharSpacing;
	int TextLength;
	int CharMapLength;
	int Length;
	int ScrollX;
} Font;

int ScrollSinTab[320];

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

	//
	// Init 3D starfield
	//

	// Use more stars, if a fast CPU is available...
	NumberOfStars = FastCPUFlag ? 100 : 50;

	if (!(Stars = AllocVec(sizeof(struct StarStruct) * NumberOfStars, MEMF_ANY)))
	{
		CleanupDemo();
		lwmf_CleanupAll();
		return FALSE;
	}

    for (int i = 0; i < NumberOfStars; ++i) 
    {
        Stars[i].x = (lwmf_XorShift32() % WIDTH - 160) << 8;
        Stars[i].y = (lwmf_XorShift32() % HEIGHT - 128) << 8;
        Stars[i].z = lwmf_XorShift32() % 800;
    }

	//
	// Init sine scoller
	//

	// Generate sinus table
	for (int i = 0; i < 320; ++i)
	{
		ScrollSinTab[i] = (int)(sin(0.03f * i) * 30.0f);
	}

	Font.Text = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!!";
	Font.CharMap = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!-,+?*()";
	Font.CharWidth = 15;
	Font.CharHeight = 20;
	Font.CharSpacing = 1;
	Font.ScrollX = WIDTH;
	Font.TextLength = strlen(Font.Text);
	Font.CharMapLength = strlen(Font.CharMap);
	Font.Length = Font.TextLength * (Font.CharWidth + Font.CharSpacing);

	if (!(Font.FontBitmap = lwmf_LoadImage("gfx/scrollfont.iff")))
	{
		CleanupDemo();
		lwmf_CleanupAll();
		return FALSE;
	}
	
	return TRUE;
}

void CleanupDemo()
{
	if (Screen->ViewPort.UCopIns)
    {
		FreeVPortCopLists(&Screen->ViewPort);
	}

	if (Stars)
	{
		FreeVec(Stars);
	}

	if (Font.FontBitmap)
	{
		lwmf_DeleteImage(Font.FontBitmap);
	}
}

void DrawDemo()
{
	// Clear background
	SetRast(&RenderPort, 0);

	const int WidthMid = WIDTH >> 1;
	const int HeightMid = HEIGHT >> 1;

	//
	// Starfield
	//

	// Since we use only bitplane 0 for the starfield, we enable only bitplane 0
	// Bitmap.Planes[0] = Bit 0
	// Bitmap.Planes[1] = Bit 1
	// ...
	// To enable bitplane 0 only set the mask as follows:
	// 00000001 = Hex 0x01
	//
	// You could also use "SetWrMsk(RP, Color)" - but it´s just a macro...

	RenderPort.Mask = 0x01;
	SetAPen(&RenderPort, 1);

	for (int i = 0; i < NumberOfStars; ++i)
	{
		Stars[i].z -= 10;
	
		if (Stars[i].z <= 1) 
		{
			Stars[i].z = 800;
		}
		
		const int x = Stars[i].x / Stars[i].z + WidthMid;
		const int y = Stars[i].y / Stars[i].z + HeightMid;
		
		if ((unsigned int)x < WIDTH && (unsigned int)y < HEIGHT)
		{
			WritePixel(&RenderPort, x, y);
		}
	}

	// Re-enable all bitplanes
	RenderPort.Mask = -1;

	//
	// Sine scroller
	//

	for (int i = 0, XPos = Font.ScrollX; i < Font.TextLength; ++i)
	{
		for (int j = 0, CharX = 0; j < Font.CharMapLength; ++j)
		{
			if (*(Font.Text + i) == *(Font.CharMap + j))
			{
				for (int x1 = 0, x = CharX; x < CharX + Font.CharWidth; x1 += 2, x += 2)
				{
					const int TempPosX = XPos + x1;

					if ((unsigned int)TempPosX + 1 < WIDTH)
					{
						BltBitMap(Font.FontBitmap->Image, x, 0, RenderPort.BitMap, TempPosX, 200 + ScrollSinTab[TempPosX], 2, Font.CharHeight, 0xC0, 0x07, NULL);
					}
				}

				break;
			}

			if (XPos >= WIDTH)
			{
				break;
			}

			CharX += Font.CharWidth + Font.CharSpacing;
		}

		XPos += Font.CharWidth + Font.CharSpacing;
	}

	Font.ScrollX -= 5;

	if (Font.ScrollX < -Font.Length)
	{
		Font.ScrollX = WIDTH;
	}

	//
	// Vector Cube
	//

	const int CubeFacesColors[] = { 8, 9, 10, 11, 12, 13 };
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
	// Depening on this, we use more or less stars (or effects in the near future...)
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

	// Load Copper table and init viewport
	if (!LoadCopperList())
	{
		return 20;
	}

	// Init all demo effects
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
	CleanupDemo();
	lwmf_CleanupAll();
	return 0;
}