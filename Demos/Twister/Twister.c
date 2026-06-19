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

#define COPPER_WORDS 6656
#define COPPER_LIST_SIZE ((ULONG)sizeof(UWORD) * COPPER_WORDS)

// VPOS offset for PAL display (first visible line = $2C = 44)
#define VPOS_OFFSET 0x2C
#define COPPER_WAIT_H 0x01

#define COLUMN_FETCH_WORDS 6
#define COLUMN_FETCH_BYTES (COLUMN_FETCH_WORDS << 1)
#define ROW_REPEAT_MOD ((UWORD)(0 - COLUMN_FETCH_BYTES))
#define COLUMN_DDFSTRT 0x0070
#define COLUMN_DDFSTOP 0x0098

#define POINTER_WORDS (NUMBEROFBITPLANES << 1)
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

static void MakePointerWords(UBYTE *Row, UWORD *Words)
{
    for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        const ULONG Addr = (ULONG)(Row + (ULONG)p * COLUMN_FETCH_BYTES);

        Words[p << 1] = (UWORD)(Addr >> 16);
        Words[(p << 1) + 1] = (UWORD)Addr;
    }
}

static UWORD *CopperPutPointerBlock(UWORD *Copperlist, const UWORD *Words)
{
    UWORD Reg = 0x0E0;

    for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
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
#define COLUMN_CENTER_X (SCREENWIDTH >> 1)
#define COLUMN_LEFT (COLUMN_CENTER_X - 48)
#define COLUMN_WIDTH 96
#define SQUARE_SCREEN_SCALE 48
#define SQUARE_SCREEN_SCALE_DEN 91
#define COLUMN_PHASES 256
#define TEXT_TEXTURE_ROWS 16
#define TEXT_ROWDATA_ROWS 9
#define TEXT_FACE_WIDTH 64
#define COLUMN_ROW_BYTES (COLUMN_FETCH_BYTES * NUMBEROFBITPLANES)
#define COLUMN_ROWDATA_SIZE ((ULONG)TEXT_ROWDATA_ROWS * COLUMN_PHASES * COLUMN_ROW_BYTES)
#define COLUMN_PHASE_WORDS 16
#define COLUMN_PHASE_PTR_SIZE ((ULONG)TEXT_TEXTURE_ROWS * COLUMN_PHASES * COLUMN_PHASE_WORDS * sizeof(UWORD))
#define COLUMN_SPLIT_ROW (SCREENHEIGHT - VPOS_OFFSET - COLUMN_TOP)
#define COLUMN_SPLIT_HEIGHT (COLUMN_HEIGHT - COLUMN_SPLIT_ROW)
#define COLUMN_MAX_SEGMENTS 2

void UpdateTwistCopperTextRangeAsm(__reg("a0") UWORD *CopperData,
                                   __reg("a1") const UWORD *PhaseWords,
                                   __reg("d0") LONG AccStart,
                                   __reg("d1") WORD PhaseDelta,
                                   __reg("d2") UWORD PhaseAdd,
                                   __reg("d3") UWORD TextAdd,
                                   __reg("d4") UWORD Count);

static UWORD ColumnTorsionPhase;
static LONG ColumnScrollPhase;
static LONG ColumnTextPhase;
static WORD ColumnScrollDir = 1;
static UBYTE *ColumnRowData;
static UBYTE *ColumnBlankRow;
static UBYTE *ColumnWorkRow;
static UWORD *ColumnPhasePtrWords;
static UBYTE FaceTextureColor[4][TEXT_ROWDATA_ROWS][TEXT_FACE_WIDTH];
static UBYTE ColumnSegmentCount[COLUMN_PHASES];
static UWORD ColumnShadeWords[COLUMN_PHASES][4];

struct ColumnSegment
{
    WORD Start;
    WORD End;
    WORD UAcc;
    WORD Step;
    UBYTE Face;
};

static struct ColumnSegment ColumnSegmentData[COLUMN_PHASES][COLUMN_MAX_SEGMENTS];

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

static void SetColumnRowPixelX(UBYTE *Row, UWORD PosX, UBYTE Color)
{
    const UBYTE Bit = (UBYTE)(0x80 >> (PosX & 7));
    const UBYTE Byte = (UBYTE)(PosX >> 3);

    Row[0 * COLUMN_FETCH_BYTES + Byte] &= (UBYTE)~Bit;
    Row[1 * COLUMN_FETCH_BYTES + Byte] &= (UBYTE)~Bit;
    Row[2 * COLUMN_FETCH_BYTES + Byte] &= (UBYTE)~Bit;
    Row[3 * COLUMN_FETCH_BYTES + Byte] &= (UBYTE)~Bit;
    Row[4 * COLUMN_FETCH_BYTES + Byte] &= (UBYTE)~Bit;

    if (Color & 1)
        Row[0 * COLUMN_FETCH_BYTES + Byte] |= Bit;
    if (Color & 2)
        Row[1 * COLUMN_FETCH_BYTES + Byte] |= Bit;
    if (Color & 4)
        Row[2 * COLUMN_FETCH_BYTES + Byte] |= Bit;
    if (Color & 8)
        Row[3 * COLUMN_FETCH_BYTES + Byte] |= Bit;
    if (Color & 16)
        Row[4 * COLUMN_FETCH_BYTES + Byte] |= Bit;
}

static inline void ClearColumnWorkRow(void)
{
    ULONG *Dst = (ULONG *)ColumnWorkRow;

    for (UBYTE i = 0; i < (COLUMN_ROW_BYTES >> 2); ++i)
    {
        *Dst++ = 0;
    }
}

static inline void CopyColumnWorkRow(UBYTE *Dst)
{
    const ULONG *Src = (const ULONG *)ColumnWorkRow;
    ULONG *Target = (ULONG *)Dst;

    for (UBYTE i = 0; i < (COLUMN_ROW_BYTES >> 2); ++i)
    {
        *Target++ = *Src++;
    }
}

// Prepare four 1bpl text masks as color indices for the visible square faces.
static void BuildFaceTextureColors(void)
{
    for (UBYTE Face = 0; Face < 4; ++Face)
    {
        for (UBYTE TexY = 0; TexY < TEXT_ROWDATA_ROWS; ++TexY)
        {
            for (UWORD U = 0; U < TEXT_FACE_WIDTH; ++U)
            {
                UBYTE Color = Face + 1;

                if (TexY < 8)
                {
                    const UBYTE CharIndex = (UBYTE)((U >> 3) & 7);
                    const UBYTE CharX = (UBYTE)(U & 7);
                    const UBYTE C = (UBYTE)FaceText[Face][CharIndex];
                    const UBYTE Bits = ASCIIFont8x8[C][TexY];

                    if (Bits & (1 << CharX))
                    {
                        Color = Face + 5;
                    }
                }

                FaceTextureColor[Face][TexY][U] = Color;
            }
        }
    }
}

static void StoreColumnSegment(UWORD Phase, UBYTE *OutCount, UBYTE Face, WORD X0, WORD X1)
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

    Segment = &ColumnSegmentData[Phase][*OutCount];
    Segment->Start = Start;
    Segment->End = End;
    Segment->UAcc = (WORD)UAcc;
    Segment->Step = Step;
    Segment->Face = Face;

    ++*OutCount;
}

