//**********************************************************************
//* Simple copper demo for Amiga with at least OS 3.0           	   *
//*														 			   *
//* (C) 2020-2021 by Stefan Kubsch                        			   *
//* Project for vbcc	                                 			   *
//*                                                      			   *
//* Compile & link with:                                 			   *
//* make_Copper.cmd							          	     		   *
//*                                                      			   *
//* Quit with mouse click                                  			   *
//**********************************************************************

// Include our own header files
#include "lwmf/lwmf.h"

//
// Screen settings
//

#define WIDTH				320
#define HEIGHT 				255
#define UPPERBORDERLINE		50
#define LOWERBORDERLINE		255

#define NUMBEROFBITPLANES	4

UWORD* CopperList = NULL;
UWORD CopperbarStart = 0;

const UWORD CopperbarColors[] =
{
	0x604, 0x605, 0x606, 0x607, 0x617, 0x618, 0x619, 0x629, 
	0x72A, 0x73B, 0x74B, 0x74C, 0x75D, 0x76E, 0x77E, 0x88F,
	0x88F, 0x77E, 0x76E, 0x75D, 0x74C, 0x74B, 0x73B, 0x72A,
	0x629, 0x619, 0x618, 0x617, 0x607, 0x606, 0x605, 0x604
};

BOOL Init_CopperList(void)
{
	// Number of CopperbarColors * 4 + init + end + spare
	const UWORD CopperListLength = (32 << 2) + 100;

	if (!(CopperList = (UWORD*)AllocVec(CopperListLength * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	// Copper init

	UWORD Index = 0;

	// Slow fetch mode (needed for AGA compatibility)
	CopperList[Index++] = 0x1FC;
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
	// BPLCON1 Scroll register (and playfield pri)
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
	// BPLCON0
	// 4 bitplanes
	// Lores
	// composite video color-burst enabled
	// 0100001000000000 = 0x4200
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x4200;

	// Init background

	static UWORD CopperbarPos = UPPERBORDERLINE + 1;

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

	// Reserve space for Copperbar
	CopperList[Index++] = (CopperbarPos << 8) + 7;
	CopperList[Index++] = 0xFFFE;

	CopperbarStart = Index;

	for (UBYTE i = 0; i < 32; ++i)
	{
		CopperList[Index++] = ((CopperbarPos + i) << 8) + 7;
		CopperList[Index++] = 0xFFFE;
		
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x003;
	}

	// Blue
	CopperList[Index++] = ((CopperbarPos + 32) << 8) + 7;
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

	// VPOS can be > 255
	CopperList[Index++] = 0xFFDF;
	CopperList[Index++] = 0xFFFE;

	// Copper list end
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;

	return TRUE;
}

void Update_Copperbar(void)
{
	static UWORD CopperbarPos = UPPERBORDERLINE + 1;
	static BYTE CopperbarSpeed = 4;
	UWORD Index = CopperbarStart;

	for (UBYTE i = 0; i < 32; ++i)
	{
		CopperList[Index++] = ((CopperbarPos + i) << 8) + 7;
		CopperList[Index++] = 0xFFFE;
		
		CopperList[Index++] = 0x180;
		CopperList[Index++] = CopperbarColors[i];
	}

	CopperbarPos += CopperbarSpeed;

	if (CopperbarPos >= LOWERBORDERLINE - 32)
	{
		CopperbarSpeed *= -1;
	}

	if (CopperbarPos <= UPPERBORDERLINE)
	{
		CopperbarSpeed *= -1;
	}
}

void Cleanup_CopperList(void)
{
	if (CopperList)
	{
		FreeVec(CopperList);
	}
}

int main()
{
	// Load libraries
	// Exit with SEVERE Error (20) if something goes wrong
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	// Gain control over the OS
	lwmf_TakeOverOS();
	
	// Init and load copperlist & screen
	if (!Init_CopperList())
	{
		lwmf_CleanupAll();
		return 20;
	}

	OwnBlitter();

	// Wait until mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		lwmf_WaitVertBlank();
		Update_Copperbar();
	}

	// Cleanup everything
	DisownBlitter();
	Cleanup_CopperList();
	lwmf_CleanupAll();
	return 0;
}