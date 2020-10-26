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

#define WIDTH				320
#define HEIGHT				256
#define UPPERBORDERLINE		20
#define LOWERBORDERLINE		235

// Our timing/fps limit is targeted at 25fps
// If you want to use 50fps instead, calc 1000000 / 50
// Is used in function "DoubleBuffering()"
#define FPS					25
#define FPSLIMIT			(1000000 / FPS)

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Extra Halfbrite mode)
#define NUMBEROFBITPLANES	4

// Include the demo effects
#include "Demo_Colors.h"
#include "Demo_SineScroller.h"
#include "Demo_FilledVectorCube.h"
#include "Demo_Starfield3D.h"
#include "Demo_Starfield2D.h"

BOOL Init_CopperList(void);
void Cleanup_CopperList(void);
BOOL Init_Demo(void);
void Cleanup_Demo(void);
inline void DemoPart1(void);
inline void DemoPart2(void);
inline void DemoPart3(void);

BOOL Init_CopperList(void)
{
	struct UCopList* UserCopperList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_ANY | MEMF_CLEAR);
	
	if (!UserCopperList)
	{
		return FALSE;
	}
	
	// Copper init

	// Needed memory: Init, Mouse, Background & End + some spare
	UCopperListInit(UserCopperList, 15);

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
	RethinkDisplay();
	
	return TRUE;
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

	if (!Init_FilledVectorCube())
	{
		return FALSE;
	}

	if (!Init_SineScroller())
	{
		return FALSE;
	}
	
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
	Draw_2DStarfield();
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
	if (!lwmf_CreateViewPort(WIDTH, HEIGHT, NUMBEROFBITPLANES))
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
	const UWORD PartDuration = 5 * FPS;

	// Init Copper (Set background, disable mouse pointer)
	if (!Init_CopperList())
	{
		Cleanup_Demo();
		lwmf_CleanupAll();
		return 20;
	}

	// Initial loading of colors
	LoadRGB4(&viewPort, DemoColorTable[CurrentDemoPart], 16);
	lwmf_UpdateViewPort();	

	// Start timer
	struct timerequest TickRequest = *TimerIO;
	TickRequest.tr_node.io_Command = TR_ADDREQUEST;
	TickRequest.tr_time.tv_secs = 0;
	TickRequest.tr_time.tv_micro = 0;
	SendIO((struct IORequest*)&TickRequest);

    //
	// This is our main loop
	//

	// Check if mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		WaitTOF();

		if (CurrentBuffer == 0) 
		{
			view.LOFCprList = LOCpr1;
			view.SHFCprList = SHCpr1;
			RenderPort.BitMap = RastPort1.BitMap;
		}
		else 
		{
			view.LOFCprList = LOCpr2;
			view.SHFCprList = SHCpr2;
			RenderPort.BitMap = RastPort2.BitMap;
		}
		
		SetRast(&RenderPort, 0);

		(*DemoParts[CurrentDemoPart])();

		// lwmf_DisplayFPSCounter() writes on the backbuffer, too - so we need to call it before blitting
		lwmf_DisplayFPSCounter(0, 10, 15);

		//***************************************************************
		// Ends here ;-)                                                *
		//***************************************************************

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
			SetRast(&RenderPort, 0);
			LoadRGB4(&viewPort, DemoColorTable[CurrentDemoPart], 16);
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