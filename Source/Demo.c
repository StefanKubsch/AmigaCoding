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
const int WidthMid = 160;
const int HeightMid = 128;

// Our timing/fps limit is targeted at 25fps
// If you want to use 50fps instead, calc 1000000 / 50
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
const int NUMBEROFBITPLANES = 4;

// Include the demo effects
#include "Colors.h"
#include "SineScroller.h"
#include "FilledVectorCube.h"
#include "Starfield3D.h"

BOOL Init_CopperList(void);
void Cleanup_CopperList(void);
BOOL Init_Demo(void);
void Cleanup_Demo(void);

BOOL Init_CopperList(void)
{
	struct UCopList* UserCopperList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_ANY | MEMF_CLEAR);
	
	if (!UserCopperList)
	{
		return FALSE;
	}
	
	// Copper init

	//Init & End + some spare
	UCopperListInit(UserCopperList, 20);

	// Set mouse pointer to blank sprite
	CMove(UserCopperList, SPR0PTH, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
    CMove(UserCopperList, SPR0PTL, (LONG)&BlankMousePointer);
	CBump(UserCopperList);
	
	// Copper list end
	CWait(UserCopperList, 10000, 255);

	Screen->ViewPort.UCopIns = UserCopperList;
	RethinkDisplay();
	
	return TRUE;
}

void Cleanup_CopperList(void)
{
	if (Screen->ViewPort.UCopIns)
    {
		FreeVPortCopLists(&Screen->ViewPort);
	}
}

BOOL Init_Demo(void)
{
	if (!Init_CopperList())
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
	Cleanup_CopperList();
	Cleanup_3DStarfield();
	Cleanup_SineScroller();
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
	if (!lwmf_CreateScreen(WIDTH, HEIGHT, NUMBEROFBITPLANES))
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

	// Init all demo effects & copper
	if (!Init_Demo())
	{
		return 20;
	}


    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
    struct ScreenBuffer* Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };

    if (!Buffer[0] || !Buffer[1])
    {
		lwmf_CleanupAll();
		return FALSE;
	}

	// Start timer
	struct timerequest TickRequest = *TimerIO;
	TickRequest.tr_node.io_Command = TR_ADDREQUEST;
	TickRequest.tr_time.tv_secs = 0;
	TickRequest.tr_time.tv_micro = 0;
	SendIO((struct IORequest*)&TickRequest);

	// Our parts, packed into an array of function pointers
	void (*DemoParts[3])() =
	{
		Draw_SineScroller, Draw_FilledVectorCube, Draw_3DStarfield
	};

	// Loop control
	int CurrentBuffer = 0;
	int CurrentDemoPart = 0;
	int TimeCount = 0;
	ULONG PartDuration = 5 * 25;

	// Set colors of first demo part
	lwmf_SetColors(DemoColorTable[CurrentDemoPart], 8);

	// Check if mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		lwmf_WaitFrame();

		RenderPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
		
		//***************************************************************
		// Here we call the drawing functions for demo stuff!            *
		//***************************************************************

		SetRast(&RenderPort, 0);

		(*DemoParts[CurrentDemoPart])();;

		// lwmf_DisplayFPSCounter() writes on the backbuffer, too - so we need to call it before blitting
		lwmf_DisplayFPSCounter(5, 10, 1);

		//***************************************************************
		// Ends here ;-)                                                *
		//***************************************************************

		ChangeScreenBuffer(Screen, Buffer[CurrentBuffer]);
		CurrentBuffer ^= 1;

		lwmf_FPSCounter();

		if (Wait(1L << TimerPort->mp_SigBit) & (1L << TimerPort->mp_SigBit))
		{
			WaitIO((struct IORequest*)&TickRequest);
			TickRequest.tr_time.tv_secs = 0;
			TickRequest.tr_time.tv_micro = FPSLIMIT;
			SendIO((struct IORequest*)&TickRequest);
		}

		++TimeCount;

		if (TimeCount >= PartDuration)
		{
			TimeCount = 0;

			++CurrentDemoPart;
			
			if (CurrentDemoPart > 2)
			{
				CurrentDemoPart = 0;
			}

			lwmf_SetColors(DemoColorTable[CurrentDemoPart], 8);
		}
	}

	// After breaking the loop, we have to make sure that there are no more TickRequests to process
	AbortIO((struct IORequest*)&TickRequest);

	// Cleanup everything
	if (Buffer[0])
	{
		lwmf_WaitBlit();
		FreeScreenBuffer(Screen, Buffer[0]);
		Buffer[0] = NULL;
	}

	if (Buffer[1])
	{
		lwmf_WaitBlit();
		FreeScreenBuffer(Screen, Buffer[1]);
		Buffer[1] = NULL;
	}

	Cleanup_Demo();
	lwmf_CleanupAll();
	return 0;
}