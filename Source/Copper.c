//**********************************************************************
//* Simple copper demo for Amiga with at least OS 3.0           	   *
//*														 			   *
//* (C) 2020 by Stefan Kubsch                            			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* vc -O4 Copper.c -o Copper -lamiga           	     			   *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

// Include our own header files
#include "lwmf/lwmf.h"

//
// Screen settings
//

#define WIDTH				320
#define HEIGHT 				256
#define UPPERBORDERLINE		50
#define LOWERBORDERLINE		255

BOOL Init_CopperList(void);
void Update_CopperList(void);
void Cleanup_CopperList(void);

UWORD* CopperList;

const UWORD Colors[] =
{
	0x0604, 0x0605, 0x0606, 0x0607, 0x0617, 0x0618, 0x0619,	0x0629, 
	0x072A, 0x073B, 0x074B, 0x074C, 0x075D, 0x076E,	0x077E, 0x088F,
	0x088F, 0x077E, 0x076E, 0x075D, 0x074C, 0x074B, 0x073B, 0x072A,
	0x0629, 0x0619, 0x0618, 0x0617, 0x0607, 0x0606, 0x0605, 0x0604
};

BOOL Init_CopperList(void)
{
	// Number Of Colors * 2 + Init & End + some spare
	const UWORD CopperListLength = 200;

	if (!(CopperList = (UWORD *) AllocVec(CopperListLength * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	return TRUE;
}

void Update_CopperList(void)
{
	static int LineCount = UPPERBORDERLINE + 1;
	static int LineAdd = 4;

	// Copper init

	int Index = 0;

	// Slow fetch mode (needed for AGA compatibility)
	CopperList[Index++] = 0x1FC;
	CopperList[Index++] = 0x0000;

	// BPLCON0
	// 4 bitplanes
	// Lores
	// composite video color-burst enabled
	// 0100001000000000 = 0x4200
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x4200;
	// BPLCON1
	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;
	// BPLCON2
	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x0000;
	// BPLCON3 (AGA sprites, palette and dualplayfield reset)
	CopperList[Index++] = 0x106;
	CopperList[Index++] = 0x0C00;

	// BPL1MOD
	CopperList[Index++] = 0x108;
	CopperList[Index++] = 0x0000;

	// BPL2MOD
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = 0x0000;

	// Display window top/left (PAL DIWSTRT)
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = 0x2C81;

	// Display window bottom/right (PAL DIWSTOP)
	CopperList[Index++] = 0x90;
	CopperList[Index++] = 0x2CC1;

	// Display data fetch start (horizontal position)
	// CopperList[Index++] = 0x92;
	// CopperList[Index++] = 0x0038;

	// Display data fetch stop (horizontal position)
	// CopperList[Index++] = 0x94;
	// CopperList[Index++] = 0x00D0;

	// Black
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;
	// White Line
	CopperList[Index++] = ((UPPERBORDERLINE - 1) << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;
	// Blue
	CopperList[Index++] = (UPPERBORDERLINE << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x003;

	// Moving Copperbar
	CopperList[Index++] = (LineCount << 8) + 7;
	CopperList[Index++] = 0xFFFE;

	for (int i = 0; i < 32; ++i)
	{
		CopperList[Index++] = ((LineCount + i) << 8) + 7;
		CopperList[Index++] = 0xFFFE;
		
		CopperList[Index++] = 0x180;
		CopperList[Index++] = Colors[i];
	}

	// Blue
	CopperList[Index++] = ((LineCount + 32) << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x003;
	// White Line
	CopperList[Index++] = ((LOWERBORDERLINE - 1) << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;
	// Black
	CopperList[Index++] = ((LOWERBORDERLINE) << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;

	// Copper list end
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;

	LineCount += LineAdd;

	if (LineCount >= LOWERBORDERLINE - 32)
	{
		LineAdd *= -1;
	}

	if (LineCount <= UPPERBORDERLINE)
	{
		LineAdd *= -1;
	}
}

void Cleanup_CopperList(void)
{
 	*COP1LC = (ULONG) ((struct GfxBase*) GfxBase)->copinit;
	
	if (CopperList)
	{
		FreeVec(CopperList);
	}
}

int main()
{
    // Load libraries
    // Exit with SEVERE Error (20) if something goes wrong
	if (!lwmf_LoadLibraries())
    {
        return 20;
    }

	// Gain control over the OS
	lwmf_TakeOverOS();
	
	// Init and load copperlist
	if (!Init_CopperList())
	{
		return 20;
	}

	Update_CopperList();

    // Wait until mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		lwmf_WaitVBeam(255);
		Update_CopperList();
	}

	// Cleanup everything
	Cleanup_CopperList();
	lwmf_CleanupAll();
	return 0;
}