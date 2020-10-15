//**********************************************************************
//* Simple combined demo for Amiga with at least OS 3.0    			   *
//*														 			   *
//* Effects: Copper background, 3D starfield, filled vector cube       *
//* and a sine scroller												   *
//*														 			   *
//*                                                      			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc 0.9g                                			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Demo.c -o Demo -lmieee -lamiga              			   	   *
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
#include <clib/diskfont_protos.h>
#include <clib/alib_protos.h>
#include <diskfont/diskfont.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

// Include our own header files
#include "lwmf/lwmf_math.h"
#include "lwmf/lwmf_hardware.h"

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;
struct DiskFontBase* DiskfontBase = NULL;

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

// Our timing/fps limit is targeted at 20fps
// If you want to use 50fps instead, calc 1000000 / 50
// If you want to use 25fps instead, calc 1000000 / 25 - I guess, you got it...
// Is used in function "DoubleBuffering()"
#define FPSLIMIT (1000000 / 20)

// Here we define, how many bitplanes we want to use...
// Colors / number of required Bitplanes
// 2 / 1
// 4 / 2
// 8 / 3
// 16 / 4
// 32 / 5
// 64 / 6 (Amiga Halfbrite mode)
#define NUMBEROFBITPLANES 3

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
BOOL InitDemo();
void CleanupDemo();
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

	if (!(DiskfontBase = (struct DiskFontBase*)OpenLibrary("diskfont.library", 39)))
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

	if (DiskfontBase)
    {
       CloseLibrary((struct Library*)DiskfontBase);
	   DiskfontBase = NULL;
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
			WaitVBeam(240);
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

struct StarStruct
{
    int x;
    int y;
    int z;
} *Stars;

int NumberOfStars;

struct IntPointStruct
{
	int x;
	int y;
};

struct OrderPair
{
	int first;
	float second;
};

struct CubeFaceStruct
{
	int p0;
	int p1;
	int p2;
	int p3;
} CubeFaces[] = { {0,1,3,2}, {4,0,2,6}, {5,4,6,7}, {1,5,7,3}, {0,1,5,4}, {2,3,7,6} };

struct CubeStruct
{
	struct OrderPair Order[6];
	struct IntPointStruct Cube[8];
} CubePreCalc[90];

int VCCount = 0;

struct BitMap* ScrollFontBitMap;
const char ScrollText[] = "...WELL,WELL...NOT PERFECT, BUT STILL WORKING ON IT !!!";
const char ScrollCharMap[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ!.,";
const int ScrollCharWidth = 16;
const int ScrollCharHeight = 28;
int YSine[360];
int ScrollTextLength = 0;
int ScrollCharMapLength = 0;
int ScrollLength = 0;
int ScrollX = 0;

BOOL InitDemo()
{
	//
	// Init Vector cube
	//

	struct VertexStruct
	{
		float x;
		float y;
		float z;
	} CubeDef[8] = { { -50.0f, -50.0f, -50.0f }, { -50.0f, -50.0f, 50.0f }, { -50.0f, 50.0f, -50.0f }, { -50.0f, 50.0f, 50.0f }, { 50.0f, -50.0f, -50.0f }, { 50.0f, -50.0f, 50.0f }, { 50.0f, 50.0f, -50.0f }, { 50.0f, 50.0f, 50.0f } };

	const float CosA = cos(0.04f);
    const float SinA = sin(0.04f);

	for (int Pre = 0; Pre < 90; ++Pre)
	{
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
			CubePreCalc[Pre].Cube[i].x = (WIDTH >> 1) + (int)CubeDef[i].x;
			CubePreCalc[Pre].Cube[i].y = (HEIGHT >> 1) + (int)CubeDef[i].y;
		}

		// selection-sort of depth/faces
		for (int i = 0; i < 6; ++i)
		{
			CubePreCalc[Pre].Order[i].second = (CubeDef[CubeFaces[i].p0].z + CubeDef[CubeFaces[i].p1].z + CubeDef[CubeFaces[i].p2].z + CubeDef[CubeFaces[i].p3].z) * 0.25f;
			CubePreCalc[Pre].Order[i].first = i;
		}

		for (int i = 0; i < 5; ++i)
		{
			int Min = i;

			for (int j = i + 1; j <= 5; ++j)
			{
				if (CubePreCalc[Pre].Order[j].second < CubePreCalc[Pre].Order[Min].second)
				{
					Min = j;
				}
			}
			
			struct OrderPair Temp = CubePreCalc[Pre].Order[Min];
			CubePreCalc[Pre].Order[Min] = CubePreCalc[Pre].Order[i];
			CubePreCalc[Pre].Order[i] = Temp;
		}
	}

	//
	// Init 3D starfield
	//

	// Use more stars, if a fast CPU is available...
	NumberOfStars = FastCPUFlag ? 100 : 50;

	Stars = AllocVec(sizeof(struct StarStruct) * NumberOfStars, MEMF_FAST);

	if (!Stars)
	{
		ReleaseOS();
		CleanupCopperList();
		CleanupRastPort();
		CleanupScreen();
		CloseLibraries();

		return FALSE;
	}

    for (int i = 0; i < NumberOfStars; ++i) 
    {
        Stars[i].x = XorShift32() % WIDTH - 160;
        Stars[i].y = XorShift32() % HEIGHT - 128;
        Stars[i].z = XorShift32() % 800;
    }

	//
	// Init sine scoller
	//

	// Generate sinus table
	for (int i = 0; i < 360; ++i)
	{
		YSine[i] = (int)(sin(0.05f * i) * 10.0f);
	}

	ScrollX = WIDTH;
	ScrollTextLength = strlen(ScrollText);
	ScrollCharMapLength = strlen(ScrollCharMap);
	ScrollLength = ScrollTextLength * ScrollCharWidth;

	// Generate bitmap for charmap
	ScrollFontBitMap = AllocBitMap(ScrollCharMapLength * ScrollCharWidth, ScrollCharHeight + 4, 1, BMF_STANDARD | BMF_INTERLEAVED | BMF_CLEAR, RenderPort.BitMap);

	if (!ScrollFontBitMap)
	{
		ReleaseOS();
		CleanupDemo();
		CleanupRastPort();
		CleanupScreen();
		CloseLibraries();
	}

	RenderPort.BitMap = ScrollFontBitMap;

	// Load font
	struct TextAttr ScrollFontAttrib =
	{
		"topaz.font", 
		16,
		FSF_BOLD,
		0
	};

	struct TextFont* ScrollFont = NULL;
	struct TextFont* OldFont = NULL;

	if (ScrollFont = OpenDiskFont(&ScrollFontAttrib))
   	{
    	// Save current font
		OldFont = RenderPort.Font;
		// Set new font
     	SetFont(&RenderPort, ScrollFont);
	}

	// Draw charmap
	SetAPen(&RenderPort, 1);
	Move(&RenderPort, 0, ScrollCharHeight);
	Text(&RenderPort, ScrollCharMap, ScrollCharMapLength);

	// Load old font
	SetFont(&RenderPort, OldFont);
    CloseFont(ScrollFont);
	
	return TRUE;
}

void CleanupDemo()
{
	if (Stars)
	{
		FreeVec(Stars);
	}

	if (ScrollFontBitMap)
	{
		FreeBitMap(ScrollFontBitMap);
	}
}

void DrawDemo()
{
	// Clear background
	SetRast(&RenderPort, 0);

	const int WidthMid = WIDTH >> 1;
	const int HeightMid = HEIGHT >> 1;

	//
	// Starfield
	//

	// Since we use only bitplane 0 for the starfield, we enable only bitplane 0
	// Bitmap.Planes[0] = Bit 0
	// Bitmap.Planes[1] = Bit 1
	// ...
	// To enable bitplane 0 only set the mask as follows:
	// 00000001 = Hex 0x01
	//
	// Another example: Enable only bitplanes 1 and 2:
	// 11111110 = Hex 0xFE

	SetWrMsk(&RenderPort, 0x01);
	SetAPen(&RenderPort, 1);

	for (int i = 0; i < NumberOfStars; ++i)
	{
		Stars[i].z -= 10;
	
		if (Stars[i].z <= 1) 
		{
			Stars[i].z = 800;
		}
		
		const int x = (Stars[i].x << 8) / Stars[i].z + WidthMid;
		const int y = (Stars[i].y << 8) / Stars[i].z + HeightMid;
		
		if ((unsigned int)x < WIDTH && (unsigned int)y < HEIGHT)
		{
			WritePixel(&RenderPort, x, y);
		}
	}

	// Re-enable all bitplanes
	SetWrMsk(&RenderPort, -1);

	//
	// Sine scroller
	//

	for (int i = 0, XPos = ScrollX; i < ScrollTextLength; ++i)
	{
		for (int j = 0, CharX = 0; j < ScrollCharMapLength; ++j)
		{
			if (*(ScrollText + i) == *(ScrollCharMap + j))
			{
				for (int x1 = 0, x = CharX; x < CharX + ScrollCharWidth; ++x1, ++x)
				{
					const int TempPosX = XPos + x1;

					if ((unsigned int)TempPosX < WIDTH)
					{
						BltBitMap(ScrollFontBitMap, x, 0, RenderPort.BitMap, TempPosX, 200 + YSine[TempPosX], 1, ScrollCharHeight + 4, 0xC0, 0x01, NULL);
					}
				}

				break;
			}

			CharX += ScrollCharWidth;
		}

		if (XPos >= WIDTH)
		{
			break;
		}

		XPos += ScrollCharWidth;
	}

	ScrollX -= 5;

	if (ScrollX < -ScrollLength)
	{
		ScrollX = WIDTH;
	}

	//
	// Vector Cube
	//

	const int CubeFacesColors[] ={ 2, 3, 4, 5, 6, 7 };
	
	// Since we see only the three faces on top, we only need to render these (3, 4 and 5)
	for (int i = 3; i < 6; ++i)
	{
		SetAPen(&RenderPort, CubeFacesColors[CubePreCalc[VCCount].Order[i].first]);

		AreaMove(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p0].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p1].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p2].y);
		AreaDraw(&RenderPort, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].x, CubePreCalc[VCCount].Cube[CubeFaces[CubePreCalc[VCCount].Order[i].first].p3].y);

		AreaEnd(&RenderPort);
	}

	if (++VCCount >= 90)
	{
		VCCount = 0;
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

	// Check which CPU is used in your Amiga (or UAE...)
	// Depening on this, we use more or less stars (or effects in the near future...)
	CheckCPU();

	// Gain control over the OS
	TakeOverOS();
	
	// Setup screen
	if (!CreateScreen())
    {
        return 20;
    }

    // Init the RenderPort (=Rastport)
	// We need to init some buffers for Area operations
	// Since our demo part draws some cube surfaces which are made out of 4 vertices, we choose 5 (4 + 1 for safety)
	if (!CreateRastPort(5, WIDTH, HEIGHT))
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

	// Init all demo effects
	if (!InitDemo())
	{
		return 20;
	}

    // This is our main loop
    // Call "DoubleBuffering" with the name of function you want to use...
	DoubleBuffering(DrawDemo);

	// Cleanup everything
	ReleaseOS();
	CleanupDemo();
	CleanupCopperList();
	CleanupRastPort();
	CleanupScreen();
	CloseLibraries();
	return 0;
}