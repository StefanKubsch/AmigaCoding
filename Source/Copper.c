//**********************************************************************
//* Simple copper demo for Amiga with at least OS 3.0           	   *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc 0.9g                                			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Copper.c -o Copper -lamiga           	     			   *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

#include <exec/exec.h>
#include <graphics/gfxbase.h>
#include <graphics/copper.h>
#include <graphics/gfxmacros.h>
#include <graphics/rastport.h>
#include <graphics/text.h>
#include <intuition/intuition.h>
#include <hardware/intbits.h>
#include <hardware/custom.h>
#include <hardware/cia.h>
#include <devices/timer.h>
#include <clib/timer_protos.h>  
#include <clib/exec_protos.h>
#include <clib/graphics_protos.h>
#include <clib/intuition_protos.h>
#include <clib/alib_protos.h>
#include <stdio.h>
#include <string.h>

// Include our own header files
#include "lwmf/lwmf_math.h"
#include "lwmf/lwmf_hardware.h"

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;

struct Screen* Screen = NULL;
struct RastPort RenderPort;

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

struct Custom* custom = NULL;

// Some stuff needed for OS takeover
struct View* OldView = NULL;
struct copinit* OldCopperInit = NULL;
UWORD Old_dmacon = 0;
UWORD Old_intena = 0;
UWORD Old_adkcon = 0;
UWORD Old_intreq = 0;

//
// Screen settings
//

#define WIDTH 320
#define HEIGHT 256

// Our timing/fps limit is targeted at 50fps
// If you want to use 20fps instead, calc 1000000 / 20
// If you want to use 25fps instead, calc 1000000 / 25 - I guess, you got it...
// Is used in function "DoubleBuffering()"
#define FPSLIMIT (1000000 / 50)

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Amiga Halfbrite mode)
#define NUMBEROFBITPLANES 1

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
const struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 0}, 
	{1, 15, 15, 15},
	{-1, 0, 0, 0} 
};

// Some global variables for our statistics...
WORD FPS = 0;
BOOL FastCPUFlag = FALSE;
char* CPUText = NULL;
int CPUTextLength = 0;

// Some needed buffers for Area operations
UBYTE* TmpRasBuffer = NULL;
UBYTE* AreaBuffer = NULL;

//
// Function declarations
//

void TakeOverOS();
void ReleaseOS();
void FPSCounter();
void DisplayStatistics(const int Color, const int PosX, const int PosY);
void CheckCPU();
BOOL LoadLibraries();
void CloseLibraries();
BOOL CreateScreen();
void CleanupScreen();
BOOL CreateRastPort(const int NumberOfVertices, const int AreaWidth, const int AreaHeight);
void CleanupRastPort();
void DoubleBuffering(void(*CallFunction)());

//
// Demo stuff
//

BOOL LoadCopperList();
void CleanupCopperList();
void DrawDemo();

//***************************************************************
// Functions for screen, bitmap, FPS and library handling       *
//***************************************************************

void TakeOverOS()
{
	// Save current view
	OldView = GfxBase->ActiView;
	// Save current copperlist
	OldCopperInit = GfxBase->copinit;
	
    // Reset view (clear anything)
	LoadView(NULL);

    WaitTOF();
    WaitTOF();

	// Set task priority
	SetTaskPri(FindTask(NULL), 100);
	
	Disable();

	// Save custom registers
	Old_dmacon = custom->dmaconr | 0x8000;
	Old_intena = custom->intenar | 0x8000;
	Old_adkcon = custom->adkconr | 0x8000;
	Old_intreq = custom->intreqr | 0x8000;
}

void ReleaseOS()
{
	// Restore custom registers
	custom->dmacon = 0x7FFF;
	custom->intena = 0x7FFF;
	custom->adkcon = 0x7FFF;
	custom->intreq = 0x7FFF;

	custom->dmacon = Old_dmacon;
	custom->intena = Old_intena;
	custom->adkcon = Old_adkcon;
	custom->intreq = Old_intreq;

	Enable();

	// Restore previously saved copperlist
	custom->cop1lc = (ULONG)OldCopperInit;
	OldCopperInit = NULL;

	// Restore previously saved vire
	LoadView(OldView);
	OldView = NULL;

	WaitTOF();
	WaitTOF();
}

