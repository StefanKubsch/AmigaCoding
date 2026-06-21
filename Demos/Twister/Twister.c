//**********************************************************************
//* Textured Twister                                                   *
//*                                                                    *
//* (C) 2026 by Stefan Kubsch / Deep4                                  *
//* Project for vbcc                                                   *
//*                                                                    *
//* Compile & link with:                                               *
//* make_Build.cmd / make_ADF.cmd                                      *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

// =====================================================================
// Screen / Copper
// =====================================================================

// VPOS offset for PAL display (first visible line = $2C = 44)
#define VPOS_OFFSET 0x2C
#define COPPER_WAIT_H 0x01

#define COLUMN_FETCH_WORDS 6
#define COLUMN_FETCH_BYTES (COLUMN_FETCH_WORDS << 1)
#define ROW_REPEAT_MOD ((UWORD)(0 - COLUMN_FETCH_BYTES))
#define COLUMN_DDFSTRT 0x0070
#define COLUMN_DDFSTOP 0x0098

#define COLUMN_ACTIVE_BITPLANES 4
#define DISPLAY_POINTER_WORDS (NUMBEROFBITPLANES << 1)
#define COLUMN_POINTER_WORDS (COLUMN_ACTIVE_BITPLANES << 1)
#define COLUMN_PALETTE_COLORS 9

static UWORD *CopperList[2];
static UWORD *CopperBodyDataLow[2];
static UWORD *CopperBodyDataHigh[2];
static const UWORD ColumnPalette[COLUMN_PALETTE_COLORS] =
    {
        0x000,
        0x013, 0x024, 0x124, 0x225,
        0x79F, 0x8AF, 0x69E, 0x9BF};

static UWORD *CopperWaitLine(UWORD *Copperlist, UWORD ScreenY, UBYTE *Past255)
{
    const UWORD BeamY = VPOS_OFFSET + ScreenY;

    if (BeamY >= 256 && !*Past255)
    {
        *Copperlist++ = 0xFFDF;
        *Copperlist++ = 0xFFFE;
        *Past255 = 1;
    }

    *Copperlist++ = (UWORD)(((BeamY & 255) << 8) | COPPER_WAIT_H);
    *Copperlist++ = 0xFFFE;

    return Copperlist;
}

static void MakePointerWords(const UBYTE *Row, UWORD *Words, UBYTE PlaneCount)
{
    for (UBYTE p = 0; p < PlaneCount; ++p)
    {
        const ULONG Addr = (ULONG)(Row + (ULONG)p * COLUMN_FETCH_BYTES);

        Words[p << 1] = (UWORD)(Addr >> 16);
        Words[(p << 1) + 1] = (UWORD)Addr;
    }
}

static UWORD *CopperPutPointerBlock(UWORD *Copperlist, const UWORD *Words, UBYTE PlaneCount)
{
    UWORD Reg = 0x0E0;

    for (UBYTE p = 0; p < PlaneCount; ++p)
    {
        *Copperlist++ = Reg;
        *Copperlist++ = Words[p << 1];
        Reg += 2;
        *Copperlist++ = Reg;
        *Copperlist++ = Words[(p << 1) + 1];
        Reg += 2;
    }

    return Copperlist;
}

// =====================================================================
// Square twist column with projected text
// =====================================================================

