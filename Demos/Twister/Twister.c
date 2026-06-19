//**********************************************************************
//* Twister                                                            *
//* 320x256, 5 bitplanes, PAL OCS                                      *
//*                                                                    *
//* Coded for vbcc / lwmf                                              *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

#define HWREG_W(a) (*(volatile UWORD *)(a))
#define HWREG_L(a) (*(volatile ULONG *)(a))

// =====================================================================
// Screen / Copper
// =====================================================================

#define BPLCON0_5BPL_LORES 0x5200
#define BPLCON0 0xDFF100
#define COPJMP1 0xDFF088
#define COPPER_WORDS 8192
#define COPPER_DISPLAY_START 0x2C
#define COPPER_WAIT_H 0x01
#define ROW_REPEAT_MOD 0xFFD8

#define BPLPTH_REG(p) (0x0E0 + ((p) << 2))
#define BPLPTL_REG(p) (0x0E2 + ((p) << 2))

static UWORD *CopperList[2];
static UWORD *CopperBodyDataLow[2];
static UWORD *CopperBodyDataHigh[2];
static ULONG CopperListSize;

static const UWORD ColumnPalette[32] =
    {
        0x000,
        0x013, 0x024, 0x124, 0x225,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000, 0x000,
        0x000, 0x000, 0x000};

static inline void CopperPut(UWORD **Cop, UWORD Reg, UWORD Value)
{
    *(*Cop)++ = Reg;
    *(*Cop)++ = Value;
}

static void CopperWaitLine(UWORD **Cop, UWORD ScreenY, UBYTE *Past255)
{
    const UWORD BeamY = COPPER_DISPLAY_START + ScreenY;

    if (BeamY >= 256 && !*Past255)
    {
        *(*Cop)++ = 0xFFDF;
        *(*Cop)++ = 0xFFFE;
        *Past255 = 1;
    }

    *(*Cop)++ = (UWORD)(((BeamY & 255) << 8) | COPPER_WAIT_H);
    *(*Cop)++ = 0xFFFE;
}

static void MakePointerWords(UBYTE *Row, UWORD *Words)
{
    for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        const ULONG Addr = (ULONG)(Row + (ULONG)p * BYTESPERROW);

        Words[p << 1] = (UWORD)(Addr >> 16);
        Words[(p << 1) + 1] = (UWORD)Addr;
    }
}

static void CopperPutPointerBlock(UWORD **Cop, const UWORD *Words)
{
    for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        CopperPut(Cop, BPLPTH_REG(p), Words[p << 1]);
        CopperPut(Cop, BPLPTL_REG(p), Words[(p << 1) + 1]);
    }
}

static UWORD *CopperPutColumnBodyBlock(UWORD **Cop, const UWORD *PointerWords)
{
    UWORD *Data = *Cop + 1;

    CopperPutPointerBlock(Cop, PointerWords);

    return Data;
}

// =====================================================================
// Square twist column
// =====================================================================

#define COLUMN_TOP 24
#define COLUMN_HEIGHT 208
#define COLUMN_HALF_HEIGHT (COLUMN_HEIGHT >> 1)
#define COLUMN_TORSION_SHIFT 7
#define COLUMN_SCROLL_SPEED 2
#define COLUMN_TORSION_FRAME_SHIFT 0
#define COLUMN_TORSION_DEADBAND 12
#define COLUMN_CENTER_X 160
#define SQUARE_SCREEN_SCALE 48
#define SQUARE_SCREEN_SCALE_DEN 91
#define COLUMN_PHASES 256
#define COLUMN_ROW_BYTES (BYTESPERROW * NUMBEROFBITPLANES)
#define COLUMN_ROWDATA_SIZE ((ULONG)COLUMN_PHASES * COLUMN_ROW_BYTES)
#define COLUMN_PHASE_WORDS 16
#define COLUMN_PHASE_PTR_SIZE ((ULONG)COLUMN_PHASES * COLUMN_PHASE_WORDS * sizeof(UWORD))
#define COLUMN_SPLIT_ROW (256 - COPPER_DISPLAY_START - COLUMN_TOP)
#define COLUMN_SPLIT_HEIGHT (COLUMN_HEIGHT - COLUMN_SPLIT_ROW)

void UpdateTwistCopperRangeAsm(__reg("a0") UWORD *CopperData,
                               __reg("a1") const UWORD *PhaseWords,
                               __reg("d0") LONG AccStart,
                               __reg("d1") WORD PhaseDelta,
                               __reg("d2") UWORD PhaseAdd,
                               __reg("d3") UWORD Count);

