#ifndef LWMF_IMAGES_H
#define LWMF_IMAGES_H

struct lwmf_Image
{
	struct BitMap* Image;
	int Width;
	int Height;
	int Depth;
	ULONG NumberOfColors;
};

BOOL lwmf_LoadImage(struct lwmf_Image* Image, const char* Filename);
void lwmf_DeleteImage(struct lwmf_Image* Image);

BOOL lwmf_LoadImage(struct lwmf_Image* Image, const char* Filename)
{
	struct BitMapHeader *Header = NULL;
	Object *dtObject = NULL;

	if (!(dtObject = NewDTObject(Filename, DTA_GroupID, GID_PICTURE, PDTA_Remap, FALSE, PDTA_Screen, Screen, TAG_END)))
	{
		lwmf_CleanupRastPort();
		lwmf_CleanupScreen();
		lwmf_CloseLibraries();	
		return FALSE;
	}
	
	DoDTMethod(dtObject, NULL, NULL, DTM_PROCLAYOUT, NULL, TRUE);
	GetDTAttrs(dtObject, PDTA_BitMapHeader, &Header, PDTA_DestBitMap, &Image->Image, PDTA_NumColors, &Image->NumberOfColors, TAG_END);

	Image->Width = Header->bmh_Width;
	Image->Height = Header->bmh_Height;
	Image->Depth = GetBitMapAttr(Image->Image, BMA_DEPTH);

	return TRUE;
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