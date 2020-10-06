//********************************************************
//* Simple demo for Amiga                                *
//*                                                      *
//* (C) 2020 by Stefan Kubsch                            *
//* Project for vbcc 0.9g                                *
//*                                                      *
//* Compile & link with:                                 *
//* vc -O4 Demo.c -o Demo -lmieee -lamiga                *
//*                                                      *
//* Quit with Ctrl-C                                     *
//********************************************************

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/graphics.h>
#include <proto/intuition.h>
#include <math.h>
#include <stdlib.h>

//
// Generic stuff for screen and library handling
//

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;
struct Screen *MyScreen = NULL;

BOOL LoadLibraries();
void CloseScreenAndLibraries();
BOOL CreateScreen();
void DoubleBuffering(void(*CallFunction)(struct RastPort*));

//
// demo stuff
//

void InitDemo();
void DrawDemo(struct RastPort* RastPort);

//***************************************************************
// Functions for screen and library handling                    *
//***************************************************************

BOOL LoadLibraries()
{
    // Since we use functions that require at least Kick 2.0, we must use "37" as least version!
    if (!(GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 37)))
    {
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
    if (MyScreen)
    {
        CloseScreen(MyScreen);
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
    // Open screen with 2 bitplanes and four given colors (dark blue, white, light grey, dark grey, last color is dummy)
    struct ColorSpec ColorTable[] = { {0, 0, 0, 3}, {1, 15, 15, 15}, {2, 10, 10, 10}, {3, 4, 4, 4}, {-1, 0, 0, 0} };

    MyScreen = OpenScreenTags(NULL,
	    SA_Pens, (ULONG) ~0,
	    SA_Depth, 2,
	    SA_ShowTitle, FALSE,
	    SA_Type, CUSTOMSCREEN,
	    SA_Colors, (long) ColorTable,
	    TAG_DONE
    );

    if (!MyScreen)
    {
        CloseScreenAndLibraries();
        return FALSE;
    }

    return TRUE;
}

void DoubleBuffering(void(*CallFunction)(struct RastPort*))
{
    struct ScreenBuffer *Buffer[2] = { AllocScreenBuffer(MyScreen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(MyScreen, NULL, SB_COPY_BITMAP) };
    struct MsgPort *DisplayPort = CreateMsgPort();
    struct MsgPort *SafePort = CreateMsgPort();

    if (Buffer[0] && Buffer[1] && DisplayPort && SafePort)
    {
        struct RastPort MyRasterPort = { 0 };
        InitRastPort(&MyRasterPort);

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
                MyRasterPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
                
                //***************************************************************
                // Here we call the drawing function for demo stuff!            *
                //***************************************************************

                (*CallFunction)(&MyRasterPort);

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
                
                while (!ChangeScreenBuffer(MyScreen, Buffer[CurrentBuffer]))
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

    FreeScreenBuffer(MyScreen, Buffer[0]);
    FreeScreenBuffer(MyScreen, Buffer[1]);
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

void DrawDemo(struct RastPort* RastPort)
{
    SetRast(RastPort, 0);

    const int WidthMid = MyScreen->Width >> 1;
    const int HeightMid = MyScreen->Height >> 1;

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
        
        if ((unsigned int)x < MyScreen->Width && (unsigned int)y < MyScreen->Height)
        {
            SetAPen(RastPort, Stars[i].z / 200 + 1);
            WritePixel(RastPort, x, y);
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

    SetAPen(RastPort, 1);

    Move(RastPort, Cube[0].x, Cube[0].y);
    Draw(RastPort, Cube[1].x, Cube[1].y);
    Draw(RastPort, Cube[5].x, Cube[5].y);
    Draw(RastPort, Cube[4].x, Cube[4].y);
    Draw(RastPort, Cube[0].x, Cube[0].y);
    Draw(RastPort, Cube[2].x, Cube[2].y);
    Draw(RastPort, Cube[6].x, Cube[6].y);
    Draw(RastPort, Cube[4].x, Cube[4].y);
    
    Move(RastPort, Cube[5].x, Cube[5].y);
    Draw(RastPort, Cube[7].x, Cube[7].y);
    Draw(RastPort, Cube[3].x, Cube[3].y);
    Draw(RastPort, Cube[1].x, Cube[1].y);
    
    Move(RastPort, Cube[2].x, Cube[2].y);
    Draw(RastPort, Cube[3].x, Cube[3].y);
    Draw(RastPort, Cube[7].x, Cube[7].y);
    Draw(RastPort, Cube[6].x, Cube[6].y);
}

//***************************************************************
// Main                                                         *
//***************************************************************

int main ()
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