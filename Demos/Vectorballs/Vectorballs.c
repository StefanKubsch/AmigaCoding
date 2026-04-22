//**********************************************************************
//* Vector balls effect                                                *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch                                          *
//*                                                                    *
//* Compile & link with:                                               *
//* make_VectorBalls.cmd                                               *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

extern void DrawVectorBallsBlit(__reg("a0") UBYTE* DestPlane0, __reg("a1") const UWORD* SortedDrawOffsetPtr, __reg("a2") UWORD* const * SortedMaskPtr, __reg("a3") UWORD* const * SortedSourcePtr);

// ---------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------

#define VECTORBALL_FILE      "gfx/Vecball16x16.iff"

#define VB_NUM_BALLS         48
#define VB_BALL_SIZE         16

#define VB_CENTER_X          160
#define VB_CENTER_Y          128

// Overall perspective scale in 8.8 fixed.
// Smaller = balls closer together.
#define VB_DISPLAY_SCALE     95      /* 95/256 = 0.3711 */

// Angle increments as 8.8 phase into 256-entry LUT.
#define VB_ANGLE_INC_X       700
#define VB_ANGLE_INC_Y       700
#define VB_ANGLE_INC_Z       700

#define FIX_SHIFT            8
#define FIX_ONE              (1 << FIX_SHIFT)

#define VB_NUM_X_CLASSES     15
#define VB_BOB_WORDS         2
#define VB_BOB_ROWS          (VB_BALL_SIZE * NUMBEROFBITPLANES)
#define VB_BOB_DATA_WORDS    (VB_BOB_ROWS * VB_BOB_WORDS)

#define VB_INTERLEAVED_ROW_BYTES  (BYTESPERROW * NUMBEROFBITPLANES)

// ---------------------------------------------------------------------
// Flat point cloud ("DEEP4")
// All base Z values are 0, so the rotation can be specialized.
// ---------------------------------------------------------------------

