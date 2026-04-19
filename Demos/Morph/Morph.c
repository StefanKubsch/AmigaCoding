//**********************************************************************
//* Amiga morph effect                                                  *
//* Amiga 500 OCS                                                       *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
//* Revised: 1 bitplane performance-oriented version                   *
//*                                                                    *
//* Objects: sphere, cube, triangular prism                            *
//* 1 visible bitplane, copper sky, white pixels                       *
//*                                                                    *
//* Notes:                                                             *
//* - specialized for NUMBEROFBITPLANES = 1                            *
//* - uses framework lwmf_SetPixel / lwmf_ClearScreen                  *
//* - waits for clear blit completion before plotting                  *
//* - hold frames are preprojected                                     *
//* - morph uses incremental 8.8 fixed-point steps                     *
//* - geometry is built while clear blitter is still running           *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Morph.cmd                                                     *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// ---------------------------------------------------------------------
// Morphing dots
// ---------------------------------------------------------------------

#define OBJECT_COUNT              3
#define SPHERE_RINGS             12
#define POINTS_PER_RING          36
#define SPHERE_POINT_COUNT       (SPHERE_RINGS * POINTS_PER_RING)
#define CUBE_EDGE_COUNT          12
#define PRISM_EDGE_COUNT          9
#define POINT_COUNT              SPHERE_POINT_COUNT

#define ANGLE_MASK               255
#define FP_SHIFT                  8
#define MORPH_FRAMES             40
#define HOLD_FRAMES              160

#define CENTER_X                 (SCREENWIDTH / 2)
#define CENTER_Y                 (SCREENHEIGHT / 2)
#define PROJ_DIST                200
#define Z_OFFSET                 440

#define SPHERE_RADIUS             78
#define CUBE_RADIUS               73
#define PRISM_TOP_Y              -72
#define PRISM_BASE_Y              54
#define PRISM_HALF_BASE           84
#define PRISM_HALF_DEPTH          42

#define BASE_ANGLE_X              20
#define BASE_ANGLE_Y              20
#define ROCK_ANGLE_Y              56

#define YROT_MIN_ANGLE           (BASE_ANGLE_Y - ROCK_ANGLE_Y)
#define YROT_MAX_ANGLE           (BASE_ANGLE_Y + ROCK_ANGLE_Y)
#define YROT_ANGLE_COUNT         (YROT_MAX_ANGLE - YROT_MIN_ANGLE + 1)

#define COORD_BIAS              128
#define COORD_RANGE             256
#define PROJ_Z_MIN              304
#define PROJ_Z_MAX              592
#define PROJ_Z_RANGE            (PROJ_Z_MAX - PROJ_Z_MIN + 1)

typedef signed char SBYTE;

typedef struct
{
    WORD x;
    WORD y;
    WORD z;
} POINT3D;

#define OBJECT_INDEX(obj, pt)    ((ULONG)(obj) * (ULONG)POINT_COUNT + (ULONG)(pt))
#define STATIC_INDEX(obj, rot, pt) ((((ULONG)(obj) * (ULONG)YROT_ANGLE_COUNT) + (ULONG)(rot)) * (ULONG)POINT_COUNT + (ULONG)(pt))

static POINT3D ObjectPoints[OBJECT_COUNT * POINT_COUNT];
static POINT3D MorphStep[OBJECT_COUNT * POINT_COUNT];
static POINT3D MorphCur[POINT_COUNT];
static SBYTE RotCosY[YROT_ANGLE_COUNT * COORD_RANGE];
static SBYTE RotSinY[YROT_ANGLE_COUNT * COORD_RANGE];
static SBYTE ProjOffset[PROJ_Z_RANGE * COORD_RANGE];
static const SBYTE* RotCosRows[YROT_ANGLE_COUNT];
static const SBYTE* RotSinRows[YROT_ANGLE_COUNT];
static const SBYTE* ProjRows[PROJ_Z_RANGE];
static UWORD StaticPackedXY[OBJECT_COUNT * YROT_ANGLE_COUNT * POINT_COUNT];
static UWORD MorphPackedXY[POINT_COUNT];
static UBYTE RockRotIndex[256];
static volatile long* DrawTarget = NULL;

static const UWORD QuarterSin[65] =
{
      0,   6,  13,  19,  25,  31,  38,  44,  50,  56,  62,  68,  74,
     80,  86,  92,  98, 104, 109, 115, 121, 126, 132, 137, 142, 147,
    152, 157, 162, 167, 172, 177, 181, 185, 190, 194, 198, 202, 206,
    209, 213, 216, 220, 223, 226, 229, 231, 234, 237, 239, 241, 243,
    245, 247, 248, 250, 251, 252, 253, 254, 255, 255, 256, 256, 256
};

