//**********************************************************************
//* Simple sine scroller demo for Amiga with at least OS 3.0           *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 SineScroller.c -o SineScroller -lmieee -lamiga  			   *
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
	0x57B,
	0x247,
	0x9BF,
	0x469,
	0x8AD,
	0xBDF
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL InitDemo();
void CleanupDemo();
void DrawDemo();

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
	if (Font.FontBitmap)
	{
		lwmf_DeleteImage(Font.FontBitmap);
	}
}

void DrawDemo()
{
	// Clear background
	SetRast(&RenderPort, 0);

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
						BltBitMap(Font.FontBitmap->Image, x, 0, RenderPort.BitMap, TempPosX, 100 + ScrollSinTab[TempPosX], 2, Font.CharHeight, 0xC0, 0x07, NULL);
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
	if (!lwmf_CreateScreen(WIDTH, HEIGHT, NUMBEROFBITPLANES, ColorTable, 8))
    {
        return 20;
    }
	
	// Init the RenderPort (=Rastport)
	if (!lwmf_CreateRastPort(1, 1, 1, 0))
	{
		return 20;
	}

	//
	// Init stuff for demo if needed
	//

	// Init sine scroller
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