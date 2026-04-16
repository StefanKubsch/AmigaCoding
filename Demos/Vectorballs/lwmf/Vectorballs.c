//**********************************************************************
//* Vector balls effect                                                *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Refactored for tighter A500 performance                            *
//*                                                                    *
//* Compile & link with:                                               *
//* make_VectorBalls.cmd                                               *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

extern void VB_ClearBoxBlit(__reg("a0") UBYTE* DestPlane0);
extern void VB_DrawVectorBallsBlit(__reg("a0") UBYTE* DestPlane0, __reg("a1") const UBYTE* ZOrderPtr, __reg("a2") const UWORD* DrawOffsetPtr, __reg("a3") const UBYTE* DrawShiftPtr, __reg("a4") UWORD* const * BobMaskShiftPtr, __reg("a6") UWORD* const * BobSourceShiftPtr);

// ---------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------

#define VECTORBALL_FILE      "gfx/vecball1.iff"

#define VB_NUM_BALLS         48
#define VB_BALL_SIZE         16

#define VB_CENTER_X          160
#define VB_CENTER_Y          128

// Overall perspective scale in 8.8 fixed.
// Smaller = balls closer together.
#define VB_DISPLAY_SCALE     80      /* 80/256 = 0.3125 */

// Angle increments as 8.8 phase into 256-entry LUT.
#define VB_ANGLE_INC_X       408
#define VB_ANGLE_INC_Y       326
#define VB_ANGLE_INC_Z       244

#define FIX_SHIFT            8
#define FIX_ONE              (1 << FIX_SHIFT)

#define VB_NUM_X_CLASSES     15
#define VB_NUM_Y_CLASSES      5

#define VB_BOB_WORDS         2
#define VB_BOB_ROWS          (VB_BALL_SIZE * NUMBEROFBITPLANES)
#define VB_BOB_DATA_WORDS    (VB_BOB_ROWS * VB_BOB_WORDS)

#define VB_INTERLEAVED_ROW_BYTES  (BYTESPERROW * NUMBEROFBITPLANES)

// ---------------------------------------------------------------------
// Flat point cloud ("DEEP4")
// All base Z values are 0, so the rotation can be specialized.
// ---------------------------------------------------------------------

static const BYTE VectorBallsDefX[VB_NUM_BALLS] =
{
	-9,-8,-5,-4,-3,-1,0,1,3,4,5,7,
	-9,-7,-5,-1,3,5,7,9,
	-9,-7,-5,-4,-1,0,3,4,5,7,8,9,
	-9,-7,-5,-1,3,9,
	-9,-8,-5,-4,-3,-1,0,1,3,9
};

static const BYTE VectorBallsDefY[VB_NUM_BALLS] =
{
	 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
	 1, 1, 1, 1, 1, 1, 1, 1,
	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	-1,-1,-1,-1,-1,-1,
	-2,-2,-2,-2,-2,-2,-2,-2,-2,-2
};

// ---------------------------------------------------------------------
// 256-entry sine LUT with amplitude 256 (8.8 fixed).
// cos(0) = 256 exactly, so the 5 text rows stay distinct.
// ---------------------------------------------------------------------

