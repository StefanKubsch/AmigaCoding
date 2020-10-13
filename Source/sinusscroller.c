/* Copyright (C) 2002 W.P. van Paassen - peter@paassen.tmfweb.nl

   This program is free software; you can redistribute it and/or modify it under
   the terms of the GNU General Public License as published by the Free
   Software Foundation; either version 2 of the License, or (at your
   option) any later version.

   This program is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
   FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
   for more details.

   You should have received a copy of the GNU General Public License
   along with this program; see the file COPYING.  If not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.  */

/*note that the code has not been fully optimized*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>

#include "tdec.h"

#define CHARACTER_WIDTH 16
#define CHARACTER_HEIGHT 32
#define SCREEN_WIDTH 480
#define SCREEN_HEIGHT 360

static SDL_Surface* font_surface;
static SDL_Surface* scroll_surface;
static SDL_Surface* copper_surface;
static SDL_Surface* copy_surface;

static short aSin[360];
static char text[] = " A 1 pixel sinus scroller - pretty retro isn't it? - cheers -   W.P. van Paassen -       starting over again in -      9  8  7  6  5  4  3  2  1                    ";
static char characters[] = " !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
static char* text_pointer = text;

void quit( int code )
{
  /*
   * Quit SDL so we can release the fullscreen
   * mode and restore the previous video settings,
   * etc.
   */
  
  SDL_FreeSurface(scroll_surface);
  SDL_FreeSurface(font_surface);
  SDL_FreeSurface(copper_surface);
  SDL_FreeSurface(copy_surface);

  SDL_Quit( );

  TDEC_print_fps();
  
  /* Exit program. */
  exit( code );
}

void handle_key_down( SDL_keysym* keysym )
{
    switch( keysym->sym )
      {
      case SDLK_ESCAPE:
        quit( 0 );
        break;
      default:
        break;
      }
}

void process_events( void )
{
    /* Our SDL event placeholder. */
    SDL_Event event;

    /* Grab all the events off the queue. */
    while( SDL_PollEvent( &event ) ) {

        switch( event.type ) {
        case SDL_KEYDOWN:
            /* Handle key presses. */
            handle_key_down( &event.key.keysym );
            break;
        case SDL_QUIT:
            /* Handle quit requests*/
            quit( 0 );
            break;
	}
    }
}

/* determine the print character */
Uint16 compute_font_pos(char scroll_char)
{
  char* p = characters;
  Uint16 pos = 0;

  if (scroll_char == '\0')
    {
      text_pointer = text;
      scroll_char = *text_pointer++;
    }

  while (*p++ != scroll_char)
    {
      pos += CHARACTER_WIDTH;
    }

  if (pos > 0)
    return pos - 1;

  return 0;
}

void print_character(void) 
{
  static SDL_Rect frect = {0, 0, CHARACTER_WIDTH, CHARACTER_HEIGHT};
  static SDL_Rect srect = {SCREEN_WIDTH + CHARACTER_WIDTH, 0, CHARACTER_WIDTH, CHARACTER_HEIGHT};

  /* determine font character according to position in scroll text */
  
  frect.x = compute_font_pos(*text_pointer++);

  /*copy character to scroll_screen */
      
  SDL_BlitSurface(font_surface, &frect, scroll_surface, &srect);  
}

