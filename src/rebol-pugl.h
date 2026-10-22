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
#include <pugl/stub.h>

// pugl.c
extern PuglWorld *Pugl_World;
extern REBCNT     Pugl_Views;          // views realized and not yet closed
void Pugl_Quit(void);

// pugl-events.c
//
// A queued event is a plain copy of Pugl's own, tagged with the view it
// came from. Conversion to event! happens in `poll-events`, on the
// interpreter's side - the producer must not allocate Rebol series.
typedef struct Pugl_Queued_Event {
	PUGLVIEWCTX *ctx;
	PuglEvent    event;
} PUGLQEVT;

extern REBCNT Pugl_Dropped_Events;     // events lost to a full queue

PuglStatus Pugl_On_Event(PuglView *view, const PuglEvent *event);
REBCNT     Pugl_Event_Count(void);
REBOOL     Pugl_Take_Event(PUGLQEVT *out);
void       Pugl_Purge_Events(PUGLVIEWCTX *ctx); // NULL purges everything

// pugl-commands.c
void Pugl_Close_All_Views(void);

// View handle callbacks. Named after the HANDLE TYPE (PUGL-VIEW); that is
// a different identifier from Pugl's own `PuglView` typedef.
int PuglView_free(void *hndl);
int PuglView_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglView_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg);
int PuglView_mold(REBHOB *hob, REBSER *str);

#endif
