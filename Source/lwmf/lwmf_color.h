#ifndef LWMF_COLOR_H
#define LWMF_COLOR_H


void lwmf_SetColors(UWORD* ColorTable, const int NumberOfColors);

void lwmf_SetColors(UWORD* ColorTable, const int NumberOfColors)
{
	LoadRGB4(&Screen->ViewPort, ColorTable, NumberOfColors);
}


#endif /* LWMF_COLOR_H */