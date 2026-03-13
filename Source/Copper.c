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

#define WIDTH				320
#define HEIGHT 				255
#define UPPERBORDERLINE		50
#define LOWERBORDERLINE		255

#define NUMBEROFBITPLANES	4

UWORD* CopperList = NULL;
UWORD CopperbarStart = 0;

// Bar sizes
#define BAR_FULL 32
#define BAR_SMALL 16

// Bar region (scanlines where copperbars can appear)
#define BAR_REGION_START (UPPERBORDERLINE + 1)
#define BAR_REGION_LINES 203

// Three copperbar palettes: purple, red, green (32 colors each, symmetric gradient)
static UWORD BarColors[3][BAR_FULL] =
{
	// Purple
	{
		0x604, 0x605, 0x606, 0x607, 0x617, 0x618, 0x619, 0x629,
		0x72A, 0x73B, 0x74B, 0x74C, 0x75D, 0x76E, 0x77E, 0x88F,
		0x88F, 0x77E, 0x76E, 0x75D, 0x74C, 0x74B, 0x73B, 0x72A,
		0x629, 0x619, 0x618, 0x617, 0x607, 0x606, 0x605, 0x604
	},
	// Red
	{
		0x200, 0x300, 0x400, 0x500, 0x610, 0x720, 0x830, 0x940,
		0xA50, 0xB60, 0xC70, 0xD80, 0xE90, 0xEA0, 0xFB0, 0xFC5,
		0xFC5, 0xFB0, 0xEA0, 0xE90, 0xD80, 0xC70, 0xB60, 0xA50,
		0x940, 0x830, 0x720, 0x610, 0x500, 0x400, 0x300, 0x200
	},
	// Green
	{
		0x020, 0x030, 0x040, 0x050, 0x061, 0x072, 0x083, 0x094,
		0x0A5, 0x0B6, 0x0C7, 0x0D8, 0x1E9, 0x2EA, 0x3FB, 0x5FC,
		0x5FC, 0x3FB, 0x2EA, 0x1E9, 0x0D8, 0x0C7, 0x0B6, 0x0A5,
		0x094, 0x083, 0x072, 0x061, 0x050, 0x040, 0x030, 0x020
	}
};

// Phase offsets for orbiting (120 degrees apart in 192-entry sine table)
#define PHASE_1 64
#define PHASE_2 128

// Sine table for smooth bounce movement (192 entries)
// One full bounce cycle (top -> bottom -> top) over 192 frames (~3.84s at 50Hz)
// pos = 51 + sin(i * pi / 191) * 171
#define SINTAB_SIZE 192
#define SINTAB_MASK (SINTAB_SIZE - 1)
static UWORD SineTab[SINTAB_SIZE] =
{
	 51,  54,  57,  59,  62,  65,  68,  71,
	 73,  76,  79,  82,  85,  87,  90,  93,
	 95,  98, 101, 104, 106, 109, 112, 114,
	117, 119, 122, 124, 127, 130, 132, 134,
	137, 139, 142, 144, 146, 149, 151, 153,
	156, 158, 160, 162, 164, 166, 168, 170,
	172, 174, 176, 178, 180, 182, 184, 185,
	187, 189, 190, 192, 194, 195, 197, 198,
	200, 201, 202, 204, 205, 206, 207, 208,
	209, 210, 211, 212, 213, 214, 215, 216,
	216, 217, 218, 218, 219, 219, 220, 220,
	221, 221, 221, 222, 222, 222, 222, 222,
	222, 222, 222, 222, 222, 221, 221, 221,
	220, 220, 219, 219, 218, 218, 217, 216,
	216, 215, 214, 213, 212, 211, 210, 209,
	208, 207, 206, 205, 204, 202, 201, 200,
	198, 197, 195, 194, 192, 190, 189, 187,
	185, 184, 182, 180, 178, 176, 174, 172,
	170, 168, 166, 164, 162, 160, 158, 156,
	153, 151, 149, 146, 144, 142, 139, 137,
	134, 132, 130, 127, 124, 122, 119, 117,
	114, 112, 109, 106, 104, 101,  98,  95,
	 93,  90,  87,  85,  82,  79,  76,  73,
	 71,  68,  65,  62,  59,  57,  54,  51
};

// Animation state
static UBYTE SinIndex = 0;

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

// 2D RGB plasma: per-component sine tables (64-entry period, doubled to 128)
#define PLASMA_COLS 40
#define LINE_WORDS (2 + 2 + 2 * PLASMA_COLS + 2)

