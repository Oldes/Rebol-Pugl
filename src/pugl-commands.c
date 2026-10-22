//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Command implementations and the view handle callbacks.
//
// The enum, the declarations, the dispatch table and the `_init` handler
// are all generated from pugl.reb.
//

#include "gen-pugl.h"
#include "rebol-pugl.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h> // MAKE_MEM / FREE_MEM

static const REBYTE* ERR_INVALID_HANDLE = (const REBYTE*)"Invalid Pugl view handle!";
static const REBYTE* ERR_NO_HANDLE      = (const REBYTE*)"Failed to create the view handle!";
static const REBYTE* ERR_NO_VIEW        = (const REBYTE*)"Failed to create the view!";
static const REBYTE* ERR_NO_WORLD       = (const REBYTE*)"Pugl world is not initialized!";
static const REBYTE* ERR_BAD_SIZE       = (const REBYTE*)"Size must be between 1x1 and 10000x10000!";

// Every open view, so they can all go before the world does.
static PUGLVIEWCTX *Views_Head = NULL;


//== helpers ==================================================================

// Validates argument `n` as a view handle (open or closed).
static PUGLVIEWCTX* Frm_View(RXIFRM *frm, REBCNT n)
{
	REBHOB *hob;
	if (!FRM_IS_HANDLE(n, Handle_PuglView)) return NULL;
	hob = RXA_HANDLE_CONTEXT(frm, n);
	if (!hob || !IS_USED_HOB(hob) || !hob->data) return NULL;
	return (PUGLVIEWCTX*)hob->data;
}

// Pugl wants a NUL-terminated string, which RL_GET_UTF8_STRING does not
// promise - so the title is copied. Pugl copies it again on its side.
static REBOOL Set_View_Title(PuglView *view, REBSER *ser, REBCNT index)
{
	REBYTE *utf8 = NULL;
	char   *buf;
	int     len = RL_GET_UTF8_STRING(ser, index, (void**)&utf8);

	if (len < 0) return FALSE;
	buf = (char*)MAKE_MEM((REBCNT)len + 1);
	if (!buf) return FALSE;
	if (len > 0) COPY_MEM(buf, utf8, len);
	buf[len] = 0;
	puglSetViewString(view, PUGL_WINDOW_TITLE, buf);
	FREE_MEM(buf);
	return TRUE;
}

static void Remember_Frame(PUGLVIEWCTX *pv)
{
	PuglView *view = (PuglView*)pv->view;
	PuglPoint p = puglGetPositionHint(view, PUGL_CURRENT_POSITION);
	PuglArea  a = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
	pv->x = p.x; pv->y = p.y;
	pv->w = a.width; pv->h = a.height;
}

/***********************************************************************
**  Destroys the native view; the handle stays and reports `open?` false.
**
**  The Pugl handle is cleared FIRST, so whatever puglFreeView() still
**  dispatches (unrealize, focus-out...) finds no context and is not
**  queued. Then the queued events of this view go, and the GC lock an
**  open view holds on its handle is dropped.
***********************************************************************/
static void Close_View(PUGLVIEWCTX *pv)
{
	PuglView     *view = (PuglView*)pv->view;
	PUGLVIEWCTX **link;

	if (!view) return;

	pv->view = NULL;
	puglSetHandle(view, NULL);
	puglFreeView(view);

	for (link = &Views_Head; *link; link = (PUGLVIEWCTX**)&(*link)->next) {
		if (*link == pv) { *link = (PUGLVIEWCTX*)pv->next; break; }
	}
	pv->next = NULL;
	if (Pugl_Views > 0) Pugl_Views--;

	Pugl_Purge_Events(pv);
	if (pv->hob) pv->hob->flags &= ~HANDLE_CONTEXT_LOCKED;
}

void Pugl_Close_All_Views(void)
{
	while (Views_Head) Close_View(Views_Head);
}

static REBYTE Modifier_Bits(PuglMods mods)
{
	REBYTE bits = 0;
	if (mods & PUGL_MOD_SHIFT) bits |= (1 << EVF_SHIFT);
	if (mods & PUGL_MOD_CTRL)  bits |= (1 << EVF_CONTROL);
	if (mods & PUGL_MOD_ALT)   bits |= (1 << EVF_ALT);
	return bits;
}

// Appends one event! to the block.
static void Append_Event(REBSER *blk, REBCNT *at, PUGLVIEWCTX *pv,
                         REBCNT type, REBYTE flags, u32 data)
{
	REBEVT ev;
	RXIARG val;

	CLEARS(&ev);
	ev.type  = (u8)type;
	ev.model = EVM_HANDLE;   // the source is our handle, and the GC marks it
	ev.hob   = pv->hob;
	ev.flags = flags;
	ev.data  = data;

	CLEARS(&val);
	COPY_MEM(&val, &ev, sizeof(ev));
	RL_SET_VALUE(blk, (*at)++, val, RXT_EVENT);
}

