#ifndef COLORS_H
#define COLORS_H


//**********************************
//* Color definitions for demo     *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

UWORD DemoColorTable[5][8] = 
{
	// TextLogo
	{ 
		0x000, // Clear color
		0x368, // Logo colors
		0x134, 
		0x012,
		0x246,
		0x146,
		0x123,
		0x001
	},
	// Sine scroller
	{ 
		0x000, // Clear color
		0xC0D, // Bitmap font
		0x000, 
		0x000,
		0x000,
		0x000,
		0x000,
		0x000
	},
	// 2D Starfield
	{ 
		0x000, // Clear color
		0x555, // Starfield
		0x888, 
		0xFFF,
		0x000,
		0x000,
		0x000,
		0x000
	},

	// Filled vector cube
	{
		0x000, // Clear color
		0x0A0, // Cube
		0x0B0,
		0x0C0,
		0x0D0,
		0x0E0,
		0x0F0,
		0x000
	},
	// 3D Starfield
	{
		0x000, // Clear color
		0xDDD, // Starfield
		0x888,
		0x444,
		0x000,
		0x000,
		0x000,
		0x000
	}
};


#endif /* COLORS_H */