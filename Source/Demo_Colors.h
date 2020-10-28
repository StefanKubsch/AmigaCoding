#ifndef COLORS_H
#define COLORS_H


//**********************************
//* Color definitions for demo     *
//*								   *
//* (C) 2020 by Stefan Kubsch      *
//**********************************

UWORD DemoColorTable[3][8] = 
{
	// Sine scroller & 2D Starfield
	{ 
		0x000, // Clear color
		0x2AF, // Bitmap font
		0x444, // Starfield
		0x999,
		0xDDD,
		0x000, // Empty
		0x000,
		0xFFF  // FPS Counter
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
		0xFFF  // FPS Counter
	},
	// 3D Starfield
	{
		0x000, // Clear color
		0xDDD, // Starfield
		0x888,
		0x444,
		0x000, // Empty
		0x000,
		0x000,
		0xFFF  // FPS Counter
	}
};


#endif /* COLORS_H */