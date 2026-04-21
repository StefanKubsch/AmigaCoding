#ifndef LWMF_IMAGES_H
#define LWMF_IMAGES_H

#ifndef MAKE_ID
#define MAKE_ID(a,b,c,d) ((ULONG)(a)<<24|(ULONG)(b)<<16|(ULONG)(c)<<8|(ULONG)(d))
#endif

struct lwmf_Image
{
	struct BitMap Image;
	UBYTE*        PlaneData;
	ULONG         PlaneDataSize;
	ULONG         Width;
	ULONG         Height;
	ULONG*        CRegs;
	UBYTE         NumberOfColors;
};

// ByteRun1 decompression from a memory buffer
// Returns pointer to the first byte after the decompressed data in the source buffer
static const UBYTE* iff_DecompressMem(const UBYTE* src, UBYTE* dst, UWORD rowBytes)
{
	const UBYTE* const end = dst + rowBytes;

	while (dst < end)
	{
		const BYTE n = (BYTE)*src++;

		if (n >= 0)
		{
			UWORD count = (UWORD)n + 1;
			while (count--) *dst++ = *src++;
		}
		else if (n != -128)
		{
			const UBYTE val = *src++;
			UWORD       count = (UWORD)(1 - n);
			while (count--) *dst++ = val;
		}
		// n == -128: NOP
	}

	return src;
}

// ByteRun1 decompression (IFF-ILBM standard)
// Fallback for when pre-buffering is not possible
static void iff_Decompress(UBYTE* dst, UWORD rowBytes, BPTR FileHandle)
{
	UWORD di = 0;

	while (di < rowBytes)
	{
		BYTE n;
		Read(FileHandle, &n, 1);

		if (n >= 0)
		{
			const UWORD count = (UWORD)n + 1;
			Read(FileHandle, dst + di, count);
			di += count;
		}
		else if (n != -128)
		{
			UBYTE val;
			Read(FileHandle, &val, 1);
			UWORD count = (UWORD)(1 - n);
			while (count--) dst[di++] = val;
		}
		// n == -128: NOP
	}
}

struct lwmf_Image* lwmf_LoadImage(const char* Filename)
{
	BPTR FileHandle = Open((STRPTR)Filename, MODE_OLDFILE);

	if (!FileHandle)
	{
		PutStr("Could not open image file.\n");
		return NULL;
	}

	// Read IFF FORM+ILBM header in a single call (12 bytes: FORM tag, size, type tag)
	ULONG Header[3];
	Read(FileHandle, Header, 12);

	if (Header[0] != MAKE_ID('F','O','R','M') || Header[2] != MAKE_ID('I','L','B','M'))
	{
		Close(FileHandle);
		PutStr("Not an IFF ILBM file.\n");
		return NULL;
	}

	UWORD bmhd_w           = 0;
	UWORD bmhd_h           = 0;
	UBYTE bmhd_nPlanes     = 0;
	UBYTE bmhd_masking     = 0;
	UBYTE bmhd_compression = 0;

	ULONG*            cmap      = NULL;
	UBYTE             numColors = 0;
	BOOL              gotBMHD   = FALSE;
	BOOL              gotBODY   = FALSE;
	UBYTE*            planeData = NULL;
	struct lwmf_Image* img      = NULL;

