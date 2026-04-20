//**********************************************************************
//* Amiga morph effect                                                  *
//* Amiga 500 OCS                                                       *
//*                                                                    *
//* (C) 2020-2026 by Stefan Kubsch                                     *
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
#define OCTA_EDGE_COUNT          12
#define ICOSA_EDGE_COUNT         30
#define POINT_COUNT              SPHERE_POINT_COUNT

#define ANGLE_MASK               255
#define FP_SHIFT                  8
#define MORPH_FRAMES             40
#define HOLD_FRAMES              160

#define CENTER_X                 (SCREENWIDTH / 2)
#define CENTER_Y                 (SCREENHEIGHT / 2)
#define PROJ_DIST                300
#define Z_OFFSET                 440

#define SPHERE_RADIUS             78
#define OCTA_RADIUS               82
#define ICOSA_UNIT                50
#define ICOSA_PHI                 81

#define BASE_ANGLE_X              20
#define BASE_ANGLE_Y              20
#define ROCK_ANGLE_Y              56

#define YROT_MIN_ANGLE           (BASE_ANGLE_Y - ROCK_ANGLE_Y)
#define YROT_MAX_ANGLE           (BASE_ANGLE_Y + ROCK_ANGLE_Y)
#define YROT_ANGLE_COUNT         (YROT_MAX_ANGLE - YROT_MIN_ANGLE + 1)

#define PHASE_STEP_COUNT        128
#define ROTATION_SLOT_COUNT      58

#define SRC_COORD_BIAS          100
#define SRC_COORD_RANGE         ((SRC_COORD_BIAS * 2) + 1)
#define PROJ_COORD_BIAS         125
#define PROJ_COORD_RANGE        ((PROJ_COORD_BIAS * 2) + 1)
#define PROJ_Z_MIN              316
#define PROJ_Z_MAX              562
#define PROJ_Z_RANGE            (PROJ_Z_MAX - PROJ_Z_MIN + 1)

typedef signed char SBYTE;

typedef struct
{
    SBYTE x;
    SBYTE y;
    SBYTE z;
} POINT3D8;

typedef struct
{
    WORD x;
    WORD y;
    WORD z;
} POINT3D;

typedef struct
{
    UBYTE a;
    UBYTE b;
} EDGE;

#define OBJECT_INDEX(obj, pt)    ((ULONG)(obj) * (ULONG)POINT_COUNT + (ULONG)(pt))

#define SCREEN_WORDS_PER_ROW     (SCREENWIDTH >> 4)
#define SCREEN_WORD_COUNT        (SCREEN_WORDS_PER_ROW * SCREENHEIGHT)

#if (CENTER_X != 160) || (CENTER_Y != 128) || (SRC_COORD_BIAS != 100) || \
    (PROJ_COORD_BIAS != 125) || ((Z_OFFSET - PROJ_Z_MIN) != 124) || \
    (SCREEN_WORDS_PER_ROW != 20) || (FP_SHIFT != 8)
#error VASM core expects the current fixed projection and screen constants
#endif

extern UWORD BuildMorphWordMaskFrameAdvanceAsm(
    POINT3D* Cur,
    const POINT3D* Step,
    ULONG PointCount,
    const SBYTE* RotC,
    const SBYTE* RotS,
    const SBYTE* const* ProjRows,
    UWORD* WordMaskAccum,
    UWORD* FrameWordIndex);

extern UWORD BuildStaticWordMaskFrameAsm(
    const POINT3D8* Points,
    ULONG PointCount,
    const SBYTE* RotC,
    const SBYTE* RotS,
    const SBYTE* const* ProjRows,
    UWORD* WordMaskAccum,
    UWORD* FrameWordIndex);

extern void UpdateFrameWordsAsm(
    UWORD* Plane,
    UWORD* PrevOffset,
    UWORD* PrevCount,
    ULONG FrameWordCount,
    UWORD* WordMaskAccum,
    const UWORD* FrameWordIndex);

static POINT3D8 ObjectPoints[OBJECT_COUNT * POINT_COUNT];
static POINT3D MorphStep[POINT_COUNT];
static POINT3D MorphCur[POINT_COUNT];
static SBYTE RotCosY[ROTATION_SLOT_COUNT * SRC_COORD_RANGE];
static SBYTE RotSinY[ROTATION_SLOT_COUNT * SRC_COORD_RANGE];
static SBYTE ProjOffset[PROJ_Z_RANGE * PROJ_COORD_RANGE];
static const SBYTE* ProjRows[PROJ_Z_RANGE];
static UWORD FrameWordIndex[POINT_COUNT];
static UWORD PrevOffset[2][POINT_COUNT];
static UWORD PrevWordCount[2];
static UBYTE RockRotSlot[PHASE_STEP_COUNT];
static UWORD WordMaskAccum[SCREEN_WORD_COUNT];

