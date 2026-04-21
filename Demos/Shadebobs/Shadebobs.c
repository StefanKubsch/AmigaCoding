//**********************************************************************
//* Shadebobs effect                                                   *
//* Amiga 500 OCS                                                      *
//* 512 KB Chip + 512 KB Slow                                          *
//* VBCC C99                                                           *
//*                                                                    *
//* Notes:                                                             *
//* - Copper + interleaved 5 bitplanes                                 *
//* - 32x32 shadebobs                                                  *
//* - Carry-based shadebob increment (+1 mod 32 under bob mask)        *
//* - No clear in main loop                                             *
//* - Fixed 512-step LUT for a clean 2D projection of a                *
//*   Lissajous knot                                                   *
//*                                                                    *
//* Quit with mouse click                                              *
//**********************************************************************

#include "lwmf/lwmf.h"

#define SCREEN_WIDTH            320
#define SCREEN_HEIGHT           256
#define BOB_SIZE                32
#define BOB_WORDS_PER_ROW       3
#define BOB_SHIFT_COUNT         16
#define PATH_STEPS              512
#define FRAME_COPY_BYTES        (BYTESPERROW * SCREEN_HEIGHT * NUMBEROFBITPLANES)
#define SHADEBOB_RADIUS         11
#define BOB_COUNT               2

static UWORD* CopperList = NULL;
static ULONG CopperListSize = 0;

static UWORD BPLPTH_Idx[NUMBEROFBITPLANES];
static UWORD BPLPTL_Idx[NUMBEROFBITPLANES];
static UWORD Color_Idx[32];

#define COPPER_FIXED_WORDS      138

static const UWORD BasePalette[32] =
{
    0x000, 0x001, 0x102, 0x103, 0x204, 0x305, 0x406, 0x507,
    0x608, 0x709, 0x80A, 0x90A, 0xA09, 0xB08, 0xC07, 0xD06,
    0xE05, 0xE13, 0xE30, 0xE50, 0xD70, 0xC90, 0xBB0, 0xAD0,
    0x9E0, 0x8F0, 0xAF2, 0xCF4, 0xDF7, 0xEFA, 0xFFD, 0xFFF
};

static const WORD BobXPath[PATH_STEPS] =
{
    228, 225, 223, 220, 217, 214, 211, 207, 204, 201, 197, 193, 190, 186, 182, 178,
    175, 171, 167, 163, 159, 155, 151, 147, 143, 139, 135, 130, 126, 122, 119, 115,
    111, 107, 103,  99,  96,  92,  89,  85,  82,  78,  75,  72,  69,  66,  63,  61,
     58,  56,  53,  51,  49,  47,  45,  43,  42,  40,  39,  38,  37,  36,  35,  35,
     34,  34,  34,  34,  34,  35,  35,  36,  36,  37,  38,  40,  41,  42,  44,  46,
     48,  50,  52,  54,  56,  59,  62,  64,  67,  70,  73,  76,  80,  83,  86,  90,
     93,  97, 101, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 148, 152,
    156, 160, 164, 168, 172, 176, 180, 184, 187, 191, 195, 198, 202, 205, 208, 212,
    215, 218, 221, 224, 226, 229, 232, 234, 236, 238, 240, 242, 244, 246, 247, 248,
    250, 251, 252, 252, 253, 253, 254, 254, 254, 254, 254, 253, 253, 252, 251, 250,
    249, 248, 246, 245, 243, 241, 239, 237, 235, 232, 230, 227, 225, 222, 219, 216,
    213, 209, 206, 203, 199, 196, 192, 189, 185, 181, 177, 173, 169, 165, 161, 157,
    153, 149, 145, 141, 137, 133, 129, 125, 121, 117, 113, 109, 106, 102,  98,  94,
     91,  87,  84,  81,  77,  74,  71,  68,  65,  62,  60,  57,  55,  53,  50,  48,
     46,  45,  43,  41,  40,  39,  38,  37,  36,  35,  35,  34,  34,  34,  34,  34,
     35,  35,  36,  37,  38,  39,  40,  41,  43,  45,  46,  48,  50,  53,  55,  57,
     60,  63,  65,  68,  71,  74,  77,  81,  84,  87,  91,  95,  98, 102, 106, 110,
    113, 117, 121, 125, 129, 133, 137, 141, 145, 149, 153, 158, 162, 166, 169, 173,
    177, 181, 185, 189, 192, 196, 199, 203, 206, 210, 213, 216, 219, 222, 225, 227,
    230, 232, 235, 237, 239, 241, 243, 245, 246, 248, 249, 250, 251, 252, 253, 253,
    254, 254, 254, 254, 254, 253, 253, 252, 252, 251, 250, 248, 247, 246, 244, 242,
    240, 238, 236, 234, 232, 229, 226, 224, 221, 218, 215, 212, 208, 205, 202, 198,
    195, 191, 187, 184, 180, 176, 172, 168, 164, 160, 156, 152, 148, 144, 140, 136,
    132, 128, 124, 120, 116, 112, 108, 104, 101,  97,  93,  90,  86,  83,  80,  76,
     73,  70,  67,  64,  62,  59,  56,  54,  52,  50,  48,  46,  44,  42,  41,  40,
     38,  37,  36,  36,  35,  35,  34,  34,  34,  34,  34,  35,  35,  36,  37,  38,
     39,  40,  42,  43,  45,  47,  49,  51,  53,  56,  58,  61,  63,  66,  69,  72,
     75,  79,  82,  85,  89,  92,  96,  99, 103, 107, 111, 115, 119, 123, 127, 131,
    135, 139, 143, 147, 151, 155, 159, 163, 167, 171, 175, 179, 182, 186, 190, 194,
    197, 201, 204, 207, 211, 214, 217, 220, 223, 226, 228, 231, 233, 235, 238, 240,
    242, 243, 245, 247, 248, 249, 250, 251, 252, 253, 253, 254, 254, 254, 254, 254,
    253, 253, 252, 251, 250, 249, 248, 247, 245, 243, 242, 240, 238, 235, 233, 231
};

