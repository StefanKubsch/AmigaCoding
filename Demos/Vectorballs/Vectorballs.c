//**********************************************************************
//* Vector balls effect                                               *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_VectorBalls.cmd                                              *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// ---------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------

#define VECTORBALL_FILE      "gfx/vectorball.iff"

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

// ---------------------------------------------------------------------
// point cloud ("DEEP4")
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

static const BYTE VectorBallsDefZ[VB_NUM_BALLS] =
{
	0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0,0,0,
	0,0,0,0,0,0,
	0,0,0,0,0,0,0,0,0,0
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
// Types
// ---------------------------------------------------------------------

typedef struct
{
	WORD x;
	WORD y;
	WORD z;
} VBPoint;

// ---------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------

struct lwmf_Image* VectorBallImg;

static VBPoint Points[VB_NUM_BALLS];
static UBYTE ZOrder[VB_NUM_BALLS];

static VBPoint BasePoints[VB_NUM_BALLS];

static UBYTE XClass[VB_NUM_BALLS];
static UBYTE YClass[VB_NUM_BALLS];

/* Unique X values present in VectorBallsDefX[] */
static const BYTE XValues[VB_NUM_X_CLASSES] =
{
	-9, -8, -7, -5, -4, -3, -1, 0, 1, 3, 4, 5, 7, 8, 9
};

/* 5 Y-rows (-2..2), 256 angle steps */
static WORD RotX_Z2[VB_NUM_Y_CLASSES][256];
static WORD RotX_Y3[VB_NUM_Y_CLASSES][256];

static WORD FrameY3[VB_NUM_Y_CLASSES];
static WORD FrameZ2SinY[VB_NUM_Y_CLASSES];
static WORD FrameZ2CosY[VB_NUM_Y_CLASSES];

/* x contribution of y-rotation for all distinct x values */
static WORD RotY_XCos[VB_NUM_X_CLASSES][256];
static WORD RotY_XNegSin[VB_NUM_X_CLASSES][256];

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
	UBYTE i;

	for (i = 0; i < VB_NUM_X_CLASSES; ++i)
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

BOOL Init_VectorBall(void)
{
	UWORD i, a, yidx, xidx;

	VectorBallImg = lwmf_LoadImage(VECTORBALL_FILE);

	if (!VectorBallImg)
	{
		return FALSE;
	}

	CopyPaletteFromImage(VectorBallImg);

	/* Precompute fixed-point base coordinates and point classes */
	for (i = 0; i < VB_NUM_BALLS; ++i)
	{
		BasePoints[i].x = ((WORD)VectorBallsDefX[i]) << FIX_SHIFT;
		BasePoints[i].y = ((WORD)VectorBallsDefY[i]) << FIX_SHIFT;
		BasePoints[i].z = ((WORD)VectorBallsDefZ[i]) << FIX_SHIFT;

		XClass[i] = FindXClass(VectorBallsDefX[i]);
		YClass[i] = (UBYTE)(VectorBallsDefY[i] + 2);

		ZOrder[i] = (UBYTE)i;
	}

	/* X-rotation results for the 5 possible Y rows.
	   Since all base Z values are 0:
	   z2 = y * sinX
	   y3 = y * cosX
	*/
	for (a = 0; a < 256; ++a)
	{
		const WORD s = VBSin((UBYTE)a);
		const WORD c = VBCos((UBYTE)a);

		for (yidx = 0; yidx < VB_NUM_Y_CLASSES; ++yidx)
		{
			const WORD y = (WORD)(yidx - 2) << FIX_SHIFT;

			RotX_Z2[yidx][a] = FixMul(y, s);
			RotX_Y3[yidx][a] = FixMul(y, c);
		}
	}

	/* Y-rotation x-contributions for all unique X values */
	for (a = 0; a < 256; ++a)
	{
		const WORD s = VBSin((UBYTE)a);
		const WORD c = VBCos((UBYTE)a);

		for (xidx = 0; xidx < VB_NUM_X_CLASSES; ++xidx)
		{
			const WORD x = ((WORD)XValues[xidx]) << FIX_SHIFT;

			RotY_XCos[xidx][a] = FixMul(x, c);
			RotY_XNegSin[xidx][a] = -FixMul(x, s);
		}
	}

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
		const WORD KeyZ = Points[Key].z;
		WORD j = (WORD)i - 1;

		while (j >= 0 && Points[ZOrder[j]].z > KeyZ)
		{
			ZOrder[j + 1] = ZOrder[j];
			--j;
		}

		ZOrder[j + 1] = Key;
	}
}