// X coordinates for the flat point cloud.
// Y is implied by 5 fixed row blocks:
//   0..11  => -2
//  12..19  => -1
//  20..31  =>  0
//  32..37  =>  1
//  38..47  =>  2
static const BYTE VectorBallsDefX[VB_NUM_BALLS] =
{
	-9,-8,-5,-4,-3,-1,0,1,3,4,5,7,
	-9,-7,-5,-1,3,5,7,9,
	-9,-7,-5,-4,-1,0,3,4,5,7,8,9,
	-9,-7,-5,-1,3,9,
	-9,-8,-5,-4,-3,-1,0,1,3,9
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

static UBYTE XClass[VB_NUM_BALLS];

// Specialized runtime Z-order for the current effect.
static UBYTE ZOrderLUT[256][VB_NUM_BALLS];

static UWORD DrawOffset[VB_NUM_BALLS];
static UBYTE DrawShift[VB_NUM_BALLS];
static UWORD RowOffset[256];

// Linear draw command stream built once per frame from the phase-specific Z order.
static UWORD SortedDrawOffset[VB_NUM_BALLS];
static UWORD* SortedMaskPtr[VB_NUM_BALLS];
static UWORD* SortedSourcePtr[VB_NUM_BALLS];

// Maps X in range [-9..+9] to XClass [0..14].
// Unused entries are 0xFF.
static const UBYTE XClassLUT[19] =
{
	0,    /* -9 */
	1,    /* -8 */
	2,    /* -7 */
	0xFF, /* -6 unused */
	3,    /* -5 */
	4,    /* -4 */
	5,    /* -3 */
	0xFF, /* -2 unused */
	6,    /* -1 */
	7,    /*  0 */
	8,    /*  1 */
	0xFF, /*  2 unused */
	9,    /*  3 */
	10,   /*  4 */
	11,   /*  5 */
	0xFF, /*  6 unused */
	12,   /*  7 */
	13,   /*  8 */
	14    /*  9 */
};

// Per-frame contributions of the 15 X classes after the combined XYZ matrix.
static WORD FrameXToX4[VB_NUM_X_CLASSES];
static WORD FrameXToY4[VB_NUM_X_CLASSES];
static WORD FrameXToZ4[VB_NUM_X_CLASSES];

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

static inline WORD MulHi16(WORD a, WORD b)
{
	return (WORD)(((LONG)a * (LONG)b) >> 16);
}

static inline WORD ScalePerspective(WORD Value)
{
#if VB_DISPLAY_SCALE == 95
	const LONG Scaled = ((LONG)Value << 6) + ((LONG)Value << 4) + ((LONG)Value << 3) +
					 ((LONG)Value << 2) + ((LONG)Value << 1) + (LONG)Value;

	return (WORD)(Scaled >> FIX_SHIFT);
#else
	return (WORD)(((LONG)Value * VB_DISPLAY_SCALE) >> FIX_SHIFT);
#endif
}

static inline void BuildXContributionTable(WORD* Out, WORD Value)
{
	const WORD Value2 = (WORD)(Value + Value);
	const WORD Value4 = (WORD)(Value2 + Value2);
	const WORD Value8 = (WORD)(Value4 + Value4);

	Out[0] = (WORD)-(Value8 + Value);   // -9
	Out[1] = (WORD)-Value8;             // -8
	Out[2] = (WORD)(Value - Value8);    // -7
	Out[3] = (WORD)-(Value4 + Value);   // -5
	Out[4] = (WORD)-Value4;             // -4
	Out[5] = (WORD)-(Value2 + Value);   // -3
	Out[6] = (WORD)-Value;              // -1
	Out[7] = 0;                         //  0
	Out[8] = Value;                     //  1
	Out[9] = (WORD)(Value2 + Value);    //  3
	Out[10] = Value4;                   //  4
	Out[11] = (WORD)(Value4 + Value);   //  5
	Out[12] = (WORD)(Value8 - Value);   //  7
	Out[13] = Value8;                   //  8
	Out[14] = (WORD)(Value8 + Value);   //  9
}

static void Init_RowOffsetTable(void)
{
	for (UWORD y = 0; y < 256; ++y)
	{
		RowOffset[y] = (UWORD)(y * VB_INTERLEAVED_ROW_BYTES);
	}
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

static void Build_BobData(void)
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
}

static void Build_DrawCommandStream(const UBYTE* Order)
{
	for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
	{
		const UBYTE Index = Order[i];
		const UBYTE Shift = DrawShift[Index];

		SortedDrawOffset[i] = DrawOffset[Index];
		SortedMaskPtr[i] = BobMaskShift[Shift];
		SortedSourcePtr[i] = BobSourceShift[Shift];
	}
}

static void Build_ZOrderLUT(void)
{
	WORD PhaseXToZ4[VB_NUM_X_CLASSES];
	WORD ZTemp[VB_NUM_BALLS];
	UBYTE Order[VB_NUM_BALLS];

	for (UWORD phase = 0; phase < 256; ++phase)
	{
		const UBYTE a = (UBYTE)phase;
		const WORD sinA = VBSin(a);
		const WORD cosA = VBCos(a);
		const WORD E = (WORD)-sinA;
		const WORD F = FixMul(sinA, cosA);
		const WORD F2 = (WORD)(F + F);

		BuildXContributionTable(PhaseXToZ4, E);

		for (UWORD i = 0; i < 12; ++i)
		{
			ZTemp[i] = (WORD)(PhaseXToZ4[XClass[i]] - F2);
		}

		for (UWORD i = 12; i < 20; ++i)
		{
			ZTemp[i] = (WORD)(PhaseXToZ4[XClass[i]] - F);
		}

		for (UWORD i = 20; i < 32; ++i)
		{
			ZTemp[i] = PhaseXToZ4[XClass[i]];
		}

		for (UWORD i = 32; i < 38; ++i)
		{
			ZTemp[i] = (WORD)(PhaseXToZ4[XClass[i]] + F);
		}

		for (UWORD i = 38; i < 48; ++i)
		{
			ZTemp[i] = (WORD)(PhaseXToZ4[XClass[i]] + F2);
		}

		for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
		{
			Order[i] = (UBYTE)i;
		}

		for (UWORD i = 1; i < VB_NUM_BALLS; ++i)
		{
			const UBYTE Key = Order[i];
			const WORD KeyZ = ZTemp[Key];
			WORD j = (WORD)i - 1;

			while (j >= 0 && ZTemp[Order[j]] > KeyZ)
			{
				Order[j + 1] = Order[j];
				--j;
			}

			Order[j + 1] = Key;
		}

		for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
		{
			ZOrderLUT[phase][i] = Order[i];
		}
	}
}

static void Init_VectorBall(void)
{
	VectorBallImg = lwmf_LoadImage(VECTORBALL_FILE);

	CopyPaletteFromImage(VectorBallImg);
	Build_BobData();
	Init_RowOffsetTable();

	// Classify every point once; the actual rotation is built from
	// 15 X contributions per frame, while the 5 Y rows stay in fixed blocks.
	for (UWORD i = 0; i < VB_NUM_BALLS; ++i)
	{
		XClass[i] = XClassLUT[(WORD)VectorBallsDefX[i] + 9];
	}

	Build_ZOrderLUT();

	lwmf_DeleteImage(VectorBallImg);
	VectorBallImg = NULL;

	AngleX = 0;
	AngleY = 0;
	AngleZ = 0;
}

inline static void Prepare_DrawPosition(UWORD Index, WORD X4, WORD Y4, WORD Z4)
{
	const WORD proj = ScalePerspective((WORD)(Z4 + (15 << FIX_SHIFT)));
	const WORD proj2 = (WORD)(proj + proj);
	const WORD x = (WORD)(VB_CENTER_X - (VB_BALL_SIZE >> 1) + MulHi16(X4, proj2));
	const WORD y = (WORD)(VB_CENTER_Y - (VB_BALL_SIZE >> 1) + MulHi16(Y4, proj2));

	DrawShift[Index] = (UBYTE)(x & 15);
	DrawOffset[Index] = (UWORD)(RowOffset[(UBYTE)y] + (((UWORD)x >> 4) << 1));
}

static void Update_VectorBalls(void)
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
	const WORD sinXsinY = FixMul(sinX, sinY);

	// Combined XYZ coefficients for points with base Z = 0.
	//
	// x4 = x*A + y*B
	// y4 = x*C + y*D
	// z4 = x*E + y*F
	//
	// This is intentionally the faster 6-coefficient path.
	const WORD A = FixMul(cosY, cosZ);
	const WORD B = (WORD)(FixMul(sinXsinY, cosZ) - FixMul(cosX, sinZ));
	const WORD C = FixMul(cosY, sinZ);
	const WORD D = (WORD)(FixMul(sinXsinY, sinZ) + FixMul(cosX, cosZ));
	const WORD E = (WORD)-sinY;
	const WORD F = FixMul(sinX, cosY);

	const WORD BX2 = (WORD)(B + B);
	const WORD DX2 = (WORD)(D + D);
	const WORD FX2 = (WORD)(F + F);

	// Build the 15 possible X contributions for this frame without FixMul(x<<8, ...).
	BuildXContributionTable(FrameXToX4, A);
	BuildXContributionTable(FrameXToY4, C);
	BuildXContributionTable(FrameXToZ4, E);

	// The point list is stored in 5 fixed Y blocks:
	//   0..11  => Y = -2
	//  12..19  => Y = -1
	//  20..31  => Y =  0
	//  32..37  => Y =  1
	//  38..47  => Y =  2
	WORD YX = (WORD)-BX2;
	WORD YY = (WORD)-DX2;
	WORD YZ = (WORD)-FX2;

	for (UWORD i = 0; i < 12; ++i)
	{
		UBYTE xc = XClass[i];
		Prepare_DrawPosition(i,	(WORD)(FrameXToX4[xc] + YX), (WORD)(FrameXToY4[xc] + YY), (WORD)(FrameXToZ4[xc] + YZ));
	}

	YX = (WORD)-B;
	YY = (WORD)-D;
	YZ = (WORD)-F;

	for (UWORD i = 12; i < 20; ++i)
	{
		const UBYTE xc = XClass[i];
		Prepare_DrawPosition(i, (WORD)(FrameXToX4[xc] + YX), (WORD)(FrameXToY4[xc] + YY), (WORD)(FrameXToZ4[xc] + YZ));
	}

	for (UWORD i = 20; i < 32; ++i)
	{
		const UBYTE xc = XClass[i];
		Prepare_DrawPosition(i,	FrameXToX4[xc],	FrameXToY4[xc],	FrameXToZ4[xc]);
	}

	YX = B;
	YY = D;
	YZ = F;

	for (UWORD i = 32; i < 38; ++i)
	{
		const UBYTE xc = XClass[i];
		Prepare_DrawPosition(i,	(WORD)(FrameXToX4[xc] + YX), (WORD)(FrameXToY4[xc] + YY), (WORD)(FrameXToZ4[xc] + YZ));
	}

	YX = BX2;
	YY = DX2;
	YZ = FX2;

	for (UWORD i = 38; i < 48; ++i)
	{
		const UBYTE xc = XClass[i];
		Prepare_DrawPosition(i,	(WORD)(FrameXToX4[xc] + YX), (WORD)(FrameXToY4[xc] + YY), (WORD)(FrameXToZ4[xc] + YZ));
	}

	Build_DrawCommandStream(ZOrderLUT[ax]);
}