static const WORD BobYPath[PATH_STEPS] =
{
    194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
    158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103,  99,
     95,  91,  87,  83,  80,  76,  72,  69,  65,  62,  58,  55,  52,  50,  47,  44,
     42,  40,  38,  36,  34,  33,  32,  30,  30,  29,  28,  28,  28,  28,  28,  29,
     30,  31,  32,  33,  35,  36,  38,  40,  42,  45,  47,  50,  53,  56,  59,  62,
     66,  69,  73,  76,  80,  84,  88,  92,  96, 100, 104, 108, 112, 116, 121, 125,
    129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
    182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
    194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
    158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103,  99,
     95,  91,  87,  83,  80,  76,  72,  69,  65,  62,  58,  55,  52,  50,  47,  44,
     42,  40,  38,  36,  34,  33,  32,  30,  30,  29,  28,  28,  28,  28,  28,  29,
     30,  31,  32,  33,  35,  36,  38,  40,  42,  45,  47,  50,  53,  56,  59,  62,
     66,  69,  73,  76,  80,  84,  88,  92,  96, 100, 104, 108, 112, 116, 121, 125,
    129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
    182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
    194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
    158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103,  99,
     95,  91,  87,  83,  80,  76,  72,  69,  65,  62,  58,  55,  52,  50,  47,  44,
     42,  40,  38,  36,  34,  33,  32,  30,  30,  29,  28,  28,  28,  28,  28,  29,
     30,  31,  32,  33,  35,  36,  38,  40,  42,  45,  47,  50,  53,  56,  59,  62,
     66,  69,  73,  76,  80,  84,  88,  92,  96, 100, 104, 108, 112, 116, 121, 125,
    129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
    182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195,
    194, 193, 192, 191, 189, 188, 186, 184, 182, 179, 177, 174, 171, 168, 165, 162,
    158, 155, 151, 148, 144, 140, 136, 132, 128, 124, 120, 116, 112, 108, 103,  99,
     95,  91,  87,  83,  80,  76,  72,  69,  65,  62,  58,  55,  52,  50,  47,  44,
     42,  40,  38,  36,  34,  33,  32,  30,  30,  29,  28,  28,  28,  28,  28,  29,
     30,  31,  32,  33,  35,  36,  38,  40,  42,  45,  47,  50,  53,  56,  59,  62,
     66,  69,  73,  76,  80,  84,  88,  92,  96, 100, 104, 108, 112, 116, 121, 125,
    129, 133, 137, 141, 144, 148, 152, 155, 159, 162, 166, 169, 172, 174, 177, 180,
    182, 184, 186, 188, 190, 191, 192, 194, 194, 195, 196, 196, 196, 196, 196, 195
};

static UWORD BobMaskShifted[BOB_SHIFT_COUNT][BOB_SIZE][BOB_WORDS_PER_ROW];