static const WORD SinTab256[256] =
{
	   0,    6,   13,   19,   25,   31,   38,   44,   50,   56,   62,   68,   74,   80,   86,   92,
	  98,  104,  109,  115,  121,  126,  132,  137,  142,  147,  152,  157,  162,  167,  172,  177,
	 181,  185,  190,  194,  198,  202,  206,  209,  213,  216,  220,  223,  226,  229,  231,  234,
	 237,  239,  241,  243,  245,  247,  248,  250,  251,  252,  253,  254,  255,  255,  256,  256,
	 256,  256,  256,  255,  255,  254,  253,  252,  251,  250,  248,  247,  245,  243,  241,  239,
	 237,  234,  231,  229,  226,  223,  220,  216,  213,  209,  206,  202,  198,  194,  190,  185,
	 181,  177,  172,  167,  162,  157,  152,  147,  142,  137,  132,  126,  121,  115,  109,  104,
	  98,   92,   86,   80,   74,   68,   62,   56,   50,   44,   38,   31,   25,   19,   13,    6,
	   0,   -6,  -13,  -19,  -25,  -31,  -38,  -44,  -50,  -56,  -62,  -68,  -74,  -80,  -86,  -92,
	 -98, -104, -109, -115, -121, -126, -132, -137, -142, -147, -152, -157, -162, -167, -172, -177,
	-181, -185, -190, -194, -198, -202, -206, -209, -213, -216, -220, -223, -226, -229, -231, -234,
	-237, -239, -241, -243, -245, -247, -248, -250, -251, -252, -253, -254, -255, -255, -256, -256,
	-256, -256, -256, -255, -255, -254, -253, -252, -251, -250, -248, -247, -245, -243, -241, -239,
	-237, -234, -231, -229, -226, -223, -220, -216, -213, -209, -206, -202, -198, -194, -190, -185,
	-181, -177, -172, -167, -162, -157, -152, -147, -142, -137, -132, -126, -121, -115, -109, -104,
	 -98,  -92,  -86,  -80,  -74,  -68,  -62,  -56,  -50,  -44,  -38,  -31,  -25,  -19,  -13,   -6
};

// ---------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------

struct lwmf_Image* VectorBallImg;

static UBYTE ZOrder[VB_NUM_BALLS];
static UBYTE XClass[VB_NUM_BALLS];
static UBYTE YClass[VB_NUM_BALLS];

static WORD BallZ[VB_NUM_BALLS];
static UWORD DrawOffset[VB_NUM_BALLS];
static UBYTE DrawShift[VB_NUM_BALLS];

// Unique X values present in VectorBallsDefX[]
static const BYTE XValues[VB_NUM_X_CLASSES] =
{
	-9, -8, -7, -5, -4, -3, -1, 0, 1, 3, 4, 5, 7, 8, 9
};

// Same values in 8.8 fixed for the frame contribution build-up
static const WORD XValuesFix[VB_NUM_X_CLASSES] =
{
	(WORD)(-9 * FIX_ONE), (WORD)(-8 * FIX_ONE), (WORD)(-7 * FIX_ONE),
	(WORD)(-5 * FIX_ONE), (WORD)(-4 * FIX_ONE), (WORD)(-3 * FIX_ONE),
	(WORD)(-1 * FIX_ONE), (WORD)( 0 * FIX_ONE), (WORD)( 1 * FIX_ONE),
	(WORD)( 3 * FIX_ONE), (WORD)( 4 * FIX_ONE), (WORD)( 5 * FIX_ONE),
	(WORD)( 7 * FIX_ONE), (WORD)( 8 * FIX_ONE), (WORD)( 9 * FIX_ONE)
};

// 5 Y rows (-2..2) in 8.8 fixed
static const WORD YValuesFix[VB_NUM_Y_CLASSES] =
{
	(WORD)(-2 * FIX_ONE), (WORD)(-1 * FIX_ONE), (WORD)(0 * FIX_ONE),
	(WORD)( 1 * FIX_ONE), (WORD)( 2 * FIX_ONE)
};

// Per-frame contributions of the 15 X classes
static WORD FrameXToX3[VB_NUM_X_CLASSES];
static WORD FrameXToZ[VB_NUM_X_CLASSES];

// Per-frame contributions of the 5 Y classes
static WORD FrameYToX3[VB_NUM_Y_CLASSES];
static WORD FrameYToZ[VB_NUM_Y_CLASSES];
static WORD FrameY3SinZ[VB_NUM_Y_CLASSES];
static WORD FrameY3CosZ[VB_NUM_Y_CLASSES];

