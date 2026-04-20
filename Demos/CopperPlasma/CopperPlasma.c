//**********************************************************************
//* Copper plasma effect                                               *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_CopperPlasma.cmd                                              *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// =====================================================================
// Copper
// =====================================================================

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD PlasmaStart = 0;
static ULONG PlasmaColorLUT[256];

// Layout: 63 + 1 + 128 + 1 + 63 = 256
#define WHITE_LINE_1        63
#define PLASMA_START_LINE   64
#define PLASMA_LINES        128
#define WHITE_LINE_2        192

#define PLASMA_COLS             40
#define PLASMA_COLS_PER_BLOCK   8
#define PLASMA_BLOCKS           (PLASMA_COLS / PLASMA_COLS_PER_BLOCK)
#define LINE_WORDS              (2 + 2 + 2 * PLASMA_COLS + 2)

// VPOS offset for PAL display (first visible Line = $2C = 44)
#define VPOS_OFFSET     		0x2C

// VPOS helpers
#define WHITE1_VPOS         	(VPOS_OFFSET + WHITE_LINE_1)
#define PLASMA_VPOS_START   	(VPOS_OFFSET + PLASMA_START_LINE)
#define WHITE2_VPOS         	(VPOS_OFFSET + WHITE_LINE_2)

// Copper list size:
// COPPERWORDS: DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0=10, COLOR00 pre-set=2, White1 WAIT+COLOR=4,
//              Plasma-start WAIT+COLOR=4, White2 WAIT+COLOR=4, footer VPOS-wrap+END=4 => 28 words
#define COPPERWORDS            28