#define XY_DATA(x, y) ((((u32)((REBINT)(y) & 0xffff)) << 16) | ((u32)((REBINT)(x) & 0xffff)))
#define HAS_XY        (1 << EVF_HAS_XY)
#define HAS_CODE      (1 << EVF_HAS_CODE)

static const REBCNT Down_Types[3] = { EVT_DOWN, EVT_ALT_DOWN, EVT_AUX_DOWN };
static const REBCNT Up_Types[3]   = { EVT_UP,   EVT_ALT_UP,   EVT_AUX_UP   };

/***********************************************************************
**  One queued Pugl event into zero, one or two event! values.
**
**  Coordinates are Pugl's own - device pixels, view-relative.
***********************************************************************/
static void Convert_Event(REBSER *blk, REBCNT *at, PUGLQEVT *q)
{
	PUGLVIEWCTX     *pv = q->ctx;
	const PuglEvent *e  = &q->event;

	switch (e->type) {
	case PUGL_BUTTON_PRESS:
	case PUGL_BUTTON_RELEASE:
		// Primary, secondary, middle - nothing above is reported yet.
		if (e->button.button > 2) break;
		Append_Event(blk, at, pv,
			(e->type == PUGL_BUTTON_PRESS ? Down_Types : Up_Types)[e->button.button],
			HAS_XY | Modifier_Bits(e->button.state),
			XY_DATA(e->button.x, e->button.y));
		break;

	case PUGL_MOTION:
		Append_Event(blk, at, pv, EVT_MOVE,
			HAS_XY | Modifier_Bits(e->motion.state),
			XY_DATA(e->motion.x, e->motion.y));
		break;

	case PUGL_POINTER_IN:
	case PUGL_POINTER_OUT:
		Append_Event(blk, at, pv,
			e->type == PUGL_POINTER_IN ? EVT_ENTER : EVT_LEAVE,
			HAS_XY, XY_DATA(e->crossing.x, e->crossing.y));
		break;

	case PUGL_SCROLL: {
		// Vertical only, in whole lines, positive away from the user.
		// A smooth scroll smaller than a line is dropped for now.
		REBINT lines = (REBINT)(e->scroll.dy < 0 ? e->scroll.dy - 0.5 : e->scroll.dy + 0.5);
		if (lines == 0) break;
		Append_Event(blk, at, pv, EVT_SCROLL_LINE, HAS_CODE, (u32)lines);
		break; }

	case PUGL_KEY_PRESS:
	case PUGL_KEY_RELEASE:
		// Pugl's key is the UNSHIFTED codepoint. Keys without one (F1,
		// arrows...) live in the Private Use Area and need a mapping to
		// EVT_NAMED_KEY - not done yet, so they are skipped.
		if (e->key.key == 0 || (e->key.key >= 0xE000 && e->key.key <= 0xF8FF)) break;
		Append_Event(blk, at, pv,
			e->type == PUGL_KEY_PRESS ? EVT_KEY : EVT_KEY_UP,
			HAS_CODE | Modifier_Bits(e->key.state), (u32)e->key.key);
		break;

	case PUGL_FOCUS_IN:
	case PUGL_FOCUS_OUT:
		Append_Event(blk, at, pv,
			e->type == PUGL_FOCUS_IN ? EVT_ACTIVE : EVT_INACTIVE, HAS_XY, 0);
		break;

	case PUGL_CLOSE:
		// Only the request - closing is the script's to do.
		Append_Event(blk, at, pv, EVT_CLOSE, HAS_XY, 0);
		break;

	case PUGL_CONFIGURE: {
		const PuglConfigureEvent *c = &e->configure;
		if (c->width != pv->w || c->height != pv->h) {
			pv->w = c->width;
			pv->h = c->height;
			Append_Event(blk, at, pv, EVT_RESIZE, HAS_XY, XY_DATA(c->width, c->height));
		}
		if (c->x != pv->x || c->y != pv->y) {
			pv->x = c->x;
			pv->y = c->y;
			Append_Event(blk, at, pv, EVT_OFFSET, HAS_XY, XY_DATA(c->x, c->y));
		}
		break; }

	default:
		// PUGL_TEXT and the rest are queued but not reported yet.
		break;
	}
}


//== commands =================================================================

