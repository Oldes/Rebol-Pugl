//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Command implementations and the window and image handle callbacks.
//
// The enum, the declarations, the dispatch table and the `_init` handler
// are all generated from pugl.reb.
//

#include "gen-pugl.h"
#include "rebol-pugl.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h> // MAKE_MEM / FREE_MEM

static const REBYTE* ERR_INVALID_HANDLE = (const REBYTE*)"Invalid Pugl window handle!";
static const REBYTE* ERR_INVALID_IMAGE  = (const REBYTE*)"Invalid Pugl image handle!";
static const REBYTE* ERR_NO_HANDLE      = (const REBYTE*)"Failed to create the handle!";
static const REBYTE* ERR_NO_WINDOW      = (const REBYTE*)"Failed to create the window!";
static const REBYTE* ERR_NO_WORLD       = (const REBYTE*)"Pugl world is not initialized!";
static const REBYTE* ERR_BAD_SIZE       = (const REBYTE*)"Size must be between 1x1 and 10000x10000!";
static const REBYTE* ERR_BAD_IMAGE      = (const REBYTE*)"Empty or invalid image!";

// Every open view, so they can all go before the world does.
static PUGLWIN *Windows_Head = NULL;


//== helpers ==================================================================

// Validates argument `n` as a window handle (open or closed).
static PUGLWIN* Frm_Window(RXIFRM *frm, REBCNT n)
{
	REBHOB *hob;
	if (!FRM_IS_HANDLE(n, Handle_PuglWindow)) return NULL;
	hob = RXA_HANDLE_CONTEXT(frm, n);
	if (!hob || !IS_USED_HOB(hob) || !hob->data) return NULL;
	return (PUGLWIN*)hob->data;
}

// ... and as an image handle (shown or removed).
static PUGLIMG* Frm_Image(RXIFRM *frm, REBCNT n)
{
	REBHOB *hob;
	if (!FRM_IS_HANDLE(n, Handle_PuglImage)) return NULL;
	hob = RXA_HANDLE_CONTEXT(frm, n);
	if (!hob || !IS_USED_HOB(hob) || !hob->data) return NULL;
	return (PUGLIMG*)hob->data;
}

// A handle context as a value - what `images` and `window` hand back.
static void Set_Handle_Arg(RXIARG *arg, REBHOB *hob)
{
	CLEARS(arg);
	arg->handle.hob   = hob;
	arg->handle.type  = hob->sym;
	arg->handle.flags = hob->flags;
	arg->handle.index = hob->index;
}

// An image! value from its series. Filled in as an image and nothing else:
// an image! carries its dimensions where a series has its index.
static void Set_Image_Arg(RXIARG *arg, REBSER *img)
{
	CLEARS(arg);
	arg->image  = img;
	arg->width  = (int)IMG_WIDE(img);
	arg->height = (int)IMG_HIGH(img);
}

// Pugl wants a NUL-terminated string, which RL_GET_UTF8_STRING does not
// promise - so the title is copied. Pugl copies it again on its side.
static REBOOL Set_Window_Title(PuglView *view, REBSER *ser, REBCNT index)
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

/***********************************************************************
**  The GC-marked slot of a handle, hob->series, is a block:
**
**      window:  [0] the image! its icon was made from, or none
**      image:   [0] the image! it shows
**
**  The block is stored in hob->series BEFORE anything else can allocate,
**  so a collection cannot take it away while it is filled.
***********************************************************************/
#define SLOT_ICON  0
#define SLOT_IMAGE 0

static REBSER *Window_Slots(PUGLWIN *pv)
{
	REBHOB *hob = pv->hob;
	REBSER *blk;
	RXIARG  none;

	if (hob->series) return hob->series;
	blk = (REBSER*)RL_MAKE_BLOCK(1);
	if (!blk) return NULL;
	hob->series = blk;
	CLEARS(&none);
	RL_SET_VALUE(blk, SLOT_ICON, none, RXT_NONE);
	return blk;
}