void Update_VectorBalls(void)
{
	const UBYTE ax = (UBYTE)(AngleX >> 8);
	const UBYTE ay = (UBYTE)(AngleY >> 8);
	const UBYTE az = (UBYTE)(AngleZ >> 8);

	const WORD sinY = VBSin(ay);
	const WORD cosY = VBCos(ay);
	const WORD sinZ = VBSin(az);
	const WORD cosZ = VBCos(az);

	UWORD i;

	for (i = 0; i < VB_NUM_BALLS; ++i)
	{
		const UBYTE xc = XClass[i];
		const UBYTE yc = YClass[i];

		/* x-rotation from LUTs */
		const WORD z2 = RotX_Z2[yc][ax];
		const WORD y3 = RotX_Y3[yc][ax];

		/* y-rotation:
		   x3 = x*cosY + z2*sinY
		   z3 = -x*sinY + z2*cosY
		*/
		const WORD x3 = RotY_XCos[xc][ay] + FixMul(z2, sinY);
		const WORD z3 = RotY_XNegSin[xc][ay] + FixMul(z2, cosY);

		/* z-rotation */
		Points[i].x = (WORD)(FixMul(x3, cosZ) - FixMul(y3, sinZ));
		Points[i].y = (WORD)(FixMul(x3, sinZ) + FixMul(y3, cosZ));
		Points[i].z = z3;
	}

	SortZOrderInsertionPersistent();
}

void Draw_VectorBalls(UBYTE Buffer)
{
	UWORD i;

	for (i = 0; i < VB_NUM_BALLS; ++i)
	{
		const UBYTE Index = ZOrder[i];
		LONG factor = (LONG)Points[Index].z + (15L << FIX_SHIFT);   // 8.8

		if (factor < (4L << FIX_SHIFT))
		{
			factor = (4L << FIX_SHIFT);
		}
		else if (factor > (26L << FIX_SHIFT))
		{
			factor = (26L << FIX_SHIFT);
		}

		LONG proj = (factor * VB_DISPLAY_SCALE) >> FIX_SHIFT;   // 8.8
		WORD x = (WORD)(VB_CENTER_X + (((LONG)Points[Index].x * (proj << 1)) >> 16));
		WORD y = (WORD)(VB_CENTER_Y + (((LONG)Points[Index].y * (proj << 1)) >> 16));

		x -= (VB_BALL_SIZE >> 1);
		y -= (VB_BALL_SIZE >> 1);

		BltBitMap(&VectorBallImg->Image, 0, 0, ScreenBitmap[Buffer], x, y, VB_BALL_SIZE, VB_BALL_SIZE, 0xE2, 0xFF, NULL);
	}

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

BOOL Init_CopperList(void)
{
	UWORD Index;
	UWORD p;
	UBYTE i;

	CopperListSize = 128 * sizeof(UWORD);

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

	// Colors 0..15
	for (i = 0; i < 16; ++i)
	{
		CopperList[Index++] = (UWORD)(0x0180 + (i << 1));
		CopperList[Index++] = BallPalette[i];
	}

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

	if (CopperList)
	{
		FreeMem(CopperList, CopperListSize);
		CopperList = NULL;
	}

	if (VectorBallImg)
	{
		lwmf_DeleteImage(VectorBallImg);
		VectorBallImg = NULL;
	}

	lwmf_CleanupScreenBitmaps();
	lwmf_CleanupAll();
}

int main(void)
{
	if (lwmf_LoadGraphicsLib() != 0)
	{
		return 20;
	}

	if (!lwmf_InitScreenBitmaps())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_VectorBall())
	{
		Cleanup_All();
		return 20;
	}

	if (!Init_CopperList())
	{
		Cleanup_All();
		return 20;
	}

	lwmf_TakeOverOS();

	UBYTE CurrentBuffer = 1;
	Update_BitplanePointers(0);

	while (*CIAA_PRA & 0x40)
	{
		lwmf_ClearScreen((long*)ScreenBitmap[CurrentBuffer]->Planes[0]);

		Update_VectorBalls();
		Draw_VectorBalls(CurrentBuffer);

		lwmf_WaitVertBlank();
		Update_BitplanePointers(CurrentBuffer);
		CurrentBuffer ^= 1;
	}

	Cleanup_All();
	return 0;
}