#define COLUMN_TOP 24
#define COLUMN_HEIGHT 208
#define COLUMN_HALF_HEIGHT (COLUMN_HEIGHT >> 1)
#define COLUMN_TORSION_SHIFT 7
#define COLUMN_SCROLL_STEP_Q8 307
#define COLUMN_TORSION_STEP_Q8 154
#define COLUMN_TORSION_DEADBAND 12
#define COLUMN_WIDTH 96
#define COLUMN_LOCAL_CENTER_X (COLUMN_WIDTH >> 1)
#define SQUARE_SCREEN_SCALE 48
#define SQUARE_SCREEN_SCALE_DEN 91
#define COLUMN_PHASES 256
#define TEXT_TEXTURE_ROWS 16
#define TEXT_ROWDATA_ROWS 9
#define TEXT_FACE_WIDTH 64
#define COLUMN_ROW_BYTES (COLUMN_FETCH_BYTES * COLUMN_ACTIVE_BITPLANES)
#define COLUMN_ROW_LONGS (COLUMN_ROW_BYTES >> 2)
#define COLUMN_BLANK_ROW_BYTES (COLUMN_FETCH_BYTES * NUMBEROFBITPLANES)
#define COLUMN_ROWDATA_SIZE ((ULONG)TEXT_ROWDATA_ROWS * COLUMN_PHASES * COLUMN_ROW_BYTES)
#define COLUMN_ROWDATA_ROW_STRIDE ((ULONG)COLUMN_PHASES * COLUMN_ROW_BYTES)
#define COLUMN_PHASE_WORDS 16
#define COLUMN_PHASE_PTR_ROW_STRIDE ((ULONG)COLUMN_PHASES * COLUMN_PHASE_WORDS)
#define COLUMN_PHASE_PTR_SIZE ((ULONG)TEXT_TEXTURE_ROWS * COLUMN_PHASES * COLUMN_PHASE_WORDS * sizeof(UWORD))
#define COLUMN_SPLIT_ROW (SCREENHEIGHT - VPOS_OFFSET - COLUMN_TOP)
#define COLUMN_SPLIT_HEIGHT (COLUMN_HEIGHT - COLUMN_SPLIT_ROW)
#define COLUMN_MAX_SEGMENTS 2
#define COPPER_MOVE_WORDS 2
#define COPPER_WAIT_WORDS 2
#define COPPER_SKIP_255_WORDS (((VPOS_OFFSET + COLUMN_TOP + COLUMN_HEIGHT) >= 256) ? 2 : 0)
#define COPPER_END_WORDS 2
#define COPPER_SETUP_WORDS 24
#define COPPER_COLOR_BODY_WORDS (4 * COPPER_MOVE_WORDS)
#define COPPER_FULL_POINTER_BLOCK_WORDS (DISPLAY_POINTER_WORDS * COPPER_MOVE_WORDS)
#define COPPER_ACTIVE_POINTER_BLOCK_WORDS (COLUMN_POINTER_WORDS * COPPER_MOVE_WORDS)
#define COPPER_BODY_LINE_WORDS (COPPER_WAIT_WORDS + COPPER_COLOR_BODY_WORDS + COPPER_ACTIVE_POINTER_BLOCK_WORDS)
#define COPPER_RESERVE_WORDS 32
#define COPPER_WORDS                                   \
    (COPPER_SETUP_WORDS +                              \
     COPPER_FULL_POINTER_BLOCK_WORDS +                 \
     (COLUMN_PALETTE_COLORS * COPPER_MOVE_WORDS) +     \
     COPPER_WAIT_WORDS +                               \
     COPPER_FULL_POINTER_BLOCK_WORDS +                 \
     ((ULONG)COLUMN_HEIGHT * COPPER_BODY_LINE_WORDS) + \
     COPPER_SKIP_255_WORDS +                           \
     COPPER_WAIT_WORDS +                               \
     COPPER_FULL_POINTER_BLOCK_WORDS +                 \
     COPPER_END_WORDS +                                \
     COPPER_RESERVE_WORDS)
#define COPPER_LIST_SIZE ((ULONG)sizeof(UWORD) * COPPER_WORDS)

#if (COLUMN_SPLIT_ROW != 188) || (COLUMN_SPLIT_HEIGHT != 20)
#error Twister_vasm.s split constants must match this screen setup.
#endif

