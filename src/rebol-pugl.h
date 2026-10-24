//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Private declarations shared by the extension's sources.
//
// Named rebol-pugl.h, not pugl.h, so it can never be mistaken for
// <pugl/pugl.h>.
//

#ifndef REBOL_PUGL_H
#define REBOL_PUGL_H

#include <pugl/pugl.h>
#include "pugl-icon.h"

// pugl.c
extern PuglWorld *Pugl_World;
extern REBCNT     Pugl_Windows;          // views realized and not yet closed
void Pugl_Quit(void);

// pugl-events.c
//
// A queued event is a plain copy of Pugl's own, tagged with the view it
// came from. Conversion to event! happens in `poll-events`, on the
// interpreter's side - the producer must not allocate Rebol series.
typedef struct Pugl_Queued_Event {
	PUGLWIN  *ctx;
	PuglEvent event;
} PUGLQEVT;

extern REBCNT Pugl_Dropped_Events;     // events lost to a full queue

PuglStatus Pugl_On_Event(PuglView *view, const PuglEvent *event);
REBCNT     Pugl_Event_Count(void);
REBOOL     Pugl_Take_Event(PUGLQEVT *out);
void       Pugl_Purge_Events(PUGLWIN *ctx); // NULL purges everything

// pugl-draw.c - everything which touches OpenGL, so that no other source
// needs the GL headers (nor, on Windows, windows.h).
PuglStatus Pugl_Setup_Backend(PuglView *view);
void       Pugl_Draw(PUGLWIN *pv, PuglView *view);

// pugl-commands.c
void Pugl_Close_All_Windows(void);

// Handle callbacks, named after the HANDLE TYPE (PUGL-WINDOW, PUGL-IMAGE).
// PuglWindow_* is a different identifier from Pugl's own `PuglView`.
// PUGL-GROUP shares the PuglImage_* ones: the context says which it is.
int PuglWindow_free(void *hndl);
int PuglWindow_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglWindow_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglWindow_mold(REBHOB *hob, REBSER *str);

int PuglImage_free(void *hndl);
int PuglImage_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglImage_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglImage_mold(REBHOB *hob, REBSER *str);

#endif
