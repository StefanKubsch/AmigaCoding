#ifndef COLORS_H
#define COLORS_H


//**********************************
//* Color definitions for demo     *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

UWORD DemoColorTable[3][8] = 
{
	// Color 0 is background/clear color (Black)
	// Color 1 is used for fps counter (White)

	// Sine scroller & 2D Starfield
	{ 
		0x000,
		0xFFF,
		0x666,
		0xAAA,
		0xCCC,
		0xDDD,
		0xEEE,
		0xFFF
	},
	// Filled vector cube
	{
		0x000,
		0xFFF,
		0x0A0,
		0x0B0,
		0x0C0,
		0x0D0,
		0x0E0,
		0x0F0
	},
	// 3D Starfield
	{
		0x000,
		0xFFF,
		0x888,
		0x444,
		0x000,
		0x000,
		0x000,
		0x000
	}
};


#endif /* COLORS_H */