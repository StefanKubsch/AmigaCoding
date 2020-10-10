//**********************************************************************
//* Simple demo for Amiga with at least OS 3.0           			   *
//*														 			   *
//* Effects: Copper background, 3D starfield and filled vector cube    *
//*														 			   *
//* This demo will run on a stock A500 in the same speed 			   *
//* as on a turbo-boosted A1200. It´s limited to 20fps,  			   *
//* which seems to be a good tradeoff.					 			   *
//*                                                      			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc 0.9g                                			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Demo3.c -o Demo3 -lmieee -lamiga              			   *
//*                                                      			   *
//* Quit with Ctrl-C                                     			   *
//**********************************************************************

#include <exec/exec.h>
#include <dos/dos.h>
#include <graphics/gfxbase.h>
#include <graphics/copper.h>
#include <graphics/videocontrol.h>
#include <graphics/gfxmacros.h>
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

// Our timing/fps limit is targeted at 20fps
// If you want to use 50fps instead, calc 1000000 / 50
// If you want to use 25fps instead, calc 1000000 / 25 - I guess, you got it...
// Is used in function "DoubleBuffering()"
const ULONG FPSLimit = 1000000 / 20;

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Amiga Halfbrite mode)
const int NumberOfBitplanes = 3;

// ...and here which colors we want to use
// Format: { Index, Red, Green, Blue }, Array must be terminated with {-1, 0, 0, 0}
const struct ColorSpec ColorTable[] = 
{ 
	{0, 0, 0, 0}, 
	{1, 15, 15, 15},
	{2, 10, 0, 10},
	{3, 11, 0, 11},
	{4, 12, 0, 12},
	{5, 13, 0, 13},
	{6, 14, 0, 14},
	{7, 15, 0, 15},
	{-1, 0, 0, 0} 
};

// Global variable for FPS Counter
WORD FPS = 0;

// Some needed buffers for Area operations
UBYTE* TmpRasBuffer = NULL;
UBYTE* AreaBuffer = NULL;

//
// Function declarations
//

void FPSCounter();
void DisplayFPSCounter(const int Color, const int PosX, const int PosY);
BOOL LoadLibraries();
void CloseLibraries();
BOOL CreateScreen();
void CleanupScreen();
BOOL CreateRastPort(const int NumberOfVertices);
void CleanupRastPort();
void DoubleBuffering(void(*CallFunction)());

//
// Demo stuff
//

BOOL LoadCopper();
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