static UWORD CompR[128] =
{
	0x0800,0x0800,0x0900,0x0A00,0x0A00,0x0B00,0x0C00,0x0C00,
	0x0D00,0x0D00,0x0E00,0x0E00,0x0E00,0x0F00,0x0F00,0x0F00,
	0x0F00,0x0F00,0x0F00,0x0F00,0x0E00,0x0E00,0x0E00,0x0D00,
	0x0D00,0x0C00,0x0C00,0x0B00,0x0A00,0x0A00,0x0900,0x0800,
	0x0800,0x0700,0x0600,0x0500,0x0500,0x0400,0x0300,0x0300,
	0x0200,0x0200,0x0100,0x0100,0x0100,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0100,0x0100,0x0100,0x0200,
	0x0200,0x0300,0x0300,0x0400,0x0500,0x0500,0x0600,0x0700,
	0x0800,0x0800,0x0900,0x0A00,0x0A00,0x0B00,0x0C00,0x0C00,
	0x0D00,0x0D00,0x0E00,0x0E00,0x0E00,0x0F00,0x0F00,0x0F00,
	0x0F00,0x0F00,0x0F00,0x0F00,0x0E00,0x0E00,0x0E00,0x0D00,
	0x0D00,0x0C00,0x0C00,0x0B00,0x0A00,0x0A00,0x0900,0x0800,
	0x0800,0x0700,0x0600,0x0500,0x0500,0x0400,0x0300,0x0300,
	0x0200,0x0200,0x0100,0x0100,0x0100,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0100,0x0100,0x0100,0x0200,
	0x0200,0x0300,0x0300,0x0400,0x0500,0x0500,0x0600,0x0700
};

static UWORD CompG[128] =
{
	0x0080,0x0080,0x0090,0x00A0,0x00A0,0x00B0,0x00C0,0x00C0,
	0x00D0,0x00D0,0x00E0,0x00E0,0x00E0,0x00F0,0x00F0,0x00F0,
	0x00F0,0x00F0,0x00F0,0x00F0,0x00E0,0x00E0,0x00E0,0x00D0,
	0x00D0,0x00C0,0x00C0,0x00B0,0x00A0,0x00A0,0x0090,0x0080,
	0x0080,0x0070,0x0060,0x0050,0x0050,0x0040,0x0030,0x0030,
	0x0020,0x0020,0x0010,0x0010,0x0010,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0010,0x0010,0x0010,0x0020,
	0x0020,0x0030,0x0030,0x0040,0x0050,0x0050,0x0060,0x0070,
	0x0080,0x0080,0x0090,0x00A0,0x00A0,0x00B0,0x00C0,0x00C0,
	0x00D0,0x00D0,0x00E0,0x00E0,0x00E0,0x00F0,0x00F0,0x00F0,
	0x00F0,0x00F0,0x00F0,0x00F0,0x00E0,0x00E0,0x00E0,0x00D0,
	0x00D0,0x00C0,0x00C0,0x00B0,0x00A0,0x00A0,0x0090,0x0080,
	0x0080,0x0070,0x0060,0x0050,0x0050,0x0040,0x0030,0x0030,
	0x0020,0x0020,0x0010,0x0010,0x0010,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0010,0x0010,0x0010,0x0020,
	0x0020,0x0030,0x0030,0x0040,0x0050,0x0050,0x0060,0x0070
};

static UWORD CompB[128] =
{
	0x0008,0x0008,0x0009,0x000A,0x000A,0x000B,0x000C,0x000C,
	0x000D,0x000D,0x000E,0x000E,0x000E,0x000F,0x000F,0x000F,
	0x000F,0x000F,0x000F,0x000F,0x000E,0x000E,0x000E,0x000D,
	0x000D,0x000C,0x000C,0x000B,0x000A,0x000A,0x0009,0x0008,
	0x0008,0x0007,0x0006,0x0005,0x0005,0x0004,0x0003,0x0003,
	0x0002,0x0002,0x0001,0x0001,0x0001,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0001,0x0001,0x0001,0x0002,
	0x0002,0x0003,0x0003,0x0004,0x0005,0x0005,0x0006,0x0007,
	0x0008,0x0008,0x0009,0x000A,0x000A,0x000B,0x000C,0x000C,
	0x000D,0x000D,0x000E,0x000E,0x000E,0x000F,0x000F,0x000F,
	0x000F,0x000F,0x000F,0x000F,0x000E,0x000E,0x000E,0x000D,
	0x000D,0x000C,0x000C,0x000B,0x000A,0x000A,0x0009,0x0008,
	0x0008,0x0007,0x0006,0x0005,0x0005,0x0004,0x0003,0x0003,
	0x0002,0x0002,0x0001,0x0001,0x0001,0x0000,0x0000,0x0000,
	0x0000,0x0000,0x0000,0x0000,0x0001,0x0001,0x0001,0x0002,
	0x0002,0x0003,0x0003,0x0004,0x0005,0x0005,0x0006,0x0007
};

static UBYTE PlasmaFrameCommon = 0;
static UBYTE PlasmaFrameRed = 0;
static UBYTE PlasmaFrameGreen = 90;
static UBYTE PlasmaFrameBlue = 60;

