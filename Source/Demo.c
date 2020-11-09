//**********************************************************************
//* Simple combined demo for Amiga with at least OS 3.0    			   *
//*														 			   *
//* Effects: Copper background, 3D starfield, filled vector cube,      *
//* a sine scroller	and a 2D starfield   						       *
//*														 			   *
//*                                                      			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* make_Demo.bat													   *
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
#define LINEPOS				20
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

struct UCopList* UserCopperList = NULL;

BOOL Init_CopperList(void);
void Update_CopperList(void);
void Cleanup_CopperList(void);
BOOL Init_Demo(void);
void Cleanup_Demo(void);
inline void DemoPart1(void);
inline void DemoPart2(void);
inline void DemoPart3(void);

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
	// Needed memory: Init, Mouse, Background & End + some spare
	UCopperListInit(UserCopperList, 100);

	// Set mouse pointer to blank sprite
	CMove(UserCopperList, SPR0PTH, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
    CMove(UserCopperList, SPR0PTL, (LONG)&BlankMousePointer);
	CBump(UserCopperList);

	// Setup background
	
	// Black
	CMove(UserCopperList, COLOR00, 0x000);
	CBump(UserCopperList);
	// White line
	CWait(UserCopperList, UPPERBORDERLINE - 1, 0);
	CBump(UserCopperList);
	CMove(UserCopperList, COLOR00, 0xFFF);
	CBump(UserCopperList);
	// Blue
	CWait(UserCopperList, UPPERBORDERLINE, 0);
	CBump(UserCopperList);
	CMove(UserCopperList, COLOR00, 0x003);
	CBump(UserCopperList);
	// White line
	CWait(UserCopperList, LOWERBORDERLINE, 0);
	CBump(UserCopperList);
	CMove(UserCopperList, COLOR00, 0xFFF);
	CBump(UserCopperList);
	// Black
	CWait(UserCopperList, LOWERBORDERLINE + 1, 0);
	CBump(UserCopperList);
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
	if (!Init_2DStarfield())
	{
		return FALSE;
	}

	if (!Init_3DStarfield())
	{
		return FALSE;
	}

	if (!Init_SineScroller())
	{
		return FALSE;
	}

	Init_FilledVectorCube();

	return TRUE;
}

void Cleanup_Demo(void)
{
	Cleanup_3DStarfield();
	Cleanup_2DStarfield();
	Cleanup_SineScroller();
	Cleanup_CopperList();
}

inline void DemoPart1(void)
{
	Draw_SineScroller();
}

inline void DemoPart2(void)
{
	Draw_2DStarfield();
}

inline void DemoPart3(void)
{
	Draw_FilledVectorCube();
}

inline void DemoPart4(void)
{
	Draw_3DStarfield();
}

int main(void)
{
    // Load libraries
    // Exit with SEVERE Error (20) if something goes wrong
	if (lwmf_LoadLibraries() != 0)
	{
        lwmf_CleanupAll();
		return 20;
	}

	// Gain control over the OS
	lwmf_TakeOverOS();

	// Check which CPU is used in your Amiga (or UAE...)
	// Depening on this, we use more or less stars (or effects in the near future...)
	lwmf_CheckCPU();
	
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

	// Initial loading of colors
	LoadRGB4(&viewPort, DemoColorTable[0], NUMBEROFCOLORS);
	lwmf_UpdateViewPort();	

	//
	// Init stuff for demo if needed
	//

	if (!Init_Demo())
	{
		Cleanup_Demo();
		lwmf_CleanupAll();
		return 20;
	}

	// Our parts, packed into an array of function pointers
	const void (*DemoParts[4])() =
	{
		DemoPart1, DemoPart2, DemoPart3, DemoPart4
	};

	// Loop control
	UBYTE CurrentBuffer = 0;
	UBYTE CurrentDemoPart = 0;
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

		// Clear bitmap/bitplanes/screen
		OwnBlitter();
		lwmf_ClearScreen((long*)RenderPort.BitMap->Planes[0]);
		lwmf_WaitBlitter();
		DisownBlitter();
		// Call actual demopart
		(*DemoParts[CurrentDemoPart])();

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

			if (++CurrentDemoPart > 3)
			{
				CurrentDemoPart = 0;
			}

			// Load colors & update viewport
			LoadRGB4(&viewPort, DemoColorTable[CurrentDemoPart], NUMBEROFCOLORS);
			lwmf_UpdateViewPort();
		}

		lwmf_WaitVertBlank();
	}

	// Cleanup everything
	Cleanup_Demo();
	lwmf_CleanupAll();
	return 0;
}