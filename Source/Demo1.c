//********************************************************
//* Simple demo for Amiga with at least OS 3.0           *
//*                                                      *
//* (C) 2020 by Stefan Kubsch                            *
//* Project for vbcc 0.9g                                *
//*                                                      *
//* Compile & link with:                                 *
//* vc -O4 Demo1.c -o Demo1 -lmieee -lamiga              *
//*                                                      *
//* Quit with Ctrl-C                                     *
//********************************************************

#include <exec/exec.h>
#include <dos/dos.h>
#include <graphics/gfxbase.h>
#include <graphics/gfxmacros.h>
#include <intuition/intuition.h>
#include <devices/timer.h>
#include <clib/exec_protos.h>
#include <clib/graphics_protos.h>
#include <clib/intuition_protos.h>
#include <clib/alib_protos.h>
#include <stdlib.h>
#include <math.h>

//
// Generic stuff for screen, bitmap, timer and library handling
//

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;

struct Screen* Screen = NULL;
struct RastPort RenderPort = NULL;

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

// Here we define, how many bitplanes we want to use...
const int NumberOfBitplanes = 3;

// ...and here which colors we want to use
struct ColorSpec ColorTable[] = { {0, 0, 0, 3}, {1, 15, 15, 15}, {2, 8, 8, 8}, {3, 4, 4, 4}, {4, 15, 0, 0}, {-1, 0, 0, 0} };

BOOL LoadLibraries();
void CloseScreenAndLibraries();
BOOL CreateScreen();
void DoubleBuffering(void(*CallFunction)());

//
// demo stuff
//

void InitDemo();
void DrawDemo();

//***************************************************************
// Functions for screen, bitmap and library handling            *
//***************************************************************

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
	
	// Since we use functions that require at least Kick 2.0, we must use "37" as least version!
    if (!(GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 37)))
    {
   		CloseScreenAndLibraries();
		return FALSE;
    }

    if (!(IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 37)))
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
	}

	if (TimerIO)
	{
		DeleteExtIO((struct IORequest*)TimerIO);
	}

	if (TimerPort)
	{
		DeletePort(TimerPort);
	}

	if (Screen)
    {
        CloseScreen(Screen);
    }

    if (IntuitionBase)
    {
        CloseLibrary((struct Library*)IntuitionBase);
    }
	
    if (GfxBase)
    {
       CloseLibrary((struct Library*)GfxBase);
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
    struct ScreenBuffer *Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };
    struct MsgPort *DisplayPort = CreateMsgPort();
    struct MsgPort *SafePort = CreateMsgPort();

    if (Buffer[0] && Buffer[1] && DisplayPort && SafePort)
    {
        InitRastPort(&RenderPort);

		struct timerequest TickRequest;

		TickRequest = *TimerIO;
		TickRequest.tr_node.io_Command = TR_ADDREQUEST;
		TickRequest.tr_time.tv_secs = 0;
		TickRequest.tr_time.tv_micro = 0;
		SendIO((struct IORequest*)&TickRequest);
		
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

                (*CallFunction)(&RenderPort);

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
                WriteOK  = FALSE;
                CurrentBuffer ^= 1;

                if (SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C)
                {
                    Continue = FALSE;
                }

				ULONG Signals = Wait(1 << TimerPort->mp_SigBit | SIGBREAKF_CTRL_C);

				if (Signals & (1 << TimerPort->mp_SigBit))
				{
					WaitIO((struct IORequest*)&TickRequest);

					if (Continue)
					{
						TickRequest.tr_time.tv_secs = 0;
						TickRequest.tr_time.tv_micro = 1000000 / 25;
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
    FreeScreenBuffer(Screen, Buffer[1]);
    DeleteMsgPort(SafePort);
    DeleteMsgPort(DisplayPort);
}

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

struct StarStruct
{
    int x;
    int y;
    int z;
} Stars[400];

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