//**********************************************************************
//* Simple copper demo for Amiga with at least OS 3.0           	   *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Copper.c -o Copper -lamiga           	     			   *
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

// Our timing/fps limit is targeted at 50fps
// If you want to use 20fps instead, calc 1000000 / 20
// If you want to use 25fps instead, calc 1000000 / 25 - I guess, you got it...
// Is used in function "DoubleBuffering()"
const int FPSLIMIT = (1000000 / 50);

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Amiga Halfbrite mode)
const int NUMBEROFBITPLANES = 1;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 0}, 
	{1, 15, 15, 15},
	{-1, 0, 0, 0} 
};

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL LoadCopperList();
void CleanupCopperList();
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

void DrawDemo()
{
	SetRast(&RenderPort, 0);
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

	// Load Copper table and init viewport
	if (!LoadCopperList())
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
	CleanupCopperList();
	lwmf_CleanupAll();
	return 0;
}