// Pre-shifted, interleaved 16x16 bob source and mask data in CHIP RAM.
// Layout per shift:
//   row0 plane0, row0 plane1, ... row0 planeN,
//   row1 plane0, row1 plane1, ...
//   Each stored sub-row is exactly 2 words wide.
static UWORD* BobSourceData = NULL;
static UWORD* BobMaskData = NULL;
static UWORD* BobSourceShift[16];
static UWORD* BobMaskShift[16];

// Palette copied from the ILBM
static UWORD BallPalette[16];

static UWORD AngleX = 0;
static UWORD AngleY = 0;
static UWORD AngleZ = 0;

// ---------------------------------------------------------------------
// Fixed-point helpers
// ---------------------------------------------------------------------

static inline WORD VBSin(UBYTE a)
{
	return SinTab256[a];
}

static inline WORD VBCos(UBYTE a)
{
	return SinTab256[(UBYTE)(a + 64)];
}

static inline WORD FixMul(WORD a, WORD b)
{
	return (WORD)(((LONG)a * (LONG)b) >> FIX_SHIFT);
}

static UBYTE FindXClass(BYTE x)
{
	for (UBYTE i = 0; i < VB_NUM_X_CLASSES; ++i)
	{
		if (XValues[i] == x)
		{
			return i;
		}
	}

	return 0;
}

// ---------------------------------------------------------------------
// Vector ball effect initialization and rendering
// ---------------------------------------------------------------------

static void CopyPaletteFromImage(const struct lwmf_Image* VectorBallImg)
{
	UBYTE i;
	UBYTE n = VectorBallImg->NumberOfColors;

	for (i = 0; i < n; ++i)
	{
		BallPalette[i] = (UWORD)VectorBallImg->CRegs[i];
	}

	for (; i < 16; ++i)
	{
		BallPalette[i] = 0x000;
	}
}

