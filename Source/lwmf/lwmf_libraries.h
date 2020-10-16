#ifndef LWMF_LIBRARIRIES_H
#define LWMF_LIBRARIRIES_H

#include <exec/exec.h>
#include <graphics/gfxbase.h>
#include <graphics/copper.h>
#include <graphics/gfxmacros.h>
#include <graphics/rastport.h>
#include <graphics/text.h>
#include <intuition/intuition.h>
#include <hardware/intbits.h>
#include <hardware/custom.h>
#include <hardware/cia.h>
#include <devices/timer.h>
#include <clib/timer_protos.h>  
#include <clib/exec_protos.h>
#include <clib/graphics_protos.h>
#include <clib/intuition_protos.h>
#include <clib/diskfont_protos.h>
#include <clib/alib_protos.h>
#include <diskfont/diskfont.h>

#include <math.h>
#include <stdio.h>
#include <string.h>

struct GfxBase* GfxBase = NULL;
struct IntuitionBase* IntuitionBase = NULL;
struct DiskFontBase* DiskfontBase = NULL;

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

struct Custom* custom = NULL;

BOOL lwmf_LoadLibraries(void);
void lwmf_CloseLibraries(void);

BOOL lwmf_LoadLibraries(void)
{
	if (TimerPort = CreatePort(0, 0))
	{
		if (TimerIO = (struct timerequest*)CreateExtIO(TimerPort, sizeof(struct timerequest)))
		{
			if (OpenDevice(TIMERNAME, UNIT_MICROHZ, (struct IORequest*)TimerIO, 0) == 0)
			{
				TimerBase = (struct Library*)TimerIO->tr_node.io_Device;
			}
			else
			{
		   		lwmf_CloseLibraries();
				return FALSE;
			}
		}
		else
		{
	   		lwmf_CloseLibraries();
			return FALSE;
		}
	}
	else
	{
   		lwmf_CloseLibraries();
		return FALSE;
	}
	
	//
	// Since we use functions that require at least OS 3.0, we must use "39" as minimum library version!
    //

	if (!(GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 39)))
    {
   		lwmf_CloseLibraries();
    }

    if (!(IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 39)))
    {
        lwmf_CloseLibraries();
        return FALSE;
    }

	if (!(DiskfontBase = (struct DiskFontBase*)OpenLibrary("diskfont.library", 39)))
	{
        lwmf_CloseLibraries();
        return FALSE;
	}
    return TRUE;
}

void lwmf_CloseLibraries(void)
{
    if (TimerBase)
	{
		CloseDevice((struct IORequest*)TimerIO);
		TimerBase = NULL;
	}

	if (TimerIO)
	{
		DeleteExtIO((struct IORequest*)TimerIO);
		TimerIO = NULL;
	}

	if (TimerPort)
	{
		DeletePort(TimerPort);
		TimerPort = NULL;
	}

	if (DiskfontBase)
    {
       CloseLibrary((struct Library*)DiskfontBase);
	   DiskfontBase = NULL;
    }     

    if (IntuitionBase)
    {
        CloseLibrary((struct Library*)IntuitionBase);
		IntuitionBase = NULL;
    }
	
    if (GfxBase)
    {
       CloseLibrary((struct Library*)GfxBase);
	   GfxBase = NULL;
    }     
}


#endif /* LWMF_LIBRARIRIES_H */