void UpdateTwistCopperTextAsm(__reg("a0") UWORD *CopperDataLow,
                              __reg("a1") UWORD *CopperDataHigh,
                              __reg("a2") const UWORD *PhaseWords,
                              __reg("d0") WORD AccStart,
                              __reg("d1") WORD PhaseDelta,
                              __reg("d2") UWORD PhaseAdd,
                              __reg("d3") UWORD TextAdd);

static UWORD ColumnTorsionPhase;
static LONG ColumnScrollPhase;
static LONG ColumnTextPhase;
static WORD ColumnScrollDir = 1;
static UBYTE *ColumnRowData;
static UBYTE *ColumnBlankRow;
static UBYTE *ColumnWorkRow;
static UWORD *ColumnPhasePtrWords;

struct ColumnSegment
{
    WORD Start;
    WORD End;
    WORD UAcc;
    WORD Step;
    UBYTE Face;
};

static const WORD SinTab[256] =
    {
        0, 3, 6, 9, 12, 16, 19, 22, 25, 28, 31, 34, 37, 40, 43, 46,
        49, 51, 54, 57, 60, 63, 65, 68, 71, 73, 76, 78, 81, 83, 85, 88,
        90, 92, 94, 96, 98, 100, 102, 104, 106, 107, 109, 111, 112, 113, 115, 116,
        117, 118, 120, 121, 122, 122, 123, 124, 125, 125, 126, 126, 126, 127, 127, 127,
        127, 127, 127, 127, 126, 126, 126, 125, 125, 124, 123, 122, 122, 121, 120, 118,
        117, 116, 115, 113, 112, 111, 109, 107, 106, 104, 102, 100, 98, 96, 94, 92,
        90, 88, 85, 83, 81, 78, 76, 73, 71, 68, 65, 63, 60, 57, 54, 51,
        49, 46, 43, 40, 37, 34, 31, 28, 25, 22, 19, 16, 12, 9, 6, 3,
        0, -3, -6, -9, -12, -16, -19, -22, -25, -28, -31, -34, -37, -40, -43, -46,
        -49, -51, -54, -57, -60, -63, -65, -68, -71, -73, -76, -78, -81, -83, -85, -88,
        -90, -92, -94, -96, -98, -100, -102, -104, -106, -107, -109, -111, -112, -113, -115, -116,
        -117, -118, -120, -121, -122, -122, -123, -124, -125, -125, -126, -126, -126, -127, -127, -127,
        -127, -127, -127, -127, -126, -126, -126, -125, -125, -124, -123, -122, -122, -121, -120, -118,
        -117, -116, -115, -113, -112, -111, -109, -107, -106, -104, -102, -100, -98, -96, -94, -92,
        -90, -88, -85, -83, -81, -78, -76, -73, -71, -68, -65, -63, -60, -57, -54, -51,
        -49, -46, -43, -40, -37, -34, -31, -28, -25, -22, -19, -16, -12, -9, -6, -3};

static const WORD SquareVertexX[4] =
    {
        -64, 64, 64, -64};

static const WORD SquareVertexZ[4] =
    {
        -64, -64, 64, 64};

static const UBYTE SquareFaceA[4] =
    {
        0, 1, 2, 3};

static const UBYTE SquareFaceB[4] =
    {
        1, 2, 3, 0};

static const WORD SquareNormalX[4] =
    {
        0, 127, 0, -127};

static const WORD SquareNormalZ[4] =
    {
        -127, 0, 127, 0};

static const char FaceText[4][9] =
    {
        "  AMIGA ",
        "  RULES ",
        "  AMIGA ",
        "  RULES "};

#if COLUMN_ROW_LONGS != 12
#error ClearColumnWorkRow() and CopyColumnWorkRow() are unrolled for 96px x 4 active bitplanes.
#endif

