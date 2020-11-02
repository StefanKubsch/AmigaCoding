#ifndef LWMF_TIMER_H
#define LWMF_TIMER_H

BOOL lwmf_InitTimer(void);
void lwmf_CleanupTimer(void);

struct Library* TimerBase = NULL;
struct MsgPort* TimerPort = NULL;
struct timerequest* TimerIO = NULL;

BOOL lwmf_InitTimer(void)
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
				lwmf_CleanupTimer();
				return FALSE;
			}
		}
		else
		{
			lwmf_CleanupTimer();
			return FALSE;
		}
	}
	else
	{
		lwmf_CleanupTimer();
		return FALSE;
	}

    return TRUE;
}

void lwmf_CleanupTimer(void)
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
}


#endif /* LWMF_TIMER_H */