/***********************************************************************
**  open-view size [pair!] /title text /at offset /hidden /fixed
**
**  Frame: 1 size, 2 /title, 3 text, 4 /at, 5 offset, 6 /hidden, 7 /fixed
***********************************************************************/
COMMAND cmd_pugl_open_view(RXIFRM *frm, void *ctx)
{
	REBHOB      *hob;
	PUGLVIEWCTX *pv;
	PuglView    *view;
	REBINT       w = (REBINT)RXA_PAIR(frm, 1).x;
	REBINT       h = (REBINT)RXA_PAIR(frm, 1).y;

	if (w <= 0 || h <= 0 || w > 10000 || h > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	if (!Pugl_World) RETURN_ERROR(ERR_NO_WORLD);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglView);
	if (!hob) RETURN_ERROR(ERR_NO_HANDLE);
	pv = (PUGLVIEWCTX*)hob->data;
	CLEARS(pv);
	pv->hob = hob;

	view = puglNewView(Pugl_World);
	if (!view) {
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_VIEW);
	}
	puglSetHandle(view, pv);
	puglSetBackend(view, puglStubBackend());
	puglSetEventFunc(view, Pugl_On_Event);
	puglSetSizeHint(view, PUGL_DEFAULT_SIZE, (unsigned)w, (unsigned)h);
	puglSetViewHint(view, PUGL_RESIZABLE, RXA_REF(frm, 7) ? PUGL_FALSE : PUGL_TRUE);

	if (RXA_REF(frm, 2)) Set_View_Title(view, RXA_SERIES(frm, 3), RXA_INDEX(frm, 3));
	if (RXA_REF(frm, 4)) {
		puglSetPositionHint(view, PUGL_DEFAULT_POSITION,
			(int)RXA_PAIR(frm, 5).x, (int)RXA_PAIR(frm, 5).y);
	}

	if (puglRealize(view) != PUGL_SUCCESS) {
		puglSetHandle(view, NULL);
		puglFreeView(view);
		Pugl_Purge_Events(pv);
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_VIEW);
	}

	pv->view = view;
	pv->next = Views_Head;
	Views_Head = pv;
	Pugl_Views++;  // the device poll pumps only while one of these exists

	// Realizing reports the initial frame; it is the starting point, not
	// a change, so it is taken as the baseline instead of an event.
	Pugl_Purge_Events(pv);
	Remember_Frame(pv);

	// The native view and every queued event point back at this context.
	hob->flags |= HANDLE_CONTEXT_LOCKED;

	if (!RXA_REF(frm, 6)) puglShow(view, PUGL_SHOW_RAISE);

	RETURN_HANDLE(hob);
}


// Closing an already closed view is not an error - it is what a `close`
// handler ends up doing when the user was quicker.
COMMAND cmd_pugl_close_view(RXIFRM *frm, void *ctx)
{
	PUGLVIEWCTX *pv = Frm_View(frm, 1);
	if (!pv) RETURN_ERROR(ERR_INVALID_HANDLE);
	Close_View(pv);
	return RXR_TRUE;
}

COMMAND cmd_pugl_show_view(RXIFRM *frm, void *ctx)
{
	PUGLVIEWCTX *pv = Frm_View(frm, 1);
	if (!pv || !pv->view) RETURN_ERROR(ERR_INVALID_HANDLE);
	puglShow((PuglView*)pv->view, PUGL_SHOW_RAISE);
	return RXR_TRUE;
}

COMMAND cmd_pugl_hide_view(RXIFRM *frm, void *ctx)
{
	PUGLVIEWCTX *pv = Frm_View(frm, 1);
	if (!pv || !pv->view) RETURN_ERROR(ERR_INVALID_HANDLE);
	puglHide((PuglView*)pv->view);
	return RXR_TRUE;
}


/***********************************************************************
**  poll-events
**
**  Runs one non-blocking Pugl main loop iteration and returns what is
**  queued, as a block of event! values. Never sleeps - WAIT does that.
***********************************************************************/
COMMAND cmd_pugl_poll_events(RXIFRM *frm, void *ctx)
{
	REBSER  *blk;
	REBCNT   count, at = 0;
	PUGLQEVT q;

	if (Pugl_World && Pugl_Views) puglUpdate(Pugl_World, 0.0);

	if (Pugl_Dropped_Events) {
		printf("Pugl: dropped %u events (queue full)\n", Pugl_Dropped_Events);
		Pugl_Dropped_Events = 0;
	}

	// A configure can become two events (resize and offset).
	count = Pugl_Event_Count();
	blk = (REBSER*)RL_MAKE_BLOCK(count * 2);
	if (!blk) RETURN_ERROR(ERR_NO_HANDLE);

	RL_PROTECT_GC(blk, 1);
	while (Pugl_Take_Event(&q)) Convert_Event(blk, &at, &q);
	RL_PROTECT_GC(blk, 0);

	RXA_SERIES(frm, 1) = blk;
	RXA_INDEX(frm, 1)  = 0;
	RXA_TYPE(frm, 1)   = RXT_BLOCK;
	return RXR_VALUE;
}