static inline void ClearColumnWorkRow(void)
{
    ULONG *Dst = (ULONG *)ColumnWorkRow;

    Dst[0] = 0;
    Dst[1] = 0;
    Dst[2] = 0;
    Dst[3] = 0;
    Dst[4] = 0;
    Dst[5] = 0;
    Dst[6] = 0;
    Dst[7] = 0;
    Dst[8] = 0;
    Dst[9] = 0;
    Dst[10] = 0;
    Dst[11] = 0;
}

static inline void CopyColumnWorkRow(UBYTE *Dst)
{
    const ULONG *Src = (const ULONG *)ColumnWorkRow;
    ULONG *Target = (ULONG *)Dst;

    Target[0] = Src[0];
    Target[1] = Src[1];
    Target[2] = Src[2];
    Target[3] = Src[3];
    Target[4] = Src[4];
    Target[5] = Src[5];
    Target[6] = Src[6];
    Target[7] = Src[7];
    Target[8] = Src[8];
    Target[9] = Src[9];
    Target[10] = Src[10];
    Target[11] = Src[11];
}

static inline UBYTE ColumnPixelBit(UWORD PosX)
{
    return (UBYTE)(0x80 >> (PosX & 7));
}

static void OrPlaneSpanX(UBYTE *Plane, UWORD Start, UWORD End)
{
    const UBYTE StartByte = (UBYTE)(Start >> 3);
    const UBYTE EndByte = (UBYTE)(End >> 3);
    const UBYTE StartMask = (UBYTE)(0xFF >> (Start & 7));
    const UBYTE EndMask = (UBYTE)(0xFF << (7 - (End & 7)));

    if (StartByte == EndByte)
    {
        Plane[StartByte] |= (UBYTE)(StartMask & EndMask);
        return;
    }

    Plane[StartByte] |= StartMask;

    for (UBYTE Byte = (UBYTE)(StartByte + 1); Byte < EndByte; ++Byte)
    {
        Plane[Byte] = 0xFF;
    }

    Plane[EndByte] |= EndMask;
}

static void DrawSegmentBase(const struct ColumnSegment *Segment)
{
    const UBYTE Color = Segment->Face + 1;

    if (Segment->End < Segment->Start)
    {
        return;
    }

    if (Color & 1)
        OrPlaneSpanX(ColumnWorkRow + 0 * COLUMN_FETCH_BYTES, (UWORD)Segment->Start, (UWORD)Segment->End);
    if (Color & 2)
        OrPlaneSpanX(ColumnWorkRow + 1 * COLUMN_FETCH_BYTES, (UWORD)Segment->Start, (UWORD)Segment->End);
    if (Color & 4)
        OrPlaneSpanX(ColumnWorkRow + 2 * COLUMN_FETCH_BYTES, (UWORD)Segment->Start, (UWORD)Segment->End);
}

static void DrawSegmentTextOverlay(UBYTE TexY, const struct ColumnSegment *Segment)
{
    LONG UAcc = Segment->UAcc;
    const WORD Step = Segment->Step;
    const UBYTE Face = Segment->Face;
    UBYTE *Plane2 = ColumnWorkRow + 2 * COLUMN_FETCH_BYTES;
    UBYTE *Plane3 = ColumnWorkRow + 3 * COLUMN_FETCH_BYTES;

    if (TexY >= 8 || Segment->End < Segment->Start)
    {
        return;
    }

    for (WORD x = Segment->Start; x <= Segment->End; ++x)
    {
        const UBYTE U = (UBYTE)((UAcc >> 8) & (TEXT_FACE_WIDTH - 1));
        const UBYTE Bits = ASCIIFont8x8[(UBYTE)FaceText[Face][U >> 3]][TexY];

        if (Bits & (1 << (U & 7)))
        {
            const UBYTE Byte = (UBYTE)((UWORD)x >> 3);
            const UBYTE Bit = ColumnPixelBit((UWORD)x);

            if (Face == 3)
            {
                Plane2[Byte] &= (UBYTE)~Bit;
                Plane3[Byte] |= Bit;
            }
            else
            {
                Plane2[Byte] |= Bit;
            }
        }

        UAcc += Step;
    }
}

