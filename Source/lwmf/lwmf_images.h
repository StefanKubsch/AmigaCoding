#ifndef LWMF_IMAGES_H
#define LWMF_IMAGES_H

struct lwmf_Image
{
	char* Filename;
	struct BitMap* Image;
	struct BitMapHeader* Header;
};

BOOL lwmf_LoadImage(struct lwmf_Image* Image);
void lwmf_DeleteImage(struct lwmf_Image* Image);

BOOL lwmf_LoadImage(struct lwmf_Image* Image)
{
	Object *dtObject = NULL;

	if (!(dtObject = NewDTObject(Image->Filename, DTA_GroupID, GID_PICTURE, PDTA_Remap, TRUE, PDTA_Screen, Screen, TAG_END)))
	{
		lwmf_CleanupRastPort();
		lwmf_CleanupScreen();
		lwmf_CloseLibraries();	
		return FALSE;
	}
	
	DoDTMethod(dtObject, NULL, NULL, DTM_PROCLAYOUT, NULL, TRUE);
	GetDTAttrs(dtObject, PDTA_BitMapHeader, &Image->Header, PDTA_DestBitMap, &Image->Image, TAG_END);

	return TRUE;
}

void lwmf_DeleteImage(struct lwmf_Image* Image)
{
	if (Image->Image)
	{
		FreeBitMap(Image->Image);
		Image->Image = NULL;
		Image->Header = NULL;
	}
}


#endif /* LWMF_IMAGES_H */