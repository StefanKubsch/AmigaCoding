//**********************************************************************
//* Simple combined demo for Amiga with at least OS 3.0    			   *
//*														 			   *
//* Effects: Copper background, 3D starfield, filled vector cube       *
//* and a sine scroller	with 2D starfield   						   *
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

#include <math.h>
#include <string.h>

// Include our own header files
#include "lwmf/lwmf.h"

//
// Screen settings
//

#define WIDTH				320
#define HEIGHT				256
#define WIDTHMID			(WIDTH >> 1)
#define HEIGHTMID			(HEIGHT >> 1)
#define UPPERBORDERLINE		20
#define LOWERBORDERLINE		(HEIGHT - 20)

// Our timing/fps limit is targeted at 50fps
#define FPSLIMIT			(1000000 / 50)

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
	Draw_2DStarfield();
	Draw_SineScroller();
}

inline void DemoPart2(void)
{
	Draw_FilledVectorCube();
}

inline void DemoPart3(void)
{
	Draw_3DStarfield();
}

int main(void)
{
    // Load libraries
    // Exit with SEVERE Error (20) if something goes wrong
	if (lwmf_LoadGraphicsLibrary() != 0)
	{
        lwmf_CleanupAll();
		return 20;
	}

	if (lwmf_LoadIntuitionLibrary() != 0)
	{
        lwmf_CleanupAll();
		return 20;
	}

	if (lwmf_LoadDatatypesLibrary() != 0)
	{
        lwmf_CleanupAll();
		return 20;
	}

	if (!lwmf_InitTimer())
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
	if (!lwmf_CreateViewPort(WIDTH, HEIGHT, NUMBEROFBITPLANES, NUMBEROFCOLORS))
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

	Update_CopperList();

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
	const void (*DemoParts[3])() =
	{
		DemoPart1, DemoPart2, DemoPart3
	};

	// Loop control
	UBYTE CurrentBuffer = 0;
	UBYTE CurrentDemoPart = 0;
	UWORD FrameCount = 0;

	// Duration of each part in frames
	const UWORD PartDuration = 150;

	// Start timer
	struct timerequest TickRequest = *TimerIO;
	TickRequest.tr_node.io_Command = TR_ADDREQUEST;
	TickRequest.tr_time.tv_secs = 0;
	TickRequest.tr_time.tv_micro = 0;
	SendIO((struct IORequest*)&TickRequest);

	const long SizeOfBitplanes = (WIDTH >> 3) * HEIGHT * NUMBEROFBITPLANES;

	//
	// This is our main loop
	//

	// Check if mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		view.LOFCprList = LOCpr[CurrentBuffer];
		RenderPort.BitMap = Buffer[CurrentBuffer].BitMap;
		
		//***************************************************************
		// Start here with drawing                                      *
		//***************************************************************

		// Clear bitmap/bitplanes
		lwmf_ClearMem((long*)Buffer[CurrentBuffer].BitMap->Planes[0], SizeOfBitplanes);
		// Call actual demopart
		(*DemoParts[CurrentDemoPart])();
		// lwmf_DisplayFPSCounter() writes on the backbuffer, too - so we need to call it before blitting
		lwmf_DisplayFPSCounter(0, 0, 7);

		//***************************************************************
		// Ends here ;-)                                                *
		//***************************************************************

		lwmf_WaitVertBlank();
		LoadView(&view);
		CurrentBuffer ^= 1;

		if (Wait(1L << TimerPort->mp_SigBit) & (1L << TimerPort->mp_SigBit))
		{
			WaitIO((struct IORequest*)&TickRequest);
			TickRequest.tr_time.tv_secs = 0;
			TickRequest.tr_time.tv_micro = FPSLIMIT;
			SendIO((struct IORequest*)&TickRequest);
		}

		lwmf_FPSCounter();

		if (++FrameCount >= PartDuration)
		{
			FrameCount = 0;

			if (++CurrentDemoPart > 2)
			{
				CurrentDemoPart = 0;
			}

			// Load colors & update viewport
			LoadRGB4(&viewPort, DemoColorTable[CurrentDemoPart], NUMBEROFCOLORS);
			lwmf_UpdateViewPort();
		}
	}

	// After breaking the loop, we have to make sure that there are no more TickRequests to process
	AbortIO((struct IORequest*)&TickRequest);

	// Cleanup everything
	Cleanup_Demo();
	lwmf_CleanupAll();
	return 0;
}