static WORD ProjectColumnVertexX(UBYTE Vertex, WORD S, WORD C)
{
    const LONG RotX = ((LONG)SquareVertexX[Vertex] * C) - ((LONG)SquareVertexZ[Vertex] * S);
    const WORD X = (WORD)(RotX >> 7);

    return COLUMN_LOCAL_CENTER_X + (WORD)(((LONG)X * SQUARE_SCREEN_SCALE) / SQUARE_SCREEN_SCALE_DEN);
}

static void StoreColumnSegment(struct ColumnSegment *Segments, UBYTE *OutCount, UBYTE Face, WORD X0, WORD X1)
{
    WORD Start;
    WORD End;
    WORD Step;
    LONG UAcc;
    UWORD Span;
    struct ColumnSegment *Segment;

    if (X0 < X1)
    {
        Start = X0;
        End = X1;
        UAcc = 0;
    }
    else
    {
        Start = X1;
        End = X0;
        UAcc = (LONG)(TEXT_FACE_WIDTH - 1) << 8;
    }

    if (Start < 0)
    {
        Start = 0;
    }

    if (End >= COLUMN_WIDTH)
    {
        End = COLUMN_WIDTH - 1;
    }

    if (End < Start)
    {
        return;
    }

    Span = (UWORD)(End - Start + 1);
    Step = (WORD)((TEXT_FACE_WIDTH << 8) / Span);

    if (X0 > X1)
    {
        Step = (WORD)(0 - Step);
    }

    Segment = &Segments[*OutCount];
    Segment->Start = Start;
    Segment->End = End;
    Segment->UAcc = (WORD)UAcc;
    Segment->Step = Step;
    Segment->Face = Face;

    ++*OutCount;
}

static UWORD MakeMetalBlueColor(UWORD Shade, UBYTE Face)
{
    UWORD r = (Shade >> 2);
    UWORD g = 1 + (Shade >> 1);
    UWORD b = 4 + ((Shade * 3) >> 2);

    r += Face >> 1;
    g += Face & 1;
    b += Face >> 1;

    if (r > 15)
    {
        r = 15;
    }

    if (g > 15)
    {
        g = 15;
    }

    if (b > 15)
    {
        b = 15;
    }

    return (UWORD)((r << 8) | (g << 4) | b);
}

static void SwapColumnSegments(struct ColumnSegment *A, struct ColumnSegment *B)
{
    const struct ColumnSegment Temp = *A;

    *A = *B;
    *B = Temp;
}

static UBYTE BuildColumnPhase(UWORD Phase, struct ColumnSegment *Segments, UWORD *ShadeWords)
{
    const WORD S = SinTab[Phase];
    const WORD C = SinTab[(Phase + 64) & 255];
    WORD ProjectedX[4];
    UBYTE Count = 0;

    for (UBYTE v = 0; v < 4; ++v)
    {
        ProjectedX[v] = ProjectColumnVertexX(v, S, C);
    }

    for (UBYTE f = 0; f < 4; ++f)
    {
        const WORD Nx = (WORD)((((LONG)SquareNormalX[f] * C) - ((LONG)SquareNormalZ[f] * S)) >> 7);
        const WORD Nz = (WORD)((((LONG)SquareNormalX[f] * S) + ((LONG)SquareNormalZ[f] * C)) >> 7);
        WORD View = (WORD)-Nz;
        WORD Light;
        WORD Spec;
        UWORD Shade;

        if (View < 0)
        {
            View = 0;
        }

        Light = (WORD)(((LONG)View * 96 - (LONG)Nx * 36) >> 7);

        if (Light < 0)
        {
            Light = 0;
        }

        Shade = (UWORD)(2 + (View >> 5) + (Light >> 5));
        Spec = (WORD)(Light - 82);

        if (Spec > 0)
        {
            Shade += (UWORD)(Spec >> 2);
        }

        if (Shade > 15)
        {
            Shade = 15;
        }

        ShadeWords[f] = MakeMetalBlueColor(Shade, f);

        if (Nz < 0)
        {
            const WORD X0 = ProjectedX[SquareFaceA[f]];
            const WORD X1 = ProjectedX[SquareFaceB[f]];

            if (X0 != X1)
            {
                StoreColumnSegment(Segments, &Count, f, X0, X1);
            }
        }
    }

    if (Count == 2 && Segments[1].Start < Segments[0].Start)
    {
        SwapColumnSegments(&Segments[0], &Segments[1]);
    }

    // Adjacent square faces share one projected edge. Keep the later face's pixel
    // and make the row draw non-overlapping, so span/text drawing can OR safely.
    if (Count == 2 && Segments[0].End >= Segments[1].Start)
    {
        Segments[0].End = (WORD)(Segments[1].Start - 1);
    }

    return Count;
}

