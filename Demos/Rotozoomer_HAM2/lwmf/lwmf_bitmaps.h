#ifndef LWMF_BITMAPS_H
#define LWMF_BITMAPS_H

// =====================================================================
// Double buffering
// =====================================================================

static struct BitMap  ScreenBitmapStruct[2];
static UBYTE*         ScreenBitmapMem[2]    = { NULL, NULL };
static struct BitMap* ScreenBitmap[2]       = { NULL, NULL };

// Own replacement for graphics.library InitBitMap() — no library call needed.
// struct BitMap layout: BytesPerRow, Rows, Flags, Depth, pad, Planes[8]
static inline void lwmf_InitBitMap(struct BitMap* bm, UBYTE depth, UWORD w, UWORD h)
{
	bm->BytesPerRow = (UWORD)(((w + 15u) / 16u) * 2u);
	bm->Rows        = h;
	bm->Flags       = 0;
	bm->Depth       = depth;
	bm->pad         = 0;
	for (UBYTE i = 0; i < 8; ++i) bm->Planes[i] = NULL;
}

static BOOL lwmf_InitScreenBitmaps(void)
{
	const ULONG screenBytes = (ULONG)BYTESPERROW * NUMBEROFBITPLANES * SCREENHEIGHT;

	for (UBYTE i = 0; i < 2; ++i)
	{
		if (!(ScreenBitmapMem[i] = (UBYTE*)AllocMem(screenBytes, MEMF_CHIP | MEMF_CLEAR)))
		{
			return FALSE;
		}

		lwmf_InitBitMap(&ScreenBitmapStruct[i], NUMBEROFBITPLANES, SCREENWIDTH, SCREENHEIGHT);
		ScreenBitmapStruct[i].BytesPerRow = BYTESPERROW * NUMBEROFBITPLANES;

		for (UBYTE p = 0; p < NUMBEROFBITPLANES; ++p)
		{
			ScreenBitmapStruct[i].Planes[p] = (PLANEPTR)(ScreenBitmapMem[i] + (ULONG)p * BYTESPERROW);
		}

		ScreenBitmap[i] = &ScreenBitmapStruct[i];
	}

	return TRUE;
}

static void lwmf_CleanupScreenBitmaps(void)
{
	const ULONG screenBytes = (ULONG)BYTESPERROW * NUMBEROFBITPLANES * SCREENHEIGHT;

	for (UBYTE i = 0; i < 2; ++i)
	{
		if (ScreenBitmapMem[i])
		{
			FreeMem(ScreenBitmapMem[i], screenBytes);
			ScreenBitmapMem[i] = NULL;
		}
	}
}

#endif /* LWMF_BITMAPS_H */