// Precalculate visible face spans for each rotation phase.
static void BuildColumnGeometry(void)
{
    for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
    {
        const WORD S = SinTab[Phase];
        const WORD C = SinTab[(Phase + 64) & 255];
        WORD ProjectedX[4];
        WORD SegmentStart[COLUMN_MAX_SEGMENTS];
        WORD SegmentX0[COLUMN_MAX_SEGMENTS];
        WORD SegmentX1[COLUMN_MAX_SEGMENTS];
        UBYTE SegmentFace[COLUMN_MAX_SEGMENTS];
        UBYTE SegmentCount = 0;
        UBYTE OutCount = 0;

        for (UBYTE v = 0; v < 4; ++v)
        {
            const LONG RotX = ((LONG)SquareVertexX[v] * C) - ((LONG)SquareVertexZ[v] * S);
            const WORD X = (WORD)(RotX >> 7);

            ProjectedX[v] = COLUMN_CENTER_X + (WORD)(((LONG)X * SQUARE_SCREEN_SCALE) / SQUARE_SCREEN_SCALE_DEN) - COLUMN_LEFT;
        }

        for (UBYTE f = 0; f < 4; ++f)
        {
            const WORD Nz = (WORD)((((LONG)SquareNormalX[f] * S) + ((LONG)SquareNormalZ[f] * C)) >> 7);

            if (Nz < 0)
            {
                const WORD X0 = ProjectedX[SquareFaceA[f]];
                const WORD X1 = ProjectedX[SquareFaceB[f]];

                if (X0 != X1)
                {
                    SegmentX0[SegmentCount] = X0;
                    SegmentX1[SegmentCount] = X1;
                    SegmentFace[SegmentCount] = f;
                    SegmentStart[SegmentCount] = (X0 < X1) ? X0 : X1;
                    ++SegmentCount;
                }
            }
        }

        for (UBYTE i = 0; i < SegmentCount; ++i)
        {
            for (UBYTE j = (UBYTE)(i + 1); j < SegmentCount; ++j)
            {
                if (SegmentStart[j] < SegmentStart[i])
                {
                    WORD TempW;
                    UBYTE TempB;

                    TempW = SegmentStart[i];
                    SegmentStart[i] = SegmentStart[j];
                    SegmentStart[j] = TempW;
                    TempW = SegmentX0[i];
                    SegmentX0[i] = SegmentX0[j];
                    SegmentX0[j] = TempW;
                    TempW = SegmentX1[i];
                    SegmentX1[i] = SegmentX1[j];
                    SegmentX1[j] = TempW;
                    TempB = SegmentFace[i];
                    SegmentFace[i] = SegmentFace[j];
                    SegmentFace[j] = TempB;
                }
            }
        }

        for (UBYTE i = 0; i < SegmentCount; ++i)
        {
            StoreColumnSegment(Phase, &OutCount, SegmentFace[i], SegmentX0[i], SegmentX1[i]);
        }

        ColumnSegmentCount[Phase] = OutCount;
    }
}