static void DrawPreparedSegment(UBYTE TexY, const struct ColumnSegment *Segment)
{
    DrawSegmentBase(Segment);
    DrawSegmentTextOverlay(TexY, Segment);
}

static void StoreColumnPhaseData(UWORD *Dst, const UWORD *ShadeWords, const UBYTE *Row)
{
    ULONG Addr;

    Dst[0] = ShadeWords[0];
    Dst[1] = ShadeWords[1];
    Dst[2] = ShadeWords[2];
    Dst[3] = ShadeWords[3];

    Addr = (ULONG)Row;
    Dst[4] = (UWORD)(Addr >> 16);
    Dst[5] = (UWORD)Addr;
    Addr += COLUMN_FETCH_BYTES;
    Dst[6] = (UWORD)(Addr >> 16);
    Dst[7] = (UWORD)Addr;
    Addr += COLUMN_FETCH_BYTES;
    Dst[8] = (UWORD)(Addr >> 16);
    Dst[9] = (UWORD)Addr;
    Addr += COLUMN_FETCH_BYTES;
    Dst[10] = (UWORD)(Addr >> 16);
    Dst[11] = (UWORD)Addr;
}

// Build row graphics and the ASM lookup table in one phase-major pass.
static void BuildColumnPrecalc(void)
{
    struct ColumnSegment Segments[COLUMN_MAX_SEGMENTS];
    UWORD ShadeWords[4];

    for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
    {
        const UBYTE Count = BuildColumnPhase(Phase, Segments, ShadeWords);
        UBYTE *Row = ColumnRowData + (ULONG)Phase * COLUMN_ROW_BYTES;
        UWORD *Dst = ColumnPhasePtrWords + (ULONG)Phase * COLUMN_PHASE_WORDS;
        const UBYTE *EmptyRow = Row + (TEXT_ROWDATA_ROWS - 1) * COLUMN_ROWDATA_ROW_STRIDE;

        for (UBYTE TexY = 0; TexY < TEXT_ROWDATA_ROWS; ++TexY)
        {
            ClearColumnWorkRow();

            for (UBYTE i = 0; i < Count; ++i)
            {
                DrawPreparedSegment(TexY, &Segments[i]);
            }

            CopyColumnWorkRow(Row);
            StoreColumnPhaseData(Dst, ShadeWords, Row);

            Row += COLUMN_ROWDATA_ROW_STRIDE;
            Dst += COLUMN_PHASE_PTR_ROW_STRIDE;
        }

        for (UBYTE TexY = TEXT_ROWDATA_ROWS; TexY < TEXT_TEXTURE_ROWS; ++TexY)
        {
            StoreColumnPhaseData(Dst, ShadeWords, EmptyRow);
            Dst += COLUMN_PHASE_PTR_ROW_STRIDE;
        }
    }
}

