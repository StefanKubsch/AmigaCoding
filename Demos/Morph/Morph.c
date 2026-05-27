//**********************************************************************
//* Morph effect                                                   *
//* Amiga 500 OCS                                                      *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch / Deep4                                  *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Build.cmd / make_ADF.cmd                                      *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

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

typedef struct
{
    WORD x;
    WORD y;
} POINT2D;

extern UWORD BuildMorphWordMaskFrameAdvanceAsm(POINT3D* Cur, const POINT3D* Step, ULONG PointCount, const SBYTE* RotC, const SBYTE* RotS, const SBYTE* const* ProjRows, UWORD* WordMaskAccum, UWORD* FrameWordIndex);
extern UWORD BuildStaticWordMaskFrameAsm(const POINT3D8* Points, ULONG PointCount, const SBYTE* RotC, const SBYTE* RotS, const SBYTE* const* ProjRows, UWORD* WordMaskAccum, UWORD* FrameWordIndex);
extern void UpdateFrameWordsAsm(UWORD* Plane, UWORD* PrevOffset, UWORD* PrevCount, ULONG FrameWordCount, UWORD* WordMaskAccum, const UWORD* FrameWordIndex);
extern void BlitClearPlaneAsm(__reg("a0") UWORD* Plane);
extern void BlitClearWireRectAsm(__reg("a0") UWORD* Plane);
extern void DrawBlitterLinesAsm(__reg("a0") UWORD* Plane, __reg("a1") const POINT2D* Verts, __reg("a2") const EDGE* Edges);


#define OBJECT_COUNT              2
#define SPHERE_RINGS             12
#define POINTS_PER_RING          36
#define SPHERE_POINT_COUNT       (SPHERE_RINGS * POINTS_PER_RING)
#define ICOSA_VERTEX_COUNT       12
#define ICOSA_EDGE_COUNT         30

#define POINT_COUNT              SPHERE_POINT_COUNT

#define ANGLE_MASK               255
#define FP_SHIFT                  8
#define FP_ONE                    (1 << FP_SHIFT)
#define MORPH_FRAMES             40
#define HOLD_FRAMES              160

#define CENTER_X                 (SCREENWIDTH / 2)
#define CENTER_Y                 (SCREENHEIGHT / 2)
#define PROJ_DIST                400
#define Z_OFFSET                 440

#define SPHERE_RADIUS             90
#define ICOSA_SHORT               59
#define ICOSA_LONG                95

#define BASE_ANGLE_X              20
#define BASE_ANGLE_Y              20
#define ROCK_ANGLE_Y              56

#define YROT_MIN_ANGLE           (BASE_ANGLE_Y - ROCK_ANGLE_Y)
#define YROT_MAX_ANGLE           (BASE_ANGLE_Y + ROCK_ANGLE_Y)
#define YROT_ANGLE_COUNT         (YROT_MAX_ANGLE - YROT_MIN_ANGLE + 1)

#define PHASE_STEP_COUNT        128
#define ROTATION_SLOT_COUNT      58

#define SRC_COORD_BIAS          128
#define SRC_COORD_RANGE         ((SRC_COORD_BIAS * 2) + 1)
#define PROJ_COORD_BIAS         140
#define PROJ_COORD_RANGE        ((PROJ_COORD_BIAS * 2) + 1)
#define PROJ_Z_MIN              316
#define PROJ_Z_MAX              562
#define PROJ_Z_RANGE            (PROJ_Z_MAX - PROJ_Z_MIN + 1)

#define OBJECT_INDEX(obj, pt)    ((obj) * POINT_COUNT + (pt))

#define SCREEN_WORDS_PER_ROW     (SCREENWIDTH >> 4)
#define SCREEN_WORD_COUNT        (SCREEN_WORDS_PER_ROW * SCREENHEIGHT)

#define BLUR_PLANES               3
#define SCREEN_LAYER_SIZE         ((SCREENWIDTH >> 3) * SCREENHEIGHT)
#define SCREEN_BUFFER_SIZE        (SCREEN_LAYER_SIZE * BLUR_PLANES)