static void BuildBobMask(void)
{
    WORD x;
    WORD y;
    UWORD shift;

    for (shift = 0; shift < BOB_SHIFT_COUNT; ++shift)
    {
        for (y = 0; y < BOB_SIZE; ++y)
        {
            BobMaskShifted[shift][y][0] = 0;
            BobMaskShifted[shift][y][1] = 0;
            BobMaskShifted[shift][y][2] = 0;
        }
    }

    for (y = 0; y < BOB_SIZE; ++y)
    {
        for (x = 0; x < BOB_SIZE; ++x)
        {
            WORD dx = x - (BOB_SIZE / 2);
            WORD dy = y - (BOB_SIZE / 2);
            WORD dist2 = (dx * dx) + (dy * dy);

            if (dist2 <= (SHADEBOB_RADIUS * SHADEBOB_RADIUS))
            {
                for (shift = 0; shift < BOB_SHIFT_COUNT; ++shift)
                {
                    UWORD bitPos = (UWORD)x + shift;
                    if (bitPos < 16)
                    {
                        BobMaskShifted[shift][y][0] |= (UWORD)(0x8000u >> bitPos);
                    }
                    else if (bitPos < 32)
                    {
                        BobMaskShifted[shift][y][1] |= (UWORD)(0x8000u >> (bitPos - 16));
                    }
                    else
                    {
                        BobMaskShifted[shift][y][2] |= (UWORD)(0x8000u >> (bitPos - 32));
                    }
                }
            }
        }
    }
}

static void CopyBuffer(UBYTE dstBuffer, UBYTE srcBuffer)
{
    CopyMemQuick(
        (CONST_APTR)ScreenBitmap[srcBuffer]->Planes[0],
        (APTR)ScreenBitmap[dstBuffer]->Planes[0],
        FRAME_COPY_BYTES);
}

static void ShadebobCarryWord(UWORD* dst, UWORD mask)
{
    UWORD* p0 = dst;
    UWORD* p1 = dst + (BYTESPERROW >> 1);
    UWORD* p2 = dst + (BYTESPERROW);
    UWORD* p3 = dst + (BYTESPERROW + (BYTESPERROW >> 1));
    UWORD* p4 = dst + (BYTESPERROW << 1);

    UWORD old0 = *p0;
    UWORD old1 = *p1;
    UWORD old2 = *p2;
    UWORD old3 = *p3;
    UWORD old4 = *p4;
    UWORD carry = mask;

    *p0 = (UWORD)(old0 ^ carry);
    carry = (UWORD)(old0 & carry);

    *p1 = (UWORD)(old1 ^ carry);
    carry = (UWORD)(old1 & carry);

    *p2 = (UWORD)(old2 ^ carry);
    carry = (UWORD)(old2 & carry);

    *p3 = (UWORD)(old3 ^ carry);
    carry = (UWORD)(old3 & carry);

    *p4 = (UWORD)(old4 ^ carry);
}

static void DrawShadebob(UBYTE buffer, WORD x, WORD y)
{
    UWORD shift;
    UWORD row;
    UWORD wordOffset;
    UWORD* dst;

    if (x < 0 || y < 0) return;
    if (x > (SCREEN_WIDTH - BOB_SIZE)) return;
    if (y > (SCREEN_HEIGHT - BOB_SIZE)) return;

    shift = (UWORD)(x & 15);
    wordOffset = (UWORD)(x >> 4);

    dst = (UWORD*)(ScreenBitmap[buffer]->Planes[0] + (y * BYTESPERROW * NUMBEROFBITPLANES));
    dst += wordOffset;

    for (row = 0; row < BOB_SIZE; ++row)
    {
        UWORD* rowDst = dst;
        UWORD mask0 = BobMaskShifted[shift][row][0];
        UWORD mask1 = BobMaskShifted[shift][row][1];
        UWORD mask2 = BobMaskShifted[shift][row][2];

        if (mask0) ShadebobCarryWord(rowDst, mask0);
        if (mask1) ShadebobCarryWord(rowDst + 1, mask1);
        if (mask2) ShadebobCarryWord(rowDst + 2, mask2);

        dst = (UWORD*)((UBYTE*)dst + (BYTESPERROW * NUMBEROFBITPLANES));
    }
}

