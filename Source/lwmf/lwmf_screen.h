#ifndef LWMF_SCREEN_H
#define LWMF_SCREEN_H

struct Screen* Screen = NULL;

BOOL lwmf_CreateScreen(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes, UWORD* ColorTable, const int NumberOfColors);
void lwmf_CleanupScreen(void);

BOOL lwmf_CreateScreen(const ULONG Width, const ULONG Height, const int NumberOfBitPlanes, UWORD* ColorTable, const int NumberOfColors)
{
	Screen = OpenScreenTags(NULL,
		SA_Width, Width,
		SA_Height, Height,
	    SA_Depth, NumberOfBitPlanes,
	    SA_ShowTitle, FALSE,
	    SA_Type, CUSTOMSCREEN,
		SA_Quiet, TRUE,
	    TAG_DONE
    );

    if (!Screen)
    {
        return FALSE;
    }

	LoadRGB4(&Screen->ViewPort, ColorTable, NumberOfColors);

    return TRUE;
}

void lwmf_CleanupScreen(void)
{
	if (Screen)
    {
        CloseScreen(Screen);
		Screen = NULL;
    }
}


#endif /* LWMF_SCREEN_H */