#ifndef LWMF_IMAGES_H
#define LWMF_IMAGES_H

struct lwmf_Image
{
	struct BitMap* Image;
	ULONG Width;
	ULONG Height;
	ULONG Depth;
	UBYTE NumberOfColors;
};

struct BitMap* lwmf_BitmapCopy(struct BitMap* SourceBM);
struct lwmf_Image* lwmf_LoadImage(const char* Filename);
void lwmf_DeleteImage(struct lwmf_Image* Image);

struct BitMap* lwmf_BitmapCopy(struct BitMap* SourceBM)
{
	struct BitMap* TargetBM = NULL;
	ULONG Width = 0;
	ULONG Height = 0;

	if (!(TargetBM = AllocBitMap(Width = GetBitMapAttr(SourceBM, BMA_WIDTH), Height = GetBitMapAttr(SourceBM, BMA_HEIGHT), GetBitMapAttr(SourceBM, BMA_DEPTH), BMF_CLEAR, NULL)))
	{
		return NULL;
	}
	
	BltBitMap(SourceBM, 0, 0, TargetBM, 0, 0, Width, Height, 0x0C0, 0xFF, NULL);

	return TargetBM;
}

struct lwmf_Image* lwmf_LoadImage(const char* Filename)
{
	struct lwmf_Image* TempImage = NULL;
	struct BitMapHeader* Header = NULL;
	struct BitMap* TempBitmap = NULL;
	ULONG NumberOfColors = 0;
	APTR dtObject = NULL;

	if (!(dtObject = NewDTObject(Filename, DTA_GroupID, GID_PICTURE, PDTA_Remap, FALSE, TAG_END)))
	{
		lwmf_CleanupAll();
		return NULL;
	}
	
	DoDTMethod(dtObject, NULL, NULL, DTM_PROCLAYOUT, NULL, TRUE);
	GetDTAttrs(dtObject, PDTA_BitMapHeader, &Header, PDTA_DestBitMap, &TempBitmap, PDTA_NumColors, &NumberOfColors, TAG_END);

	if (!(TempImage = AllocMem(sizeof(struct lwmf_Image), MEMF_ANY | MEMF_CLEAR)))
	{
		lwmf_CleanupAll();
		return NULL;
	}

	if (!(TempImage->Image = lwmf_BitmapCopy(TempBitmap)))
	{
		lwmf_CleanupAll();
		return NULL;
	}

	TempImage->Width = Header->bmh_Width;
	TempImage->Height = Header->bmh_Height;
	TempImage->Depth = GetBitMapAttr (TempImage->Image, BMA_DEPTH);
	TempImage->NumberOfColors = NumberOfColors;
	
	DisposeDTObject(dtObject);
	return TempImage;
}

void lwmf_DeleteImage(struct lwmf_Image* Image)
{
	if (Image->Image)
	{
		FreeBitMap(Image->Image);
		Image->Image = NULL;
	}
}


#endif /* LWMF_IMAGES_H */