void FPSCounter()
{
	// Get system time
	static struct timeval tt;
	struct timeval a;
	struct timeval b;

	GetSysTime(&a);
	b = a;
	SubTime(&b, &tt);
	tt = a;

	const ULONG SystemTime = b.tv_secs * 1000 + b.tv_micro / 1000;
	
	// Calculate fps
	static WORD FPSFrames = 0;
	static ULONG FPSUpdate = 0;

	FPSUpdate += SystemTime;

	if (FPSUpdate >= 1000)
	{
		FPS = FPSFrames;
		FPSFrames = 0;
		FPSUpdate = SystemTime;
	}

	++FPSFrames;
}

void DisplayStatistics(const int Color, const int PosX, const int PosY)
{
	UBYTE FPSStr[10];
	sprintf(FPSStr, "%d fps", FPS);
								
	SetAPen(&RenderPort, Color);
	Move(&RenderPort, PosX, PosY);
	Text(&RenderPort, FPSStr, strlen(FPSStr));

	Move(&RenderPort, PosX, PosY + 10);
	Text(&RenderPort, CPUText, CPUTextLength);
}

void CheckCPU()
{
	struct ExecBase *SysBase = *((struct ExecBase**)4L);

	// Check if CPU is a 68020, 030, 040, 060 (this is the "0x80")
	// If yes, we can calculate more stuff...
	if (SysBase->AttnFlags & AFF_68020 || SysBase->AttnFlags & AFF_68030 || SysBase->AttnFlags & AFF_68040 || SysBase->AttnFlags & 0x80)
	{
		FastCPUFlag = TRUE;
		CPUText = "CPU:68020 or higher";
	}
	else
	{
		CPUText = "CPU:68000 or 68010";
	}

	CPUTextLength = strlen(CPUText);
}

BOOL LoadLibraries()
{
	if (TimerPort = CreatePort(0, 0))
	{
		if (TimerIO = (struct timerequest*)CreateExtIO(TimerPort, sizeof(struct timerequest)))
		{
			if (OpenDevice(TIMERNAME, UNIT_MICROHZ, (struct IORequest*)TimerIO, 0) == 0)
			{
				TimerBase = (struct Library*)TimerIO->tr_node.io_Device;
			}
			else
			{
		   		CloseLibraries();
				return FALSE;
			}
		}
		else
		{
	   		CloseLibraries();
			return FALSE;
		}
	}
	else
	{
   		CloseLibraries();
		return FALSE;
	}
	
	//
	// Since we use functions that require at least OS 3.0, we must use "39" as minimum library version!
    //

	if (!(GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 39)))
    {
   		CloseLibraries();
		return FALSE;
    }

    if (!(IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 39)))
    {
        CloseLibraries();
        return FALSE;
    }

    return TRUE;
}

void CloseLibraries()
{
    if (TimerBase)
	{
		CloseDevice((struct IORequest*)TimerIO);
		TimerBase = NULL;
	}

	if (TimerIO)
	{
		DeleteExtIO((struct IORequest*)TimerIO);
		TimerIO = NULL;
	}

	if (TimerPort)
	{
		DeletePort(TimerPort);
		TimerPort = NULL;
	}

    if (IntuitionBase)
    {
        CloseLibrary((struct Library*)IntuitionBase);
		IntuitionBase = NULL;
    }
	
    if (GfxBase)
    {
       CloseLibrary((struct Library*)GfxBase);
	   GfxBase = NULL;
    }     
}

BOOL CreateScreen()
{
	// Open screen with given number of bitplanes and given colors
	Screen = OpenScreenTags(NULL,
	    SA_DisplayID, LORES_KEY,
		SA_Width, WIDTH,
		SA_Height, HEIGHT,
		SA_Pens, ~0,
	    SA_Depth, NUMBEROFBITPLANES,
	    SA_ShowTitle, FALSE,
	    SA_Type, CUSTOMSCREEN,
	    SA_Colors, ColorTable,
	    TAG_DONE
    );

    if (!Screen)
    {
        return FALSE;
    }

    return TRUE;
}

