#ifndef LWMF_DOUBLEBUFFER_H
#define LWMF_DOUBLEBUFFER_H

void lwmf_DoubleBuffering(void(*CallFunction)(), const int FPSLimit);

void lwmf_DoubleBuffering(void(*CallFunction)(), const int FPSLimit)
{
    struct ScreenBuffer* Buffer[2] = { AllocScreenBuffer(Screen, NULL, SB_SCREEN_BITMAP), AllocScreenBuffer(Screen, NULL, SB_COPY_BITMAP) };

    if (Buffer[0] && Buffer[1])
    {
		volatile struct CIA *ciaa = (struct CIA *)0xBFE001;

		// Start timer
		struct timerequest TickRequest = *TimerIO;
		TickRequest.tr_node.io_Command = TR_ADDREQUEST;
		TickRequest.tr_time.tv_secs = 0;
		TickRequest.tr_time.tv_micro = 0;
		SendIO((struct IORequest*)&TickRequest);
	
		// Loop control
        int CurrentBuffer = 0;

        // Loop until mouse button is pressed...
		while (ciaa->ciapra & CIAF_GAMEPORT0)
        {
			RenderPort.BitMap = Buffer[CurrentBuffer]->sb_BitMap;
			
			//***************************************************************
			// Here we call the drawing function for demo stuff!            *
			//***************************************************************

			(*CallFunction)();

			// DisplayStatistics() writes on the backbuffer, too - so we need to call it before blitting
			lwmf_DisplayStatistics(RenderPort, 1, 5, 10);

			//***************************************************************
			// Ends here ;-)                                                *
			//***************************************************************

			lwmf_WaitBlit();
			ChangeScreenBuffer(Screen, Buffer[CurrentBuffer]);
			lwmf_WaitVBeam(240);
			CurrentBuffer ^= 1;
			lwmf_FPSCounter();

			if (Wait(1 << TimerPort->mp_SigBit) & (1 << TimerPort->mp_SigBit))
			{
				WaitIO((struct IORequest*)&TickRequest);
				TickRequest.tr_time.tv_secs = 0;
				TickRequest.tr_time.tv_micro = FPSLimit;
				SendIO((struct IORequest*)&TickRequest);
			}

        }

        // After breaking the loop, we have to make sure that there are no more TickRequests to process
		AbortIO((struct IORequest*)&TickRequest);

	    FreeScreenBuffer(Screen, Buffer[0]);
		Buffer[0] = NULL;
		FreeScreenBuffer(Screen, Buffer[1]);
		Buffer[1] = NULL;
    }
}


#endif /* LWMF_DOUBLEBUFFER_H */