//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The event queue between Pugl's event callback and `poll-events`.
//
// Plain C memory: the callback runs inside puglUpdate(), which may be
// called from the device poll, so it must not allocate Rebol series.
// Events are kept as copies of Pugl's own and converted later.
//

#include "gen-pugl.h"
#include "rebol-pugl.h"

#define PUGL_QUEUE_SIZE 256                  // must be a power of two
#define PUGL_QUEUE_MASK (PUGL_QUEUE_SIZE - 1)

static PUGLQEVT Queue[PUGL_QUEUE_SIZE];
static REBCNT   Q_Head = 0;  // next to read  (free-running, masked on use)
static REBCNT   Q_Tail = 0;  // next to write

REBCNT Pugl_Dropped_Events = 0;

REBCNT Pugl_Event_Count(void) {
	return Q_Tail - Q_Head; // unsigned wrap keeps this right
}

// The most recently queued event, if any.
static PUGLQEVT *Last_Event(void) {
	if (Q_Tail == Q_Head) return NULL;
	return &Queue[(Q_Tail - 1) & PUGL_QUEUE_MASK];
}

// Callback set on every view with puglSetEventFunc().
PuglStatus Pugl_On_Event(PuglView *view, const PuglEvent *event) {
	PUGLVIEWCTX *ctx = (PUGLVIEWCTX*)puglGetHandle(view);
	PUGLQEVT    *last;

	if (!ctx) return PUGL_SUCCESS;

	switch (event->type) {
	case PUGL_MOTION:
	case PUGL_CONFIGURE:
		// Consecutive moves (or resizes) of the same view collapse into
		// the latest one. Only when nothing came in between, so the order
		// of events is never changed.
		last = Last_Event();
		if (last && last->ctx == ctx && last->event.type == event->type) {
			last->event = *event;
			return PUGL_SUCCESS;
		}
		break;

	case PUGL_CLOSE:
	case PUGL_FOCUS_IN:
	case PUGL_FOCUS_OUT:
	case PUGL_KEY_PRESS:
	case PUGL_KEY_RELEASE:
	case PUGL_TEXT:
	case PUGL_POINTER_IN:
	case PUGL_POINTER_OUT:
	case PUGL_BUTTON_PRESS:
	case PUGL_BUTTON_RELEASE:
	case PUGL_SCROLL:
		break;

	default:
		// Realize, expose, update, timers, clipboard... nothing the stub
		// backend has to report yet.
		return PUGL_SUCCESS;
	}

	if (Q_Tail - Q_Head >= PUGL_QUEUE_SIZE) {
		Pugl_Dropped_Events++;
		return PUGL_SUCCESS;
	}
	Queue[Q_Tail & PUGL_QUEUE_MASK].ctx   = ctx;
	Queue[Q_Tail & PUGL_QUEUE_MASK].event = *event;
	Q_Tail++;
	return PUGL_SUCCESS;
}

REBOOL Pugl_Take_Event(PUGLQEVT *out) {
	if (Q_Tail == Q_Head) return FALSE;
	*out = Queue[Q_Head & PUGL_QUEUE_MASK];
	Q_Head++;
	return TRUE;
}

// Drops the events of one view (it is going away), or all of them.
void Pugl_Purge_Events(PUGLVIEWCTX *ctx) {
	REBCNT r, w;

	if (!ctx) {
		Q_Head = Q_Tail = 0;
		return;
	}
	w = Q_Head;
	for (r = Q_Head; r != Q_Tail; r++) {
		PUGLQEVT *e = &Queue[r & PUGL_QUEUE_MASK];
		if (e->ctx == ctx) continue;
		if (w != r) Queue[w & PUGL_QUEUE_MASK] = *e;
		w++;
	}
	Q_Tail = w;
}