void CleanupScreen()
{
	if (Screen)
    {
        CloseScreen(Screen);
		Screen = NULL;
    }
}

BOOL CreateRastPort(const int NumberOfVertices, const int AreaWidth, const int AreaHeight)
{
	InitRastPort(&RenderPort);

	struct TmpRas tmpRas;
	struct AreaInfo areaInfo;

	const ULONG RasSize = RASSIZE(AreaWidth, AreaHeight);

	if (TmpRasBuffer = AllocVec(RasSize, MEMF_CHIP | MEMF_CLEAR))
	{
		InitTmpRas(&tmpRas, TmpRasBuffer, RasSize);
		RenderPort.TmpRas = &tmpRas;
	}
	else
	{
		CleanupRastPort();
		return FALSE;
	}

	// We need to allocate 5bytes per vertex
	if (AreaBuffer = AllocVec(5 * NumberOfVertices, MEMF_CHIP | MEMF_CLEAR))
	{
		InitArea(&areaInfo, AreaBuffer, NumberOfVertices);
		RenderPort.AreaInfo = &areaInfo;
	}
	else
	{
		CleanupRastPort();
		return FALSE;
	}

	return TRUE;
}

void CleanupRastPort()
{
	if (TmpRasBuffer)
	{
		FreeVec(TmpRasBuffer);
		RenderPort.TmpRas = NULL;
	}

	if (AreaBuffer)
	{
		FreeVec(AreaBuffer);
		RenderPort.AreaInfo = NULL;
	}
}

void DoubleBuffering(void(*CallFunction)())
{
    struct ScreenBuffer* Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };

    if (Buffer[0] && Buffer[1])
    {
		volatile struct CIA *ciaa = (struct CIA *)0xBFE001;

		// Start timer
		struct timerequest TickRequest = *TimerIO;
		TickRequest.tr_node.io_Command = TR_ADDREQUEST;
		TickRequest.tr_time.tv_secs = 0;
		TickRequest.tr_time.tv_micro = 0;
		SendIO((struct IORequest*)&TickRequest);
	
		// Loop control
        int CurrentBuffer = 0;

        // Loop until mouse button is pressed...
		while (ciaa->ciapra & CIAF_GAMEPORT0)
        {
			RenderPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
			
			//***************************************************************
			// Here we call the drawing function for demo stuff!            *
			//***************************************************************

			(*CallFunction)();

			// DisplayStatistics() writes on the backbuffer, too - so we need to call it before blitting
			DisplayStatistics(1, 5, 10);

			//***************************************************************
			// Ends here ;-)                                                *
			//***************************************************************

			ForcedWaitBlit();
			ChangeScreenBuffer(Screen, Buffer[CurrentBuffer]);
			WaitVBeam(255);
			CurrentBuffer ^= 1;
			FPSCounter();

			if (Wait(1 << TimerPort->mp_SigBit) & (1 << TimerPort->mp_SigBit))
			{
				WaitIO((struct IORequest*)&TickRequest);
				TickRequest.tr_time.tv_secs = 0;
				TickRequest.tr_time.tv_micro = FPSLIMIT;
				SendIO((struct IORequest*)&TickRequest);
			}

        }

        // After breaking the loop, we have to make sure that there are no more TickRequests to process
		AbortIO((struct IORequest*)&TickRequest);

	    FreeScreenBuffer(Screen, Buffer[0]);
		Buffer[0] = NULL;
		FreeScreenBuffer(Screen, Buffer[1]);
		Buffer[1] = NULL;
    }
}

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

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
	if (!LoadLibraries())
    {
        return 20;
    }

	// Check which CPU is used in your Amiga (or UAE...)
	CheckCPU();

	// Gain control over the OS
	TakeOverOS();
	
	// Setup screen
	if (!CreateScreen())
    {
        return 20;
    }

    // Init the RenderPort (=Rastport)
	if (!CreateRastPort(1, 1, 1))
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
	DoubleBuffering(DrawDemo);

	// Cleanup everything
	ReleaseOS();
	CleanupCopperList();
	CleanupRastPort();
	CleanupScreen();
	CloseLibraries();
	return 0;
}