static WORD Sin256(UWORD Angle)
{
    const UWORD a = (UWORD)(Angle & ANGLE_MASK);
    const UWORD q = (UWORD)(a >> 6);
    const UWORD t = (UWORD)(a & 63u);

    switch (q)
    {
        case 0:  return (WORD)QuarterSin[t];
        case 1:  return (WORD)QuarterSin[64u - t];
        case 2:  return (WORD)-(WORD)QuarterSin[t];
        default: return (WORD)-(WORD)QuarterSin[64u - t];
    }
}

static WORD Cos256(UWORD Angle)
{
    return Sin256((UWORD)((Angle + 64u) & ANGLE_MASK));
}

static WORD MulS8(WORD a, WORD b)
{
    return (WORD)(((LONG)a * (LONG)b) >> FP_SHIFT);
}

static WORD LerpFracCoord(WORD a, WORD b, UWORD numer, UWORD denom)
{
    return (WORD)(a + ((((LONG)(b - a)) * (LONG)numer) / (LONG)denom));
}

static UWORD PackXY(WORD px, WORD py)
{
    if (px < 0) px = 0;
    if (px > 255) px = 255;
    if (py < 0) py = 0;
    if (py > 255) py = 255;

    return (UWORD)((((UWORD)py) << 8) | (UWORD)px);
}

static void PlotPackedDots(const UWORD* PackedXY)
{
    const UWORD* Packed = PackedXY;

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        const UWORD p = *Packed++;
        lwmf_SetPixel1bpl((WORD)(p & 0x00FFu), (WORD)(p >> 8), (long*)DrawTarget);
    }
}

static void InitLookupRows(void)
{
    for (UWORD i = 0; i < YROT_ANGLE_COUNT; ++i)
    {
        RotCosRows[i] = &RotCosY[(ULONG)i * (ULONG)COORD_RANGE];
        RotSinRows[i] = &RotSinY[(ULONG)i * (ULONG)COORD_RANGE];
    }

    for (UWORD i = 0; i < PROJ_Z_RANGE; ++i)
    {
        ProjRows[i] = &ProjOffset[(ULONG)i * (ULONG)COORD_RANGE];
    }
}

static void InitYRotationTables(void)
{
    for (WORD Angle = YROT_MIN_ANGLE; Angle <= YROT_MAX_ANGLE; ++Angle)
    {
        const WORD sy = Sin256((UWORD)Angle);
        const WORD cy = Cos256((UWORD)Angle);
        const ULONG TableBase = (ULONG)(Angle - YROT_MIN_ANGLE) * (ULONG)COORD_RANGE;

        for (WORD c = -COORD_BIAS; c < (COORD_RANGE - COORD_BIAS); ++c)
        {
            const UWORD ci = (UWORD)(c + COORD_BIAS);
            RotCosY[TableBase + ci] = (SBYTE)(((LONG)c * (LONG)cy) >> FP_SHIFT);
            RotSinY[TableBase + ci] = (SBYTE)(((LONG)c * (LONG)sy) >> FP_SHIFT);
        }
    }
}

static void InitProjectionTable(void)
{
    for (WORD z = PROJ_Z_MIN; z <= PROJ_Z_MAX; ++z)
    {
        const ULONG TableBase = (ULONG)(z - PROJ_Z_MIN) * (ULONG)COORD_RANGE;

        for (WORD c = -COORD_BIAS; c < (COORD_RANGE - COORD_BIAS); ++c)
        {
            LONG Value = ((LONG)c * (LONG)PROJ_DIST) / (LONG)z;
            const UWORD ci = (UWORD)(c + COORD_BIAS);

            if (Value < -127L) Value = -127L;
            if (Value > 127L) Value = 127L;
            ProjOffset[TableBase + ci] = (SBYTE)Value;
        }
    }
}

static void InitRockPhaseTable(void)
{
    for (UWORD Phase = 0; Phase < 256u; ++Phase)
    {
        const WORD AngleY = (WORD)(BASE_ANGLE_Y + ((Sin256(Phase) * ROCK_ANGLE_Y) >> FP_SHIFT));
        RockRotIndex[Phase] = (UBYTE)(AngleY - YROT_MIN_ANGLE);
    }
}