// Build a double-buffered copper list. The 255-line split is handled by two data ranges.
static void BuildCopperList(UBYTE Buffer)
{
    UWORD BlankWords[DISPLAY_POINTER_WORDS];
    UWORD Index = 0;
    UWORD *Copperlist;
    UBYTE Past255 = 0;

    MakePointerWords(ColumnBlankRow, BlankWords, NUMBEROFBITPLANES);

    // Static display setup. Register numbers are Copper MOVE addresses.
    CopperList[Buffer][Index++] = 0x8E;
    CopperList[Buffer][Index++] = 0x2C81;
    CopperList[Buffer][Index++] = 0x90;
    CopperList[Buffer][Index++] = 0x2CC1;
    CopperList[Buffer][Index++] = 0x92;
    CopperList[Buffer][Index++] = COLUMN_DDFSTRT;
    CopperList[Buffer][Index++] = 0x94;
    CopperList[Buffer][Index++] = COLUMN_DDFSTOP;

    CopperList[Buffer][Index++] = 0x106;
    CopperList[Buffer][Index++] = 0x0000;
    CopperList[Buffer][Index++] = 0x10C;
    CopperList[Buffer][Index++] = 0x0000;
    CopperList[Buffer][Index++] = 0x1FC;
    CopperList[Buffer][Index++] = 0x0000;

    CopperList[Buffer][Index++] = 0x100;
    CopperList[Buffer][Index++] = (UWORD)((NUMBEROFBITPLANES << 12) | 0x0200);
    CopperList[Buffer][Index++] = 0x102;
    CopperList[Buffer][Index++] = 0x0000;
    CopperList[Buffer][Index++] = 0x104;
    CopperList[Buffer][Index++] = 0x0000;
    CopperList[Buffer][Index++] = 0x108;
    CopperList[Buffer][Index++] = ROW_REPEAT_MOD;
    CopperList[Buffer][Index++] = 0x10A;
    CopperList[Buffer][Index++] = ROW_REPEAT_MOD;

    Copperlist = &CopperList[Buffer][Index];
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords, NUMBEROFBITPLANES);

    for (UBYTE c = 0; c < COLUMN_PALETTE_COLORS; ++c)
    {
        *Copperlist++ = (UWORD)(0x180 + c * 2);
        *Copperlist++ = ColumnPalette[c];
    }

    Copperlist = CopperWaitLine(Copperlist, COLUMN_TOP - 1, &Past255);
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords, NUMBEROFBITPLANES);

    // Body lines contain dynamic color and BPL1..BPL4 pointer data words, updated by ASM.
    // BPL5 stays on the blank row because the generated texture uses color 0..8 only.
    for (UWORD y = 0; y < COLUMN_HEIGHT; ++y)
    {
        UWORD *Data;

        Copperlist = CopperWaitLine(Copperlist, COLUMN_TOP + y, &Past255);
        Data = Copperlist + 1;

        *Copperlist++ = 0x182;
        *Copperlist++ = ColumnPhasePtrWords[0];
        *Copperlist++ = 0x184;
        *Copperlist++ = ColumnPhasePtrWords[1];
        *Copperlist++ = 0x186;
        *Copperlist++ = ColumnPhasePtrWords[2];
        *Copperlist++ = 0x188;
        *Copperlist++ = ColumnPhasePtrWords[3];
        Copperlist = CopperPutPointerBlock(Copperlist, ColumnPhasePtrWords + 4, COLUMN_ACTIVE_BITPLANES);

        if (y == 0)
        {
            CopperBodyDataLow[Buffer] = Data;
        }
        else if (y == COLUMN_SPLIT_ROW)
        {
            CopperBodyDataHigh[Buffer] = Data;
        }
    }

    Copperlist = CopperWaitLine(Copperlist, COLUMN_TOP + COLUMN_HEIGHT, &Past255);
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords, NUMBEROFBITPLANES);

    *Copperlist++ = 0xFFFF;
    *Copperlist++ = 0xFFFE;
}

