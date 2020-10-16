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
// 64 / 6 (Amiga Halfbrite mode)
const int NUMBEROFBITPLANES = 3;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 0}, 
	{1, 15, 15, 15},
	{2, 10, 0, 10},
	{3, 11, 0, 11},
	{4, 12, 0, 12},
	{5, 13, 0, 13},
	{6, 14, 0, 14},
	{7, 15, 0, 15},
	{-1, 0, 0, 0} 
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL LoadCopperList();
void CleanupCopperList();
BOOL InitDemo();
void CleanupDemo();
void DrawDemo();

BOOL LoadCopperList()
{
	struct UCopList* uCopList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_CHIP | MEMF_CLEAR);

	if (uCopList == NULL)
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

    const int NumberOfColors = sizeof(Colors) / sizeof(*Colors);

	CINIT(uCopList, NumberOfColors);

	for (int i = 0; i < NumberOfColors; ++i)
	{
		CWAIT(uCopList, i * (HEIGHT / NumberOfColors), 0);
		CMOVE(uCopList, custom->color[0], Colors[i]);
	}

	CEND(uCopList);
	
	Screen->ViewPort.UCopIns = uCopList;
	RethinkDisplay();
	
	return TRUE;
}

void CleanupCopperList()
{
	if (Screen->ViewPort.UCopIns)
    {
		FreeVPortCopLists(&Screen->ViewPort);
	}
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

int VCCount = 0;

struct BitMap* ScrollFontBitMap;
const char ScrollText[] = "...WELL, WELL...NOT PERFECT, BUT STILL WORKING ON IT !!!";
const char ScrollCharMap[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ!.,";
const int ScrollCharWidth = 16;
const int ScrollCharHeight = 28;
int YSine[360];
int ScrollTextLength = 0;
int ScrollCharMapLength = 0;
int ScrollLength = 0;
int ScrollX = 0;

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

	Stars = AllocVec(sizeof(struct StarStruct) * NumberOfStars, MEMF_FAST);

	if (!Stars)
	{
		CleanupCopperList();
		lwmf_CleanupAll();
		return FALSE;
	}

    for (int i = 0; i < NumberOfStars; ++i) 
    {
        Stars[i].x = lwmf_XorShift32() % WIDTH - 160;
        Stars[i].y = lwmf_XorShift32() % HEIGHT - 128;
        Stars[i].z = lwmf_XorShift32() % 800;
    }

	//
	// Init sine scoller
	//

	// Generate sinus table
	for (int i = 0; i < 360; ++i)
	{
		YSine[i] = (int)(sin(0.05f * i) * 10.0f);
	}

	ScrollX = WIDTH;
	ScrollTextLength = strlen(ScrollText);
	ScrollCharMapLength = strlen(ScrollCharMap);
	ScrollLength = ScrollTextLength * ScrollCharWidth;

	// Generate bitmap for charmap
	ScrollFontBitMap = AllocBitMap(ScrollCharMapLength * ScrollCharWidth, ScrollCharHeight + 4, 1, BMF_STANDARD | BMF_INTERLEAVED | BMF_CLEAR, RenderPort.BitMap);

	if (!ScrollFontBitMap)
	{
		CleanupDemo();
		CleanupCopperList();
		lwmf_CleanupAll();
	}

	RenderPort.BitMap = ScrollFontBitMap;

	// Load font
	struct TextAttr ScrollFontAttrib =
	{
		"topaz.font", 
		16,
		FSF_BOLD,
		0
	};

	struct TextFont* ScrollFont = NULL;
	struct TextFont* OldFont = NULL;

	if (ScrollFont = OpenDiskFont(&ScrollFontAttrib))
   	{
    	// Save current font
		OldFont = RenderPort.Font;
		// Set new font
     	SetFont(&RenderPort, ScrollFont);
	}

	// Draw charmap
	SetAPen(&RenderPort, 1);
	Move(&RenderPort, 0, ScrollCharHeight);
	Text(&RenderPort, ScrollCharMap, ScrollCharMapLength);

	// Load old font
	SetFont(&RenderPort, OldFont);
    CloseFont(ScrollFont);
	
	return TRUE;
}

void CleanupDemo()
{
	if (Stars)
	{
		FreeVec(Stars);
	}

	if (ScrollFontBitMap)
	{
		FreeBitMap(ScrollFontBitMap);
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
	// Another example: Enable only bitplanes 1 and 2:
	// 11111110 = Hex 0xFE

	SetWrMsk(&RenderPort, 0x01);
	SetAPen(&RenderPort, 1);

	for (int i = 0; i < NumberOfStars; ++i)
	{
		Stars[i].z -= 10;
	
		if (Stars[i].z <= 1) 
		{
			Stars[i].z = 800;
		}
		
		const int x = (Stars[i].x << 8) / Stars[i].z + WidthMid;
		const int y = (Stars[i].y << 8) / Stars[i].z + HeightMid;
		
		if ((unsigned int)x < WIDTH && (unsigned int)y < HEIGHT)
		{
			WritePixel(&RenderPort, x, y);
		}
	}

	// Re-enable all bitplanes
	SetWrMsk(&RenderPort, -1);

	//
	// Sine scroller
	//

	for (int i = 0, XPos = ScrollX; i < ScrollTextLength; ++i)
	{
		for (int j = 0, CharX = 0; j < ScrollCharMapLength; ++j)
		{
			if (*(ScrollText + i) == *(ScrollCharMap + j))
			{
				for (int x1 = 0, x = CharX; x < CharX + ScrollCharWidth; ++x1, ++x)
				{
					const int TempPosX = XPos + x1;

					if ((unsigned int)TempPosX < WIDTH)
					{
						BltBitMap(ScrollFontBitMap, x, 0, RenderPort.BitMap, TempPosX, 200 + YSine[TempPosX], 1, ScrollCharHeight + 4, 0xC0, 0x01, NULL);
					}
				}

				break;
			}

			if (XPos >= WIDTH)
			{
				break;
			}

			CharX += ScrollCharWidth;
		}

		XPos += ScrollCharWidth;
	}

	ScrollX -= 5;

	if (ScrollX < -ScrollLength)
	{
		ScrollX = WIDTH;
	}

	//
	// Vector Cube
	//

	const int CubeFacesColors[] ={ 2, 3, 4, 5, 6, 7 };
	
	// Since we see only the three faces on top, we only need to render these (3, 4 and 5)
	for (int i = 3; i < 6; ++i)
	{
		SetAPen(&RenderPort, CubeFacesColors[CubePreCalc[VCCount].Order[i].first]);

		AreaMove(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].y);

		AreaEnd(&RenderPort);
	}

	if (++VCCount >= 90)
	{
		VCCount = 0;
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
	if (!lwmf_CreateScreen(WIDTH, HEIGHT, NUMBEROFBITPLANES, ColorTable))
    {
        return 20;
    }

    // Init the RenderPort (=Rastport)
	// We need to init some buffers for Area operations
	// Since our demo part draws some cube surfaces which are made out of 4 vertices, we choose 5 (4 + 1 for safety)
	if (!lwmf_CreateRastPort(5, WIDTH, HEIGHT))
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
	lwmf_DoubleBuffering(DrawDemo, FPSLIMIT);

	// Cleanup everything
	CleanupDemo();
	CleanupCopperList();
	lwmf_CleanupAll();
	return 0;
}