void DisplayFPSCounter(const int Color, const int PosX, const int PosY)
{
	UBYTE String[10];
	sprintf(String, "%d fps", FPS);
								
	SetAPen(&RenderPort, Color);
	Move(&RenderPort, PosX, PosY);
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
	struct Rectangle Rectangle = { 0, 0, 319, 255 };

	Screen = OpenScreenTags(NULL,
	    SA_DisplayID, LORES_KEY,
		SA_Width, 320,
		SA_Height, 256,
		SA_Pens, ~0,
	    SA_Depth, NumberOfBitplanes,
	    SA_ShowTitle, FALSE,
	    SA_Type, CUSTOMSCREEN,
	    SA_Colors, ColorTable,
		SA_DClip, &Rectangle,
	    TAG_DONE
    );

    if (!Screen)
    {
        CleanupScreen();
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

BOOL CreateRastPort(const int NumberOfVertices)
{
	InitRastPort(&RenderPort);

	struct TmpRas tmpras;
	struct AreaInfo areainfo;

	// We only allocate as little memory as needed to keep the impact on blitter low...
	const ULONG RasSize = RASSIZE(130, 130);

	if (TmpRasBuffer = AllocVec(RasSize, MEMF_CHIP | MEMF_CLEAR))
	{
		InitTmpRas(&tmpras, TmpRasBuffer, RasSize);
		RenderPort.TmpRas = &tmpras;
	}
	else
	{
		return FALSE;
	}

	// We need to allocate 5bytes per vertex
	if (AreaBuffer = AllocVec(5 * NumberOfVertices, MEMF_CLEAR))
	{
		InitArea(&areainfo, AreaBuffer, NumberOfVertices);
		RenderPort.AreaInfo = &areainfo;
	}
	else
	{
		return FALSE;
	}

	return TRUE;
}

void CleanupRastPort()
{
	struct ViewPort* viewPort = &Screen->ViewPort;
    
	if (viewPort->UCopIns != NULL)
    {
		FreeVPortCopLists(viewPort);
		MakeScreen(Screen);
		RethinkDisplay();	
	}

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
    struct MsgPort* DisplayPort = CreateMsgPort();
    struct MsgPort* SafePort = CreateMsgPort();

    if (Buffer[0] && Buffer[1] && DisplayPort && SafePort)
    {
		// Start timer
		struct timerequest TickRequest = *TimerIO;
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
				DisplayFPSCounter(1, 5, 10);

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

BOOL LoadCopper()
{
	struct TagItem uCopTags[] =
    {
    	{ VTAG_USERCLIP_SET, 0 },
        { VTAG_END_CM, 0 }
    };

	struct UCopList* uCopList = (struct UCopList*)AllocMem(sizeof(struct UCopList), MEMF_CHIP | MEMF_CLEAR);

	if (uCopList == NULL)
	{
		return FALSE;
	}
	
	extern struct Custom custom;

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
		CWAIT(uCopList, i * (Screen->Height / NumberOfColors), 0);
		CMOVE(uCopList, custom.color[0], Colors[i]);
	}

	CEND(uCopList);
	
	struct ViewPort* viewPort = &Screen->ViewPort;
	
	Forbid();
	viewPort->UCopIns = uCopList;
	Permit();
	VideoControl(viewPort->ColorMap, uCopTags );
	RethinkDisplay();
	
	return TRUE;
}

struct StarStruct
{
    int x;
    int y;
    int z;
} Stars[150];

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

	// Since we use only bitplane 0 here, we enable only bitplane 0
	// Bitmap.Planes[0] = Bit 0
	// Bitmap.Planes[1] = Bit 1
	// ...
	// To enable bitplane 0 only set the mask as following:
	// 00000001 = Hex 0x01
	//
	// Another example: Enable only bitplanes 1 and 2:
	// 11111110 = Hex 0xFE

	SetWrMsk(&RenderPort, 0x01);
	SetAPen(&RenderPort, 1);

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
			WritePixel(&RenderPort, x, y);
		}
	}

	// Re-enable all bitplanes
	SetWrMsk(&RenderPort, -1);

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

	static struct CubeFaceStruct
	{
		int p0;
		int p1;
		int p2;
		int p3;
	} CubeFaces[] = { {0,1,3,2}, {4,0,2,6}, {5,4,6,7}, {1,5,7,3}, {0,1,5,4}, {2,3,7,6} };

	struct OrderPair
	{
		int first;
		float second;
	};
	
	struct OrderPair Order[6];

	// selection-sort of depth/faces
	for (int i = 0; i < 6; ++i)
	{
		Order[i].second = (CubeDef[CubeFaces[i].p0].z + CubeDef[CubeFaces[i].p1].z + CubeDef[CubeFaces[i].p2].z + CubeDef[CubeFaces[i].p3].z) * 0.25f;
		Order[i].first = i;
	}

	for (int i = 0; i < 5; ++i)
	{
		int Min = i;

		for (int j = i + 1; j <= 5; ++j)
		{
			if (Order[j].second < Order[Min].second)
			{
				Min = j;
			}
		}
		
		struct OrderPair Temp = Order[Min];
		Order[Min] = Order[i];
		Order[i] = Temp;
	}

	const int CubeFacesColors[] ={ 2, 3, 4, 5, 6, 7 };
	
	// Since we see only the three faces on top, we only need to render these (3, 4 and 5)
	for (int i = 3; i < 6; ++i)
	{
		SetAPen(&RenderPort, CubeFacesColors[Order[i].first]);

		AreaMove(&RenderPort, Cube[CubeFaces[Order[i].first].p0].x, Cube[CubeFaces[Order[i].first].p0].y);
		AreaDraw(&RenderPort, Cube[CubeFaces[Order[i].first].p1].x, Cube[CubeFaces[Order[i].first].p1].y);
		AreaDraw(&RenderPort, Cube[CubeFaces[Order[i].first].p2].x, Cube[CubeFaces[Order[i].first].p2].y);
		AreaDraw(&RenderPort, Cube[CubeFaces[Order[i].first].p3].x, Cube[CubeFaces[Order[i].first].p3].y);

		AreaEnd(&RenderPort);
	}
}

int main()
{
    // Load libraries
    // Exit with SEVERE Error (20) if something goes wrong
	if (!LoadLibraries())
    {
        return 20;
    }

	// Setup screen
	if (!CreateScreen())
    {
        return 20;
    }

    // Init the RenderPort (=Rastport)
	// We need to init some buffers for Area operations
	// Since our demo part draw some cube surfaces which are made out of 4 vertices, we choose 5 (4 + 1 for safety)
	if (!CreateRastPort(5))
	{
		return 20;
	}

	//
	// Init stuff for demo if needed
	//

	// Load Copper table and init viewport
	if (!LoadCopper())
	{
		return 20;
	}

	// Init starfield an precalc cos and sin
	InitDemo();

    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
	DoubleBuffering(DrawDemo);

	// Cleanup everything
	CleanupRastPort();
	CleanupScreen();
	CloseLibraries();
	return 0;
}