static void DrawShadebobs(UBYTE buffer, UWORD phase)
{
    WORD x;
    WORD y;
    UWORD idx;
    UWORD i;

    for (i = 0; i < BOB_COUNT; ++i)
    {
        idx = (UWORD)((phase + (i * (PATH_STEPS / BOB_COUNT))) & (PATH_STEPS - 1));
        x = BobXPath[idx];
        y = BobYPath[idx];
        DrawShadebob(buffer, x, y);
    }
}

BOOL Init(void)
{
    if (NUMBEROFBITPLANES != 5)
    {
        return FALSE;
    }

    BuildBobMask();
    return TRUE;
}

void Init_CopperList(void)
{
    const ULONG CopperListLength = COPPER_FIXED_WORDS;
    UWORD Index = 0;
    UWORD p;
    UWORD c;

    CopperListSize = CopperListLength * sizeof(UWORD);
    CopperList = (UWORD*)AllocMem(CopperListSize, MEMF_CHIP | MEMF_CLEAR);
    if (!CopperList) return;

    CopperList[Index++] = 0x08E; CopperList[Index++] = 0x2C81;
    CopperList[Index++] = 0x090; CopperList[Index++] = 0x2CC1;
    CopperList[Index++] = 0x092; CopperList[Index++] = 0x0038;
    CopperList[Index++] = 0x094; CopperList[Index++] = 0x00D0;

    CopperList[Index++] = 0x100;
    CopperList[Index++] = (UWORD)((NUMBEROFBITPLANES << 12) | 0x0200);
    CopperList[Index++] = 0x102; CopperList[Index++] = 0x0000;
    CopperList[Index++] = 0x104; CopperList[Index++] = 0x0000;

    CopperList[Index++] = 0x108;
    CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);
    CopperList[Index++] = 0x10A;
    CopperList[Index++] = BYTESPERROW * (NUMBEROFBITPLANES - 1);

    for (p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        CopperList[Index++] = (UWORD)(0x0E0u + (p * 4u));
        BPLPTH_Idx[p] = Index;
        CopperList[Index++] = 0x0000;

        CopperList[Index++] = (UWORD)(0x0E2u + (p * 4u));
        BPLPTL_Idx[p] = Index;
        CopperList[Index++] = 0x0000;
    }

    for (c = 0; c < 32; ++c)
    {
        CopperList[Index++] = (UWORD)(0x0180u + (c * 2u));
        Color_Idx[c] = Index;
        CopperList[Index++] = BasePalette[c];
    }

    CopperList[Index++] = 0xFFFF;
    CopperList[Index++] = 0xFFFE;

    *COP1LC = (ULONG)CopperList;
}

void Update_BitplanePointers(UBYTE Buffer)
{
    ULONG Ptr = (ULONG)ScreenBitmap[Buffer]->Planes[0];
    UWORD p;

    for (p = 0; p < NUMBEROFBITPLANES; ++p)
    {
        CopperList[BPLPTH_Idx[p]] = (UWORD)(Ptr >> 16);
        CopperList[BPLPTL_Idx[p]] = (UWORD)(Ptr & 0xFFFFu);
        Ptr += BYTESPERROW;
    }
}

void Cleanup_All(void)
{
    lwmf_WaitBlitter();

    if (CopperList)
    {
        FreeMem(CopperList, CopperListSize);
        CopperList = NULL;
    }

    lwmf_CleanupScreenBitmaps();
    lwmf_CleanupAll();
}

int main(void)
{
    UBYTE ViewBuffer = 0;
    UBYTE DrawBuffer = 1;
    UWORD Phase = 0;

    lwmf_LoadGraphicsLib();
    lwmf_InitScreenBitmaps();

    if (!Init())
    {
        Cleanup_All();
        return 0;
    }

    Init_CopperList();
    if (!CopperList)
    {
        Cleanup_All();
        return 0;
    }

    lwmf_ClearScreen((long*)ScreenBitmap[0]->Planes[0]);
    lwmf_ClearScreen((long*)ScreenBitmap[1]->Planes[0]);

    Update_BitplanePointers(ViewBuffer);
    lwmf_TakeOverOS();

    while (*CIAA_PRA & 0x40)
    {
        CopyBuffer(DrawBuffer, ViewBuffer);
        DrawShadebobs(DrawBuffer, Phase);

        lwmf_WaitVertBlank();
        Update_BitplanePointers(DrawBuffer);

        ViewBuffer ^= 1;
        DrawBuffer ^= 1;
        Phase = (UWORD)((Phase + 1) & (PATH_STEPS - 1));
    }

    Cleanup_All();
    return 0;
}
