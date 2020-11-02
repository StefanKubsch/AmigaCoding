#ifndef LWMF_LIBRARIRIES_H
#define LWMF_LIBRARIRIES_H

#include <exec/exec.h>
#include <exec/types.h>
#include <graphics/copper.h>
#include <graphics/rastport.h>
#include <datatypes/pictureclass.h>
#include <devices/timer.h>
#include <clib/timer_protos.h>  
#include <clib/exec_protos.h>
#include <clib/dos_protos.h>
#include <clib/graphics_protos.h>
#include <clib/alib_protos.h>
#include <clib/datatypes_protos.h>

//
// Global symbols for our assembler functions
//

__reg("d0") ULONG lwmf_LoadGraphicsLibrary(void);
__reg("d0") ULONG lwmf_LoadIntuitionLibrary(void);
__reg("d0") ULONG lwmf_LoadDatatypesLibrary(void);
void lwmf_CloseLibraries();
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
extern long IntuitionBase;
extern long DataTypesBase;

//
//
//

BOOL lwmf_LoadLibraries(void);
void lwmf_CloseLibs(void);

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

	if (lwmf_LoadGraphicsLibrary() != 0)
	{
		return FALSE;
	}

	if (lwmf_LoadIntuitionLibrary() != 0)
	{
		return FALSE;
	}

	if (lwmf_LoadDatatypesLibrary() != 0)
	{
		return FALSE;
	}

    return TRUE;
}

void lwmf_CloseLibs(void)
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

    lwmf_CloseLibraries();
}


#endif /* LWMF_LIBRARIRIES_H */