// Asks for the whole window to be drawn again, at the next main loop
// iteration - whatever an image did, it may have uncovered what was under.
static void Window_Changed(PUGLWIN *win)
{
	if (win && win->view) puglObscureView((PuglView*)win->view);
}

/***********************************************************************
**  A texture of an image which is going away, to be deleted at the
**  window's next draw - the only time its GL context is current. If
**  the list cannot grow, the texture is simply left to the context,
**  which deletes it when the window closes.
***********************************************************************/
static void Retire_Texture(PUGLWIN *win, REBCNT tex)
{
	if (!tex || !win->view) return;   // a closed window took it already
	if (win->dead_count == win->dead_size) {
		REBCNT  size  = win->dead_size ? win->dead_size * 2 : 8;
		REBCNT *grown = (REBCNT*)MAKE_MEM(size * sizeof(REBCNT));
		if (!grown) return;
		if (win->dead) {
			COPY_MEM(grown, win->dead, win->dead_count * sizeof(REBCNT));
			FREE_MEM(win->dead);
		}
		win->dead      = grown;
		win->dead_size = size;
	}
	win->dead[win->dead_count++] = tex;
}

/***********************************************************************
**  Takes an image out of its window. The handle stays, and reports
**  none for everything from then on; it lets go of its image! and of
**  the GC lock it held while it was shown.
***********************************************************************/
static void Detach_Image(PUGLIMG *im)
{
	PUGLWIN  *win = (PUGLWIN*)im->win;
	PUGLIMG **link;

	if (!win) return;
	for (link = (PUGLIMG**)&win->images; *link; link = (PUGLIMG**)&(*link)->next) {
		if (*link == im) { *link = (PUGLIMG*)im->next; break; }
	}
	Retire_Texture(win, im->texture);
	Window_Changed(win);
	// A removed image reports nothing, not even a `leave`; the next move
	// reports `enter` on whatever is there instead.
	if (win->hover == im) win->hover = NULL;

	im->win     = NULL;
	im->next    = NULL;
	im->image   = NULL;
	im->texture = 0;
	if (im->hob) {
		im->hob->series = NULL;
		im->hob->flags &= ~HANDLE_CONTEXT_LOCKED;
	}
}

/***********************************************************************
**  Sets the view's icon, or puts the default back with NULL.
**
**  The platform gets a COPY of the pixels now - the series may move once
**  this returns - and the image! itself is kept in the slot only so that
**  `icon` reads back the very value it was given. Drawing into it
**  afterwards therefore shows only when it is set again.
**
**  The whole image, whatever its index: an image! crossing the ABI has
**  its dimensions where a series has its index.
***********************************************************************/
static REBOOL Set_Window_Icon(PUGLWIN *pv, RXIARG *arg)
{
	REBSER *slots = Window_Slots(pv);
	REBSER *img;
	RXIARG  none;

	if (!slots || !pv->view) return FALSE;
	if (!arg) {
		if (!Pugl_Set_Native_Icon((PuglView*)pv->view, pv->icon, NULL, 0, 0)) return FALSE;
		CLEARS(&none);
		RL_SET_VALUE(slots, SLOT_ICON, none, RXT_NONE);
		return TRUE;
	}
	img = (REBSER*)arg->image;
	if (!img || IMG_WIDE(img) == 0 || IMG_HIGH(img) == 0) return FALSE;
	if (!Pugl_Set_Native_Icon((PuglView*)pv->view, pv->icon,
	                          (const unsigned char*)IMG_DATA(img),
	                          (int)IMG_WIDE(img), (int)IMG_HIGH(img)))
		return FALSE;
	RL_SET_VALUE(slots, SLOT_ICON, *arg, RXT_IMAGE);
	return TRUE;
}