static BOOL Build_BobData(void)
{
	const UWORD SourceBytesPerRow = VectorBallImg->Image.BytesPerRow;
	const ULONG TotalWords = (ULONG)16 * (ULONG)VB_BOB_DATA_WORDS;

	BobSourceData = (UWORD*)AllocMem(TotalWords * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR);
	BobMaskData = (UWORD*)AllocMem(TotalWords * sizeof(UWORD), MEMF_CHIP | MEMF_CLEAR);

	for (UBYTE Shift = 0; Shift < 16; ++Shift)
	{
		UWORD* SrcOut = BobSourceData + ((ULONG)Shift * VB_BOB_DATA_WORDS);
		UWORD* MaskOut = BobMaskData + ((ULONG)Shift * VB_BOB_DATA_WORDS);

		BobSourceShift[Shift] = SrcOut;
		BobMaskShift[Shift] = MaskOut;

		for (UBYTE Row = 0; Row < VB_BALL_SIZE; ++Row)
		{
			UWORD PlaneRow[NUMBEROFBITPLANES];
			UWORD OpaqueMask = 0;

			for (UBYTE Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
			{
				const UWORD* RowPtr = (const UWORD*)((const UBYTE*)VectorBallImg->Image.Planes[Plane] + ((ULONG)Row * SourceBytesPerRow));
				PlaneRow[Plane] = RowPtr[0];
				OpaqueMask |= PlaneRow[Plane];
			}

			const ULONG ShiftedMask = ((ULONG)OpaqueMask << 16) >> Shift;
			const UWORD MaskWord0 = (UWORD)(ShiftedMask >> 16);
			const UWORD MaskWord1 = (UWORD)(ShiftedMask & 0xFFFFu);

			for (UBYTE Plane = 0; Plane < NUMBEROFBITPLANES; ++Plane)
			{
				const ULONG ShiftedSrc = ((ULONG)PlaneRow[Plane] << 16) >> Shift;

				*SrcOut++ = (UWORD)(ShiftedSrc >> 16);
				*SrcOut++ = (UWORD)(ShiftedSrc & 0xFFFFu);

				*MaskOut++ = MaskWord0;
				*MaskOut++ = MaskWord1;
			}
		}
	}

	return TRUE;
}

BOOL Init_VectorBall(void)
{
	VectorBallImg = lwmf_LoadImage(VECTORBALL_FILE);

	CopyPaletteFromImage(VectorBallImg);
	Build_BobData();

	// Classify every point once; the actual rotation is built from
	// 15 X contributions and 5 Y contributions per frame.
	for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
	{
		XClass[i] = FindXClass(VectorBallsDefX[i]);
		YClass[i] = (UBYTE)(VectorBallsDefY[i] + 2);
		ZOrder[i] = (UBYTE)i;
	}

	lwmf_DeleteImage(VectorBallImg);
	VectorBallImg = NULL;

	AngleX = 0;
	AngleY = 0;
	AngleZ = 0;

	return TRUE;
}

static void SortZOrderInsertionPersistent(void)
{
	for (UWORD i = 1; i < VB_NUM_BALLS; ++i)
	{
		const UBYTE Key = ZOrder[i];
		const WORD KeyZ = BallZ[Key];
		WORD j = (WORD)i - 1;

		while (j >= 0 && BallZ[ZOrder[j]] > KeyZ)
		{
			ZOrder[j + 1] = ZOrder[j];
			--j;
		}

		ZOrder[j + 1] = Key;
	}
}

static inline void Prepare_DrawPosition(UWORD Index, WORD X4, WORD Y4, WORD Z4)
{
	LONG factor = (LONG)Z4 + (15L << FIX_SHIFT);

	if (factor < (4L << FIX_SHIFT))
	{
		factor = (4L << FIX_SHIFT);
	}
	else if (factor > (26L << FIX_SHIFT))
	{
		factor = (26L << FIX_SHIFT);
	}

	LONG proj = (factor * VB_DISPLAY_SCALE) >> FIX_SHIFT;

	WORD x = (WORD)(VB_CENTER_X + (((LONG)X4 * (proj << 1)) >> 16));
	WORD y = (WORD)(VB_CENTER_Y + (((LONG)Y4 * (proj << 1)) >> 16));

	x -= (VB_BALL_SIZE >> 1);
	y -= (VB_BALL_SIZE >> 1);

	DrawShift[Index] = (UBYTE)(x & 15);
	DrawOffset[Index] = (UWORD)(((UWORD)y * VB_INTERLEAVED_ROW_BYTES) + (((UWORD)x >> 4) << 1));
	BallZ[Index] = Z4;
}

void Update_VectorBalls(void)
{
	const UBYTE ax = (UBYTE)(AngleX >> 8);
	const UBYTE ay = (UBYTE)(AngleY >> 8);
	const UBYTE az = (UBYTE)(AngleZ >> 8);

	const WORD sinX = VBSin(ax);
	const WORD cosX = VBCos(ax);
	const WORD sinY = VBSin(ay);
	const WORD cosY = VBCos(ay);
	const WORD sinZ = VBSin(az);
	const WORD cosZ = VBCos(az);

	// Build the 15 possible X contributions for this frame.
	for (UWORD xidx = 0; xidx < VB_NUM_X_CLASSES; ++xidx)
	{
		const WORD x = XValuesFix[xidx];

		FrameXToX3[xidx] = FixMul(x, cosY);
		FrameXToZ[xidx] = -FixMul(x, sinY);
	}

	// Build the 5 possible Y contributions for this frame.
	// To preserve the original fixed-point rounding, the combined x3 term
	// is still rotated around Z per ball, while the pure y3 term is reused
	// per Y row. */
	for (UWORD yidx = 0; yidx < VB_NUM_Y_CLASSES; ++yidx)
	{
		const WORD y = YValuesFix[yidx];
		const WORD z2 = FixMul(y, sinX);
		const WORD y3 = FixMul(y, cosX);

		FrameYToX3[yidx] = FixMul(z2, sinY);
		FrameYToZ[yidx] = FixMul(z2, cosY);
		FrameY3SinZ[yidx] = FixMul(y3, sinZ);
		FrameY3CosZ[yidx] = FixMul(y3, cosZ);
	}

	// Combine class contributions for all 48 balls and directly prepare
	// screen offsets + shift indices for the fixed blitter bob path.
	for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
	{
		const UBYTE xc = XClass[i];
		const UBYTE yc = YClass[i];
		const WORD x3 = (WORD)(FrameXToX3[xc] + FrameYToX3[yc]);
		const WORD x4 = (WORD)(FixMul(x3, cosZ) - FrameY3SinZ[yc]);
		const WORD y4 = (WORD)(FixMul(x3, sinZ) + FrameY3CosZ[yc]);
		const WORD z4 = (WORD)(FrameXToZ[xc] + FrameYToZ[yc]);

		Prepare_DrawPosition(i, x4, y4, z4);
	}

	SortZOrderInsertionPersistent();
}

void Draw_VectorBalls(UBYTE Buffer)
{
	VB_DrawVectorBallsBlit((UBYTE*)ScreenBitmap[Buffer]->Planes[0], ZOrder,	DrawOffset,	DrawShift, BobMaskShift, BobSourceShift);

	AngleX += VB_ANGLE_INC_X;
	AngleY += VB_ANGLE_INC_Y;
	AngleZ += VB_ANGLE_INC_Z;
}

// ---------------------------------------------------------------------
// Copper / palette
// ---------------------------------------------------------------------

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];