inline static void Draw_VectorBalls(UBYTE Buffer)
{
	DrawVectorBallsBlit((UBYTE*)ScreenBitmap[Buffer]->Planes[0], SortedDrawOffset, SortedMaskPtr, SortedSourcePtr);

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

// Fixed Copper words:
// DIWSTRT+DIWSTOP+DDFSTRT+DDFSTOP+BPLCON0/1/2+BPL1MOD+BPL2MOD = 18
// 4 bitplane pointers = 16
// COLOR00 preset + COLOR01..COLOR15 = 32
// END = 2
#define COPPER_FIXED_WORDS      68

static void Init_CopperList(void)
{
	const ULONG CopperListLength = COPPER_FIXED_WORDS;
	CopperListSize = CopperListLength * sizeof(UWORD);

	CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

	UWORD Index = 0;

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
	for (UWORD p = 0; p < NUMBEROFBITPLANES; ++p)
	{
		CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
		BPLPTH_Idx[p] = Index;
		CopperList[Index++] = 0x0000;

		CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
		BPLPTL_Idx[p] = Index;
		CopperList[Index++] = 0x0000;
	}

	// Set background color to black
	CopperList[Index++] = 0x0180;
	CopperList[Index++] = 0x0000;

	// Ball palette colors 1..15.
	for (UBYTE i = 1; i < 16; ++i)
	{
		CopperList[Index++] = (UWORD)(0x0180 + (i << 1));
		CopperList[Index++] = BallPalette[i];
	}

	CopperList[Index++] = 0xFFFF;
	CopperList[Index++] = 0xFFFE;

	*COP1LC = (ULONG)CopperList;
}

static void Update_BitplanePointers(UBYTE Buffer)
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

static void Cleanup_All(void)
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
		Update_VectorBalls();
		lwmf_ClearScreen((long*)ScreenBitmap[CurrentBuffer]->Planes[0]);
		Draw_VectorBalls(CurrentBuffer);

		lwmf_WaitVertBlank();
		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;
	}

	Cleanup_All();
	return 0;
}