static void Remember_Frame(PUGLWIN *pv)
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
static void Close_Window(PUGLWIN *pv)
{
	PuglView *view = (PuglView*)pv->view;
	PUGLWIN **link;

	if (!view) return;

	pv->view = NULL;
	puglSetHandle(view, NULL);
	puglFreeView(view);
	// Only now: the window used them until it was gone.
	Pugl_Free_Native_Icon(pv->icon);

	// Its images go with it. Their textures went with the GL context, so
	// nothing is retired (pv->view is already NULL), and the list of the
	// ones retired earlier is only memory now.
	pv->hover = NULL;
	while (pv->images) Detach_Image((PUGLIMG*)pv->images);
	if (pv->dead) FREE_MEM(pv->dead);
	pv->dead = NULL;
	pv->dead_count = pv->dead_size = 0;

	for (link = &Windows_Head; *link; link = (PUGLWIN**)&(*link)->next) {
		if (*link == pv) { *link = (PUGLWIN*)pv->next; break; }
	}
	pv->next = NULL;
	if (Pugl_Windows > 0) Pugl_Windows--;

	Pugl_Purge_Events(pv);

	// A closed window lets go of its icon, and of its GC lock.
	if (pv->hob) {
		pv->hob->series = NULL;
		pv->hob->flags &= ~HANDLE_CONTEXT_LOCKED;
	}
}

void Pugl_Close_All_Windows(void)
{
	while (Windows_Head) Close_Window(Windows_Head);
}

static REBYTE Modifier_Bits(PuglMods mods)
{
	REBYTE bits = 0;
	if (mods & PUGL_MOD_SHIFT) bits |= (1 << EVF_SHIFT);
	if (mods & PUGL_MOD_CTRL)  bits |= (1 << EVF_CONTROL);
	if (mods & PUGL_MOD_ALT)   bits |= (1 << EVF_ALT);
	return bits;
}

// Appends one event! to the block, with `source` - a window or an image
// handle - as its source.
static void Append_Event_Of(REBSER *blk, REBCNT *at, REBHOB *source,
                            REBCNT type, REBYTE flags, u32 data)
{
	REBEVT ev;
	RXIARG val;

	CLEARS(&ev);
	ev.type  = (u8)type;
	ev.model = EVM_HANDLE;   // the source is our handle, and the GC marks it
	ev.hob   = source;
	ev.flags = flags;
	ev.data  = data;

	CLEARS(&val);
	COPY_MEM(&val, &ev, sizeof(ev));
	RL_SET_VALUE(blk, (*at)++, val, RXT_EVENT);
}

#define Append_Event(blk, at, pv, type, flags, data) \
	Append_Event_Of(blk, at, (pv)->hob, type, flags, data)

#define XY_DATA(x, y) ((((u32)((REBINT)(y) & 0xffff)) << 16) | ((u32)((REBINT)(x) & 0xffff)))
#define HAS_XY        (1 << EVF_HAS_XY)
#define HAS_CODE      (1 << EVF_HAS_CODE)

/***********************************************************************
**  The topmost visible image under a point of the window, or NULL.
**  The list is in drawing order, so the last match is the one on top.
**  The right and bottom edges are outside, so images laid edge to edge
**  never both claim a point.
***********************************************************************/
static PUGLIMG *Image_At(PUGLWIN *win, REBINT x, REBINT y)
{
	PUGLIMG *im, *top = NULL;
	for (im = (PUGLIMG*)win->images; im; im = (PUGLIMG*)im->next) {
		REBINT w, h;
		if (!im->visible || !im->image) continue;
		w = im->w > 0 ? im->w : (REBINT)IMG_WIDE((REBSER*)im->image);
		h = im->h > 0 ? im->h : (REBINT)IMG_HIGH((REBSER*)im->image);
		if (x >= im->x && y >= im->y && x < im->x + w && y < im->y + h) top = im;
	}
	return top;
}