static void InitSpherePoints(void)
{
    UWORD Index = 0;
    POINT3D* Out = &ObjectPoints[OBJECT_INDEX(0, 0)];

    for (UWORD ring = 0; ring < SPHERE_RINGS; ++ring)
    {
        const UWORD LatAngle = (UWORD)(192u + ((ring * 128u) / (SPHERE_RINGS - 1u)));
        const WORD y = (WORD)(((LONG)Sin256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const WORD ringRadius = (WORD)(((LONG)Cos256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const UWORD ringOffset = (UWORD)((ring & 1u) ? 2u : 0u);

        for (UWORD seg = 0; seg < POINTS_PER_RING; ++seg)
        {
            const UWORD Angle = (UWORD)(ringOffset + ((seg * 256u) / POINTS_PER_RING));

            Out[Index].x = (WORD)(((LONG)Cos256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            Out[Index].y = y;
            Out[Index].z = (WORD)(((LONG)Sin256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            ++Index;
        }
    }
}

static void InitCubePoints(void)
{
    static const WORD VX[8] =
    {
        -CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS, -CUBE_RADIUS,
        -CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS, -CUBE_RADIUS
    };

    static const WORD VY[8] =
    {
        -CUBE_RADIUS, -CUBE_RADIUS, -CUBE_RADIUS, -CUBE_RADIUS,
         CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS
    };

    static const WORD VZ[8] =
    {
        -CUBE_RADIUS, -CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS,
        -CUBE_RADIUS, -CUBE_RADIUS,  CUBE_RADIUS,  CUBE_RADIUS
    };

    static const UBYTE E0[CUBE_EDGE_COUNT] = { 0, 1, 2, 3, 0, 1, 2, 3, 4, 5, 6, 7 };
    static const UBYTE E1[CUBE_EDGE_COUNT] = { 1, 2, 3, 0, 4, 5, 6, 7, 5, 6, 7, 4 };

    UWORD Index = 0;
    POINT3D* Out = &ObjectPoints[OBJECT_INDEX(1, 0)];
    const UWORD InteriorPerEdge = (UWORD)((POINT_COUNT - 8u) / CUBE_EDGE_COUNT);
    const UWORD InteriorRemainder = (UWORD)((POINT_COUNT - 8u) % CUBE_EDGE_COUNT);

    for (UWORD edge = 0; edge < 8u; ++edge)
    {
        Out[Index].x = VX[edge];
        Out[Index].y = VY[edge];
        Out[Index].z = VZ[edge];
        ++Index;
    }

    for (UWORD edge = 0; edge < CUBE_EDGE_COUNT; ++edge)
    {
        const WORD ax = VX[E0[edge]];
        const WORD ay = VY[E0[edge]];
        const WORD az = VZ[E0[edge]];
        const WORD bx = VX[E1[edge]];
        const WORD by = VY[E1[edge]];
        const WORD bz = VZ[E1[edge]];
        const UWORD Count = (UWORD)(InteriorPerEdge + ((edge < InteriorRemainder) ? 1u : 0u));

        for (UWORD step = 0; step < Count; ++step)
        {
            const UWORD Numer = (UWORD)(step + 1u);
            const UWORD Denom = (UWORD)(Count + 1u);

            Out[Index].x = LerpFracCoord(ax, bx, Numer, Denom);
            Out[Index].y = LerpFracCoord(ay, by, Numer, Denom);
            Out[Index].z = LerpFracCoord(az, bz, Numer, Denom);
            ++Index;
        }
    }
}

static void InitTriPrismPoints(void)
{
    static const WORD VX[6] =
    {
         0, -PRISM_HALF_BASE,  PRISM_HALF_BASE,
         0, -PRISM_HALF_BASE,  PRISM_HALF_BASE
    };

    static const WORD VY[6] =
    {
        PRISM_TOP_Y, PRISM_BASE_Y, PRISM_BASE_Y,
        PRISM_TOP_Y, PRISM_BASE_Y, PRISM_BASE_Y
    };

    static const WORD VZ[6] =
    {
        -PRISM_HALF_DEPTH, -PRISM_HALF_DEPTH, -PRISM_HALF_DEPTH,
         PRISM_HALF_DEPTH,  PRISM_HALF_DEPTH,  PRISM_HALF_DEPTH
    };

    static const UBYTE E0[PRISM_EDGE_COUNT] = { 0, 1, 2, 3, 4, 5, 0, 1, 2 };
    static const UBYTE E1[PRISM_EDGE_COUNT] = { 1, 2, 0, 4, 5, 3, 3, 4, 5 };

    UWORD Index = 0;
    POINT3D* Out = &ObjectPoints[OBJECT_INDEX(2, 0)];
    const UWORD InteriorPerEdge = (UWORD)((POINT_COUNT - 6u) / PRISM_EDGE_COUNT);
    const UWORD InteriorRemainder = (UWORD)((POINT_COUNT - 6u) % PRISM_EDGE_COUNT);

    for (UWORD edge = 0; edge < 6u; ++edge)
    {
        Out[Index].x = VX[edge];
        Out[Index].y = VY[edge];
        Out[Index].z = VZ[edge];
        ++Index;
    }

    for (UWORD edge = 0; edge < PRISM_EDGE_COUNT; ++edge)
    {
        const WORD ax = VX[E0[edge]];
        const WORD ay = VY[E0[edge]];
        const WORD az = VZ[E0[edge]];
        const WORD bx = VX[E1[edge]];
        const WORD by = VY[E1[edge]];
        const WORD bz = VZ[E1[edge]];
        const UWORD Count = (UWORD)(InteriorPerEdge + ((edge < InteriorRemainder) ? 1u : 0u));

        for (UWORD step = 0; step < Count; ++step)
        {
            const UWORD Numer = (UWORD)(step + 1u);
            const UWORD Denom = (UWORD)(Count + 1u);

            Out[Index].x = LerpFracCoord(ax, bx, Numer, Denom);
            Out[Index].y = LerpFracCoord(ay, by, Numer, Denom);
            Out[Index].z = LerpFracCoord(az, bz, Numer, Denom);
            ++Index;
        }
    }
}

static void ApplyBaseXTilt(void)
{
    const WORD sx = Sin256(BASE_ANGLE_X);
    const WORD cx = Cos256(BASE_ANGLE_X);

    for (UWORD Obj = 0; Obj < OBJECT_COUNT; ++Obj)
    {
        POINT3D* P = &ObjectPoints[OBJECT_INDEX(Obj, 0)];

        for (UWORD i = 0; i < POINT_COUNT; ++i)
        {
            const WORD y = P[i].y;
            const WORD z = P[i].z;

            P[i].y = (WORD)(MulS8(y, cx) - MulS8(z, sx));
            P[i].z = (WORD)(MulS8(y, sx) + MulS8(z, cx));
        }
    }
}

static void InitMorphSteps(void)
{
    for (UWORD Obj = 0; Obj < OBJECT_COUNT; ++Obj)
    {
        const UWORD Next = (UWORD)((Obj + 1u) % OBJECT_COUNT);
        POINT3D* Step = &MorphStep[OBJECT_INDEX(Obj, 0)];
        const POINT3D* Src = &ObjectPoints[OBJECT_INDEX(Obj, 0)];
        const POINT3D* Dst = &ObjectPoints[OBJECT_INDEX(Next, 0)];

        for (UWORD i = 0; i < POINT_COUNT; ++i)
        {
            if (MORPH_FRAMES > 1)
            {
                Step[i].x = (WORD)((((LONG)(Dst[i].x - Src[i].x)) << FP_SHIFT) / (LONG)(MORPH_FRAMES - 1));
                Step[i].y = (WORD)((((LONG)(Dst[i].y - Src[i].y)) << FP_SHIFT) / (LONG)(MORPH_FRAMES - 1));
                Step[i].z = (WORD)((((LONG)(Dst[i].z - Src[i].z)) << FP_SHIFT) / (LONG)(MORPH_FRAMES - 1));
            }
            else
            {
                Step[i].x = 0;
                Step[i].y = 0;
                Step[i].z = 0;
            }
        }
    }
}

static void InitObjects(void)
{
    InitSpherePoints();
    InitCubePoints();
    InitTriPrismPoints();
    ApplyBaseXTilt();
    InitMorphSteps();
}

static void BuildStaticPackedFrame(UWORD ObjIndex, UBYTE RotIndex)
{
    const POINT3D* P = &ObjectPoints[OBJECT_INDEX(ObjIndex, 0)];
    UWORD* Out = &StaticPackedXY[STATIC_INDEX(ObjIndex, RotIndex, 0)];
    const SBYTE* RotC = RotCosRows[RotIndex];
    const SBYTE* RotS = RotSinRows[RotIndex];

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        const UWORD xc = (UWORD)(P[i].x + COORD_BIAS);
        const UWORD zc = (UWORD)(P[i].z + COORD_BIAS);
        const WORD xr = (WORD)RotC[xc] + (WORD)RotS[zc];
        const WORD zr = (WORD)RotC[zc] - (WORD)RotS[xc];
        const SBYTE* Proj = ProjRows[(UWORD)(zr + Z_OFFSET - PROJ_Z_MIN)];
        const UWORD xrc = (UWORD)(xr + COORD_BIAS);
        const UWORD yc = (UWORD)(P[i].y + COORD_BIAS);
        const WORD px = (WORD)(CENTER_X + (WORD)Proj[xrc]);
        const WORD py = (WORD)(CENTER_Y + (WORD)Proj[yc]);

        Out[i] = PackXY(px, py);
    }
}

static void InitStaticPackedFrames(void)
{
    for (UWORD Obj = 0; Obj < OBJECT_COUNT; ++Obj)
    {
        for (UBYTE RotIndex = 0; RotIndex < YROT_ANGLE_COUNT; ++RotIndex)
        {
            BuildStaticPackedFrame(Obj, RotIndex);
        }
    }
}

static void InitMorphState(UWORD PairIndex)
{
    const POINT3D* Src = &ObjectPoints[OBJECT_INDEX(PairIndex, 0)];

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        MorphCur[i].x = (WORD)(Src[i].x << FP_SHIFT);
        MorphCur[i].y = (WORD)(Src[i].y << FP_SHIFT);
        MorphCur[i].z = (WORD)(Src[i].z << FP_SHIFT);
    }
}

static void BuildMorphPackedDotsAndAdvance(UWORD PairIndex, UBYTE RotIndex, BOOL Advance)
{
    POINT3D* Cur = MorphCur;
    const POINT3D* Step = &MorphStep[OBJECT_INDEX(PairIndex, 0)];
    UWORD* Out = MorphPackedXY;
    const SBYTE* RotC = RotCosRows[RotIndex];
    const SBYTE* RotS = RotSinRows[RotIndex];

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        const WORD x = (WORD)(Cur[i].x >> FP_SHIFT);
        const WORD y = (WORD)(Cur[i].y >> FP_SHIFT);
        const WORD z = (WORD)(Cur[i].z >> FP_SHIFT);
        const UWORD xc = (UWORD)(x + COORD_BIAS);
        const UWORD zc = (UWORD)(z + COORD_BIAS);
        const WORD xr = (WORD)RotC[xc] + (WORD)RotS[zc];
        const WORD zr = (WORD)RotC[zc] - (WORD)RotS[xc];
        const SBYTE* Proj = ProjRows[(UWORD)(zr + Z_OFFSET - PROJ_Z_MIN)];
        const UWORD xrc = (UWORD)(xr + COORD_BIAS);
        const UWORD yc = (UWORD)(y + COORD_BIAS);
        const WORD px = (WORD)(CENTER_X + (WORD)Proj[xrc]);
        const WORD py = (WORD)(CENTER_Y + (WORD)Proj[yc]);

        Out[i] = PackXY(px, py);

        if (Advance)
        {
            Cur[i].x = (WORD)(Cur[i].x + Step[i].x);
            Cur[i].y = (WORD)(Cur[i].y + Step[i].y);
            Cur[i].z = (WORD)(Cur[i].z + Step[i].z);
        }
    }
}

// ---------------------------------------------------------------------
// Copper / palette
// ---------------------------------------------------------------------

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD BPL1PTH_Idx;
static UWORD BPL1PTL_Idx;

#define VPOS_OFFSET             0x2C

typedef struct
{
    UWORD Line;
    UWORD Color;
} SKYKEY;

static const SKYKEY SkyKeys[] =
{
    {   0, 0x012 },
    {  28, 0x124 },
    {  56, 0x336 },
    {  84, 0x648 },
    { 112, 0xA63 },
    { 140, 0xD95 },
    { 168, 0xCB8 },
    { 196, 0x9BD },
    { 224, 0x8CF },
    { 255, 0xBDF }
};

static UWORD SkyColorForLine(UWORD y)
{
    for (UWORD i = 0; i < (UWORD)((sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1u); ++i)
    {
        const UWORD p0 = SkyKeys[i].Line;
        const UWORD p1 = SkyKeys[i + 1u].Line;

        if (y >= p0 && y <= p1)
        {
            return lwmf_RGBLerp(SkyKeys[i].Color, SkyKeys[i + 1u].Color, y - p0, p1 - p0);
        }
    }

    return SkyKeys[(sizeof(SkyKeys) / sizeof(SkyKeys[0])) - 1u].Color;
}

static void AddSkyLine(UWORD** CopperPtr, UWORD y)
{
    UWORD VPOS = (UWORD)(VPOS_OFFSET + y);

    if (VPOS == 256u)
    {
        *(*CopperPtr)++ = 0xFFDF;
        *(*CopperPtr)++ = 0xFFFE;
    }

    *(*CopperPtr)++ = (UWORD)(((VPOS & 0x00FFu) << 8) | 0x0007u);
    *(*CopperPtr)++ = 0xFFFE;
    *(*CopperPtr)++ = 0x0180;
    *(*CopperPtr)++ = SkyColorForLine(y);
}

#define COPPER_FIXED_WORDS      28
#define SKY_COPPER_WORDS        ((SCREENHEIGHT * 4) + 2)

void Init_CopperList(void)
{
    const ULONG CopperListLength = (ULONG)COPPER_FIXED_WORDS + (ULONG)SKY_COPPER_WORDS;
    const ULONG CopperListSize = CopperListLength * sizeof(UWORD);
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

	// 1 bitplane
	CopperList[Index++] = 0x100;
	CopperList[Index++] = 0x1200;

    // BPLCON1
    CopperList[Index++] = 0x102;
    CopperList[Index++] = 0x0000;

  	// Bitplane pointers
    CopperList[Index++] = 0x0E0;
    BPL1PTH_Idx = (UWORD)Index;
    CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0E2;
    BPL1PTL_Idx = (UWORD)Index;
    CopperList[Index++] = 0x0000;

    // Black background, white foreground
    CopperList[Index++] = 0x0180;
    CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x0182;
    CopperList[Index++] = 0x0FFF;

  	// Full-screen Copper sky in COLOR00 behind the vector balls.
    UWORD* CopperPtr = &CopperList[Index];

    for (UWORD y = 0; y < SCREENHEIGHT; ++y)
    {
        AddSkyLine(&CopperPtr, y);
    }

    Index = (ULONG)(CopperPtr - CopperList);

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

void Update_BitplanePointers(UBYTE Buffer)
{
    const ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0];
    CopperList[BPL1PTH_Idx] = (UWORD)(Ptr >> 16);
    CopperList[BPL1PTL_Idx] = (UWORD)(Ptr & 0xFFFFu);
}

// ---------------------------------------------------------------------
// Cleanup / main
// ---------------------------------------------------------------------

void Cleanup_All(void)
{
    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();
    lwmf_InitScreenBitmaps();

    lwmf_TakeOverOS();

    InitYRotationTables();
    InitProjectionTable();
    InitLookupRows();
    InitRockPhaseTable();
    InitObjects();
    InitStaticPackedFrames();

    Init_CopperList();

    UBYTE CurrentBuffer = 1;
    UBYTE RockPhase = 0;
    UBYTE CurrentObject = 0;
    UWORD StateFrame = 0;
    BOOL Morphing = FALSE;

    Update_BitplanePointers(0);

    while (*CIAA_PRA & 0x40)
    {
        UBYTE RotIndex = RockRotIndex[RockPhase];

        DrawTarget = (volatile long*)ScreenBitmap[CurrentBuffer]->Planes[0];
        lwmf_ClearScreen((long*)ScreenBitmap[CurrentBuffer]->Planes[0]);

        if (Morphing)
        {
            BOOL Advance = (BOOL)((StateFrame + 1u) < MORPH_FRAMES);
            BuildMorphPackedDotsAndAdvance(CurrentObject, RotIndex, Advance);
            lwmf_WaitBlitter();
            PlotPackedDots(MorphPackedXY);

            ++StateFrame;
            if (StateFrame >= MORPH_FRAMES)
            {
                StateFrame = 0;
                Morphing = FALSE;
                CurrentObject = (UBYTE)((CurrentObject + 1u) % OBJECT_COUNT);
            }
        }
        else
        {
            const UWORD* Packed = &StaticPackedXY[STATIC_INDEX(CurrentObject, RotIndex, 0)];
            lwmf_WaitBlitter();
            PlotPackedDots(Packed);

            ++StateFrame;
            if (StateFrame >= HOLD_FRAMES)
            {
                StateFrame = 0;
                Morphing = TRUE;
                InitMorphState(CurrentObject);
            }
        }

        lwmf_WaitVertBlank();
        Update_BitplanePointers(CurrentBuffer);
        CurrentBuffer ^= 1u;
        RockPhase = (UBYTE)((RockPhase + 2u) & ANGLE_MASK);
    }

    Cleanup_All();
    return 0;
}
