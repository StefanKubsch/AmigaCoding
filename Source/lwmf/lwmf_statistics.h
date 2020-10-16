#ifndef LWMF_STATISTICS_H
#define LWMF_STATISTICS_H

// Some global variables for our statistics...
WORD FPS = 0;
BOOL FastCPUFlag = FALSE;
char* CPUText = NULL;
int CPUTextLength = 0;

void lwmf_FPSCounter(void);
void lwmf_DisplayStatistics(struct RastPort RPort, const int Color, const int PosX, const int PosY);
void lwmf_CheckCPU(void);

void lwmf_FPSCounter(void)
{
	// Get system time
	static struct timeval tt;
	struct timeval a;
	struct timeval b;

	GetSysTime(&a);
	b = a;
	SubTime(&b, &tt);
	tt = a;

	const ULONG SystemTime = b.tv_secs * 1000 + b.tv_micro / 1000;
	
	// Calculate fps
	static WORD FPSFrames = 0;
	static ULONG FPSUpdate = 0;

	FPSUpdate += SystemTime;

	if (FPSUpdate >= 1000)
	{
		FPS = FPSFrames;
		FPSFrames = 0;
		FPSUpdate = SystemTime;
	}

	++FPSFrames;
}

void lwmf_DisplayStatistics(struct RastPort RPort, const int Color, const int PosX, const int PosY)
{
	UBYTE FPSStr[10];
	sprintf(FPSStr, "%d fps", FPS);
								
	SetAPen(&RPort, Color);
	Move(&RPort, PosX, PosY);
	Text(&RPort, FPSStr, strlen(FPSStr));

	Move(&RPort, PosX, PosY + 10);
	Text(&RPort, CPUText, CPUTextLength);
}

void lwmf_CheckCPU(void)
{
	struct ExecBase *SysBase = *((struct ExecBase**)4L);

	// Check if CPU is a 68020, 030, 040, 060 (this is the "0x80")
	// If yes, we can calculate more stuff...
	if (SysBase->AttnFlags & AFF_68020 || SysBase->AttnFlags & AFF_68030 || SysBase->AttnFlags & AFF_68040 || SysBase->AttnFlags & 0x80)
	{
		FastCPUFlag = TRUE;
		CPUText = "CPU:68020 or higher";
	}
	else
	{
		CPUText = "CPU:68000 or 68010";
	}

	CPUTextLength = strlen(CPUText);
}


#endif /* LWMF_STATISTICS_H */