static POINT3D8 ObjectPoints[OBJECT_COUNT * POINT_COUNT];
static POINT3D MorphStep[POINT_COUNT];
static POINT3D MorphCur[POINT_COUNT];
static SBYTE RotCosY[ROTATION_SLOT_COUNT * SRC_COORD_RANGE];
static SBYTE RotSinY[ROTATION_SLOT_COUNT * SRC_COORD_RANGE];
static const SBYTE* RotCosPtr[ROTATION_SLOT_COUNT];
static const SBYTE* RotSinPtr[ROTATION_SLOT_COUNT];
static SBYTE ProjOffset[PROJ_Z_RANGE * PROJ_COORD_RANGE];
static const SBYTE* ProjRows[PROJ_Z_RANGE];
static UWORD FrameWordIndex[POINT_COUNT];
static UWORD PrevOffset[2][BLUR_PLANES][POINT_COUNT];
static UWORD PrevWordCount[2][BLUR_PLANES];
static UBYTE RockRotSlot[PHASE_STEP_COUNT];
static UWORD WordMaskAccum[SCREEN_WORD_COUNT];
static POINT2D WireVerts[ICOSA_VERTEX_COUNT];

static UBYTE* ScreenBuffer[2];
static UBYTE* ScreenPlane[2][BLUR_PLANES];
static UBYTE TrailHead[2];


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
    const UWORD a = Angle & ANGLE_MASK;
    const UWORD q = a >> 6;
    const UWORD t = a & 63;

    switch (q)
    {
        case 0:  return QuarterSin[t];
        case 1:  return QuarterSin[64 - t];
        case 2:  return (WORD)-QuarterSin[t];
        default: return (WORD)-QuarterSin[64 - t];
    }
}

static WORD Cos256(UWORD Angle)
{
    return Sin256((Angle + 64) & ANGLE_MASK);
}

static WORD MulS8(WORD a, WORD b)
{
    return ((LONG)a * b) >> FP_SHIFT;
}

