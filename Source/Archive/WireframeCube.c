//***********************************************************
//* Simple demo for Amiga with at least OS 3.0           	*
//*														 	*
//* Effects: 3D-Starfield and wireframe vector cube      	*
//*														 	*
//* This demo will run on a stock A500 in the same speed 	*
//* as on a turbo-boosted A1200. It´s limited to 25fps,  	*
//* which seems to be a good tradeoff.					 	*
//*                                                      	*
//* (C) 2020 by Stefan Kubsch                            	*
//* Project for vbcc 0.9g                                	*
//*                                                      	*
//* Compile & link with:                                 	*
//* vc -O4 WireframeCube.c -o WireframeCube -lmieee -lamiga	*
//*                                                     	*
//* Quit with Ctrl-C                                     	*
//***********************************************************

#include <exec/exec.h>
#include <dos/dos.h>
#include <graphics/gfxbase.h>
#include <intuition/intuition.h>
#include <devices/timer.h>
#include <proto/timer.h>   
#include <clib/exec_protos.h>
#include <clib/graphics_protos.h>
#include <clib/intuition_protos.h>
#include <clib/alib_protos.h>
#include <stdlib.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;

struct Screen* Screen = NULL;
struct RastPort RenderPort;

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

// Our timing/fps limit is targeted at 25fps
// If you want to use 50fps instead, calc 1000000 / 50
// Is used in function "DoubleBuffering()"
const ULONG FPSLimit = 1000000 / 50;

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6
const int NumberOfBitplanes = 3;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
//
// Our colors here are:
// {0, 0, 0, 3}		- Dark Blue
// {1, 15, 15, 15}	- White
// {2, 8, 8, 8}		- Grey
// {3, 4, 4, 4}		- Dark Grey
// {4, 15, 0, 0}	- Red
// {5, 0, 15, 0}	- Green
const struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 3}, 
	{1, 15, 15, 15}, 
	{2, 8, 8, 8}, 
	{3, 4, 4, 4}, 
	{4, 15, 0, 0}, 
	{5, 0, 15, 0}, 
	{-1, 0, 0, 0} 
};

// Global variable for FPS Counter
WORD FPS = 0;

void FPSCounter();
void DisplayFPSCounter();
BOOL LoadLibraries();
void CloseScreenAndLibraries();
BOOL CreateScreen();
void DoubleBuffering(void(*CallFunction)());

//
// Demo stuff
//

void InitDemo();
void DrawDemo();

//***************************************************************
// Functions for screen, bitmap, FPS and library handling       *
//***************************************************************

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

void DisplayFPSCounter()
{
	UBYTE String[10];
	sprintf(String, "%d fps", FPS);
								
	SetAPen(&RenderPort, 5);
	Move(&RenderPort, 10, 10);
	Text(&RenderPort, String, strlen(String));
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
		   		CloseScreenAndLibraries();
				return FALSE;
			}
		}
		else
		{
	   		CloseScreenAndLibraries();
			return FALSE;
		}
	}
	else
	{
   		CloseScreenAndLibraries();
		return FALSE;
	}
	
	//
	// Since we use functions that require at least OS 3.0, we must use "39" as minimum library version!
    //

	if (!(GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 39)))
    {
   		CloseScreenAndLibraries();
		return FALSE;
    }

    if (!(IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 39)))
    {
        CloseScreenAndLibraries();
        return FALSE;
    }

    return TRUE;
}

void CloseScreenAndLibraries()
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
		TimerPort = 0;
	}

	if (Screen)
    {
        CloseScreen(Screen);
		Screen = NULL;
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
	    SA_Pens, ~0,
	    SA_Depth, NumberOfBitplanes,
	    SA_ShowTitle, FALSE,
	    SA_Type, CUSTOMSCREEN,
	    SA_Colors, ColorTable,
	    TAG_DONE
    );

    if (!Screen)
    {
        CloseScreenAndLibraries();
        return FALSE;
    }

    return TRUE;
}

