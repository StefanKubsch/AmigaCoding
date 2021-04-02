//**********************************************************************
//* Simple combined demo for Amiga with at least OS 3.0    			   *
//*														 			   *
//* Effects: Copper background, 3D starfield, filled vector cube,      *
//* a sine scroller, moving text logo and a 2D starfield   			   *
//*														 			   *
//*                                                      			   *
//* (C) 2020-2021 by Stefan Kubsch / Deep4                 			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* make_Demo.cmd													   *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

// Include our own header files
#include "lwmf/lwmf.h"

// Enable (set to 1) for debugging
// When enabled, copperlist is not executed and load per frame will be displayed via color changing of background
#define DEBUG 				0

//
// Screen settings
//

#define SCREENWIDTH			320
#define SCREENHEIGHT		256
#define SCREENWIDTHMID		(SCREENWIDTH >> 1)
#define SCREENHEIGHTMID		(SCREENHEIGHT >> 1)
#define LINEPOS				30
#define UPPERBORDERLINE		LINEPOS
#define LOWERBORDERLINE		(SCREENHEIGHT - LINEPOS)

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Extra Halfbrite mode)
#define NUMBEROFBITPLANES	3
#define NUMBEROFCOLORS		8

// Include the demo effects
#include "Demo_Colors.h"
#include "Demo_SineScroller.h"
#include "Demo_FilledVectorCube.h"
#include "Demo_Starfield3D.h"
#include "Demo_Starfield2D.h"
#include "Demo_TextLogo.h"

struct UCopList* UserCopperList = NULL;

BOOL Init_CopperList(void)
{
	if (!(UserCopperList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_ANY | MEMF_CLEAR)))
	{
		return FALSE;
	}

	return TRUE;
}