// VPOS offset for PAL display (first visible line = $2C = 44)
#define VPOS_OFFSET             0x2C

// Fixed Copper words:
// DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0/1/2+BPL1MOD+BPL2MOD = 18
// 4 bitplane pointers = 16
// COLOR00 preset + COLOR01..COLOR15 = 32
// END = 2
#define COPPER_FIXED_WORDS      68

// Per visible line: WAIT + MOVE COLOR00 = 4 words
// One extra WAIT is needed when VPOS wraps from 255 to 0.
#define SKY_COPPER_WORDS        ((SCREENHEIGHT * 4) + 2)

typedef struct
{
	UWORD Line;
	UWORD Color;
} SKYKEY;

static const SKYKEY SkyKeys[] =
{
	// Line, RGB4 Color
	{   0, 0x012 }, // very dark blue
	{  28, 0x124 }, // blue-violet
	{  56, 0x336 }, // purple
	{  84, 0x648 }, // warm purple
	{ 112, 0xA63 }, // sunrise orange
	{ 140, 0xD95 }, // bright peach
	{ 168, 0xCB8 }, // pale warm sky
	{ 196, 0x9BD }, // light cyan
	{ 224, 0x8CF }, // bright sky blue
	{ 255, 0xBDF }  // pale morning blue
};

