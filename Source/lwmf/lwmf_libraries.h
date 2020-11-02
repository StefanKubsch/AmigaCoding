#ifndef LWMF_LIBRARIRIES_H
#define LWMF_LIBRARIRIES_H

#include <exec/exec.h>
#include <exec/types.h>
#include <graphics/copper.h>
#include <graphics/rastport.h>
#include <intuition/intuition.h>
#include <datatypes/pictureclass.h>
#include <devices/timer.h>
#include <clib/timer_protos.h>  
#include <clib/exec_protos.h>
#include <clib/dos_protos.h>
#include <clib/graphics_protos.h>
#include <clib/intuition_protos.h>
#include <clib/alib_protos.h>
#include <clib/datatypes_protos.h>

//
// Global symbols for our assembler functions
//

void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);
void lwmf_WaitVertBlank(void);
void lwmf_WaitBlitter(void);
void lwmf_ClearMem(__reg("a0") long* Address, __reg("d0") long NumberOfBytes);
__reg("d0") ULONG lwmf_Random(void);

//
// External variables as defined in asm sources
//

extern long GfxBase;

//
//
//

BOOL lwmf_LoadLibraries(void);
void lwmf_CloseLibraries(void);

struct IntuitionBase* IntuitionBase = NULL;
struct Library* DataTypesBase = NULL;

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

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

    if (!(IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 39)))
    {
        lwmf_CloseLibraries();
        return FALSE;
    }

	if (!(DataTypesBase = (struct Library*)OpenLibrary("datatypes.library", 39)))
    {
   		lwmf_CloseLibraries();
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

	if (DataTypesBase)
	{
		CloseLibrary(DataTypesBase);
		DataTypesBase = NULL;
	}

    if (IntuitionBase)
    {
        CloseLibrary((struct Library*)IntuitionBase);
		IntuitionBase = NULL;
    }
	
}


#endif /* LWMF_LIBRARIRIES_H */