void Update_CopperList(void)
{
	const UWORD CopperColors[] =
	{
		0x0FF, 0x0EF, 0x0DF, 0x0CF, 0x0BF, 0x0AF, 0x09F, 0x08F,
		0x07F, 0x06F, 0x05F, 0x04F, 0x03F, 0x02F, 0x01F, 0x00F,
		0x00E, 0x00D, 0x00C, 0x00B, 0x00A, 0x009, 0x008, 0x007,
		0x006, 0x005, 0x004, 0x003, 0x003, 0x003
	};

	// Needed memory: Init, Mouse, Background & End + some spare
	UCopperListInit(UserCopperList, 70);

	// Set mouse pointer to blank sprite
	CMove(UserCopperList, SPR0PTH, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
	CMove(UserCopperList, SPR0PTL, (LONG)&BlankMousePointer);
	CBump(UserCopperList);

	// Setup background

	// Black
	CMove(UserCopperList, COLOR00, 0x000);
	CBump(UserCopperList);

	// Upper color bars
	for (int i = 0; i <= UPPERBORDERLINE; ++i)
	{
		CWait(UserCopperList, i, 0);
		CBump(UserCopperList);
		CMove(UserCopperList, COLOR00, CopperColors[i]);
		CBump(UserCopperList);
	}
	
	// Blue
	CMove(UserCopperList, COLOR00, 0x003);
	CBump(UserCopperList);
	
	// Lower color bars
	for (int i = LOWERBORDERLINE, j = 29; i < SCREENHEIGHT; ++i, --j)
	{
		CWait(UserCopperList, i, 0);
		CBump(UserCopperList);
		CMove(UserCopperList, COLOR00, CopperColors[j]);
		CBump(UserCopperList);
	}

	// Black
	CMove(UserCopperList, COLOR00, 0x000);
	CBump(UserCopperList);

	// Copper list end
	CWait(UserCopperList, 10000, 255);

	viewPort.UCopIns = UserCopperList;
}

void Cleanup_CopperList(void)
{
	if (viewPort.UCopIns)
	{
		FreeVPortCopLists(&viewPort);
	}
}

BOOL Init_Demo(void)
{
	if (!Init_TextLogo())
	{
		return FALSE;
	}

	if (!Init_SineScroller())
	{
		return FALSE;
	}

	Init_2DStarfield();
	Init_3DStarfield();
	Init_FilledVectorCube();

	return TRUE;
}

void Cleanup_Demo(void)
{
	Cleanup_SineScroller();
	Cleanup_TextLogo();
	Cleanup_CopperList();
}

int main(void)
{
	// Load libraries
	// Exit with SEVERE Error (20) if something goes wrong
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	if (lwmf_LoadDatatypesLib() != 0)
	{
		return 20;
	}

	// Gain control over the OS
	lwmf_TakeOverOS();

	// Setup screen
	if (!lwmf_CreateViewPort(SCREENWIDTH, SCREENHEIGHT, NUMBEROFBITPLANES, NUMBEROFCOLORS))
	{
		lwmf_CleanupAll();
		return 20;
	}

	// Init the RenderPort (=Rastport)
	// We need to init some buffers for Area operations
	// Since our demo part draws some cube surfaces which are made out of 4 vertices, we choose 5 (4 + 1 for safety)
	if (!lwmf_CreateRenderPort(5, 130, 130))
	{
		lwmf_CleanupAll();
		return 20;
	}

	// Init Copper (Set background, disable mouse pointer)
	if (!Init_CopperList())
	{
		lwmf_CleanupAll();
		return 20;
	}

	if (DEBUG == 0)
	{
		Update_CopperList();
	}

	//
	// Init stuff for demo if needed
	//

	// Initial loading of colors
	LoadRGB4(&viewPort, DemoColorTable[0], NUMBEROFCOLORS);
	lwmf_UpdateViewPort();	

	if (!Init_Demo())
	{
		Cleanup_Demo();
		lwmf_CleanupAll();
		return 20;
	}

	// Our parts, packed into an array of function pointers
	const void (*DemoParts[])() =
	{
		Draw_TextLogo, Draw_SineScroller, Draw_2DStarfield, Draw_FilledVectorCube, Draw_3DStarfield
	};

	// Loop control
	UBYTE CurrentBuffer = 0;
	UBYTE CurrentDemoPart = 0;
	const UBYTE NumberOfDemoParts = sizeof(DemoParts)/sizeof(DemoParts[0]);
	UWORD FrameCount = 0;

	// Duration of each part in frames
	const UWORD PartDuration = 250;

	//
	// This is our main loop
	//

	// Check if mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		if (DEBUG == 1)
		{
			*COLOR00 = 0x000;
		}

		view.LOFCprList = LOCpr[CurrentBuffer];
		RenderPort.BitMap = Buffer[CurrentBuffer].BitMap;

		//***************************************************************
		// Start here with drawing                                      *
		//***************************************************************

		OwnBlitter();
		lwmf_ClearScreen((long*)RenderPort.BitMap->Planes[0]);
		
		if (CurrentDemoPart != 0)
		{
			DisownBlitter();
		}

		// Call actual demopart
		(*DemoParts[CurrentDemoPart])();

		if (CurrentDemoPart == 0)
		{
			DisownBlitter();
		}

		//***************************************************************
		// Ends here ;-)                                                *
		//***************************************************************

		if (DEBUG == 1)
		{
			*COLOR00 = 0xF00;
		}

		LoadView(&view);
		CurrentBuffer ^= 1;

		if (++FrameCount >= PartDuration)
		{
			FrameCount = 0;

			if (++CurrentDemoPart >= NumberOfDemoParts)
			{
				CurrentDemoPart = 0;
			}

			// Load colors for next demopart & update viewport
			LoadRGB4(&viewPort, DemoColorTable[CurrentDemoPart], NUMBEROFCOLORS);
			lwmf_UpdateViewPort();
		}

		lwmf_WaitVertBlank();
	}

	Cleanup_Demo();
	lwmf_CleanupAll();
	return 0;
}