static WORD LerpFracCoord(WORD a, WORD b, UWORD numer, UWORD denom)
{
    return a + (((LONG)(b - a) * numer) / denom);
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
        const UWORD Phase = PhaseStep << 1;
        const WORD AngleY = BASE_ANGLE_Y + ((Sin256(Phase) * ROCK_ANGLE_Y) >> FP_SHIFT);
        const UWORD AngleIndex = AngleY - YROT_MIN_ANGLE;
        SBYTE Slot = AngleToSlot[AngleIndex];

        if (Slot < 0)
        {
            const WORD sy = Sin256((UWORD)AngleY);
            const WORD cy = Cos256((UWORD)AngleY);
            const ULONG TableBase = (ULONG)SlotCount * (ULONG)SRC_COORD_RANGE;

            Slot = (SBYTE)SlotCount;
            AngleToSlot[AngleIndex] = Slot;
            ++SlotCount;

            RotCosPtr[Slot] = &RotCosY[TableBase + SRC_COORD_BIAS];
            RotSinPtr[Slot] = &RotSinY[TableBase + SRC_COORD_BIAS];

            for (WORD c = -SRC_COORD_BIAS; c <= SRC_COORD_BIAS; ++c)
            {
                const UWORD ci = c + SRC_COORD_BIAS;
                RotCosY[TableBase + ci] = (SBYTE)(((LONG)c * cy) >> FP_SHIFT);
                RotSinY[TableBase + ci] = (SBYTE)(((LONG)c * sy) >> FP_SHIFT);
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
            const UWORD ci = c + PROJ_COORD_BIAS;
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
        const UWORD LatAngle = (UWORD)(192 + ((ring * 128) / (SPHERE_RINGS - 1)));
        const WORD y = (WORD)(((LONG)Sin256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const WORD ringRadius = (WORD)(((LONG)Cos256(LatAngle) * (LONG)SPHERE_RADIUS) >> FP_SHIFT);
        const UWORD ringOffset = (UWORD)((ring & 1) ? 2 : 0);

        for (UWORD seg = 0; seg < POINTS_PER_RING; ++seg)
        {
            const UWORD Angle = (UWORD)(ringOffset + ((seg * 256) / POINTS_PER_RING));

            Out[Index].x = (SBYTE)(((LONG)Cos256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            Out[Index].y = (SBYTE)y;
            Out[Index].z = (SBYTE)(((LONG)Sin256(Angle) * (LONG)ringRadius) >> FP_SHIFT);
            ++Index;
        }
    }
}

static const POINT3D8 IcosaVerts[ICOSA_VERTEX_COUNT] =
{
    { 0,            ICOSA_SHORT,  ICOSA_LONG  },
    { 0,            ICOSA_SHORT, -ICOSA_LONG  },
    { 0,           -ICOSA_SHORT,  ICOSA_LONG  },
    { 0,           -ICOSA_SHORT, -ICOSA_LONG  },
    { ICOSA_SHORT,  ICOSA_LONG,   0           },
    { ICOSA_SHORT, -ICOSA_LONG,   0           },
    {-ICOSA_SHORT,  ICOSA_LONG,   0           },
    {-ICOSA_SHORT, -ICOSA_LONG,   0           },
    { ICOSA_LONG,   0,            ICOSA_SHORT },
    { ICOSA_LONG,   0,           -ICOSA_SHORT },
    {-ICOSA_LONG,   0,            ICOSA_SHORT },
    {-ICOSA_LONG,   0,           -ICOSA_SHORT }
};

static const EDGE IcosaEdges[ICOSA_EDGE_COUNT] =
{
    { 0,  2 }, { 0,  4 }, { 0,  6 }, { 0,  8 }, { 0, 10 },
    { 1,  3 }, { 1,  4 }, { 1,  6 }, { 1,  9 }, { 1, 11 },
    { 2,  5 }, { 2,  7 }, { 2,  8 }, { 2, 10 },
    { 3,  5 }, { 3,  7 }, { 3,  9 }, { 3, 11 },
    { 4,  6 }, { 4,  8 }, { 4,  9 },
    { 5,  7 }, { 5,  8 }, { 5,  9 },
    { 6, 10 }, { 6, 11 },
    { 7, 10 }, { 7, 11 },
    { 8,  9 }, {10, 11 }
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
        const UWORD Count = InteriorPerEdge + ((edge < InteriorRemainder) ? 1 : 0);

        for (UWORD step = 0; step < Count; ++step)
        {
            const UWORD Numer = step + 1;
            const UWORD Denom = Count + 1;

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

static const UWORD MorphMap[OBJECT_COUNT][POINT_COUNT] =
{
    {
        1, 249, 250, 251, 106, 107, 311, 108, 254, 109, 307, 255,
        316, 315, 5, 111, 319, 389, 388, 431, 361, 112, 256, 322,
        323, 393, 113, 325, 395, 324, 394, 326, 396, 4, 372, 180,
        258, 186, 216, 367, 365, 364, 362, 363, 77, 2, 41, 292,
        293, 294, 295, 183, 222, 259, 150, 151, 152, 153, 156, 155,
        154, 227, 226, 225, 224, 188, 190, 191, 192, 189, 223, 187,
        193, 262, 263, 265, 219, 221, 397, 76, 75, 40, 3, 39,
        327, 185, 184, 257, 264, 261, 157, 158, 160, 163, 164, 161,
        228, 230, 233, 232, 231, 229, 194, 197, 199, 200, 198, 195,
        201, 196, 215, 270, 268, 266, 399, 398, 220, 328, 329, 330,
        260, 267, 271, 269, 159, 162, 165, 167, 169, 170, 168, 234,
        236, 241, 239, 238, 240, 237, 235, 202, 205, 207, 204, 203,
        209, 214, 210, 206, 276, 278, 280, 282, 274, 272, 273, 275,
        281, 279, 277, 166, 172, 179, 173, 175, 178, 176, 306, 242,
        243, 248, 245, 246, 247, 244, 383, 379, 375, 211, 213, 212,
        218, 400, 404, 407, 208, 283, 286, 288, 289, 284, 290, 287,
        285, 171, 174, 177, 333, 181, 182, 297, 298, 301, 303, 309,
        312, 318, 253, 252, 391, 385, 380, 378, 373, 369, 368, 217,
        74, 401, 402, 406, 412, 413, 427, 429, 430, 291, 360, 359,
        358, 337, 343, 335, 332, 331, 38, 296, 300, 304, 310, 314,
        317, 320, 321, 110, 392, 390, 387, 384, 381, 376, 370, 366,
        73, 403, 405, 408, 410, 415, 422, 425, 428, 149, 356, 352,
        349, 342, 339, 336, 334, 37, 36, 35, 299, 302, 305, 308,
        313, 102, 105, 104, 103, 386, 382, 377, 374, 371, 71, 72,
        69, 70, 409, 411, 414, 418, 420, 423, 146, 148, 147, 354,
        351, 347, 344, 341, 340, 338, 34, 33, 32, 29, 26, 22,
        100, 96, 98, 99, 97, 95, 94, 58, 62, 64, 66, 68,
        65, 67, 416, 417, 419, 421, 424, 426, 144, 145, 357, 355,
        353, 350, 348, 346, 345, 31, 30, 28, 24, 21, 19, 16,
        88, 91, 93, 92, 90, 89, 87, 53, 55, 57, 61, 63,
        59, 60, 131, 132, 134, 136, 138, 140, 141, 143, 142, 101,
        139, 137, 135, 133, 27, 25, 23, 20, 15, 14, 13, 11,
        80, 82, 83, 84, 85, 86, 81, 47, 48, 49, 50, 56,
        115, 116, 78, 79, 45, 9, 43, 7, 44, 8, 114, 117,
        42, 6, 0, 46, 10, 118, 119, 120, 12, 121, 122, 123,
        124, 51, 125, 52, 126, 127, 17, 128, 54, 18, 129, 130
    },
    {
        396, 381, 126, 184, 172, 2, 401, 405, 408, 410, 378, 377,
        379, 376, 380, 375, 342, 341, 340, 343, 306, 339, 344, 305,
        307, 304, 270, 303, 269, 271, 308, 268, 234, 235, 233, 197,
        232, 196, 160, 266, 159, 194, 398, 404, 406, 409, 360, 361,
        362, 363, 395, 394, 324, 325, 359, 326, 327, 288, 358, 289,
        290, 323, 252, 291, 287, 253, 286, 254, 216, 217, 218, 181,
        180, 182, 219, 322, 147, 256, 397, 400, 402, 403, 387, 388,
        386, 389, 385, 390, 351, 350, 352, 349, 353, 315, 316, 279,
        314, 317, 313, 278, 280, 277, 243, 281, 244, 242, 245, 207,
        241, 206, 208, 205, 171, 209, 399, 407, 411, 412, 369, 368,
        370, 367, 371, 366, 333, 332, 334, 331, 335, 297, 298, 296,
        299, 295, 261, 260, 262, 259, 225, 263, 226, 224, 227, 189,
        153, 330, 81, 80, 83, 45, 430, 425, 345, 382, 383, 346,
        311, 312, 34, 29, 24, 19, 14, 10, 56, 55, 54, 53,
        50, 51, 52, 95, 94, 93, 86, 92, 91, 90, 89, 87,
        88, 130, 310, 129, 128, 127, 357, 393, 392, 356, 391, 320,
        354, 319, 35, 30, 26, 20, 16, 11, 68, 69, 70, 71,
        36, 39, 37, 38, 103, 77, 104, 105, 106, 107, 72, 76,
        75, 73, 74, 140, 141, 142, 428, 422, 418, 348, 318, 32,
        25, 15, 57, 58, 67, 59, 66, 60, 65, 61, 96, 64,
        62, 63, 139, 102, 131, 97, 101, 138, 132, 98, 100, 137,
        99, 133, 136, 134, 135, 431, 429, 427, 426, 424, 423, 421,
        420, 419, 417, 416, 415, 347, 355, 414, 413, 384, 33, 31,
        28, 27, 23, 22, 21, 18, 17, 13, 12, 9, 8, 7,
        6, 5, 4, 3, 123, 230, 125, 309, 124, 195, 231, 267,
        161, 162, 198, 163, 272, 164, 165, 199, 273, 166, 200, 236,
        274, 167, 201, 237, 275, 168, 202, 238, 276, 203, 239, 169,
        204, 240, 170, 265, 158, 122, 229, 193, 264, 157, 228, 192,
        121, 156, 302, 120, 191, 155, 301, 190, 154, 300, 338, 337,
        119, 336, 118, 117, 373, 372, 84, 374, 85, 48, 47, 46,
        49, 1, 111, 220, 110, 183, 321, 109, 146, 255, 108, 145,
        144, 143, 179, 215, 285, 251, 178, 214, 177, 284, 250, 213,
        176, 283, 249, 212, 175, 282, 248, 211, 174, 247, 210, 173,
        246, 148, 257, 221, 112, 185, 149, 222, 258, 292, 150, 186,
        223, 113, 151, 187, 293, 152, 188, 294, 114, 328, 329, 115,
        116, 364, 365, 78, 79, 82, 40, 41, 42, 43, 44, 0
    }
};

static void InitObjects(void)
{
    InitSpherePoints();
    InitWireObject(1, IcosaVerts, ICOSA_VERTEX_COUNT, IcosaEdges, ICOSA_EDGE_COUNT);
    ApplyBaseXTilt();
}

static UWORD BuildStaticWordMaskFrame(UWORD ObjIndex, UBYTE RotSlot)
{
    return BuildStaticWordMaskFrameAsm(&ObjectPoints[OBJECT_INDEX(ObjIndex, 0)], POINT_COUNT, RotCosPtr[RotSlot], RotSinPtr[RotSlot], &ProjRows[Z_OFFSET - PROJ_Z_MIN], WordMaskAccum, FrameWordIndex);
}

static void InitMorphState(UWORD PairIndex)
{
    const UWORD Next = (PairIndex + 1) % OBJECT_COUNT;
    const POINT3D8* Src = &ObjectPoints[OBJECT_INDEX(PairIndex, 0)];
    const POINT3D8* Dst = &ObjectPoints[OBJECT_INDEX(Next, 0)];
    const UWORD* Map = MorphMap[PairIndex];

    for (UWORD i = 0; i < POINT_COUNT; ++i)
    {
        const POINT3D8* Target = &Dst[Map[i]];

        MorphCur[i].x = (WORD)Src[i].x * FP_ONE;
        MorphCur[i].y = (WORD)Src[i].y * FP_ONE;
        MorphCur[i].z = (WORD)Src[i].z * FP_ONE;

        MorphStep[i].x = ((WORD)(Target->x - Src[i].x) * FP_ONE) / (MORPH_FRAMES - 1);
        MorphStep[i].y = ((WORD)(Target->y - Src[i].y) * FP_ONE) / (MORPH_FRAMES - 1);
        MorphStep[i].z = ((WORD)(Target->z - Src[i].z) * FP_ONE) / (MORPH_FRAMES - 1);
    }
}

static UWORD BuildMorphWordMaskFrameAdvance(UBYTE RotSlot)
{
    return BuildMorphWordMaskFrameAdvanceAsm(MorphCur, MorphStep, POINT_COUNT, RotCosPtr[RotSlot], RotSinPtr[RotSlot], &ProjRows[Z_OFFSET - PROJ_Z_MIN], WordMaskAccum, FrameWordIndex);
}

static void AdvanceTrail(UBYTE Buffer)
{
    ++TrailHead[Buffer];

    if (TrailHead[Buffer] >= BLUR_PLANES)
    {
        TrailHead[Buffer] = 0;
    }
}

static void RenderPointFrame(UBYTE Buffer, UWORD FrameWordCount)
{
    AdvanceTrail(Buffer);
    UpdateFrameWordsAsm((UWORD*)ScreenPlane[Buffer][TrailHead[Buffer]], PrevOffset[Buffer][TrailHead[Buffer]], &PrevWordCount[Buffer][TrailHead[Buffer]], FrameWordCount, WordMaskAccum, FrameWordIndex);
}

static void ProjectWireVerts(UBYTE RotSlot)
{
    const SBYTE* const RotC = RotCosPtr[RotSlot];
    const SBYTE* const RotS = RotSinPtr[RotSlot];

    for (UWORD i = 0; i < ICOSA_VERTEX_COUNT; ++i)
    {
        const POINT3D8* const P = &ObjectPoints[OBJECT_INDEX(1, i)];
        const WORD x = P->x;
        const WORD y = P->y;
        const WORD z = P->z;
        const WORD xr = RotC[x] + RotS[z];
        const WORD zr = RotC[z] - RotS[x];
        const SBYTE* const Proj = ProjRows[Z_OFFSET - PROJ_Z_MIN + zr];

        WireVerts[i].x = CENTER_X + Proj[xr];
        WireVerts[i].y = CENTER_Y + Proj[y];
    }
}

static void ClearAllLayers(UBYTE Buffer)
{
    for (UBYTE i = 0; i < BLUR_PLANES; ++i)
    {
        BlitClearPlaneAsm((UWORD*)ScreenPlane[Buffer][i]);
    }

    lwmf_WaitBlitter();

    for (UBYTE i = 0; i < BLUR_PLANES; ++i)
    {
        PrevWordCount[Buffer][i] = 0;
    }
}

static void RenderWireFrame(UBYTE Buffer, UBYTE RotSlot)
{
    AdvanceTrail(Buffer);

    ProjectWireVerts(RotSlot);
    BlitClearWireRectAsm((UWORD*)ScreenPlane[Buffer][TrailHead[Buffer]]);
    PrevWordCount[Buffer][TrailHead[Buffer]] = 0;
    DrawBlitterLinesAsm((UWORD*)ScreenPlane[Buffer][TrailHead[Buffer]], WireVerts, IcosaEdges);
}

static void ClearBuffer(UBYTE Buffer)
{
    ClearAllLayers(Buffer);
    TrailHead[Buffer] = 0;
}


static void InitScreenPlanes(void)
{
    for (UBYTE b = 0; b < 2; ++b)
    {
        ScreenBuffer[b] = AllocMem(SCREEN_BUFFER_SIZE, MEMF_CHIP | MEMF_CLEAR);

        for (UBYTE p = 0; p < BLUR_PLANES; ++p)
        {
            ScreenPlane[b][p] = ScreenBuffer[b] + (p * SCREEN_LAYER_SIZE);
        }
    }
}

static void CleanupScreenPlanes(void)
{
    for (UBYTE b = 0; b < 2; ++b)
    {
        if (ScreenBuffer[b])
        {
            FreeMem(ScreenBuffer[b], SCREEN_BUFFER_SIZE);
            ScreenBuffer[b] = NULL;
        }
    }
}

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;
static UWORD BPLxPTH_Idx[BLUR_PLANES];
static UWORD BPLxPTL_Idx[BLUR_PLANES];

#define COPPER_FIXED_WORDS      42

static void Init_CopperList(void)
{
    // Three-bitplane PAL copperlist. Grey/white trail with dark blue background.
    CopperListSize = COPPER_FIXED_WORDS * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);

    UWORD Index = 0;

    CopperList[Index++] = 0x08E;
    CopperList[Index++] = 0x2C81;
    CopperList[Index++] = 0x090;
    CopperList[Index++] = 0x2CC1;
    CopperList[Index++] = 0x092;
    CopperList[Index++] = 0x0038;
    CopperList[Index++] = 0x094;
    CopperList[Index++] = 0x00D0;

    CopperList[Index++] = 0x100;
    CopperList[Index++] = 0x3200;
    CopperList[Index++] = 0x102;
    CopperList[Index++] = 0x0000;

    for (UBYTE p = 0; p < BLUR_PLANES; ++p)
    {
        CopperList[Index++] = 0x0E0 + (p << 2);
        BPLxPTH_Idx[p] = Index;
        CopperList[Index++] = 0x0000;
        CopperList[Index++] = 0x0E2 + (p << 2);
        BPLxPTL_Idx[p] = Index;
        CopperList[Index++] = 0x0000;
    }

    static const UWORD Palette[8] =
    {
        0x006, 0x666, 0x999, 0xBBB,
        0xFFF, 0xFFF, 0xFFF, 0xFFF
    };

    for (UBYTE c = 0; c < 8; ++c)
    {
        CopperList[Index++] = 0x0180 + (c << 1);
        CopperList[Index++] = Palette[c];
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

static void SetBitplanePointer(UBYTE Plane, UBYTE Buffer, UBYTE Layer)
{
    const ULONG Ptr = (ULONG)ScreenPlane[Buffer][Layer];

    CopperList[BPLxPTH_Idx[Plane]] = Ptr >> 16;
    CopperList[BPLxPTL_Idx[Plane]] = Ptr & 0xFFFF;
}

static UBYTE AddLayer(UBYTE Layer, UBYTE Add)
{
    Layer += Add;

    if (Layer >= BLUR_PLANES)
    {
        Layer -= BLUR_PLANES;
    }

    return Layer;
}

static void Update_BitplanePointersBlur(UBYTE Buffer)
{
    const UBYTE Newest = TrailHead[Buffer];

    SetBitplanePointer(0, Buffer, AddLayer(Newest, 1));
    SetBitplanePointer(1, Buffer, AddLayer(Newest, 2));
    SetBitplanePointer(2, Buffer, Newest);
}

static void Cleanup_All(void)
{
    lwmf_ReleaseOS();

    FreeMem(CopperList, CopperListSize);
    CopperList = NULL;
    CopperListSize = 0;

    CleanupScreenPlanes();
    lwmf_CloseLibraries();
}

int main(void)
{
    lwmf_LoadGraphicsLib();
    InitScreenPlanes();

    InitRotationSlotsAndTables();
    InitProjectionTable();
    InitObjects();

    lwmf_TakeOverOS();
    Init_CopperList();

    UBYTE CurrentBuffer = 1;
    UBYTE RockPhaseStep = 0;
    UBYTE CurrentObject = 0;
    UWORD StateFrame = 0;
    BOOL Morphing = FALSE;
    UBYTE ClearPointBuffers = 0;
    UBYTE ClearWireBuffers = 0;

    Update_BitplanePointersBlur(0);

    while (*CIAA_PRA & 0x40)
    {
        const UBYTE RotSlot = RockRotSlot[RockPhaseStep];
        UWORD FrameWordCount;

        if (Morphing)
        {
            if ((StateFrame + 1) < MORPH_FRAMES)
            {
                FrameWordCount = BuildMorphWordMaskFrameAdvance(RotSlot);
            }
            else
            {
                FrameWordCount = BuildStaticWordMaskFrame((UWORD)((CurrentObject + 1) % OBJECT_COUNT), RotSlot);
            }

            ++StateFrame;

            if (StateFrame >= MORPH_FRAMES)
            {
                StateFrame = 0;
                Morphing = FALSE;
                CurrentObject ^= 1;

                if (CurrentObject == 1)
                {
                    ClearWireBuffers = 3;
                }
            }

            if (ClearPointBuffers & (1 << CurrentBuffer))
            {
                ClearBuffer(CurrentBuffer);
                ClearPointBuffers &= ~(1 << CurrentBuffer);
            }

            RenderPointFrame(CurrentBuffer, FrameWordCount);
        }
        else
        {
            if (CurrentObject == 1)
            {
                if (ClearWireBuffers & (1 << CurrentBuffer))
                {
                    ClearBuffer(CurrentBuffer);
                    ClearWireBuffers &= ~(1 << CurrentBuffer);
                }

                RenderWireFrame(CurrentBuffer, RotSlot);
            }
            else
            {
                FrameWordCount = BuildStaticWordMaskFrame(CurrentObject, RotSlot);
                RenderPointFrame(CurrentBuffer, FrameWordCount);
            }

            ++StateFrame;

            if (StateFrame >= HOLD_FRAMES)
            {
                StateFrame = 0;
                Morphing = TRUE;

                if (CurrentObject == 1)
                {
                    ClearPointBuffers = 3;
                }

                InitMorphState(CurrentObject);
            }
        }

        lwmf_WaitVertBlank();
        Update_BitplanePointersBlur(CurrentBuffer);
        CurrentBuffer ^= 1;
        RockPhaseStep = (UBYTE)((RockPhaseStep + 1) & (PHASE_STEP_COUNT - 1));
    }

    Cleanup_All();
    return 0;
}
