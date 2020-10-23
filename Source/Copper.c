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

const ULONG WIDTH = 320;
const ULONG HEIGHT = 256;

//***************************************************************
// Demo stuff                                                   *
//***************************************************************

BOOL InitCopperList(void);
void LoadCopperList(void);
void CleanupCopperList(void);

UWORD* CopperList;

BOOL InitCopperList(void)
{
	// NumberOfColors * 2 + Init & End + some spare
	const UWORD CopperListLength = 25 + (32 * 2);

	if (!(CopperList = (UWORD *) AllocVec(CopperListLength * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	return TRUE;
}

void LoadCopperList(void)
{
	const UWORD Colors[] =
	{
		0x0604, 0x0605, 0x0606, 0x0607, 0x0617, 0x0618, 0x0619,	0x0629, 
		0x072A, 0x073B, 0x074B, 0x074C, 0x075D, 0x076E,	0x077E, 0x088F, 
		0x07AF, 0x06CF, 0x05FF, 0x04FB, 0x04F7,	0x03F3, 0x07F2, 0x0BF1, 
		0x0FF0, 0x0FC0, 0x0EA0, 0x0E80,	0x0E60, 0x0D40, 0x0D20, 0x0D00
	};

	// Copper init

	int Index = 0;

	// Slow fetch mode (needed for AGA compatibility)
	CopperList[Index++] = 0x1FC;
	CopperList[Index++] = 0;

	// BPLCON0 Set 4 bitplanes (0100001000000000)
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x4200;

	// BPLCON1 no scrolling
	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;

	// BPLCON2
	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x000F;

	// BPL1MOD Two byte between bitplanes
	CopperList[Index++] = 0x108;
	CopperList[Index++] = 0x0002;

	// BPL2MOD Two byte between bitplanes
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = 0x0002;

	// Display window top/left (PAL DIWSTRT)
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = 0x2C81;

	// Display window bottom/right (PAL DIWSTOP)
	CopperList[Index++] = 0x90;
	CopperList[Index++] = 0x2CC1;

	// Display data fetch start (horizontal position)
	CopperList[Index++] = 0x92;
	CopperList[Index++] = 0x38;

	// Display data fetch stop (horizontal position)
	CopperList[Index++] = 0x94;
	CopperList[Index++] = 0xD0;

	for (int i = 0, Temp = HEIGHT >> 5; i < 32; ++i)
	{
		// WAIT
		CopperList[Index++] = ((i * Temp) << 8) + 7;
		CopperList[Index++] = 0xFFFE;
		// CMOVE
		// Write Colors[i] into color register 0x180 (COLOR00)
		CopperList[Index++] = 0x180;
		CopperList[Index++] = Colors[i];
	}

	// Copper list end
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;
}

void CleanupCopperList(void)
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
	if (!InitCopperList())
	{
		return 20;
	}

	LoadCopperList();

    // Wait until mouse button is pressed...
	while (*CIAA_PRA & PRA_FIR0)
	{
		*COP1LC = (ULONG)CopperList;
	}

	// Cleanup everything
	CleanupCopperList();
	lwmf_CleanupAll();
	return 0;
}