static UWORD MorphMap[OBJECT_COUNT][POINT_COUNT];

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

static void InitRotationSlotsAndTables(void)
{
    SBYTE AngleToSlot[YROT_ANGLE_COUNT];
    UWORD SlotCount = 0;

    for (UWORD i = 0; i < YROT_ANGLE_COUNT; ++i)
    {
        AngleToSlot[i] = -1;
    }

    for (UWORD PhaseStep = 0; PhaseStep < PHASE_STEP_COUNT; ++PhaseStep)
    {
        const UWORD Phase = (UWORD)(PhaseStep << 1u);
        const WORD AngleY = (WORD)(BASE_ANGLE_Y + ((Sin256(Phase) * ROCK_ANGLE_Y) >> FP_SHIFT));
        const UWORD AngleIndex = (UWORD)(AngleY - YROT_MIN_ANGLE);
        SBYTE Slot = AngleToSlot[AngleIndex];

        if (Slot < 0)
        {
            const WORD sy = Sin256((UWORD)AngleY);
            const WORD cy = Cos256((UWORD)AngleY);
            const ULONG TableBase = (ULONG)SlotCount * (ULONG)SRC_COORD_RANGE;

            Slot = (SBYTE)SlotCount;
            AngleToSlot[AngleIndex] = Slot;
            ++SlotCount;

            for (WORD c = -SRC_COORD_BIAS; c <= SRC_COORD_BIAS; ++c)
            {
                const UWORD ci = (UWORD)(c + SRC_COORD_BIAS);
                RotCosY[TableBase + ci] = (SBYTE)(((LONG)c * (LONG)cy) >> FP_SHIFT);
                RotSinY[TableBase + ci] = (SBYTE)(((LONG)c * (LONG)sy) >> FP_SHIFT);
            }
        }

        RockRotSlot[PhaseStep] = (UBYTE)Slot;
    }
}

static void InitProjectionTable(void)
{
    for (WORD z = PROJ_Z_MIN; z <= PROJ_Z_MAX; ++z)
    {
        const ULONG TableBase = (ULONG)(z - PROJ_Z_MIN) * (ULONG)PROJ_COORD_RANGE;
        SBYTE* const Row = &ProjOffset[TableBase];

        ProjRows[z - PROJ_Z_MIN] = Row + PROJ_COORD_BIAS;

        for (WORD c = -PROJ_COORD_BIAS; c <= PROJ_COORD_BIAS; ++c)
        {
            const UWORD ci = (UWORD)(c + PROJ_COORD_BIAS);
            Row[ci] = (SBYTE)(((LONG)c * (LONG)PROJ_DIST) / (LONG)z);
        }
    }
}