static void DrawPreparedSegment(UBYTE TexY, const struct ColumnSegment *Segment)
{
    LONG UAcc = Segment->UAcc;
    const WORD Step = Segment->Step;
    const UBYTE Face = Segment->Face;

    for (WORD x = Segment->Start; x <= Segment->End; ++x)
    {
        const UWORD U = (UWORD)((UAcc >> 8) & (TEXT_FACE_WIDTH - 1));
        const UBYTE Color = FaceTextureColor[Face][TexY][U];

        SetColumnRowPixelX(ColumnWorkRow, (UWORD)x, Color);
        UAcc += Step;
    }
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

static void BuildShadeWords(UWORD Phase, UWORD *Dst)
{
    const WORD S = SinTab[Phase];
    const WORD C = SinTab[(Phase + 64) & 255];

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

        Dst[f] = MakeMetalBlueColor(Shade, f);
    }
}

// Build one metallic blue shade set per rotation phase for COLOR01..04.
static void BuildShadeTable(void)
{
    for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
    {
        BuildShadeWords(Phase, ColumnShadeWords[Phase]);
    }
}

// Draw the phase rows once into Chip RAM, using the prepared geometry and text masks.
static void BuildColumnRows(void)
{
    for (UBYTE TexY = 0; TexY < TEXT_ROWDATA_ROWS; ++TexY)
    {
        for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
        {
            UBYTE *Row = ColumnRowData + (((ULONG)TexY << 8) + Phase) * COLUMN_ROW_BYTES;
            const UBYTE Count = ColumnSegmentCount[Phase];

            ClearColumnWorkRow();

            for (UBYTE i = 0; i < Count; ++i)
            {
                DrawPreparedSegment(TexY, &ColumnSegmentData[Phase][i]);
            }

            CopyColumnWorkRow(Row);
        }
    }
}

// Combine shade words and row pointers into the table consumed by the ASM copper updater.
static void BuildPhaseData(void)
{
    for (UBYTE TexY = 0; TexY < TEXT_TEXTURE_ROWS; ++TexY)
    {
        const UBYTE RowTexY = (TexY < 8) ? TexY : 8;

        for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
        {
            UWORD *Dst = ColumnPhasePtrWords + (((ULONG)TexY << 8) + Phase) * COLUMN_PHASE_WORDS;
            UBYTE *Row = ColumnRowData + (((ULONG)RowTexY << 8) + Phase) * COLUMN_ROW_BYTES;

            Dst[0] = ColumnShadeWords[Phase][0];
            Dst[1] = ColumnShadeWords[Phase][1];
            Dst[2] = ColumnShadeWords[Phase][2];
            Dst[3] = ColumnShadeWords[Phase][3];
            MakePointerWords(Row, Dst + 4);
        }
    }
}

