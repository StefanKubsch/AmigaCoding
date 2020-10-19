#ifndef LWMF_DOUBLEBUFFER_H
#define LWMF_DOUBLEBUFFER_H

BOOL lwmf_DoubleBuffering(void(*CallFunction)(), const int FPSLimit, const BOOL DisplayFPS);

BOOL lwmf_DoubleBuffering(void(*CallFunction)(), const int FPSLimit, const BOOL DisplayFPS)
{
    struct ScreenBuffer* Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };

    if (!Buffer[0] || !Buffer[1])
    {
		lwmf_CleanupAll();
		return FALSE;
	}

	// Use odd CIA (CIA-A) for check if mouse button is pressed
	// https://www.amigacoding.com/index.php/CIA_Memory_Map
	// Use Port Register 1 0xBFE001
	volatile UBYTE* CIAA_PRA = (volatile UBYTE *) 0xBFE001;
	// Set bit 6 (Port 0 fire button)
	const LONG PRA_FIR0 = 1L << 6;
	
	// Start timer
	struct timerequest TickRequest = *TimerIO;
	TickRequest.tr_node.io_Command = TR_ADDREQUEST;
	TickRequest.tr_time.tv_secs = 0;
	TickRequest.tr_time.tv_micro = 0;
	SendIO((struct IORequest*)&TickRequest);

	// Loop control
	int CurrentBuffer = 0;

	// Loop until mouse button is pressed...
	while (*CIAA_PRA & PRA_FIR0)
	{
		RenderPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
		
		//***************************************************************
		// Here we call the drawing function for demo stuff!            *
		//***************************************************************

		(*CallFunction)();

		// lwmf_DisplayFPSCounter() writes on the backbuffer, too - so we need to call it before blitting
		if (DisplayFPS)
		{
			lwmf_DisplayFPSCounter(5, 10, 1);
		}

		//***************************************************************
		// Ends here ;-)                                                *
		//***************************************************************

		lwmf_WaitBlit();
		ChangeScreenBuffer(Screen, Buffer[CurrentBuffer]);
		CurrentBuffer ^= 1;
		lwmf_FPSCounter();

		if (Wait(1L << TimerPort->mp_SigBit) & (1L << TimerPort->mp_SigBit))
		{
			WaitIO((struct IORequest*)&TickRequest);
			TickRequest.tr_time.tv_secs = 0;
			TickRequest.tr_time.tv_micro = FPSLimit;
			SendIO((struct IORequest*)&TickRequest);
		}

		lwmf_WaitVBeam(255);
	}

	// After breaking the loop, we have to make sure that there are no more TickRequests to process
	AbortIO((struct IORequest*)&TickRequest);

	if (Buffer[0])
	{
		lwmf_WaitBlit();
		FreeScreenBuffer(Screen, Buffer[0]);
		Buffer[0] = NULL;
	}

	if (Buffer[1])
	{
		lwmf_WaitBlit();
		FreeScreenBuffer(Screen, Buffer[1]);
		Buffer[1] = NULL;
	}

	return TRUE;
}


#endif /* LWMF_DOUBLEBUFFER_H */