BOOL Init_CopperList(void)
{
	const UWORD CopperListLength = 30 + (BAR_REGION_LINES * LINE_WORDS) + 20;

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
	CopperbarStart = Index;

	for (UWORD i = 0; i < BAR_REGION_LINES; ++i)
	{
		// Pre-color: set COLOR00 before WAIT so left border has correct color
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x000;

		// WAIT with 4px dithering between even/odd lines
		UWORD h = (i & 1) ? 0x41 : 0x3F;
		CopperList[Index++] = ((BAR_REGION_START + i) << 8) | h;
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

void Update_Copperbar(void)
{
	// Pre-compute copperbar positions and heights
	UWORD BarPos[3];
	UBYTE BarHeight[3];
	UBYTE BarColorOff[3];

	UBYTE si0 = SinIndex;
	UBYTE si1 = (SinIndex + PHASE_1) % SINTAB_SIZE;
	UBYTE si2 = (SinIndex + PHASE_2) % SINTAB_SIZE;

	BarPos[0] = SineTab[si0];
	BarPos[1] = SineTab[si1];
	BarPos[2] = SineTab[si2];

	for (UBYTE i = 0; i < 3; ++i)
	{
		BarHeight[i] = BAR_SMALL + (UBYTE)(((BarPos[i] - BAR_REGION_START) * 3) >> 5);
		BarColorOff[i] = (BAR_FULL - BarHeight[i]) >> 1;
	}

	// Sort by Y (painter's algorithm: back-to-front)
	UBYTE Order[3];
	Order[0] = 0;
	Order[1] = 1;
	Order[2] = 2;

	if (BarPos[Order[0]] > BarPos[Order[1]])
	{
		UBYTE t = Order[0]; Order[0] = Order[1]; Order[1] = t;
	}

	if (BarPos[Order[1]] > BarPos[Order[2]])
	{
		UBYTE t = Order[1]; Order[1] = Order[2]; Order[2] = t;
	}

	if (BarPos[Order[0]] > BarPos[Order[1]])
	{
		UBYTE t = Order[0]; Order[0] = Order[1]; Order[1] = t;
	}

	// Single merged pass: plasma + copperbars top-to-bottom
	// Writing each line before the beam reaches it avoids race conditions
	for (UWORD row = 0; row < BAR_REGION_LINES; ++row)
	{
		UWORD *lineBase = &CopperList[CopperbarStart + row * LINE_WORDS];
		UWORD *cop = lineBase + 5;
		UWORD absLine = BAR_REGION_START + row;

		// Check if any copperbar covers this line (back-to-front, last wins)
		UBYTE isSolid = 0;
		UWORD solidColor = 0;

		for (UBYTE b = 0; b < 3; ++b)
		{
			const UBYTE bi = Order[b];
			const UWORD pos = BarPos[bi];
			const UBYTE h = BarHeight[bi];

			if (absLine == pos - 1 || absLine == pos + h)
			{
				isSolid = 1;
				solidColor = 0x000;
			}
			else if (absLine >= pos && absLine < pos + h)
			{
				isSolid = 1;
				solidColor = BarColors[bi][BarColorOff[bi] + (absLine - pos)];
			}
		}

		if (isSolid)
		{
			// Pre-color (left border) and trailing (right border)
			lineBase[1] = solidColor;
			for (UBYTE j = 0; j < PLASMA_COLS; ++j) { *cop = solidColor; cop += 2; }
			*cop = solidColor;
		}
		else
		{
			UBYTE common = PlasmaSin[(UBYTE)(row * 3 + PlasmaFrameCommon)] >> 2;
			UBYTE r_off = (PlasmaSin[(UBYTE)(row * 2 + PlasmaFrameRed)] + common) & 63;
			UBYTE g_off = (PlasmaSin[(UBYTE)(row * 5 + PlasmaFrameGreen)] + common) & 63;
			UBYTE b_off = (PlasmaSin[(UBYTE)(row * 11 + PlasmaFrameBlue)] + common) & 63;

			UWORD *rv = &CompR[r_off];
			UWORD *gv = &CompG[g_off];
			UWORD *bv = &CompB[b_off];

			// Pre-color: first column color for left border
			lineBase[1] = *rv | *gv | *bv;

			for (UBYTE j = 0; j < PLASMA_COLS; ++j)
			{
				*cop = *rv++ | *gv++ | *bv++;
				cop += 2;
			}

			// Trailing: last column color for right border
			*cop = *(rv - 1) | *(gv - 1) | *(bv - 1);
		}
	}

	PlasmaFrameCommon += 1;
	PlasmaFrameRed += 3;
	PlasmaFrameGreen += 2;
	PlasmaFrameBlue += 5;

	if (++SinIndex >= SINTAB_SIZE) SinIndex = 0;
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
		Update_Copperbar();
	}

	// Cleanup everything
	Cleanup_CopperList();
	lwmf_CleanupAll();
	return 0;
}