// Build a double-buffered copper list. The 255-line split is handled by two data ranges.
static void BuildCopperList(UBYTE Buffer)
{
    UWORD BlankWords[POINTER_WORDS];
    UWORD Index = 0;
    UWORD *Copperlist;
    UBYTE Past255 = 0;

    MakePointerWords(ColumnBlankRow, BlankWords);

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
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords);

    for (UBYTE c = 0; c < COLUMN_PALETTE_COLORS; ++c)
    {
        *Copperlist++ = (UWORD)(0x180 + c * 2);
        *Copperlist++ = ColumnPalette[c];
    }

    Copperlist = CopperWaitLine(Copperlist, COLUMN_TOP - 1, &Past255);
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords);

    // Body lines contain dynamic color and bitplane-pointer data words, updated by ASM.
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
        Copperlist = CopperPutPointerBlock(Copperlist, ColumnPhasePtrWords + 4);

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
    Copperlist = CopperPutPointerBlock(Copperlist, BlankWords);

    *Copperlist++ = 0xFFFF;
    *Copperlist++ = 0xFFFE;
}

static void Init_TwistColumn(void)
{
    CopperList[0] = (UWORD *)AllocMem(COPPER_LIST_SIZE, MEMF_CHIP | MEMF_CLEAR);
    CopperList[1] = (UWORD *)AllocMem(COPPER_LIST_SIZE, MEMF_CHIP | MEMF_CLEAR);
    ColumnRowData = (UBYTE *)AllocMem(COLUMN_ROWDATA_SIZE, MEMF_CHIP | MEMF_CLEAR);
    ColumnBlankRow = (UBYTE *)AllocMem(COLUMN_ROW_BYTES, MEMF_CHIP | MEMF_CLEAR);
    ColumnWorkRow = (UBYTE *)lwmf_AllocCpuMem(COLUMN_ROW_BYTES, MEMF_CLEAR);
    ColumnPhasePtrWords = (UWORD *)lwmf_AllocCpuMem(COLUMN_PHASE_PTR_SIZE, MEMF_CLEAR);

    BuildFaceTextureColors();
    BuildColumnGeometry();
    BuildShadeTable();
    BuildColumnRows();
    BuildPhaseData();
    BuildCopperList(0);
    BuildCopperList(1);
}

// Update only copper data words; bitplane graphics stay in static row patterns.
static void Update_TwistColumn(UBYTE Buffer)
{
    const UBYTE TwistPhase = (UBYTE)(ColumnTorsionPhase >> 8);
    const WORD TorsionWave = SinTab[TwistPhase];
    const WORD Torsion = TorsionWave + (TorsionWave >> 1);
    const WORD PhaseDelta = Torsion;
    const LONG AccStartLow = -((LONG)COLUMN_HALF_HEIGHT * Torsion);
    const LONG AccStartHigh = AccStartLow + (LONG)COLUMN_SPLIT_ROW * PhaseDelta;
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

    UpdateTwistCopperTextRangeAsm(CopperBodyDataLow[Buffer], ColumnPhasePtrWords, AccStartLow, PhaseDelta, PhaseAdd, TextAdd, COLUMN_SPLIT_ROW);
    UpdateTwistCopperTextRangeAsm(CopperBodyDataHigh[Buffer], ColumnPhasePtrWords, AccStartHigh, PhaseDelta, PhaseAdd, TextAdd + COLUMN_SPLIT_ROW, COLUMN_SPLIT_HEIGHT);
}

static void Cleanup_TwistColumn(void)
{
    FreeMem(ColumnPhasePtrWords, COLUMN_PHASE_PTR_SIZE);
    FreeMem(ColumnWorkRow, COLUMN_ROW_BYTES);
    FreeMem(ColumnBlankRow, COLUMN_ROW_BYTES);
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