static UWORD ColumnFrame;
static UWORD ColumnScrollPhase;
static WORD ColumnScrollDir = 1;
static UBYTE *ColumnRowData;
static UBYTE *ColumnBlankRow;
static UWORD *ColumnPhasePtrWords;

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

static void SetFullRowPixelX(UBYTE *Row, UWORD PosX, UBYTE Color)
{
    const UBYTE Bit = (UBYTE)(0x80 >> (PosX & 7));
    const UBYTE Byte = (UBYTE)(PosX >> 3);

    Row[0 * BYTESPERROW + Byte] &= (UBYTE)~Bit;
    Row[1 * BYTESPERROW + Byte] &= (UBYTE)~Bit;
    Row[2 * BYTESPERROW + Byte] &= (UBYTE)~Bit;
    Row[3 * BYTESPERROW + Byte] &= (UBYTE)~Bit;
    Row[4 * BYTESPERROW + Byte] &= (UBYTE)~Bit;

    if (Color & 1)
        Row[0 * BYTESPERROW + Byte] |= Bit;
    if (Color & 2)
        Row[1 * BYTESPERROW + Byte] |= Bit;
    if (Color & 4)
        Row[2 * BYTESPERROW + Byte] |= Bit;
    if (Color & 8)
        Row[3 * BYTESPERROW + Byte] |= Bit;
    if (Color & 16)
        Row[4 * BYTESPERROW + Byte] |= Bit;
}

static void DrawSquareFace(UBYTE *Row, UBYTE Face, WORD X0, WORD X1)
{
    WORD Start;
    WORD End;
    const UBYTE Color = Face + 1;

    if (X0 < X1)
    {
        Start = X0;
        End = X1;
    }
    else
    {
        Start = X1;
        End = X0;
    }

    if (Start < 0)
    {
        Start = 0;
    }

    if (End >= SCREENWIDTH)
    {
        End = SCREENWIDTH - 1;
    }

    for (WORD x = Start; x <= End; ++x)
    {
        SetFullRowPixelX(Row, (UWORD)x, Color);
    }
}

static void BuildColumnRows(void)
{
    for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
    {
        UBYTE *Row = ColumnRowData + (ULONG)Phase * COLUMN_ROW_BYTES;
        const WORD S = SinTab[Phase];
        const WORD C = SinTab[(Phase + 64) & 255];
        WORD ProjectedX[4];
        WORD SegmentStart[4];
        WORD SegmentX0[4];
        WORD SegmentX1[4];
        UBYTE SegmentFace[4];
        UBYTE SegmentCount = 0;

        for (UBYTE v = 0; v < 4; ++v)
        {
            const LONG RotX = ((LONG)SquareVertexX[v] * C) - ((LONG)SquareVertexZ[v] * S);
            const WORD X = (WORD)(RotX >> 7);

            ProjectedX[v] = COLUMN_CENTER_X + (WORD)(((LONG)X * SQUARE_SCREEN_SCALE) / SQUARE_SCREEN_SCALE_DEN);
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
            DrawSquareFace(Row, SegmentFace[i], SegmentX0[i], SegmentX1[i]);
        }
    }
}

static void BuildPhasePointers(void)
{
    for (UWORD Phase = 0; Phase < COLUMN_PHASES; ++Phase)
    {
        UWORD *Dst = ColumnPhasePtrWords + (Phase << 4);
        UBYTE *Row = ColumnRowData + (ULONG)Phase * COLUMN_ROW_BYTES;

        MakePointerWords(Row, Dst);
    }
}

static void BuildCopperList(UBYTE Buffer)
{
    UWORD BlankWords[10];
    UWORD *Cop = CopperList[Buffer];
    UBYTE Past255 = 0;

    MakePointerWords(ColumnBlankRow, BlankWords);
    CopperPut(&Cop, 0x8E, 0x2C81);
    CopperPut(&Cop, 0x90, 0x2CC1);
    CopperPut(&Cop, 0x92, 0x0038);
    CopperPut(&Cop, 0x94, 0x00D0);

    CopperPut(&Cop, 0x106, 0x0000);
    CopperPut(&Cop, 0x10C, 0x0000);
    CopperPut(&Cop, 0x1FC, 0x0000);

    CopperPut(&Cop, 0x100, BPLCON0_5BPL_LORES);
    CopperPut(&Cop, 0x102, 0x0000);
    CopperPut(&Cop, 0x104, 0x0000);
    CopperPut(&Cop, 0x108, ROW_REPEAT_MOD);
    CopperPut(&Cop, 0x10A, ROW_REPEAT_MOD);

    CopperPutPointerBlock(&Cop, BlankWords);

    for (UBYTE c = 0; c < 32; ++c)
    {
        CopperPut(&Cop, 0x180 + c * 2, ColumnPalette[c]);
    }

    CopperWaitLine(&Cop, COLUMN_TOP - 1, &Past255);
    CopperPutPointerBlock(&Cop, BlankWords);

    for (UWORD y = 0; y < COLUMN_HEIGHT; ++y)
    {
        UWORD *Data;

        CopperWaitLine(&Cop, COLUMN_TOP + y, &Past255);
        Data = CopperPutColumnBodyBlock(&Cop, BlankWords);

        if (y == 0)
        {
            CopperBodyDataLow[Buffer] = Data;
        }
        else if (y == COLUMN_SPLIT_ROW)
        {
            CopperBodyDataHigh[Buffer] = Data;
        }
    }

    CopperWaitLine(&Cop, COLUMN_TOP + COLUMN_HEIGHT, &Past255);
    CopperPutPointerBlock(&Cop, BlankWords);

    *Cop++ = 0xFFFF;
    *Cop++ = 0xFFFE;
}