/***********************************************************************
**  `enter` and `leave` per image, for the images with `track?` on.
**
**  Worked out from the pointer's position whenever a pointer event is
**  converted: when the topmost image under it changes, the old one gets
**  `leave` where it was last seen over it, and the new one `enter` - in
**  that order, and before the window's own event, the same order
**  Rebol-GUI reports for widgets. `inside` FALSE is the pointer leaving
**  the window, which leaves whatever it was over.
**
**  Hover is kept for every image, tracked or not - `hover?` reads it,
**  and an untracked image on top still covers a tracked one below.
**  It is as of the last event: an image moved under a pointer which
**  stays still is not entered until the pointer moves.
***********************************************************************/
static void Hover_To(REBSER *blk, REBCNT *at, PUGLWIN *win,
                     REBINT x, REBINT y, REBOOL inside)
{
	PUGLIMG *now = inside ? Image_At(win, x, y) : NULL;
	PUGLIMG *was = (PUGLIMG*)win->hover;

	if (now != was) {
		if (was && was->track && was->hob)
			Append_Event_Of(blk, at, was->hob, EVT_LEAVE, HAS_XY,
			                XY_DATA(win->hover_x, win->hover_y));
		if (now && now->track && now->hob)
			Append_Event_Of(blk, at, now->hob, EVT_ENTER, HAS_XY, XY_DATA(x, y));
		win->hover = now;
	}
	win->hover_x = x;
	win->hover_y = y;
}

static const REBCNT Down_Types[3] = { EVT_DOWN, EVT_ALT_DOWN, EVT_AUX_DOWN };
static const REBCNT Up_Types[3]   = { EVT_UP,   EVT_ALT_UP,   EVT_AUX_UP   };