void DoubleBuffering(void(*CallFunction)())
{
    struct ScreenBuffer* Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };
    struct MsgPort* DisplayPort = CreateMsgPort();
    struct MsgPort* SafePort = CreateMsgPort();

    if (Buffer[0] && Buffer[1] && DisplayPort && SafePort)
    {
        InitRastPort(&RenderPort);

		// Start timer
		struct timerequest TickRequest;

		TickRequest = *TimerIO;
		TickRequest.tr_node.io_Command = TR_ADDREQUEST;
		TickRequest.tr_time.tv_secs = 0;
		TickRequest.tr_time.tv_micro = 0;
		SendIO((struct IORequest*)&TickRequest);
	
		// Loop control
		BOOL TickRequestPending = TRUE;
        BOOL WriteOK = TRUE;
        BOOL ChangeOK = TRUE;
        BOOL Continue = TRUE;
        int CurrentBuffer = 0;

        while (Continue)
        {
            if (!WriteOK)
            {
                while (!GetMsg(SafePort))
                {
                    if (Wait((1 << SafePort->mp_SigBit) | SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                    {
                        Continue = FALSE;
                        break;
                    }
                }

                WriteOK = TRUE;
            }

            if (Continue)
            {
				RenderPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
                
                //***************************************************************
                // Here we call the drawing function for demo stuff!            *
                //***************************************************************

                (*CallFunction)();

				// DisplayFPSCounter() writes on the backbuffer, too - so we need to call it before blitting
				DisplayFPSCounter();

                //***************************************************************
                // Ends here ;-)                                                *
                //***************************************************************

                if (!ChangeOK)
                {
                    while (!GetMsg(DisplayPort))
                    {
                        if (Wait((1 << DisplayPort->mp_SigBit) | SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                        {
                            Continue = FALSE;
                            break;
                        }
                    }

                    ChangeOK = TRUE;
					FPSCounter();
                }
            }

            if (Continue)
            {
                WaitBlit();
                Buffer[CurrentBuffer]->sb_DBufInfo->dbi_SafeMessage.mn_ReplyPort = SafePort;
                Buffer[CurrentBuffer]->sb_DBufInfo->dbi_DispMessage.mn_ReplyPort = DisplayPort;
                
                while (!ChangeScreenBuffer(Screen, Buffer[CurrentBuffer]))
                {
                    if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                    {
                        Continue = FALSE;
                        break;
                    }
                }

                ChangeOK = FALSE;
                WriteOK = FALSE;
                CurrentBuffer ^= 1;

                if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                {
                    Continue = FALSE;
                }

				const ULONG Signals = Wait(1 << TimerPort->mp_SigBit | SIGBREAKF_CTRL_C);

				if (Signals & (1 << TimerPort->mp_SigBit))
				{
					WaitIO((struct IORequest*)&TickRequest);

					if (Continue)
					{
						TickRequest.tr_time.tv_secs = 0;
						TickRequest.tr_time.tv_micro = FPSLimit;
						SendIO((struct IORequest*)&TickRequest);
						WriteOK = TRUE;
					}
					else
					{
						TickRequestPending = FALSE;
					}
				}

				if (Signals & SIGBREAKF_CTRL_C)
				{
					Continue = FALSE;
				}

				if (!Continue && TickRequestPending)
				{
					AbortIO((struct IORequest*)&TickRequest);
				}
            }
        }

        // After breaking the loop, we have to make sure that there are no more signals to process.
		// Without these last two checks, a crash is very possible...
		
		if (!WriteOK)
        {
            while (!GetMsg (SafePort))
            {
                if (Wait ((1 << SafePort->mp_SigBit) | SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                {
                    break;
                }
            }
        }

        if (!ChangeOK)
        {
            while (!GetMsg (DisplayPort))
            {
                if (Wait ((1 << DisplayPort->mp_SigBit) | SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                {
                    break;
                }
            }
        }
    }

    FreeScreenBuffer(Screen, Buffer[0]);
	Buffer[0] = NULL;
    FreeScreenBuffer(Screen, Buffer[1]);
	Buffer[1] = NULL;
    DeleteMsgPort(SafePort);
	SafePort = NULL;
    DeleteMsgPort(DisplayPort);
	DisplayPort = NULL;
}

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

struct StarStruct
{
    int x;
    int y;
    int z;
} Stars[200];

float CosA;
float SinA;

void InitDemo()
{
    CosA = cos(0.03f);
    SinA = sin(0.03f);

    const int NumberOfStars = sizeof(Stars) / sizeof(*Stars);
    
    for (int i = 0; i < NumberOfStars; ++i) 
    {
        Stars[i].x = rand() % 40000 - 15000;
        Stars[i].y = rand() % 40000 - 15000;
        Stars[i].z = rand() % 500;
    }
}

void DrawDemo()
{
	SetRast(&RenderPort, 0);

	const int WidthMid = Screen->Width >> 1;
	const int HeightMid = Screen->Height >> 1;

	//
	// Starfield
	//

	static const int NumberOfStars = sizeof(Stars) / sizeof(*Stars);

	for (int i = 0; i < NumberOfStars; ++i)
	{
		Stars[i].z -= 10;
	
		if (Stars[i].z <= 0) 
		{
			Stars[i].x = rand() % 40000 - 15000;
			Stars[i].y = rand() % 40000 - 15000;
			Stars[i].z = 500;
		}
		
		const int x = WidthMid + Stars[i].x / Stars[i].z;
		const int y = HeightMid + Stars[i].y / Stars[i].z;
		
		if ((unsigned int)x < Screen->Width && (unsigned int)y < Screen->Height)
		{
			SetAPen(&RenderPort, Stars[i].z / 200 + 1);
			WritePixel(&RenderPort, x, y);
		}
	}

	//
	// Vector Cube
	//

	static struct VertexStruct
	{
		float x;
		float y;
		float z;
	} CubeDef[8] = { { -50.0f, -50.0f, -50.0f }, { -50.0f, -50.0f, 50.0f }, { -50.0f, 50.0f, -50.0f }, { -50.0f, 50.0f, 50.0f }, { 50.0f, -50.0f, -50.0f }, { 50.0f, -50.0f, 50.0f }, { 50.0f, 50.0f, -50.0f }, { 50.0f, 50.0f, 50.0f } };
	
	struct IntPointStruct
	{
		int x;
		int y;
	} Cube[8];

	for (int i = 0; i < 8; ++i)
	{
		// x - rotation
		const float y = CubeDef[i].y;
		CubeDef[i].y = y * CosA - CubeDef[i].z * SinA;

		// y - rotation
		const float z = CubeDef[i].z * CosA + y * SinA;
		CubeDef[i].z = z * CosA + CubeDef[i].x * SinA;

		// z - rotation
		const float x = CubeDef[i].x * CosA - z * SinA;
		CubeDef[i].x = x * CosA - CubeDef[i].y * SinA;
		CubeDef[i].y = CubeDef[i].y * CosA + x * SinA;

		// 2D projection & translate
		Cube[i].x = WidthMid + (int)CubeDef[i].x;
		Cube[i].y = HeightMid + (int)CubeDef[i].y;
	}

	SetAPen(&RenderPort, 4);

	Move(&RenderPort, Cube[0].x, Cube[0].y);
	Draw(&RenderPort, Cube[1].x, Cube[1].y);
	Draw(&RenderPort, Cube[5].x, Cube[5].y);
	Draw(&RenderPort, Cube[4].x, Cube[4].y);
	Draw(&RenderPort, Cube[0].x, Cube[0].y);
	Draw(&RenderPort, Cube[2].x, Cube[2].y);
	Draw(&RenderPort, Cube[6].x, Cube[6].y);
	Draw(&RenderPort, Cube[4].x, Cube[4].y);
	
	Move(&RenderPort, Cube[5].x, Cube[5].y);
	Draw(&RenderPort, Cube[7].x, Cube[7].y);
	Draw(&RenderPort, Cube[3].x, Cube[3].y);
	Draw(&RenderPort, Cube[1].x, Cube[1].y);
	
	Move(&RenderPort, Cube[2].x, Cube[2].y);
	Draw(&RenderPort, Cube[3].x, Cube[3].y);
	Draw(&RenderPort, Cube[7].x, Cube[7].y);
	Draw(&RenderPort, Cube[6].x, Cube[6].y);
}

int main()
{
    // Load libraries and setup screen
    // Exit with SEVERE Error (20) if something goes wrong
	if (!LoadLibraries() || !CreateScreen())
    {
        return 20;
    }

    // Init stuff for demo if needed
	InitDemo();

    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
	DoubleBuffering(DrawDemo);

	CloseScreenAndLibraries();
	return 0;
}