static void InitSpherePoints(void)
{
    UWORD Index = 0;
    POINT3D8* Out = &ObjectPoints[OBJECT_INDEX(0, 0)];

    for (UWORD ring = 0; ring < SPHERE_RINGS; ++ring)
    {
        const UWORD LatAngle = (UWORD)(192u + ((ring * 128u) / (SPHERE_RINGS - 1u)));
        const WORD y = (WORD)(((LONG)Sin256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const WORD ringRadius = (WORD)(((LONG)Cos256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const UWORD ringOffset = (UWORD)((ring & 1u) ? 2u : 0u);

        for (UWORD seg = 0; seg < POINTS_PER_RING; ++seg)
        {
            const UWORD Angle = (UWORD)(ringOffset + ((seg * 256u) / POINTS_PER_RING));

            Out[Index].x = (SBYTE)(((LONG)Cos256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            Out[Index].y = (SBYTE)y;
            Out[Index].z = (SBYTE)(((LONG)Sin256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            ++Index;
        }
    }
}

static const POINT3D8 OctaVerts[6] =
{
    {   0,  OCTA_RADIUS,   0 },
    {   0, -OCTA_RADIUS,   0 },
    { -OCTA_RADIUS, 0,     0 },
    {  OCTA_RADIUS, 0,     0 },
    {   0, 0, -OCTA_RADIUS },
    {   0, 0,  OCTA_RADIUS }
};

static const EDGE OctaEdges[OCTA_EDGE_COUNT] =
{
    { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 },
    { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 },
    { 2, 4 }, { 2, 5 }, { 3, 4 }, { 3, 5 }
};

static const POINT3D8 IcosaVerts[12] =
{
    {   0, -ICOSA_UNIT, -ICOSA_PHI }, {   0, -ICOSA_UNIT,  ICOSA_PHI },
    {   0,  ICOSA_UNIT, -ICOSA_PHI }, {   0,  ICOSA_UNIT,  ICOSA_PHI },
    { -ICOSA_UNIT, -ICOSA_PHI, 0 },   { -ICOSA_UNIT,  ICOSA_PHI, 0 },
    {  ICOSA_UNIT, -ICOSA_PHI, 0 },   {  ICOSA_UNIT,  ICOSA_PHI, 0 },
    { -ICOSA_PHI, 0, -ICOSA_UNIT },   { -ICOSA_PHI, 0,  ICOSA_UNIT },
    {  ICOSA_PHI, 0, -ICOSA_UNIT },   {  ICOSA_PHI, 0,  ICOSA_UNIT }
};

static const EDGE IcosaEdges[ICOSA_EDGE_COUNT] =
{
    { 0, 2 }, { 0, 4 }, { 0, 6 }, { 0, 8 }, { 0, 10 },
    { 1, 3 }, { 1, 4 }, { 1, 6 }, { 1, 9 }, { 1, 11 },
    { 2, 5 }, { 2, 7 }, { 2, 8 }, { 2, 10 },
    { 3, 5 }, { 3, 7 }, { 3, 9 }, { 3, 11 },
    { 4, 6 }, { 4, 8 }, { 4, 9 },
    { 5, 7 }, { 5, 8 }, { 5, 9 },
    { 6, 10 }, { 6, 11 },
    { 7, 10 }, { 7, 11 },
    { 8, 9 },
    { 10, 11 }
};

static void InitWireObject(UWORD ObjIndex, const POINT3D8* Verts, UWORD VertexCount, const EDGE* Edges, UWORD EdgeCount)
{
    UWORD Index = 0;
    POINT3D8* Out = &ObjectPoints[OBJECT_INDEX(ObjIndex, 0)];
    const UWORD InteriorPerEdge = (UWORD)((POINT_COUNT - VertexCount) / EdgeCount);
    const UWORD InteriorRemainder = (UWORD)((POINT_COUNT - VertexCount) % EdgeCount);

    for (UWORD vertex = 0; vertex < VertexCount; ++vertex)
    {
        Out[Index++] = Verts[vertex];
    }

    for (UWORD edge = 0; edge < EdgeCount; ++edge)
    {
        const POINT3D8* A = &Verts[Edges[edge].a];
        const POINT3D8* B = &Verts[Edges[edge].b];
        const UWORD Count = (UWORD)(InteriorPerEdge + ((edge < InteriorRemainder) ? 1u : 0u));

        for (UWORD step = 0; step < Count; ++step)
        {
            const UWORD Numer = (UWORD)(step + 1u);
            const UWORD Denom = (UWORD)(Count + 1u);

            Out[Index].x = (SBYTE)LerpFracCoord((WORD)A->x, (WORD)B->x, Numer, Denom);
            Out[Index].y = (SBYTE)LerpFracCoord((WORD)A->y, (WORD)B->y, Numer, Denom);
            Out[Index].z = (SBYTE)LerpFracCoord((WORD)A->z, (WORD)B->z, Numer, Denom);
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
        POINT3D8* P = &ObjectPoints[OBJECT_INDEX(Obj, 0)];

        for (UWORD i = 0; i < POINT_COUNT; ++i)
        {
            const WORD y = (WORD)P[i].y;
            const WORD z = (WORD)P[i].z;

            P[i].y = (SBYTE)(MulS8(y, cx) - MulS8(z, sx));
            P[i].z = (SBYTE)(MulS8(y, sx) + MulS8(z, cx));
        }
    }
}

static WORD AbsW(WORD v)
{
    return (WORD)((v < 0) ? -v : v);
}

static BOOL IsFrontHalfXZ(const POINT3D8* P)
{
    return (BOOL)((P->z > 0) || ((P->z == 0) && (P->x >= 0)));
}

static BOOL PointSortBefore(const POINT3D8* Points, UWORD a, UWORD b)
{
    const POINT3D8* Pa = &Points[a];
    const POINT3D8* Pb = &Points[b];

    if (Pa->y != Pb->y)
    {
        return (BOOL)(Pa->y > Pb->y);
    }

    {
        const BOOL Ha = IsFrontHalfXZ(Pa);
        const BOOL Hb = IsFrontHalfXZ(Pb);

        if (Ha != Hb)
        {
            return (BOOL)(Ha > Hb);
        }
    }

    {
        const LONG Cross = ((LONG)(WORD)Pa->x * (LONG)(WORD)Pb->z) - ((LONG)(WORD)Pa->z * (LONG)(WORD)Pb->x);

        if (Cross != 0)
        {
            return (BOOL)(Cross > 0);
        }
    }

    {
        const WORD Ra = (WORD)(AbsW((WORD)Pa->x) + AbsW((WORD)Pa->z));
        const WORD Rb = (WORD)(AbsW((WORD)Pb->x) + AbsW((WORD)Pb->z));

        if (Ra != Rb)
        {
            return (BOOL)(Ra > Rb);
        }
    }

    return (BOOL)(a < b);
}

static void SortPointOrder(const POINT3D8* Points)
{
    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        FrameWordIndex[i] = i;
    }

    for (UWORD Gap = (UWORD)(POINT_COUNT >> 1); Gap != 0; Gap >>= 1)
    {
        for (UWORD i = Gap; i < POINT_COUNT; ++i)
        {
            const UWORD Temp = FrameWordIndex[i];
            UWORD j = i;

            while ((j >= Gap) && PointSortBefore(Points, Temp, FrameWordIndex[j - Gap]))
            {
                FrameWordIndex[j] = FrameWordIndex[j - Gap];
                j = (UWORD)(j - Gap);
            }

            FrameWordIndex[j] = Temp;
        }
    }
}

static UWORD PointDistance(const POINT3D8* A, const POINT3D8* B)
{
    return (UWORD)(AbsW((WORD)A->x - (WORD)B->x) +
                   AbsW((WORD)A->y - (WORD)B->y) +
                   AbsW((WORD)A->z - (WORD)B->z));
}

static void BuildMorphMap(UWORD Obj)
{
    const UWORD Next = (UWORD)((Obj + 1u) % OBJECT_COUNT);
    const POINT3D8* Src = &ObjectPoints[OBJECT_INDEX(Obj, 0)];
    const POINT3D8* Dst = &ObjectPoints[OBJECT_INDEX(Next, 0)];
    UWORD* Map = MorphMap[Obj];
    UBYTE* Used = (UBYTE*)MorphCur;

    SortPointOrder(Src);

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        Used[i] = 0u;
    }

    for (UWORD Rank = 0; Rank < POINT_COUNT; ++Rank)
    {
        const UWORD SrcIndex = FrameWordIndex[Rank];
        UWORD BestDst = 0;
        UWORD BestDist = 0xFFFFu;

        for (UWORD DstIndex = 0; DstIndex < POINT_COUNT; ++DstIndex)
        {
            if (!Used[DstIndex])
            {
                const UWORD Dist = PointDistance(&Src[SrcIndex], &Dst[DstIndex]);

                if ((Dist < BestDist) ||
                    ((Dist == BestDist) && PointSortBefore(Dst, DstIndex, BestDst)))
                {
                    BestDist = Dist;
                    BestDst = DstIndex;
                }
            }
        }

        Used[BestDst] = 1u;
        Map[SrcIndex] = BestDst;
    }
}

static void InitMorphMaps(void)
{
    for (UWORD Obj = 0; Obj < OBJECT_COUNT; ++Obj)
    {
        BuildMorphMap(Obj);
    }
}

static void InitObjects(void)
{
    InitSpherePoints();
    InitWireObject(1, OctaVerts,  (UWORD)(sizeof(OctaVerts) / sizeof(OctaVerts[0])), OctaEdges,  (UWORD)(sizeof(OctaEdges) / sizeof(OctaEdges[0])));
    InitWireObject(2, IcosaVerts, (UWORD)(sizeof(IcosaVerts) / sizeof(IcosaVerts[0])), IcosaEdges, (UWORD)(sizeof(IcosaEdges) / sizeof(IcosaEdges[0])));
    ApplyBaseXTilt();
    InitMorphMaps();
}

static UWORD BuildStaticWordMaskFrame(UWORD ObjIndex, UBYTE RotSlot)
{
    const ULONG RotBase = (ULONG)RotSlot * (ULONG)SRC_COORD_RANGE;

    return BuildStaticWordMaskFrameAsm(&ObjectPoints[OBJECT_INDEX(ObjIndex, 0)], (ULONG)POINT_COUNT,
                                       &RotCosY[RotBase + SRC_COORD_BIAS], &RotSinY[RotBase + SRC_COORD_BIAS],
                                       &ProjRows[Z_OFFSET - PROJ_Z_MIN], WordMaskAccum, FrameWordIndex);
}

static void InitMorphState(UWORD PairIndex)
{
    const UWORD Next = (UWORD)((PairIndex + 1u) % OBJECT_COUNT);
    const POINT3D8* Src = &ObjectPoints[OBJECT_INDEX(PairIndex, 0)];
    const POINT3D8* Dst = &ObjectPoints[OBJECT_INDEX(Next, 0)];
    const UWORD* Map = MorphMap[PairIndex];

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        const POINT3D8* Target = &Dst[Map[i]];

        MorphCur[i].x = (WORD)((LONG)(WORD)Src[i].x * (LONG)(1u << FP_SHIFT));
        MorphCur[i].y = (WORD)((LONG)(WORD)Src[i].y * (LONG)(1u << FP_SHIFT));
        MorphCur[i].z = (WORD)((LONG)(WORD)Src[i].z * (LONG)(1u << FP_SHIFT));

        if (MORPH_FRAMES > 1)
        {
            MorphStep[i].x = (WORD)((((LONG)((WORD)Target->x - (WORD)Src[i].x)) * (LONG)(1u << FP_SHIFT)) / (LONG)(MORPH_FRAMES - 1));
            MorphStep[i].y = (WORD)((((LONG)((WORD)Target->y - (WORD)Src[i].y)) * (LONG)(1u << FP_SHIFT)) / (LONG)(MORPH_FRAMES - 1));
            MorphStep[i].z = (WORD)((((LONG)((WORD)Target->z - (WORD)Src[i].z)) * (LONG)(1u << FP_SHIFT)) / (LONG)(MORPH_FRAMES - 1));
        }
        else
        {
            MorphStep[i].x = 0;
            MorphStep[i].y = 0;
            MorphStep[i].z = 0;
        }
    }
}

static UWORD BuildMorphWordMaskFrameAdvance(UBYTE RotSlot)
{
    const ULONG RotBase = (ULONG)RotSlot * (ULONG)SRC_COORD_RANGE;

    return BuildMorphWordMaskFrameAdvanceAsm(MorphCur, MorphStep, (ULONG)POINT_COUNT,
                                             &RotCosY[RotBase + SRC_COORD_BIAS], &RotSinY[RotBase + SRC_COORD_BIAS],
                                             &ProjRows[Z_OFFSET - PROJ_Z_MIN], WordMaskAccum, FrameWordIndex);
}

static void UpdateFrameWords(UWORD* Plane, UBYTE Buffer, UWORD FrameWordCount)
{
    UpdateFrameWordsAsm(Plane, PrevOffset[Buffer], &PrevWordCount[Buffer], FrameWordCount, WordMaskAccum, FrameWordIndex);
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
    CopperListSize = 0;
    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    lwmf_LoadGraphicsLib();
    lwmf_InitScreenBitmaps();

    lwmf_TakeOverOS();

    InitRotationSlotsAndTables();
    InitProjectionTable();
    InitObjects();

    Init_CopperList();

    lwmf_ClearScreen((long*)ScreenBitmap[0]->Planes[0]);
    lwmf_ClearScreen((long*)ScreenBitmap[1]->Planes[0]);

    UBYTE CurrentBuffer = 1;
    UBYTE RockPhaseStep = 0;
    UBYTE CurrentObject = 0;
    UWORD StateFrame = 0;
    BOOL Morphing = FALSE;

    Update_BitplanePointers(0);

    while (*CIAA_PRA & 0x40)
    {
        const UBYTE RotSlot = RockRotSlot[RockPhaseStep];
        UWORD FrameWordCount;

        if (Morphing)
        {
            if ((StateFrame + 1u) < MORPH_FRAMES)
            {
                FrameWordCount = BuildMorphWordMaskFrameAdvance(RotSlot);
            }
            else
            {
                FrameWordCount = BuildStaticWordMaskFrame((UWORD)((CurrentObject + 1u) % OBJECT_COUNT), RotSlot);
            }

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
            FrameWordCount = BuildStaticWordMaskFrame(CurrentObject, RotSlot);

            ++StateFrame;
            if (StateFrame >= HOLD_FRAMES)
            {
                StateFrame = 0;
                Morphing = TRUE;
                InitMorphState(CurrentObject);
            }
        }

        UpdateFrameWords((UWORD*)ScreenBitmap[CurrentBuffer]->Planes[0], CurrentBuffer, FrameWordCount);

        lwmf_WaitVertBlank();
        Update_BitplanePointers(CurrentBuffer);
        CurrentBuffer ^= 1u;
        RockPhaseStep = (UBYTE)((RockPhaseStep + 1u) & (PHASE_STEP_COUNT - 1u));
    }

    Cleanup_All();
    return 0;
}