static UWORD SkyColorForLine(UWORD y)
{
	for (UWORD i = 0; i < (sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1; ++i)
	{
		const UWORD p0 = SkyKeys[i].Line;
		const UWORD p1 = SkyKeys[i + 1].Line;

		if (y >= p0 && y <= p1)
		{
			return lwmf_RGBLerp(SkyKeys[i].Color, SkyKeys[i + 1].Color, y - p0, p1 - p0);
		}
	}

	return SkyKeys[(sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1].Color;
}

static void AddSkyLine(UWORD **Copperlist, UWORD y)
{
	const UWORD VPOS = VPOS_OFFSET + y;

	if (VPOS == 256)
	{
		*(*Copperlist)++ = 0xFFDF;
		*(*Copperlist)++ = 0xFFFE;
	}

	*(*Copperlist)++ = ((VPOS & 0xFF) << 8) | 0x07;
	*(*Copperlist)++ = 0xFFFE;
	*(*Copperlist)++ = 0x180;
	*(*Copperlist)++ = SkyColorForLine(y);
}

BOOL Init_CopperList(void)
{
	UWORD Index;
	UWORD p;
	UBYTE i;
	UWORD *Copperlist;
	const ULONG CopperListLength = COPPER_FIXED_WORDS + SKY_COPPER_WORDS;

	CopperListSize = CopperListLength * sizeof(UWORD);

	if (!(CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR)))
	{
		return FALSE;
	}

	Index = 0;

	// PAL display window
	CopperList[Index++] = 0x08E;
	CopperList[Index++] = 0x2C81; // DIWSTRT
	CopperList[Index++] = 0x090;
	CopperList[Index++] = 0x2CC1; // DIWSTOP
	CopperList[Index++] = 0x092;
	CopperList[Index++] = 0x0038; // DDFSTRT
	CopperList[Index++] = 0x094;
	CopperList[Index++] = 0x00D0; // DDFSTOP

	// 4 bitplanes
	CopperList[Index++] = 0x100;
	CopperList[Index++] = (UWORD)((NUMBEROFBITPLANES << 12) | 0x0200);

	CopperList[Index++] = 0x102;
	CopperList[Index++] = 0x0000; // BPLCON1
	CopperList[Index++] = 0x104;
	CopperList[Index++] = 0x0000; // BPLCON2

	// Interleaved bitmaps
	CopperList[Index++] = 0x108;
	CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);

	CopperList[Index++] = 0x10A;
	CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);

	// Bitplane pointers
	for (p = 0; p < NUMBEROFBITPLANES; ++p)
	{
		CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
		BPLPTH_Idx[p] = Index;
		CopperList[Index++] = 0x0000;

		CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
		BPLPTL_Idx[p] = Index;
		CopperList[Index++] = 0x0000;
	}

	// Pre-set COLOR00 to black so the top border stays black until the first sky WAIT.
	CopperList[Index++] = 0x0180;
	CopperList[Index++] = 0x0000;

	// Ball palette colors 1..15. COLOR00 is owned by the Copper sky.
	for (i = 1; i < 16; ++i)
	{
		CopperList[Index++] = (UWORD)(0x0180 + (i << 1));
		CopperList[Index++] = BallPalette[i];
	}

	// Full-screen Copper sky in COLOR00 behind the vector balls.
	Copperlist = &CopperList[Index];

	for (UWORD y = 0; y < SCREENHEIGHT; ++y)
	{
		AddSkyLine(&Copperlist, y);
	}

	Index = (UWORD)(Copperlist - CopperList);

	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;
	return TRUE;
}

void Update_BitplanePointers(UBYTE Buffer)
{
	ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0];

	CopperList[BPLPTH_Idx[0]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[0]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += BYTESPERROW;
	CopperList[BPLPTH_Idx[1]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[1]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += BYTESPERROW;
	CopperList[BPLPTH_Idx[2]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[2]] = (UWORD)(Ptr & 0xFFFFu);

	Ptr += BYTESPERROW;
	CopperList[BPLPTH_Idx[3]] = (UWORD)(Ptr >> 16);
	CopperList[BPLPTL_Idx[3]] = (UWORD)(Ptr & 0xFFFFu);
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

void Cleanup_All(void)
{
	lwmf_WaitBlitter();

	FreeMem(CopperList, CopperListSize);
	CopperList = NULL;

	FreeMem(BobSourceData, (ULONG)16 * (ULONG)VB_BOB_DATA_WORDS * sizeof(UWORD));
	BobSourceData = NULL;

	FreeMem(BobMaskData, (ULONG)16 * (ULONG)VB_BOB_DATA_WORDS * sizeof(UWORD));
	BobMaskData = NULL;

	lwmf_CleanupScreenBitmaps();
	lwmf_CleanupAll();
}

int main(void)
{
	lwmf_LoadGraphicsLib();
	lwmf_InitScreenBitmaps();
	Init_VectorBall();
	Init_CopperList();

	lwmf_TakeOverOS();

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	while (*CIAA_PRA & 0x40)
	{
		VB_ClearBoxBlit((UBYTE*)ScreenBitmap[CurrentBuffer]->Planes[0]);
		Update_VectorBalls();
		Draw_VectorBalls(CurrentBuffer);

		lwmf_WaitVertBlank();
		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;
	}

	Cleanup_All();
	return 0;
}