void init()
{
  SDL_Surface* s;
  float rad;
  Uint16 i;
  short centery = SCREEN_HEIGHT >> 1;
  SDL_Color colors[129];
  SDL_Rect r = {0,0, SCREEN_WIDTH, 1};
  
  /*create sin lookup table */
  for (i = 0; i < 360; i++)
    {
      rad =  (float)i * 0.0174532; 
      aSin[i] = centery + (short)((sin(rad) * 45.0));
    }
  
  /* create scroll surface, this surface must be wider than the screenwidth to print the characters outside the screen */
  
  s = SDL_CreateRGBSurface(SDL_HWSURFACE, SCREEN_WIDTH + CHARACTER_WIDTH * 2, CHARACTER_HEIGHT, 8, r_mask, g_mask, b_mask, a_mask); 
  
  scroll_surface = SDL_DisplayFormat(s);
  
  SDL_FreeSurface(s);
  
  /* load font */
  
  font_surface = IMG_Load("../GFX/font.pcx");

  /*create copper surface*/
  s = SDL_CreateRGBSurface(SDL_HWSURFACE, SCREEN_WIDTH, 128, 8,  r_mask, g_mask, b_mask, a_mask); 
  
  copper_surface = SDL_DisplayFormat(s);
  
  for (i = 0; i < 32; ++i)
    {
      colors[i].r = i << 3;
      colors[i].g = 255 - ((i << 3) + 1); 
      colors[i].b = 0;
      colors[i+32].r = 255;
      colors[i+32].g = (i << 3) + 1;
      colors[i+32].b = 0;
      colors[i+64].r = 255 - ((i << 3) + 1);
      colors[i+64].g = 255 - ((i << 3) + 1);
      colors[i+64].b = i << 3;
      colors[i+96].r = 0;
      colors[i+96].g = i << 3;
      colors[i+96].b = 255 - (i << 3); 
    }
  
  for (i = 0; i < 128; ++i)
    {
      SDL_FillRect(copper_surface, &r, SDL_MapRGB(copper_surface->format, colors[i].r, colors[i].g, colors[i].b));
      r.y++;
    }
  
  SDL_FreeSurface(s);
  
  /* create copy surface */
  
  copy_surface = TDEC_copy_surface(copper_surface); 
  
  /*disable events */

  for (i = 0; i < SDL_NUMEVENTS; ++i)
    {
      if (i != SDL_KEYDOWN && i != SDL_QUIT)
	{
	  SDL_EventState(i, SDL_IGNORE);
	}
    }

  SDL_ShowCursor(SDL_DISABLE);
}

int main( int argc, char* argv[] )
{
  Uint32 i, displacement = 0, j = 0, temp;
  SDL_Rect srect2 = {0, 0, 1, CHARACTER_HEIGHT};
  SDL_Rect drect = {0, 0, 1, CHARACTER_HEIGHT}; 
  SDL_Rect srect = {2, 0, SCREEN_WIDTH + (CHARACTER_WIDTH * 2), CHARACTER_HEIGHT};
  SDL_Rect frect = {0, SCREEN_HEIGHT / 2 - 45, SCREEN_WIDTH, 130};
  SDL_Rect crect1 = {0, 1, SCREEN_WIDTH, 127};
  SDL_Rect crect2 = {0, 0, SCREEN_WIDTH, 127};
  SDL_Rect crect3 = {0, 127, SCREEN_WIDTH, 1}; 
  
  if (argc > 1)
    {
      printf("Retro Sinus Scroller - W.P. van Paassen - 2002\n");
      return -1;
    }

  if (!TDEC_set_video(SCREEN_WIDTH, SCREEN_HEIGHT, 8, SDL_HWSURFACE | SDL_HWACCEL | SDL_HWPALETTE /*| SDL_FULLSCREEN*/))
   quit(1);

  TDEC_init_timer();

  SDL_WM_SetCaption("Retro - Sinus Scroller - ", "");
  
  init();

  SDL_SetColorKey(screen, SDL_SRCCOLORKEY, SDL_MapRGB(screen->format, 0xFF, 0xFF, 0xFF));

  TDEC_set_fps(50);

  /* time based demo loop */
  while( 1 ) 
    {
      TDEC_new_time();

      process_events();

      /* scroll scroll_surface to the left */

      SDL_BlitSurface(scroll_surface, &srect, scroll_surface, 0);
      displacement += 2;
      
      /* print character? */
      if (displacement > 12)
	{
	  print_character();
	  displacement = 0;
	}
      
      /* scroll copper bars up */
      
      temp = *(Uint32*)copper_surface->pixels;
      SDL_BlitSurface(copper_surface, &crect1, copper_surface, &crect2);
      SDL_FillRect(copper_surface, &crect3, temp);
      
      /* clean sinus area */
      
      SDL_FillRect(screen, &frect, 0);
      
      /* create sinus in scroll */
      
      for (i = 0; i < SCREEN_WIDTH; ++i)
	{
	  srect2.x = CHARACTER_WIDTH + i;
	  drect.x = i;
	  drect.y = aSin[(j + i) % 360];
	  SDL_BlitSurface(scroll_surface, &srect2, screen, &drect);
	}
      j += 6;
      j %= 360;
      
      /* blend copper and sinus scroll*/
        
      SDL_BlitSurface(copper_surface, 0, copy_surface, 0);
      SDL_BlitSurface(screen, &frect, copy_surface, 0);
      SDL_BlitSurface(copy_surface, 0, screen, &frect);
      
      if (TDEC_fps_ok())
	SDL_Flip(screen);
    }
  
  return 0; /* never reached */
}