static void Init_TwistColumn(void)
{
    CopperList[0] = (UWORD *)AllocMem(COPPER_LIST_SIZE, MEMF_CHIP | MEMF_CLEAR);
    CopperList[1] = (UWORD *)AllocMem(COPPER_LIST_SIZE, MEMF_CHIP | MEMF_CLEAR);
    ColumnRowData = (UBYTE *)AllocMem(COLUMN_ROWDATA_SIZE, MEMF_CHIP | MEMF_CLEAR);
    ColumnBlankRow = (UBYTE *)AllocMem(COLUMN_BLANK_ROW_BYTES, MEMF_CHIP | MEMF_CLEAR);
    ColumnWorkRow = (UBYTE *)lwmf_AllocCpuMem(COLUMN_ROW_BYTES, MEMF_CLEAR);
    ColumnPhasePtrWords = (UWORD *)lwmf_AllocCpuMem(COLUMN_PHASE_PTR_SIZE, MEMF_CLEAR);

    BuildColumnPrecalc();
    BuildCopperList(0);
    BuildCopperList(1);
}

// Update only copper data words; bitplane graphics stay in static row patterns.
static void Update_TwistColumn(UBYTE Buffer)
{
    const UBYTE TwistPhase = (UBYTE)(ColumnTorsionPhase >> 8);
    const WORD TorsionWave = SinTab[TwistPhase];
    const WORD Torsion = TorsionWave + (TorsionWave >> 1);
    const WORD AccStart = (WORD)(-((LONG)COLUMN_HALF_HEIGHT * Torsion));
    UWORD PhaseAdd;
    UWORD TextAdd;

    if (Torsion > COLUMN_TORSION_DEADBAND)
    {
        ColumnScrollDir = 1;
    }
    else if (Torsion < -COLUMN_TORSION_DEADBAND)
    {
        ColumnScrollDir = -1;
    }

    ColumnTorsionPhase += COLUMN_TORSION_STEP_Q8;
    ColumnScrollPhase += (LONG)ColumnScrollDir * COLUMN_SCROLL_STEP_Q8;
    ColumnTextPhase += COLUMN_SCROLL_STEP_Q8;
    PhaseAdd = (UWORD)(ColumnScrollPhase >> 8);
    TextAdd = (UWORD)(ColumnTextPhase >> 8);

    UpdateTwistCopperTextAsm(CopperBodyDataLow[Buffer], CopperBodyDataHigh[Buffer], ColumnPhasePtrWords, AccStart, Torsion, PhaseAdd, TextAdd);
}

static void Cleanup_TwistColumn(void)
{
    FreeMem(ColumnPhasePtrWords, COLUMN_PHASE_PTR_SIZE);
    FreeMem(ColumnWorkRow, COLUMN_ROW_BYTES);
    FreeMem(ColumnBlankRow, COLUMN_BLANK_ROW_BYTES);
    FreeMem(ColumnRowData, COLUMN_ROWDATA_SIZE);
    FreeMem(CopperList[1], COPPER_LIST_SIZE);
    FreeMem(CopperList[0], COPPER_LIST_SIZE);
}

// =====================================================================
// Main
// =====================================================================

int main(void)
{
    lwmf_LoadGraphicsLib();
    Init_TwistColumn();
    Update_TwistColumn(0);

    *COP1LC = (ULONG)CopperList[0];

    lwmf_TakeOverOS();

    UBYTE Buffer = 0;

    while (*CIAA_PRA & 0x40)
    {
        Buffer ^= 1;
        Update_TwistColumn(Buffer);
        lwmf_WaitVertBlank();
        *COP1LC = (ULONG)CopperList[Buffer];
    }

    lwmf_WaitVertBlank();
    lwmf_CleanupAll();
    Cleanup_TwistColumn();

    return 0;
}