/***********************************************************************
**  One queued Pugl event into zero, one or two event! values.
**
**  Coordinates are Pugl's own - device pixels, view-relative.
***********************************************************************/
static void Convert_Event(REBSER *blk, REBCNT *at, PUGLQEVT *q)
{
	PUGLWIN         *pv = q->ctx;
	const PuglEvent *e  = &q->event;

	switch (e->type) {
	case PUGL_BUTTON_PRESS:
	case PUGL_BUTTON_RELEASE:
		// Primary, secondary, middle - nothing above is reported yet.
		if (e->button.button > 2) break;
		Hover_To(blk, at, pv, (REBINT)e->button.x, (REBINT)e->button.y, TRUE);
		Append_Event(blk, at, pv,
			(e->type == PUGL_BUTTON_PRESS ? Down_Types : Up_Types)[e->button.button],
			HAS_XY | Modifier_Bits(e->button.state),
			XY_DATA(e->button.x, e->button.y));
		break;

	case PUGL_MOTION:
		Hover_To(blk, at, pv, (REBINT)e->motion.x, (REBINT)e->motion.y, TRUE);
		Append_Event(blk, at, pv, EVT_MOVE,
			HAS_XY | Modifier_Bits(e->motion.state),
			XY_DATA(e->motion.x, e->motion.y));
		break;

	// The window's own enter goes before an image's, and its leave after:
	// the pointer is inside the window whenever it is over an image.
	case PUGL_POINTER_IN:
		Append_Event(blk, at, pv, EVT_ENTER,
			HAS_XY, XY_DATA(e->crossing.x, e->crossing.y));
		Hover_To(blk, at, pv, (REBINT)e->crossing.x, (REBINT)e->crossing.y, TRUE);
		break;

	case PUGL_POINTER_OUT:
		Hover_To(blk, at, pv, (REBINT)e->crossing.x, (REBINT)e->crossing.y, FALSE);
		Append_Event(blk, at, pv, EVT_LEAVE,
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
**  open-window size [pair!] /title text /at offset /hidden /fixed
**
**  Frame: 1 size, 2 /title, 3 text, 4 /at, 5 offset, 6 /hidden, 7 /fixed
***********************************************************************/
COMMAND cmd_pugl_open_window(RXIFRM *frm, void *ctx)
{
	REBHOB      *hob;
	PUGLWIN     *pv;
	PuglView    *view;
	REBINT       w = (REBINT)RXA_PAIR(frm, 1).x;
	REBINT       h = (REBINT)RXA_PAIR(frm, 1).y;

	if (w <= 0 || h <= 0 || w > 10000 || h > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	if (!Pugl_World) RETURN_ERROR(ERR_NO_WORLD);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglWindow);
	if (!hob) RETURN_ERROR(ERR_NO_HANDLE);
	pv = (PUGLWIN*)hob->data;
	CLEARS(pv);
	pv->hob = hob;

	view = puglNewView(Pugl_World);
	if (!view) {
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_WINDOW);
	}
	puglSetHandle(view, pv);
	Pugl_Setup_Backend(view);
	puglSetEventFunc(view, Pugl_On_Event);
	puglSetSizeHint(view, PUGL_DEFAULT_SIZE, (unsigned)w, (unsigned)h);
	puglSetViewHint(view, PUGL_RESIZABLE, RXA_REF(frm, 7) ? PUGL_FALSE : PUGL_TRUE);

	if (RXA_REF(frm, 2)) Set_Window_Title(view, RXA_SERIES(frm, 3), RXA_INDEX(frm, 3));
	if (RXA_REF(frm, 4)) {
		puglSetPositionHint(view, PUGL_DEFAULT_POSITION,
			(int)RXA_PAIR(frm, 5).x, (int)RXA_PAIR(frm, 5).y);
	}

	if (puglRealize(view) != PUGL_SUCCESS) {
		puglSetHandle(view, NULL);
		puglFreeView(view);
		Pugl_Purge_Events(pv);
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_WINDOW);
	}

	pv->view = view;
	pv->next = Windows_Head;
	Windows_Head = pv;
	Pugl_Windows++;  // the device poll pumps only while one of these exists

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
COMMAND cmd_pugl_close_window(RXIFRM *frm, void *ctx)
{
	PUGLWIN *pv = Frm_Window(frm, 1);
	if (!pv) RETURN_ERROR(ERR_INVALID_HANDLE);
	Close_Window(pv);
	return RXR_TRUE;
}

COMMAND cmd_pugl_show_window(RXIFRM *frm, void *ctx)
{
	PUGLWIN *pv = Frm_Window(frm, 1);
	if (!pv || !pv->view) RETURN_ERROR(ERR_INVALID_HANDLE);
	puglShow((PuglView*)pv->view, PUGL_SHOW_RAISE);
	return RXR_TRUE;
}

COMMAND cmd_pugl_hide_window(RXIFRM *frm, void *ctx)
{
	PUGLWIN *pv = Frm_Window(frm, 1);
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

	if (Pugl_World && Pugl_Windows) puglUpdate(Pugl_World, 0.0);

	if (Pugl_Dropped_Events) {
		printf("Pugl: dropped %u events (queue full)\n", Pugl_Dropped_Events);
		Pugl_Dropped_Events = 0;
	}

	// A configure can become two events (resize and offset), and a pointer
	// event three (an image's leave, another's enter, and its own).
	count = Pugl_Event_Count();
	blk = (REBSER*)RL_MAKE_BLOCK(count * 3);
	if (!blk) RETURN_ERROR(ERR_NO_HANDLE);

	RL_PROTECT_GC(blk, 1);
	while (Pugl_Take_Event(&q)) Convert_Event(blk, &at, &q);
	RL_PROTECT_GC(blk, 0);

	RXA_SERIES(frm, 1) = blk;
	RXA_INDEX(frm, 1)  = 0;
	RXA_TYPE(frm, 1)   = RXT_BLOCK;
	return RXR_VALUE;
}


/***********************************************************************
**  redraw target [handle!]
**
**  Uploads an image's pixels again and shows them - or, given a window,
**  every image in it. Needed after drawing into an image: the window
**  only holds a reference, and has no way of knowing the pixels changed.
**  One main loop iteration is run, so the new pixels are normally on
**  screen when this returns.
***********************************************************************/
COMMAND cmd_pugl_redraw(RXIFRM *frm, void *ctx)
{
	PUGLIMG *im = Frm_Image(frm, 1);
	PUGLWIN *win;

	if (im) {
		if (!im->win) RETURN_ERROR(ERR_INVALID_IMAGE);
		im->dirty = TRUE;
		win = (PUGLWIN*)im->win;
	} else {
		win = Frm_Window(frm, 1);
		if (!win || !win->view) RETURN_ERROR(ERR_INVALID_HANDLE);
		for (im = (PUGLIMG*)win->images; im; im = (PUGLIMG*)im->next) im->dirty = TRUE;
	}
	Window_Changed(win);
	puglUpdate(Pugl_World, 0.0);
	return RXR_TRUE;
}


/***********************************************************************
**  add-image window [handle!] image [image!] offset [pair!] /size sz
**
**  Frame: 1 window, 2 image, 3 offset, 4 /size, 5 sz
**
**  The window keeps a REFERENCE to the image, not a copy: drawing into
**  that same image and calling `redraw` is how it is animated. Added at
**  the end of the window's list, so it is drawn above everything added
**  before it.
***********************************************************************/
COMMAND cmd_pugl_add_image(RXIFRM *frm, void *ctx)
{
	PUGLWIN  *win = Frm_Window(frm, 1);
	REBSER   *img = (REBSER*)RXA_IMAGE(frm, 2);
	REBHOB   *hob;
	REBSER   *slots;
	PUGLIMG  *im;
	PUGLIMG **link;
	REBINT    w = 0, h = 0;

	if (!win || !win->view) RETURN_ERROR(ERR_INVALID_HANDLE);
	if (!img || IMG_WIDE(img) == 0 || IMG_HIGH(img) == 0) RETURN_ERROR(ERR_BAD_IMAGE);
	if (RXA_REF(frm, 4)) {
		w = (REBINT)RXA_PAIR(frm, 5).x;
		h = (REBINT)RXA_PAIR(frm, 5).y;
		if (w < 0 || h < 0 || w > 10000 || h > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	}

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglImage);
	if (!hob) RETURN_ERROR(ERR_NO_HANDLE);
	im = (PUGLIMG*)hob->data;
	CLEARS(im);
	im->hob = hob;

	// The image! as it arrived, dimensions and all, in the slot the GC
	// marks - which keeps it alive while it is shown.
	slots = (REBSER*)RL_MAKE_BLOCK(1);
	if (!slots) {
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_HANDLE);
	}
	hob->series = slots;
	RL_SET_VALUE(slots, SLOT_IMAGE, RXA_ARG(frm, 2), RXT_IMAGE);

	im->win     = win;
	im->image   = img;
	im->x       = (REBINT)RXA_PAIR(frm, 3).x;
	im->y       = (REBINT)RXA_PAIR(frm, 3).y;
	im->w       = w;
	im->h       = h;
	im->visible = TRUE;
	im->dirty   = TRUE;

	for (link = (PUGLIMG**)&win->images; *link; link = (PUGLIMG**)&(*link)->next);
	*link = im;

	// The window's list points at this context.
	hob->flags |= HANDLE_CONTEXT_LOCKED;
	Window_Changed(win);

	RETURN_HANDLE(hob);
}


// Removing an image which is no longer shown is not an error - its window
// may have been closed, which removes everything in it.
COMMAND cmd_pugl_remove_image(RXIFRM *frm, void *ctx)
{
	PUGLIMG *im = Frm_Image(frm, 1);
	if (!im) RETURN_ERROR(ERR_INVALID_IMAGE);
	Detach_Image(im);
	return RXR_TRUE;
}


//== window handle callbacks ==================================================

// Reached through an explicit `release`, or at shutdown - an open window is
// locked against the GC.
int PuglWindow_free(void *hndl)
{
	REBHOB  *hob = (REBHOB*)hndl;
	PUGLWIN *pv;

	if (!hob) return 0;
	pv = (PUGLWIN*)hob->data;
	if (pv) {
		Close_Window(pv);
		debug_print("releasing Pugl window handle: %p\n", (void*)pv);
		CLEARS(pv);
	}
	UNMARK_HOB(hob);
	return 0;
}


int PuglWindow_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLWIN  *pv   = (PUGLWIN*)hob->data;
	PuglView *view = (PuglView*)pv->view;

	word = RL_FIND_WORD(Pugl_arg_words, word);

	// A closed window answers none - except `open?` and `id`. Unknown words
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

	// A new block each time, in drawing order; empty rather than none, so
	// it can always be iterated.
	case W_PUGL_ARG_IMAGES: {
		PUGLIMG *im;
		REBSER  *blk;
		REBCNT   n = 0;
		RXIARG   val;
		for (im = (PUGLIMG*)pv->images; im; im = (PUGLIMG*)im->next) n++;
		blk = (REBSER*)RL_MAKE_BLOCK(n);
		if (!blk) { *type = RXT_NONE; break; }
		n = 0;
		for (im = (PUGLIMG*)pv->images; im; im = (PUGLIMG*)im->next) {
			Set_Handle_Arg(&val, im->hob);
			RL_SET_VALUE(blk, n++, val, RXT_HANDLE);
		}
		arg->series = blk;
		arg->index  = 0;
		*type = RXT_BLOCK;
		break; }

	// The image! it was given, from the slot - not read back from the
	// platform, which keeps only its own converted copy.
	case W_PUGL_ARG_ICON: {
		RXIARG val;
		REBSER *img;
		if (!hob->series || RL_GET_VALUE(hob->series, SLOT_ICON, &val) != RXT_IMAGE) {
			*type = RXT_NONE;
			break;
		}
		img = (REBSER*)val.image;
		Set_Image_Arg(arg, img);
		*type = RXT_IMAGE;
		break; }

	default:
		return PE_BAD_SELECT;
	}
	return PE_USE;
}