void Init_CopperList(void)
{
	const ULONG CopperListLength = COPPERWORDS + (PLASMA_LINES * LINE_WORDS);

	CopperListSize = CopperListLength * sizeof(UWORD);
	CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

	UWORD Index = 0;

	// DIWSTRT = $2C81: VSTART=$2C (line 44, first visible PAL line), HSTART=$81 (lores left edge)
	CopperList[Index++] = 0x8E;
	CopperList[Index++] = 0x2C81;

	// DIWSTOP = $2CC1: VSTOP=$12C (line 300, lower 8 bits=$2C stored), HSTOP=$C1 (lores right edge)
	// Together with DIWSTRT this defines the standard PAL 320x256 display window
	CopperList[Index++] = 0x90;
	CopperList[Index++] = 0x2CC1;

	// DDFSTRT = $0038: DMA fetch starts at CCK $38; lores canonical value
	CopperList[Index++] = 0x92;
	CopperList[Index++] = 0x0038;

	// DDFSTOP = $00D0: DMA fetch ends at CCK $D0; ($D0-$38)/8+1 = 20 fetches x 16px = 320px lores
	CopperList[Index++] = 0x94;
	CopperList[Index++] = 0x00D0;

	// BPLCON0 = $0200: BPU=0 (no bitplanes), bit 9 (COLOR enable) set, HIRES=0 (lores), LACE=0
	// Pure Copper-driven display — no bitplane DMA active
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x0200;

	// Set background color to dark blue
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x003;

	// --- White Line 1
	// WAIT HP=$07 (fires at start of line), mask $FFFE (BFD=1, ignore blitter, compare all VP/HP bits)
	CopperList[Index++] = (WHITE1_VPOS << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;

	// --- Per-scanline plasma region ---
	// Initial WAIT at plasma start line + set COLOR00=black as baseline before first plasma row
	CopperList[Index++] = (PLASMA_VPOS_START << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x000;

	PlasmaStart = Index;

	for (UWORD i = 0; i < PLASMA_LINES; ++i)
	{
		// Pre-WAIT COLOR00: sets background color for the left border before the WAIT fires
		CopperList[Index++] = 0x180;
		CopperList[Index++] = 0x000;

		// WAIT: HP=odd $41 / even $3F — 2 color-clock offset between lines for sub-pixel dithering
		// mask $FFFE: BFD=1 (don't wait for blitter), compare all VP and HP bits
		UWORD h = (i & 1) ? 0x41 : 0x3F;
		CopperList[Index++] = ((PLASMA_VPOS_START + i) << 8) | h;
		CopperList[Index++] = 0xFFFE;

		// 40 x MOVE COLOR00: one color change per 8-pixel lores column = 320px wide plasma strip
		for (UWORD j = 0; j < PLASMA_COLS; ++j)
		{
			CopperList[Index++] = 0x180;
			CopperList[Index++] = 0x000;
		}

		// End-of-line WAIT at HP=$DF (HPOS=$DE=222, safely right of the 320px visible area)
		// Prevents the next row's pre-WAIT COLOR00 from leaking into the current line's right border
		CopperList[Index++] = ((PLASMA_VPOS_START + i) << 8) | 0xDF;
		CopperList[Index++] = 0xFFFE;
	}

	// --- White Line 2
	CopperList[Index++] = (WHITE2_VPOS << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0xFFF;

 	// Set color to dark blue
	CopperList[Index++] = ((WHITE2_VPOS + 1) << 8) | 0x07;
	CopperList[Index++] = 0xFFFE;
	CopperList[Index++] = 0x180;
	CopperList[Index++] = 0x003;

	// Copper list end: $FFFF/$FFFE — Copper halts until COP1LC is reloaded on next VBlank
	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;
}

// =====================================================================
// Plasma
// =====================================================================

// Sine table, used by the plasma
// 256 entries, values 0..63, one full period
static const UBYTE SinTab256[256] =
{
	32,32,33,34,35,35,36,37,38,38,39,40,41,41,42,43,44,44,45,46,46,47,48,48,49,50,50,51,51,52,53,53,
	54,54,55,55,56,56,57,57,58,58,59,59,59,60,60,60,61,61,61,61,62,62,62,62,62,63,63,63,63,63,63,63,
	63,63,63,63,63,63,63,63,62,62,62,62,62,61,61,61,61,60,60,60,59,59,59,58,58,57,57,56,56,55,55,54,
	54,53,53,52,51,51,50,50,49,48,48,47,46,46,45,44,44,43,42,41,41,40,39,38,38,37,36,35,35,34,33,32,
	32,31,30,29,28,28,27,26,25,25,24,23,22,22,21,20,19,19,18,17,17,16,15,15,14,13,13,12,12,11,10,10,
	 9, 9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0,
	 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9,
	 9,10,10,11,12,12,13,13,14,15,15,16,17,17,18,19,19,20,21,22,22,23,24,25,25,26,27,28,28,29,30,31
};

static void Init_Plasma(void)
{
	// 2D RGB plasma: base table (64-entry period, doubled to 128)
	const UBYTE CompBase[128] =
	{
		8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
		8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7,
		8, 8, 9,10,10,11,12,12,13,13,14,14,14,15,15,15,15,15,15,15,14,14,14,13,13,12,12,11,10,10, 9, 8,
		8, 7, 6, 5, 5, 4, 3, 3, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 3, 3, 4, 5, 5, 6, 7
	};

	for (UWORD i = 0; i < 256; ++i)
	{
		const UBYTE r = CompBase[i & 127];
		const UBYTE g = CompBase[(i + 43) & 127];
		const UBYTE b = CompBase[(i + 85) & 127];
		PlasmaColorLUT[i] = 0x01800000UL | ((ULONG)r << 8) | ((ULONG)g << 4) | b;
	}
}

void Update_Plasma(void)
{
	static UBYTE Phase1 = 0;
	// Interlaced row update: process only even or odd rows per frame.
	// Each row is refreshed at 25 Hz instead of 50 Hz, halving the number of
	// Chip RAM writes per frame.
	// The Phase2 value computed for each processed row is identical to the
	// non-interlaced version, so visual quality is preserved.
	static UBYTE RowToggle = 0;

	// Start p at the phase that corresponds to the first processed row
	// (RowToggle=0 → row 0, RowToggle=1 → row 1); since p = Phase1 + row
	// in both cases this keeps the per-row color identical to the original.
	UBYTE p = Phase1 + RowToggle;
	UWORD *lineBase = &CopperList[PlasmaStart] + RowToggle * LINE_WORDS;

	UBYTE count = PLASMA_LINES / 2;
	do
	{
		UBYTE Phase2_base = (UBYTE)(SinTab256[p] + SinTab256[(UBYTE)(p + 90)] + Phase1);

		// Write pre-WAIT COLOR00 first — Copper reads this before the WAIT fires
		*(ULONG *)(void *)lineBase = PlasmaColorLUT[Phase2_base];

		// Write column COLOR00 moves RIGHT TO LEFT (column 39 first, column 0 last).
		// The Copper scans columns left to right; writing right-to-left means the CPU
		// always writes a column before the Copper reads it, eliminating the race
		// condition that causes black stripes on the right side of each plasma row.
		// Phase2 values per column are identical to the left-to-right order — no visual change.
		ULONG *lcop = (ULONG *)(void *)(lineBase + 4) + (PLASMA_COLS - 1);
		UBYTE ph = (UBYTE)(Phase2_base + PLASMA_COLS); // Phase2 value for rightmost column

		UBYTE blocks = PLASMA_BLOCKS;
		do
		{
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
			*lcop-- = PlasmaColorLUT[ph--];
		} while (--blocks);

		p        += 2;
		lineBase += 2 * LINE_WORDS;
	} while (--count);

	RowToggle ^= 1;
	++Phase1;
}

// =====================================================================
// Cleanup & Main
// =====================================================================

void Cleanup_All(void)
{
	FreeMem(CopperList, CopperListSize);
	lwmf_CleanupAll();
}

int main()
{
	lwmf_LoadGraphicsLib();
	Init_CopperList();
	Init_Plasma();

	lwmf_TakeOverOS();

	while (*CIAA_PRA & 0x40)
	{
		lwmf_WaitVertBlank();
		Update_Plasma();
	}

	Cleanup_All();
	return 0;
}