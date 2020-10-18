//**********************************************************************
//* Simple starfield demo for Amiga with at least OS 3.0  			   *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Starfield.c -o Starfield -lamiga	             			   *
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
// 64 / 6 (Amiga Halfbrite mode)
const int NUMBEROFBITPLANES = 2;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 3}, 
	{1, 15, 15, 15}, 
	{2, 8, 8, 8}, 
	{3, 4, 4, 4}, 
	{-1, 0, 0, 0} 
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL InitDemo();
void CleanupDemo();
void DrawDemo();

struct StarStruct
{
    int x;
    int y;
    int z;
} *Stars;

int NumberOfStars;

BOOL InitDemo()
{
	//
	// Init 3D starfield
	//

	// Use more stars, if a fast CPU is available...
	NumberOfStars = FastCPUFlag ? 300 : 100;

	Stars = AllocVec(sizeof(struct StarStruct) * NumberOfStars, MEMF_ANY);

	if (!Stars)
	{
		lwmf_CleanupAll();
		return FALSE;
	}

    for (int i = 0; i < NumberOfStars; ++i) 
    {
        Stars[i].x = lwmf_XorShift32() % WIDTH - 160;
        Stars[i].y = lwmf_XorShift32() % HEIGHT - 128;
        Stars[i].z = lwmf_XorShift32() % 800;
    }

	return TRUE;
}

void CleanupDemo()
{
	if (Stars)
	{
		FreeVec(Stars);
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
			SetAPen(&RenderPort, Stars[i].z / 300 + 1);
			WritePixel(&RenderPort, x, y);
		}
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
	if (!lwmf_CreateRastPort(1, 1, 1, 0))
	{
		return 20;
	}

	//
	// Init stuff for demo if needed
	//

	// Init starfield
	if (!InitDemo())
	{
		return 20;
	}

    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
	if (!lwmf_DoubleBuffering(DrawDemo, FPSLIMIT))
	{
		return 20;
	}

	// Cleanup everything
	CleanupDemo();
	lwmf_CleanupAll();
	return 0;
}