int PuglWindow_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLWIN  *pv   = (PUGLWIN*)hob->data;
	PuglView *view = (PuglView*)pv->view;

	if (!view) return PE_BAD_SET; // closed windows are read-only

	switch (RL_FIND_WORD(Pugl_arg_words, word)) {
	case W_PUGL_ARG_TITLE:
		if (*type != RXT_STRING) return PE_BAD_SET_TYPE;
		if (!Set_Window_Title(view, (REBSER*)arg->series, arg->index)) return PE_BAD_SET;
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

	case W_PUGL_ARG_ICON:
		if (*type == RXT_NONE) {
			if (!Set_Window_Icon(pv, NULL)) return PE_BAD_SET;
			break;
		}
		if (*type != RXT_IMAGE) return PE_BAD_SET_TYPE;
		if (!Set_Window_Icon(pv, arg)) return PE_BAD_SET;
		break;

	default:
		return PE_BAD_SET;
	}
	return PE_OK;
}


int PuglWindow_mold(REBHOB *hob, REBSER *str)
{
	int      len;
	PUGLWIN *pv;

	if (!str || !hob || !(pv = (PUGLWIN*)hob->data)) return 0;

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


//== image handle callbacks ===================================================

// Reached through an explicit `release`, or at shutdown - a shown image is
// locked against the GC, and its window holds a pointer to it.
int PuglImage_free(void *hndl)
{
	REBHOB  *hob = (REBHOB*)hndl;
	PUGLIMG *im;

	if (!hob) return 0;
	im = (PUGLIMG*)hob->data;
	if (im) {
		Detach_Image(im);
		CLEARS(im);
	}
	UNMARK_HOB(hob);
	return 0;
}


int PuglImage_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLIMG *im = (PUGLIMG*)hob->data;
	RXIARG   val;

	word = RL_FIND_WORD(Pugl_arg_words, word);

	// A removed image answers none for everything. Unknown words (0) are
	// refused, so PD_Handle can still answer `type`.
	if (word != 0 && !im->win) {
		*type = RXT_NONE;
		return PE_USE;
	}

	switch (word) {
	// The very series it was given, from the slot.
	case W_PUGL_ARG_IMAGE:
		if (!hob->series || RL_GET_VALUE(hob->series, SLOT_IMAGE, &val) != RXT_IMAGE) {
			*type = RXT_NONE;
			break;
		}
		Set_Image_Arg(arg, (REBSER*)val.image);
		*type = RXT_IMAGE;
		break;

	case W_PUGL_ARG_OFFSET:
		arg->pair.x = (float)im->x;
		arg->pair.y = (float)im->y;
		*type = RXT_PAIR;
		break;

	// What it is drawn at, a zero axis resolved to the image's own.
	case W_PUGL_ARG_SIZE:
		arg->pair.x = (float)(im->w > 0 ? im->w : (REBINT)IMG_WIDE((REBSER*)im->image));
		arg->pair.y = (float)(im->h > 0 ? im->h : (REBINT)IMG_HIGH((REBSER*)im->image));
		*type = RXT_PAIR;
		break;

	case W_PUGL_ARG_VISIBLEQ:
		arg->int32a = im->visible ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	case W_PUGL_ARG_TRACKQ:
		arg->int32a = im->track ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	case W_PUGL_ARG_HOVERQ:
		arg->int32a = (((PUGLWIN*)im->win)->hover == im) ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	case W_PUGL_ARG_WINDOW:
		Set_Handle_Arg(arg, ((PUGLWIN*)im->win)->hob);
		*type = RXT_HANDLE;
		break;

	default:
		return PE_BAD_SELECT;
	}
	return PE_USE;
}