//== view handle callbacks ====================================================

// Reached through an explicit `release`, or at shutdown - an open view is
// locked against the GC.
int PuglView_free(void *hndl)
{
	REBHOB      *hob = (REBHOB*)hndl;
	PUGLVIEWCTX *pv;

	if (!hob) return 0;
	pv = (PUGLVIEWCTX*)hob->data;
	if (pv) {
		Close_View(pv);
		debug_print("releasing Pugl view handle: %p\n", (void*)pv);
		CLEARS(pv);
	}
	UNMARK_HOB(hob);
	return 0;
}


int PuglView_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLVIEWCTX *pv   = (PUGLVIEWCTX*)hob->data;
	PuglView    *view = (PuglView*)pv->view;

	word = RL_FIND_WORD(Pugl_arg_words, word);

	// A closed view answers none - except `open?` and `id`. Unknown words
	// (0) are refused, so PD_Handle can still answer `type`.
	if (word != 0 && !view && word != W_PUGL_ARG_OPENQ && word != W_PUGL_ARG_ID) {
		*type = RXT_NONE;
		return PE_USE;
	}

	switch (word) {
	case W_PUGL_ARG_TITLE: {
		const char *s = puglGetViewString(view, PUGL_WINDOW_TITLE);
		if (!s) { *type = RXT_NONE; break; }
		arg->series = RL_DECODE_UTF_STRING((REBYTE*)s, (REBCNT)strlen(s), 8, FALSE, FALSE);
		if (!arg->series) { *type = RXT_NONE; break; }
		arg->index = 0;
		*type = RXT_STRING;
		break; }

	case W_PUGL_ARG_SIZE: {
		PuglArea a = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
		arg->pair.x = (float)a.width;
		arg->pair.y = (float)a.height;
		*type = RXT_PAIR;
		break; }

	case W_PUGL_ARG_OFFSET: {
		PuglPoint p = puglGetPositionHint(view, PUGL_CURRENT_POSITION);
		arg->pair.x = (float)p.x;
		arg->pair.y = (float)p.y;
		*type = RXT_PAIR;
		break; }

	case W_PUGL_ARG_SCALE:
		arg->dec64 = puglGetScaleFactor(view);
		*type = RXT_DECIMAL;
		break;

	case W_PUGL_ARG_ID:
		arg->int64 = view ? (i64)puglGetNativeView(view) : 0;
		*type = RXT_INTEGER;
		break;

	case W_PUGL_ARG_VISIBLEQ:
		arg->int32a = puglGetVisible(view) ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	case W_PUGL_ARG_OPENQ:
		arg->int32a = view ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	default:
		return PE_BAD_SELECT;
	}
	return PE_USE;
}


int PuglView_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLVIEWCTX *pv   = (PUGLVIEWCTX*)hob->data;
	PuglView    *view = (PuglView*)pv->view;

	if (!view) return PE_BAD_SET; // closed views are read-only

	switch (RL_FIND_WORD(Pugl_arg_words, word)) {
	case W_PUGL_ARG_TITLE:
		if (*type != RXT_STRING) return PE_BAD_SET_TYPE;
		if (!Set_View_Title(view, (REBSER*)arg->series, arg->index)) return PE_BAD_SET;
		break;

	case W_PUGL_ARG_SIZE:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		if (arg->pair.x < 1 || arg->pair.y < 1
		 || arg->pair.x > 10000 || arg->pair.y > 10000) return PE_BAD_RANGE;
		if (puglSetSizeHint(view, PUGL_CURRENT_SIZE,
		        (unsigned)arg->pair.x, (unsigned)arg->pair.y) != PUGL_SUCCESS)
			return PE_BAD_SET;
		break;

	case W_PUGL_ARG_OFFSET:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		if (puglSetPositionHint(view, PUGL_CURRENT_POSITION,
		        (int)arg->pair.x, (int)arg->pair.y) != PUGL_SUCCESS)
			return PE_BAD_SET;
		break;

	default:
		return PE_BAD_SET;
	}
	return PE_OK;
}


int PuglView_mold(REBHOB *hob, REBSER *str)
{
	int          len;
	PUGLVIEWCTX *pv;

	if (!str || !hob || !(pv = (PUGLVIEWCTX*)hob->data)) return 0;

	SERIES_TAIL(str) = 0;
	if (pv->view) {
		PuglArea a = puglGetSizeHint((PuglView*)pv->view, PUGL_CURRENT_SIZE);
		APPEND_STRING(str, "0#%lx %dx%d",
			(unsigned long)puglGetNativeView((PuglView*)pv->view),
			(int)a.width, (int)a.height);
	} else {
		APPEND_STRING(str, "%s", "closed");
	}
	return len;
}