	while (!gotBODY)
	{
		// Read chunk tag and size in a single call (8 bytes)
		// On the 68000 (big-endian), ULONGs read from file are already in native byte order
		ULONG chunkHdr[2];

		if (Read(FileHandle, chunkHdr, 8) != 8)
		{
			break;
		}

		const ULONG tag         = chunkHdr[0];
		const ULONG chunkSize   = chunkHdr[1];
		const ULONG alignedSize = (chunkSize + 1) & ~1UL;

		if (tag == MAKE_ID('B','M','H','D'))
		{
			// BMHD is always 20 bytes — read in a single call
			UBYTE raw[20];
			Read(FileHandle, raw, 20);
			bmhd_w           = (UWORD)((raw[0] << 8) | raw[1]);
			bmhd_h           = (UWORD)((raw[2] << 8) | raw[3]);
			// raw[4..7] = x, y (not needed)
			bmhd_nPlanes     = raw[8];
			bmhd_masking     = raw[9];
			bmhd_compression = raw[10];
			// raw[11..19] = pad, transparentColor, aspect, pageSize (not needed)
			gotBMHD = TRUE;
		}
		else if (tag == MAKE_ID('C','M','A','P'))
		{
			numColors = (UBYTE)(chunkSize / 3);

			if ((cmap = (ULONG*)lwmf_AllocCpuMem((ULONG)numColors * sizeof(ULONG), MEMF_CLEAR)))
			{
				// Read all RGB triples in a single call
				UBYTE cmapRaw[256 * 3];
				Read(FileHandle, cmapRaw, (ULONG)numColors * 3);

				const UBYTE* src = cmapRaw;

				for (UBYTE i = 0; i < numColors; ++i)
				{
					// RGB8 -> RGB4 (upper nibble only)
					cmap[i] = (ULONG)(((src[0] & 0xF0) << 4) | (src[1] & 0xF0) | (src[2] >> 4));
					src += 3;
				}

				if (chunkSize & 1)
				{
					UBYTE dummy;
					Read(FileHandle, &dummy, 1);
				}
			}
			else
			{
				Seek(FileHandle, (LONG)alignedSize, OFFSET_CURRENT);
			}
		}
		else if (tag == MAKE_ID('B','O','D','Y'))
		{
			if (!gotBMHD)
			{
				Close(FileHandle);
				return NULL;
			}

			// Bytes per row per plane (word-aligned)
			const UWORD rowBytes  = (UWORD)(((bmhd_w + 15) / 16) * 2);
			// Interleaved: all planes stored consecutively per row
			const ULONG rowStride = (ULONG)rowBytes * bmhd_nPlanes;
			const ULONG dataSize  = rowStride * bmhd_h;

			planeData = (UBYTE*)AllocMem(dataSize, MEMF_CHIP);
			img       = (struct lwmf_Image*)lwmf_AllocCpuMem(sizeof(struct lwmf_Image), MEMF_CLEAR);

			if (!planeData || !img)
			{
				if (planeData) FreeMem(planeData, dataSize);
				if (img)       FreeMem(img, sizeof(struct lwmf_Image));
				if (cmap)      FreeMem(cmap, (ULONG)numColors * sizeof(ULONG));
				Close(FileHandle);
				PutStr("Out of Chip RAM for image.\n");
				return NULL;
			}

			// Build interleaved bitmap (all planes consecutive per row)
			lwmf_InitBitMap(&img->Image, bmhd_nPlanes, bmhd_w, bmhd_h);
			img->Image.BytesPerRow = (UWORD)rowStride;

			for (UBYTE p = 0; p < bmhd_nPlanes; ++p)
			{
				img->Image.Planes[p] = (PLANEPTR)(planeData + (ULONG)p * rowBytes);
			}

			// Decode BODY row by row, plane by plane
			if (bmhd_compression == 0)
			{
				// Uncompressed: read entire body in a single call
				Read(FileHandle, planeData, dataSize);
			}
			else
			{
				// Pre-read the entire compressed chunk into a temp buffer,
				// then decompress from RAM — avoids one AmigaDOS syscall per byte
				UBYTE* compBuf = (UBYTE*)lwmf_AllocCpuMem(chunkSize, MEMF_CLEAR);

				if (compBuf)
				{
					Read(FileHandle, compBuf, chunkSize);

					const UBYTE* src     = compBuf;
					UBYTE*       rowBase = planeData;

					for (UWORD y = 0; y < bmhd_h; ++y)
					{
						for (UBYTE p = 0; p < bmhd_nPlanes; ++p)
						{
							src = iff_DecompressMem(src, rowBase + (ULONG)p * rowBytes, rowBytes);
						}

						// Skip mask plane if present (buffer sized for up to 1024px)
						if (bmhd_masking == 1)
						{
							UBYTE dummy[128];
							src = iff_DecompressMem(src, dummy, rowBytes);
						}

						rowBase += rowStride;
					}

					FreeMem(compBuf, chunkSize);
				}
				else
				{
					// Fallback: decompress directly from file (one syscall per byte)
					UBYTE* rowBase = planeData;

					for (UWORD y = 0; y < bmhd_h; ++y)
					{
						for (UBYTE p = 0; p < bmhd_nPlanes; ++p)
						{
							iff_Decompress(rowBase + (ULONG)p * rowBytes, rowBytes, FileHandle);
						}

						// Skip mask plane if present (buffer sized for up to 1024px)
						if (bmhd_masking == 1)
						{
							UBYTE dummy[128];
							iff_Decompress(dummy, rowBytes, FileHandle);
						}

						rowBase += rowStride;
					}
				}
			}

			img->PlaneData      = planeData;
			img->PlaneDataSize  = dataSize;
			img->Width          = bmhd_w;
			img->Height         = bmhd_h;
			img->CRegs          = cmap;
			img->NumberOfColors = numColors;
			gotBODY = TRUE;
		}
		else
		{
			Seek(FileHandle, (LONG)alignedSize, OFFSET_CURRENT);
		}
	}

	Close(FileHandle);
	return img;
}

void lwmf_DeleteImage(struct lwmf_Image* Image)
{
	if (!Image)
	{
		return;
	}

	if (Image->PlaneData)
	{
		FreeMem(Image->PlaneData, Image->PlaneDataSize);
	}

	if (Image->CRegs)
	{
		FreeMem(Image->CRegs, (ULONG)Image->NumberOfColors * sizeof(ULONG));
	}

	FreeMem(Image, sizeof(struct lwmf_Image));
}


#endif /* LWMF_IMAGES_H */