static void Init_TwistColumn(void)
{
    CopperListSize = sizeof(UWORD) * COPPER_WORDS;
    CopperList[0] = (UWORD *)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);
    CopperList[1] = (UWORD *)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);
    ColumnRowData = (UBYTE *)AllocMem(COLUMN_ROWDATA_SIZE, MEMF_CHIP | MEMF_CLEAR);
    ColumnBlankRow = (UBYTE *)AllocMem(COLUMN_ROW_BYTES, MEMF_CHIP | MEMF_CLEAR);
    ColumnPhasePtrWords = (UWORD *)lwmf_AllocCpuMem(COLUMN_PHASE_PTR_SIZE, MEMF_CLEAR);

    BuildColumnRows();
    BuildPhasePointers();
    BuildCopperList(0);
    BuildCopperList(1);
}

static void Update_TwistColumn(UBYTE Buffer)
{
    const WORD TorsionWave = SinTab[(ColumnFrame >> COLUMN_TORSION_FRAME_SHIFT) & 255];
    const WORD Torsion = TorsionWave + (TorsionWave >> 1);
    const WORD PhaseDelta = Torsion;
    const LONG AccStartLow = -((LONG)COLUMN_HALF_HEIGHT * Torsion);
    const LONG AccStartHigh = AccStartLow + (LONG)COLUMN_SPLIT_ROW * PhaseDelta;

    if (Torsion > COLUMN_TORSION_DEADBAND)
    {
        ColumnScrollDir = 1;
    }
    else if (Torsion < -COLUMN_TORSION_DEADBAND)
    {
        ColumnScrollDir = -1;
    }

    ColumnScrollPhase = (UWORD)(ColumnScrollPhase + (WORD)(ColumnScrollDir * COLUMN_SCROLL_SPEED));

    UpdateTwistCopperRangeAsm(CopperBodyDataLow[Buffer], ColumnPhasePtrWords, AccStartLow, PhaseDelta, ColumnScrollPhase, COLUMN_SPLIT_ROW);
    UpdateTwistCopperRangeAsm(CopperBodyDataHigh[Buffer], ColumnPhasePtrWords, AccStartHigh, PhaseDelta, ColumnScrollPhase, COLUMN_SPLIT_HEIGHT);
}

static void Cleanup_TwistColumn(void)
{
    FreeMem(ColumnPhasePtrWords, COLUMN_PHASE_PTR_SIZE);
    FreeMem(ColumnBlankRow, COLUMN_ROW_BYTES);
    FreeMem(ColumnRowData, COLUMN_ROWDATA_SIZE);
    FreeMem(CopperList[1], CopperListSize);
    FreeMem(CopperList[0], CopperListSize);
}

// =====================================================================
// Main
// =====================================================================

int main(void)
{
    UBYTE Buffer = 0;

    lwmf_LoadGraphicsLib();
    Init_TwistColumn();
    Update_TwistColumn(0);
    ++ColumnFrame;

    lwmf_TakeOverOS();

    *SPR0PTH = (ULONG)BlankMousePointer >> 16;
    *SPR0PTL = (ULONG)BlankMousePointer & 0xFFFF;
    *COP1LC = (ULONG)CopperList[0];
    HWREG_W(COPJMP1) = 0x0000;

    while (*CIAA_PRA & 0x40)
    {
        Buffer ^= 1;
        Update_TwistColumn(Buffer);
        ++ColumnFrame;

        lwmf_WaitVertBlank();
        *COP1LC = (ULONG)CopperList[Buffer];
        HWREG_W(COPJMP1) = 0x0000;
    }

    lwmf_WaitVertBlank();
    HWREG_W(BPLCON0) = 0x0000;
    lwmf_CleanupAll();
    Cleanup_TwistColumn();

    return 0;
}
