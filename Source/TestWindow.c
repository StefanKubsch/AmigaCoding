#include <exec/exec.h>
#include <dos/dos.h>
#include <intuition/intuition.h>
#include <clib/exec_protos.h>
#include <clib/intuition_protos.h>
#include <stdlib.h>

/* our system libraries addresses */
struct GfxBase* GfxBase = 0;
struct IntuitionBase* IntuitionBase = 0;

struct RenderEngineData
{
	struct Window* window;
	BOOL run;
};

void DispatchWindowMessage(struct RenderEngineData* rd, struct IntuiMessage* msg)
{
	switch(msg->Class)
	{
		case IDCMP_CLOSEWINDOW:
		{
			/* User pressed the window's close gadget: exit the main loop as
			 * soon as possible */
			rd->run = FALSE;
			break;
		}
		case IDCMP_REFRESHWINDOW:
		{
			BeginRefresh(rd->window);
			EndRefresh(rd->window, TRUE);
			break;
		}
	}
}

int MainLoop(struct RenderEngineData* rd)
{
	struct MsgPort* winport;
	ULONG winSig;

	/* remember the window port in a local variable for more easy use */
	winport = rd->window->UserPort;

	/* create our waitmask for the window port */
	winSig = 1 << winport->mp_SigBit;

	/* our main loop */
	while(rd->run)
	{
		struct Message* msg;

		/* let's sleep until a message from our window arrives */
		Wait(winSig);

		/* our window signaled us, so let's harvest all its messages
		 * in a loop... */
		while((msg = GetMsg(winport)))
		{
			/* ...and dispatch and reply each of them */
			DispatchWindowMessage(rd, (struct IntuiMessage*)msg);
			ReplyMsg(msg);
		}
	}

	return RETURN_OK;
}

int RunEngine(void)
{
	struct RenderEngineData* rd;

	/* as long we did not enter our main loop we report an error */
	int result = RETURN_ERROR;

	/* allocate the memory for our runtime data and ititialize it
	 * with zeros */
	if ((rd = (struct RenderEngineData*)AllocMem(sizeof(struct RenderEngineData), MEMF_ANY | MEMF_CLEAR)))
	{
		/* now let's open our window */
		static struct NewWindow newWindow =
		{
			0, 14,
			320, 160,
			(UBYTE)~0, (UBYTE)~0,
			IDCMP_CLOSEWINDOW | IDCMP_NEWSIZE | IDCMP_REFRESHWINDOW,
			WFLG_CLOSEGADGET | WFLG_DRAGBAR | WFLG_DEPTHGADGET |
			WFLG_SIMPLE_REFRESH | WFLG_SIZEBBOTTOM | WFLG_SIZEGADGET,
			0, 0,
			"This is a test window!",
			0,
			0,
			96, 48,
			(UWORD)~0, (UWORD)~0,
			WBENCHSCREEN
		};

		if ((rd->window = OpenWindow(&newWindow)))
		{
			/* the main loop will run as long this is TRUE */
			rd->run = TRUE;

			result = MainLoop(rd);

			/* cleanup: close the window */
			CloseWindow(rd->window);
			rd->window = 0;
		}

		/* free our runtime data */
		FreeMem(rd, sizeof(struct RenderEngineData));
		rd = 0;
	}

	return result;
}

int main(int argc, char* argv[])
{
	/* as long we did not execute RunEngine() we report a failure */
	int result = RETURN_FAIL;

	/* we need at least 1.2 graphic.library's drawing functions */
	if ((GfxBase = (struct GfxBase*)OpenLibrary("graphics.library", 33)))
	{
		/* we need at least 1.2 intuition.library for our window */
		if ((IntuitionBase = (struct IntuitionBase*)OpenLibrary("intuition.library", 33)))
		{
			/* All libraries needed are available, so let's run... */
			result = RunEngine();

			CloseLibrary((struct Library*)IntuitionBase);
			IntuitionBase = 0;
		}

		CloseLibrary((struct Library*)GfxBase);
		GfxBase = 0;
	}

	/* some startup codes do ignore main's return value, that's
	 * why we use exit() here instead of a simple return */
	exit(result);
}
