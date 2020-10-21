#ifndef LWMF_OS_H
#define LWMF_OS_H

// Some stuff needed for OS takeover
struct View* OldView = NULL;
struct copinit* OldCopperInit = NULL;

void lwmf_TakeOverOS(void);
void lwmf_ReleaseOS(void);

void lwmf_TakeOverOS(void)
{
	// Set task priority
	SetTaskPri(FindTask(NULL), 20);

	// Disable task rescheduling
	Forbid();

	// Save current view
	OldView = GfxBase->ActiView;
	// Save current copperlist
	OldCopperInit = GfxBase->copinit;
	
    // Reset view (clear anything)
	LoadView(NULL);

    WaitTOF();
    WaitTOF();

	// Disable interrupts
	Disable();
}

void lwmf_ReleaseOS(void)
{
	// Enable interrupts
	Enable();
	
	// Restore previously saved copperlist
	custom->cop1lc = (ULONG)OldCopperInit;
	OldCopperInit = NULL;

	// Restore previously saved vire
	LoadView(OldView);
	OldView = NULL;

	WaitTOF();
	WaitTOF();

	// Enable task rescheduling
	Permit();
}


#endif /* LWMF_OS_H */