int PuglImage_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLIMG *im = (PUGLIMG*)hob->data;

	if (!im->win) return PE_BAD_SET; // removed images are read-only

	switch (RL_FIND_WORD(Pugl_arg_words, word)) {
	// Swapping the image is swapping the reference the GC marks; the
	// texture is uploaded again at the next draw.
	case W_PUGL_ARG_IMAGE: {
		REBSER *img;
		if (*type != RXT_IMAGE) return PE_BAD_SET_TYPE;
		img = (REBSER*)arg->image;
		if (!img || IMG_WIDE(img) == 0 || IMG_HIGH(img) == 0) return PE_BAD_SET;
		RL_SET_VALUE(hob->series, SLOT_IMAGE, *arg, RXT_IMAGE);
		im->image = img;
		im->dirty = TRUE;
		break; }

	case W_PUGL_ARG_OFFSET:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		im->x = (REBINT)arg->pair.x;
		im->y = (REBINT)arg->pair.y;
		break;

	// A zero axis is the image's own, so `0x0` undoes a scaling.
	case W_PUGL_ARG_SIZE:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		if (arg->pair.x < 0 || arg->pair.y < 0
		 || arg->pair.x > 10000 || arg->pair.y > 10000) return PE_BAD_RANGE;
		im->w = (REBINT)arg->pair.x;
		im->h = (REBINT)arg->pair.y;
		break;

	case W_PUGL_ARG_VISIBLEQ:
		if (*type != RXT_LOGIC) return PE_BAD_SET_TYPE;
		im->visible = arg->int32a ? TRUE : FALSE;
		break;

	// Only a flag: hover is kept either way, so turning it on while the
	// pointer is already over the image reports nothing until it leaves.
	case W_PUGL_ARG_TRACKQ:
		if (*type != RXT_LOGIC) return PE_BAD_SET_TYPE;
		im->track = arg->int32a ? TRUE : FALSE;
		return PE_OK;   // nothing to redraw

	default:
		return PE_BAD_SET;
	}
	Window_Changed((PUGLWIN*)im->win);
	return PE_OK;
}


int PuglImage_mold(REBHOB *hob, REBSER *str)
{
	int      len;
	PUGLIMG *im;

	if (!str || !hob || !(im = (PUGLIMG*)hob->data)) return 0;

	SERIES_TAIL(str) = 0;
	if (im->win && im->image) {
		APPEND_STRING(str, "%dx%d at %dx%d",
			(int)(im->w > 0 ? im->w : (REBINT)IMG_WIDE((REBSER*)im->image)),
			(int)(im->h > 0 ? im->h : (REBINT)IMG_HIGH((REBSER*)im->image)),
			(int)im->x, (int)im->y);
	} else {
		APPEND_STRING(str, "%s", "removed");
	}
	return len;
}
