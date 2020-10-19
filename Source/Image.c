//**********************************************************************
//* Simple image demo for Amiga with at least OS 3.0  		    	   *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Image.c -o Image -lamiga	             			 	       *
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
// 64 / 6 (Extra Halfbrite mode)
const int NUMBEROFBITPLANES = 3;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 0}, 
	{1, 15, 15, 15},
	{2, 11, 13, 15},
	{3, 7, 9, 13},
	{4, 5, 7, 10},
	{5, 3, 5, 8},
	{6, 1, 3, 5},
	{7, 0, 2, 4},
	{-1, 0, 0, 0} 
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL InitDemo();
void CleanupDemo();
void DrawDemo();

struct lwmf_Image TestImage;

BOOL InitDemo()
{
	TestImage.Filename = "font1.iff";
	lwmf_LoadImage(&TestImage);
	return TRUE;
}

void CleanupDemo()
{
	lwmf_DeleteImage(&TestImage);
}

void DrawDemo()
{
	// Clear background
	SetRast(&RenderPort, 0);
	BltBitMap(TestImage.Image, 0, 0, RenderPort.BitMap, 0, 20, 300, 100, 0xC0, 0xFF, NULL);
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
	if (!lwmf_DoubleBuffering(DrawDemo, FPSLIMIT, TRUE))
	{
		return 20;
	}

	// Cleanup everything
	CleanupDemo();
	lwmf_CleanupAll();
	return 0;
}