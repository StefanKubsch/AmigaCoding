//**********************************************************************
//* Copper demo for Amiga with at least OS 3.0                   	   *
//*														 			   *
//* (C) 2020-2026 by Stefan Kubsch                        			   *
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

#define UPPERBORDERLINE		50
#define LOWERBORDERLINE		255

UWORD* CopperList = NULL;
UWORD PlasmaStart = 0;

// Plasma region
#define PLASMA_REGION_START (UPPERBORDERLINE + 1)
#define PLASMA_REGION_LINES 203

// Plasma background
// Wave sine table (256 entries, values 0..63)
static UBYTE PlasmaSin[256] =
{
	32,32,33,34,35,35,36,37,38,38,39,40,41,41,42,43,
	44,44,45,46,46,47,48,48,49,50,50,51,51,52,53,53,
	54,54,55,55,56,56,57,57,58,58,59,59,59,60,60,60,
	61,61,61,61,62,62,62,62,62,63,63,63,63,63,63,63,
	63,63,63,63,63,63,63,63,62,62,62,62,62,61,61,61,
	61,60,60,60,59,59,59,58,58,57,57,56,56,55,55,54,
	54,53,53,52,51,51,50,50,49,48,48,47,46,46,45,44,
	44,43,42,41,41,40,39,38,38,37,36,35,35,34,33,32,
	32,31,30,29,28,28,27,26,25,25,24,23,22,22,21,20,
	19,19,18,17,17,16,15,15,14,13,13,12,12,11,10,10,
	 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 4, 3, 3, 3,
	 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
	 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2,
	 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
	 9,10,10,11,12,12,13,13,14,15,15,16,17,17,18,19,
	19,20,21,22,22,23,24,25,25,26,27,28,28,29,30,31
};

// 2D RGB plasma: single base table (64-entry period, doubled to 128)
// R/G/B derived by shifting into the correct OCS nibble position
#define PLASMA_COLS 40
#define LINE_WORDS (2 + 2 + 2 * PLASMA_COLS + 2)

static UBYTE CompBase[128] =
{
	8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,
	15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
	 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0,
	 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7,
	 8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,
	15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
	 8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0,
	 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7
};

static UBYTE PlasmaFrameCommon = 0;
static UBYTE PlasmaFrameRed = 0;
static UBYTE PlasmaFrameGreen = 90;
static UBYTE PlasmaFrameBlue = 60;

BOOL Init_CopperList(void)
{
	const UWORD CopperListLength = 30 + (PLASMA_REGION_LINES * LINE_WORDS) + 20;

	if (!(CopperList = (UWORD*)AllocVec(CopperListLength * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

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
	// BPLCON1
	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000;
	// BPLCON2
	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x0000;
	// BPLCON3
	CopperList[Index++] = 0x106;
	CopperList[Index++] = 0x0C00;
	// BPL1MOD
	CopperList[Index++] = 0x108;
	CopperList[Index++] = 0x0000;
	// BPL2MOD
	CopperList[Index++] = 0x10A;
	CopperList[Index++] = 0x0000;
	// BPLCON0 - no bitplanes, just copper colors
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x0200;

	// Black
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;
	// White Line
	CopperList[Index++] = ((UPPERBORDERLINE - 1) << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;
	// Black before plasma
	CopperList[Index++] = (UPPERBORDERLINE << 8) + 7;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;

	// Per-scanline plasma region (40 COLOR00 MOVEs per line)
	PlasmaStart = Index;

	for (UWORD i = 0; i < PLASMA_REGION_LINES; ++i)
	{
		// Pre-color: set COLOR00 before WAIT so left border has correct color
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x000;

		// WAIT with 4px dithering between even/odd lines
		UWORD h = (i & 1) ? 0x41 : 0x3F;
		CopperList[Index++] = ((PLASMA_REGION_START + i) << 8) | h;
		CopperList[Index++] = 0xFFFE;

		for (UWORD j = 0; j < PLASMA_COLS; ++j)
		{
			CopperList[Index++] = 0x180;
			CopperList[Index++] = 0x000;
		}

		// Trailing: hold last color through right border
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x000;
	}

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

void Update_Plasma(void)
{
	UBYTE idx3 = PlasmaFrameCommon;
	UBYTE idx2 = PlasmaFrameRed;
	UBYTE idx5 = PlasmaFrameGreen;
	UBYTE idx11 = PlasmaFrameBlue;

	UWORD *lineBase = &CopperList[PlasmaStart];

	for (UWORD row = 0; row < PLASMA_REGION_LINES; ++row)
	{
		UBYTE common = PlasmaSin[idx3] >> 2;
		UBYTE r_off = (PlasmaSin[idx2] + common) & 63;
		UBYTE g_off = (PlasmaSin[idx5] + common) & 63;
		UBYTE b_off = (PlasmaSin[idx11] + common) & 63;

		UBYTE *rp = &CompBase[r_off];
		UBYTE *gp = &CompBase[g_off];
		UBYTE *bp = &CompBase[b_off];

		UWORD firstCol = ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp;
		lineBase[1] = firstCol;

		ULONG *lcop = (ULONG *)(lineBase + 4);
		UBYTE j;

		for (j = 0; j < PLASMA_COLS; j += 8)
		{
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
			*lcop++ = 0x01800000UL | ((UWORD)*rp << 8) | ((UWORD)*gp << 4) | *bp; rp++; gp++; bp++;
		}

		lineBase[LINE_WORDS - 1] = ((UWORD)*(rp - 1) << 8) | ((UWORD)*(gp - 1) << 4) | *(bp - 1);

		idx3 += 3;
		idx2 += 2;
		idx5 += 5;
		idx11 += 11;
		lineBase += LINE_WORDS;
	}

	PlasmaFrameCommon += 1;
	PlasmaFrameRed += 3;
	PlasmaFrameGreen += 2;
	PlasmaFrameBlue += 5;
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

	// Wait until mouse button is pressed...
	// PRA_FIR0 = Bit 6 (0x40)
	while (*CIAA_PRA & 0x40)
	{
		lwmf_WaitVertBlank();
		Update_Plasma();
	}

	// Cleanup everything
	Cleanup_CopperList();
	lwmf_CleanupAll();
	return 0;
}