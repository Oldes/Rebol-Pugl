//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Entry points, the Pugl world and the device which pumps it.
//
//   REB_EXT defined ... standalone pugl-x64.rebx
//   REB_EXT absent .... compiled into the host
//
// One-time setup lives in Pugl_Init(), called from the generated `_init`
// command when the module body evaluates.
//

#include "gen-pugl.h"
#include "rebol-pugl.h"

#ifdef REB_EXT
RL_LIB *RL;
#endif

static char *init_block = PUGL_EXT_INIT_CODE;

// Note: the handle type is PUGL-WINDOW, so its callbacks are PuglWindow_*.
// That is a different identifier from Pugl's own `PuglView` typedef.
REBCNT Handle_PuglWindow = 0;

// One world for the whole process - every view belongs to it.
PuglWorld *Pugl_World = NULL;
REBCNT     Pugl_Windows = 0;


/***********************************************************************
**  The Pugl device.
**
**  RDO_AUTO_POLL makes the host call Poll_Pugl() from OS_Wait, so one
**  Pugl main loop iteration runs while the interpreter sits in WAIT.
**
**  No port and no doorbell event yet: `do-events` waits with a timeout
**  and drains the queue after it.
***********************************************************************/

int Pugl_Dev_Id = 0; // 0 = not registered

static DEVICE_CMD Init_Pugl(REBREQ *dr) {
	REBDEV *dev = (REBDEV*)dr;
	SET_FLAG(dev->flags, RDF_INIT);
	return DR_DONE;
}

static DEVICE_CMD Quit_Pugl(REBREQ *dr) {
	return DR_DONE;
}

// ALWAYS DR_DONE - the request is a stack temporary lent by
// OS_Poll_Devices; DR_PEND would link it into the pending list.
// See the note on Poll_Gui in Rebol-GUI.
static DEVICE_CMD Poll_Pugl(REBREQ *dr) {
	// Nothing to pump with no view open.
	if (Pugl_Windows == 0 || !Pugl_World) return DR_DONE;
	puglUpdate(Pugl_World, 0.0); // never blocks
	return DR_DONE;
}

static DEVICE_CMD_FUNC Pugl_Dev_Cmds[RDC_MAX] = {
	Init_Pugl,
	Quit_Pugl,
	0,       // RDC_OPEN
	0,       // RDC_CLOSE
	0,       // RDC_READ
	0,       // RDC_WRITE
	Poll_Pugl,
	0,       // RDC_CONNECT
	0,       // RDC_QUERY
};

DEFINE_DEV(Dev_Pugl, "Rebol Pugl device", 1, Pugl_Dev_Cmds, RDC_MAX, 0);


// Returns plain TRUE/FALSE, NOT an RXR_* code.
int Pugl_Init(void) {
	REBHSP spec;

	spec.size     = sizeof(PUGLWIN);
	spec.flags    = HANDLE_REQUIRES_HOB_ON_FREE;
	spec.free     = PuglWindow_free;
	spec.get_path = PuglWindow_get_path;
	spec.set_path = PuglWindow_set_path;
	spec.mold     = PuglWindow_mold;

	Handle_PuglWindow = RL_REGISTER_HANDLE_SPEC(cb_cast("PUGL-WINDOW"), &spec);
	if (Handle_PuglWindow == 0) return FALSE;

	if (!Pugl_World) {
		// PUGL_PROGRAM: we are the application - on macOS this sets up
		// the NSApplication, on Windows the DPI awareness.
		Pugl_World = puglNewWorld(PUGL_PROGRAM, 0);
		if (!Pugl_World) return FALSE;
		puglSetWorldString(Pugl_World, PUGL_CLASS_NAME, "RebolPugl");
	}

	// Last: the first poll may come as soon as the interpreter waits.
	SET_FLAG(Dev_Pugl.flags, RDO_AUTO_POLL);
	Pugl_Dev_Id = RL_REGISTER_DEVICE(&Dev_Pugl, sizeof(REBDEV));

	return TRUE;
}

// Views must go before the world they belong to.
void Pugl_Quit(void) {
	Pugl_Close_All_Windows();
	Pugl_Purge_Events(NULL);
	if (Pugl_World) {
		puglFreeWorld(Pugl_World);
		Pugl_World = NULL;
	}
}


#ifdef REB_EXT

/***********************************************************************
**  Standalone extension library
***********************************************************************/

RXIEXT const char *RX_Init(int opts, RL_LIB *lib) {
	REBYTE ver[8];
	RL = lib;
	RL_VERSION(ver);

	if (MIN_REBOL_VERSION > VERSION(ver[1], ver[2], ver[3])) return 0;
	if (!CHECK_STRUCT_ALIGN) {
		trace("CHECK_STRUCT_ALIGN failed!");
		return 0;
	}
	return init_block;
}

RXIEXT int RX_Quit(int opts) {
	Pugl_Quit();
	return 0;
}

RXIEXT int RX_Abi(void) {
	return RL_ABI_VERSION;
}

RXIEXT int RX_Call(int cmd, RXIFRM *frm, void *ctx) {
	return Pugl_RX_Call(cmd, frm, ctx);
}

#endif
