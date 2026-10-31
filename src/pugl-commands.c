//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Command implementations and the window, image and group handle callbacks.
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
static const REBYTE* ERR_INVALID_TARGET = (const REBYTE*)"Not an open Pugl window or a shown group!";
static const REBYTE* ERR_NO_HANDLE      = (const REBYTE*)"Failed to create the handle!";
static const REBYTE* ERR_NO_WINDOW      = (const REBYTE*)"Failed to create the window!";
static const REBYTE* ERR_NO_WORLD       = (const REBYTE*)"Pugl world is not initialized!";
static const REBYTE* ERR_BAD_SIZE       = (const REBYTE*)"Size must be between 1x1 and 10000x10000!";
static const REBYTE* ERR_BAD_IMAGE      = (const REBYTE*)"Empty or invalid image!";
static const REBYTE* ERR_BAD_PART       = (const REBYTE*)"Part must be [offset size] inside the image!";
static const REBYTE* ERR_INVALID_FONT   = (const REBYTE*)"Invalid Pugl font handle!";
static const REBYTE* ERR_BAD_GLYPH      = (const REBYTE*)"A glyph must be char [offset size bearing advance], inside the atlas!";
static const REBYTE* ERR_BAD_TEXT       = (const REBYTE*)"Failed to read the text!";

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

static void Set_Handle_Arg(RXIARG *arg, REBHOB *hob);
static void Update_Cursor(PUGLWIN *win);

// ... and as an image or a group handle (shown or removed).
static PUGLNODE* Frm_Node(RXIFRM *frm, REBCNT n)
{
	REBHOB *hob;
	if (!FRM_IS_HANDLE(n, Handle_PuglImage) && !FRM_IS_HANDLE(n, Handle_PuglGroup)
	 && !FRM_IS_HANDLE(n, Handle_PuglText))
		return NULL;
	hob = RXA_HANDLE_CONTEXT(frm, n);
	if (!hob || !IS_USED_HOB(hob) || !hob->data) return NULL;
	return (PUGLNODE*)hob->data;
}

// ... and as a font handle.
static PUGLFONT* Frm_Font(RXIFRM *frm, REBCNT n)
{
	REBHOB *hob;
	if (!FRM_IS_HANDLE(n, Handle_PuglFont)) return NULL;
	hob = RXA_HANDLE_CONTEXT(frm, n);
	if (!hob || !IS_USED_HOB(hob) || !hob->data) return NULL;
	return ((PUGLFONT*)hob->data)->glyphs ? (PUGLFONT*)hob->data : NULL;
}

/***********************************************************************
**  A string! as characters, UTF-32 in C memory - what a text node keeps,
**  so that drawing never calls into the interpreter. Through UTF-8, the
**  form the API hands strings over in. *chars is NULL for an empty text.
***********************************************************************/
static REBOOL Text_Chars(REBSER *ser, REBCNT index, u32 **chars, REBCNT *count)
{
	REBYTE *utf8 = NULL;
	int     len  = RL_GET_UTF8_STRING(ser, index, (void**)&utf8);
	u32    *out;
	REBCNT  n = 0;
	int     i = 0;

	*chars = NULL;
	*count = 0;
	if (len < 0) return FALSE;
	if (len == 0) return TRUE;
	out = (u32*)MAKE_MEM((REBCNT)len * sizeof(u32));   // never more chars than bytes
	if (!out) return FALSE;
	while (i < len) {
		REBYTE b = utf8[i];
		u32    c;
		int    more;
		if      (b < 0x80)           { c = b;        more = 0; }
		else if ((b & 0xE0) == 0xC0) { c = b & 0x1F; more = 1; }
		else if ((b & 0xF0) == 0xE0) { c = b & 0x0F; more = 2; }
		else if ((b & 0xF8) == 0xF0) { c = b & 0x07; more = 3; }
		else { i++; continue; }      // not a lead byte - skipped
		i++;
		while (more-- > 0 && i < len && (utf8[i] & 0xC0) == 0x80)
			c = (c << 6) | (utf8[i++] & 0x3F);
		out[n++] = c;
	}
	*chars = out;
	*count = n;
	return TRUE;
}

// A character as UTF-8, into `out` (up to 4 bytes); returns how many.
static REBCNT UTF8_Of(u32 c, REBYTE *out)
{
	if (c < 0x80)    { out[0] = (REBYTE)c; return 1; }
	if (c < 0x800)   { out[0] = (REBYTE)(0xC0 | (c >> 6));
	                   out[1] = (REBYTE)(0x80 | (c & 0x3F)); return 2; }
	if (c < 0x10000) { out[0] = (REBYTE)(0xE0 | (c >> 12));
	                   out[1] = (REBYTE)(0x80 | ((c >> 6) & 0x3F));
	                   out[2] = (REBYTE)(0x80 | (c & 0x3F)); return 3; }
	out[0] = (REBYTE)(0xF0 | (c >> 18));
	out[1] = (REBYTE)(0x80 | ((c >> 12) & 0x3F));
	out[2] = (REBYTE)(0x80 | ((c >> 6) & 0x3F));
	out[3] = (REBYTE)(0x80 | (c & 0x3F));
	return 4;
}

// A text node's characters replaced, and its size measured again.
static void Set_Text_Chars(PUGLNODE *n, u32 *chars, REBCNT count)
{
	if (n->chars) FREE_MEM(n->chars);
	n->chars  = chars;
	n->nchars = count;
	Pugl_Text_Size((PUGLFONT*)n->font, n->chars, n->nchars, &n->text_w, &n->text_h);
}

// A font is used by one more text node - and locked against the GC while
// any shows it - or by one less.
static void Font_Use(PUGLFONT *f, REBINT by)
{
	if (!f) return;
	if (by > 0) f->uses++;
	else if (f->uses) f->uses--;
	if (f->hob) {
		if (f->uses) f->hob->flags |=  HANDLE_CONTEXT_LOCKED;
		else         f->hob->flags &= ~HANDLE_CONTEXT_LOCKED;
	}
}

// What `add-image` and `add-group` add to: an open window, or a group
// shown in one. Gives the window and the list to append to.
static PUGLWIN* Frm_Target(RXIFRM *frm, REBCNT n, PUGLNODE **parent)
{
	PUGLWIN  *win = Frm_Window(frm, n);
	PUGLNODE *grp;

	*parent = NULL;
	if (win) return win->view ? win : NULL;
	grp = Frm_Node(frm, n);
	if (!grp || !grp->group || !grp->win) return NULL;
	*parent = grp;
	return (PUGLWIN*)grp->win;
}

// The list a node is in.
static PUGLNODE **Node_List(PUGLWIN *win, PUGLNODE *parent)
{
	return parent ? (PUGLNODE**)&parent->children : (PUGLNODE**)&win->images;
}

// Whether `n` is `from` or one of the groups `from` is in.
static REBOOL In_Chain(PUGLNODE *from, PUGLNODE *n)
{
	for (; from; from = (PUGLNODE*)from->parent) if (from == n) return TRUE;
	return FALSE;
}

// Every image in a list, groups included, to be uploaded again - each
// shared texture once, however many of them show it.
static void Mark_Dirty(PUGLWIN *win, PUGLNODE *list)
{
	for (; list; list = (PUGLNODE*)list->next) {
		if (list->group) Mark_Dirty(win, (PUGLNODE*)list->children);
		else if (list->slot && list->slot <= win->tex_size) win->tex[list->slot - 1].dirty = TRUE;
	}
}

// A list as a block of handles, in drawing order. Empty rather than none,
// so it can always be iterated.
static REBOOL Nodes_Block(PUGLNODE *list, RXIARG *arg)
{
	PUGLNODE *n;
	REBSER   *blk;
	REBCNT    count = 0;
	RXIARG    val;

	for (n = list; n; n = (PUGLNODE*)n->next) count++;
	blk = (REBSER*)RL_MAKE_BLOCK(count);
	if (!blk) return FALSE;
	count = 0;
	for (n = list; n; n = (PUGLNODE*)n->next) {
		Set_Handle_Arg(&val, n->hob);
		RL_SET_VALUE(blk, count++, val, RXT_HANDLE);
	}
	arg->series = blk;
	arg->index  = 0;
	return TRUE;
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
**  A part of an image! - [offset size], two pairs at the block's index,
**  the size not zero, all of it inside the image. Into x, y, w, h.
**
**  What follows them is not looked at, so a block of many parts can be
**  walked - `forskip parts 2 [add-image/part w img 0x0 parts]`.
***********************************************************************/
static REBOOL Read_Box(REBSER *blk, REBCNT index, REBINT max_w, REBINT max_h,
                       REBINT min_size, REBINT box[4])
{
	RXIARG off, size;

	if (RL_GET_VALUE(blk, index,     &off)  != RXT_PAIR) return FALSE;
	if (RL_GET_VALUE(blk, index + 1, &size) != RXT_PAIR) return FALSE;

	box[0] = (REBINT)off.pair.x;
	box[1] = (REBINT)off.pair.y;
	box[2] = (REBINT)size.pair.x;
	box[3] = (REBINT)size.pair.y;
	return box[0] >= 0 && box[1] >= 0 && box[2] >= min_size && box[3] >= min_size
	    && box[0] + box[2] <= max_w && box[1] + box[3] <= max_h;
}

static REBOOL Read_Part(REBSER *blk, REBCNT index, REBSER *img, REBINT part[4])
{
	return Read_Box(blk, index, (REBINT)IMG_WIDE(img), (REBINT)IMG_HIGH(img), 1, part);
}

// A box as a new [offset size] block, for the getters.
static REBOOL Box_Block(REBINT x, REBINT y, REBINT w, REBINT h, RXIARG *arg)
{
	REBSER *blk = (REBSER*)RL_MAKE_BLOCK(2);
	RXIARG  val;
	if (!blk) return FALSE;
	CLEARS(&val);
	val.pair.x = (float)x;  val.pair.y = (float)y;
	RL_SET_VALUE(blk, 0, val, RXT_PAIR);
	val.pair.x = (float)w;  val.pair.y = (float)h;
	RL_SET_VALUE(blk, 1, val, RXT_PAIR);
	arg->series = blk;
	arg->index  = 0;
	return TRUE;
}

/***********************************************************************
**  The texture slot of an image! in a window, shared by every handle
**  showing it: found, or a free one taken - the slots grow when there is
**  none. 0 if there is no memory for it.
***********************************************************************/
static REBCNT Tex_Use(PUGLWIN *win, REBSER *img)
{
	REBCNT n, free_slot = 0;

	for (n = 0; n < win->tex_size; n++) {
		PUGLTEX *t = &win->tex[n];
		if (t->refs && t->image == img) { t->refs++; return n + 1; }
		if (!t->refs && !free_slot) free_slot = n + 1;
	}
	if (!free_slot) {
		REBCNT   size  = win->tex_size ? win->tex_size * 2 : 8;
		PUGLTEX *grown = (PUGLTEX*)MAKE_MEM(size * sizeof(PUGLTEX));
		if (!grown) return 0;
		memset(grown, 0, size * sizeof(PUGLTEX));
		if (win->tex) {
			COPY_MEM(grown, win->tex, win->tex_size * sizeof(PUGLTEX));
			FREE_MEM(win->tex);
		}
		free_slot    = win->tex_size + 1;
		win->tex     = grown;
		win->tex_size = size;
	}
	win->tex[free_slot - 1].image   = img;
	win->tex[free_slot - 1].texture = 0;
	win->tex[free_slot - 1].refs    = 1;
	win->tex[free_slot - 1].dirty   = TRUE;
	return free_slot;
}

// A handle lets go of its slot; the last one retires the texture.
static void Tex_Drop(PUGLWIN *win, REBCNT slot)
{
	PUGLTEX *t;
	if (!slot || slot > win->tex_size) return;
	t = &win->tex[slot - 1];
	if (!t->refs || --t->refs) return;
	Retire_Texture(win, t->texture);
	CLEARS(t);
}

// The slot of an image handle, or NULL.
static PUGLTEX *Tex_Of(PUGLWIN *win, PUGLNODE *n)
{
	if (!n->slot || n->slot > win->tex_size) return NULL;
	return &win->tex[n->slot - 1];
}

/***********************************************************************
**  A node already out of its list - and, for a group, all that is in it.
**  The handles stay, and report none for everything from then on; they
**  let go of their image! and of the GC lock they held while shown.
***********************************************************************/
static void Release_Node(PUGLNODE *n, PUGLWIN *win)
{
	while (n->children) {
		PUGLNODE *c = (PUGLNODE*)n->children;
		n->children = c->next;
		Release_Node(c, win);
	}
	Tex_Drop(win, n->slot);
	Retire_Texture(win, n->pat_tex);   // a part's pattern copy, if it has one
	n->pat_tex = 0;
	if (n->is_text) {
		Font_Use((PUGLFONT*)n->font, -1);
		if (n->chars) FREE_MEM(n->chars);
		n->chars  = NULL;
		n->nchars = 0;
		n->font   = NULL;
	}

	n->win     = NULL;
	n->parent  = NULL;
	n->next    = NULL;
	n->image   = NULL;
	n->slot    = 0;
	if (n->hob) {
		n->hob->series = NULL;
		n->hob->flags &= ~HANDLE_CONTEXT_LOCKED;
	}
}

/***********************************************************************
**  Takes an image out of its window, or a group with all that is in it.
**
**  What is removed reports nothing, not even a `leave`. The pointer is
**  still in the groups around it, though, so the hover goes up to the
**  group it was in: those get no second `enter` at the next move, and
**  their `leave` still comes when the pointer goes.
***********************************************************************/
static void Detach_Node(PUGLNODE *n)
{
	PUGLWIN   *win = (PUGLWIN*)n->win;
	PUGLNODE **link;

	if (!win) return;
	if (In_Chain((PUGLNODE*)win->hover, n)) win->hover = n->parent;
	// Nor does it get its release: that goes to the window.
	if (In_Chain((PUGLNODE*)win->capture, n)) win->capture = NULL;
	for (link = Node_List(win, (PUGLNODE*)n->parent); *link; link = (PUGLNODE**)&(*link)->next) {
		if (*link == n) { *link = (PUGLNODE*)n->next; break; }
	}
	Release_Node(n, win);
	Window_Changed(win);
	Update_Cursor(win);   // it may have had the pointer's shape
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

/***********************************************************************
**  Units and device pixels.
**
**  Pugl works in device pixels throughout - sizes, positions, pointer
**  coordinates; Rebol, as in Rebol-GUI, in units: pixels / scale, the
**  scale being the screen's, as pugl says now (2.0 on a Retina display).
**  So everything is converted where it crosses: sizes and positions at
**  the pugl calls, pointer coordinates as events are converted, and the
**  drawing is scaled as a whole (Pugl_Draw).
***********************************************************************/
// The screen's scale, as pugl says now.
static double Screen_Scale(PuglView *view)
{
	double k = view ? puglGetScaleFactor(view) : 1.0;
	return k > 0.0 ? k : 1.0;
}

// The window's: the one set with `window/scale:`, or else its screen's.
static double Scale_Of(PUGLWIN *pv)
{
	return pv->scale > 0.0 ? pv->scale : Screen_Scale((PuglView*)pv->view);
}

// A size or a position in units - to the nearest.
static REBINT To_Units(double px, double k)    { return (REBINT)floor(px / k + 0.5); }
// ... and back, in device pixels.
static REBINT To_Pixels(double units, double k) { return (REBINT)floor(units * k + 0.5); }

static void Remember_Frame(PUGLWIN *pv)
{
	PuglView *view = (PuglView*)pv->view;
	PuglPoint p = puglGetPositionHint(view, PUGL_CURRENT_POSITION);
	PuglArea  a = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
	double    k = Scale_Of(pv);
	pv->x = p.x; pv->y = p.y;
	pv->w = a.width; pv->h = a.height;
	pv->ux = To_Units(p.x, k);     pv->uy = To_Units(p.y, k);
	pv->uw = To_Units(a.width, k); pv->uh = To_Units(a.height, k);
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
	pv->hover   = NULL;
	pv->capture = NULL;
	while (pv->images) Detach_Node((PUGLNODE*)pv->images);
	if (pv->tex) FREE_MEM(pv->tex);
	pv->tex = NULL;
	pv->tex_size = 0;
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
**  The topmost visible image under a point of a list, or NULL - the
**  point in the units of the list's owner (the window, or a group).
**
**  Each node takes the point back through its own transform, into its
**  own units, where its box is simply 0,0 to its size - so a turned or
**  scaled image is hit by its real shape. In drawing order, so the last
**  match is the one on top; a group is searched where it is in the list,
**  only while it is visible, and only inside its size when it clips. The
**  right and bottom edges are outside, so images laid edge to edge never
**  both claim a point. Opacity does not matter: a faded image is there.
***********************************************************************/
static PUGLNODE *Image_At(PUGLNODE *list, double x, double y)
{
	PUGLNODE *n, *hit, *top = NULL;
	for (n = list; n; n = (PUGLNODE*)n->next) {
		PUGLXFORM m;
		double    lx = x, ly = y, w, h;

		if (!n->visible) continue;
		Pugl_Node_Xform(n, &m);
		if (!Pugl_Xform_Undo(&m, &lx, &ly)) continue;   // scaled to nothing

		if (n->group) {
			// What a group clips away is not there to be hit either.
			if (n->w > 0 && (lx < 0 || lx >= n->w)) continue;
			if (n->h > 0 && (ly < 0 || ly >= n->h)) continue;
			hit = Image_At((PUGLNODE*)n->children, lx, ly);
			if (hit) top = hit;
			continue;
		}
		if (n->is_text) {
			// The box its text takes.
			w = n->text_w;
			h = n->text_h;
		} else {
			REBINT dw, dh;
			if (!n->image) continue;
			Pugl_Drawn_Size(n, &dw, &dh);
			w = dw;
			h = dh;
		}
		if (lx >= 0 && ly >= 0 && lx < w && ly < h) top = n;
	}
	return top;
}

// The first node from `n` up - itself, then the groups it is in - which
// tracks the pointer, or NULL.
static PUGLNODE *Tracked_In(PUGLNODE *n)
{
	for (; n; n = (PUGLNODE*)n->parent) if (n->track && n->hob) return n;
	return NULL;
}

// The handle an event comes from: the node, or else the window.
static REBHOB *Source_Of(PUGLWIN *win, PUGLNODE *n)
{
	return (n && n->hob) ? n->hob : win->hob;
}

/***********************************************************************
**  The cursor to show: the first of the node under the pointer - or,
**  during a drag, the one which took the press - and the groups around
**  it which has one; else the window's. Set on the view only when it
**  changes, and its result not looked at: a system which cannot set one
**  (X11 without Xcursor) keeps what it has.
***********************************************************************/
static PuglCursor Cursor_Of_Word(REBCNT w)
{
	switch (w) {
	case W_PUGL_CURSOR_CARET:              return PUGL_CURSOR_CARET;
	case W_PUGL_CURSOR_CROSSHAIR:          return PUGL_CURSOR_CROSSHAIR;
	case W_PUGL_CURSOR_HAND:               return PUGL_CURSOR_HAND;
	case W_PUGL_CURSOR_NO:                 return PUGL_CURSOR_NO;
	case W_PUGL_CURSOR_LEFT_RIGHT:         return PUGL_CURSOR_LEFT_RIGHT;
	case W_PUGL_CURSOR_UP_DOWN:            return PUGL_CURSOR_UP_DOWN;
	case W_PUGL_CURSOR_UP_LEFT_DOWN_RIGHT: return PUGL_CURSOR_UP_LEFT_DOWN_RIGHT;
	case W_PUGL_CURSOR_UP_RIGHT_DOWN_LEFT: return PUGL_CURSOR_UP_RIGHT_DOWN_LEFT;
	case W_PUGL_CURSOR_ALL_SCROLL:         return PUGL_CURSOR_ALL_SCROLL;
	}
	return PUGL_CURSOR_ARROW;
}

static void Update_Cursor(PUGLWIN *win)
{
	PUGLNODE *n = (PUGLNODE*)(win->capture ? win->capture : win->hover);
	REBCNT    w = 0;

	if (!win->view) return;
	for (; n && !w; n = (PUGLNODE*)n->parent) w = n->cursor;
	if (!w) w = win->cursor ? win->cursor : W_PUGL_CURSOR_ARROW;
	if (w == win->cursor_now) return;
	win->cursor_now = w;
	puglSetCursor((PuglView*)win->view, Cursor_Of_Word(w));
}

// A cursor word given to a setter: its W_PUGL_CURSOR_*, or 0 if none.
static REBCNT Cursor_Word(REBCNT *type, RXIARG *arg)
{
	if (*type != RXT_WORD) return 0;
	return RL_FIND_WORD(Pugl_cursor_words, (REBCNT)arg->int32a);
}

// `enter` for the groups `n` is in and then `n` itself - outermost first -
// leaving out those the pointer was in already.
static void Enter_Chain(REBSER *blk, REBCNT *at, PUGLNODE *n, PUGLNODE *was,
                        REBINT x, REBINT y)
{
	if (!n || In_Chain(was, n)) return;   // and so are all around it
	Enter_Chain(blk, at, (PUGLNODE*)n->parent, was, x, y);
	if (n->track && n->hob)
		Append_Event_Of(blk, at, n->hob, EVT_ENTER, HAS_XY, XY_DATA(x, y));
}

/***********************************************************************
**  `enter` and `leave` per image and group, for those with `track?` on.
**
**  Worked out from the pointer's position whenever a pointer event is
**  converted: when the topmost image under it changes, the old one gets
**  `leave` where it was last seen over it, and the new one `enter` - in
**  that order, and before the window's own event, the same order
**  Rebol-GUI reports for widgets. `inside` FALSE is the pointer leaving
**  the window, which leaves whatever it was over.
**
**  A group is over while one of its images is: going from one of its
**  images to another reports nothing for it. Leaves go innermost first,
**  the image before its groups; enters outermost first.
**
**  Hover is kept for every image, tracked or not - `hover?` reads it,
**  and an untracked image on top still covers a tracked one below.
**  It is as of the last event: an image moved under a pointer which
**  stays still is not entered until the pointer moves.
***********************************************************************/
static void Hover_To(REBSER *blk, REBCNT *at, PUGLWIN *win,
                     double fx, double fy, REBOOL inside)
{
	// Hit at the unit fraction - finer than the reported whole units, so
	// on a Retina display an edge is found to its device pixel.
	PUGLNODE *now = inside ? Image_At((PUGLNODE*)win->images, fx, fy) : NULL;
	PUGLNODE *was = (PUGLNODE*)win->hover;
	PUGLNODE *n;
	REBINT    x = (REBINT)floor(fx), y = (REBINT)floor(fy);

	if (now != was) {
		for (n = was; n && !In_Chain(now, n); n = (PUGLNODE*)n->parent) {
			if (n->track && n->hob)
				Append_Event_Of(blk, at, n->hob, EVT_LEAVE, HAS_XY,
				                XY_DATA(win->hover_x, win->hover_y));
		}
		Enter_Chain(blk, at, now, was, x, y);
		win->hover = now;
	}
	win->hover_x = x;
	win->hover_y = y;
}

/***********************************************************************
**  A key with a name in system/catalog/event-keys: the EVK_* number,
**  or 0. The same keys, and the same names, as Rebol-GUI reports - so
**  a handler works with either extension.
**
**  Escape, Backspace and Delete are named although Pugl gives them a
**  codepoint (they make no character in a text); Shift-Tab is `backtab`.
**  Tab and Enter stay characters, #"^-" and #"^M". The keypad's own
**  navigation keys - Num Lock off - are the main ones'.
***********************************************************************/
static REBCNT Named_Key_Of(u32 key, PuglMods mods)
{
	if (key >= PUGL_KEY_F1 && key <= PUGL_KEY_F12) return EVK_F1 + (REBCNT)(key - PUGL_KEY_F1);
	switch (key) {
	case PUGL_KEY_PAGE_UP:   case PUGL_KEY_PAD_PAGE_UP:   return EVK_PAGE_UP;
	case PUGL_KEY_PAGE_DOWN: case PUGL_KEY_PAD_PAGE_DOWN: return EVK_PAGE_DOWN;
	case PUGL_KEY_END:       case PUGL_KEY_PAD_END:       return EVK_END;
	case PUGL_KEY_HOME:      case PUGL_KEY_PAD_HOME:      return EVK_HOME;
	case PUGL_KEY_LEFT:      case PUGL_KEY_PAD_LEFT:      return EVK_LEFT;
	case PUGL_KEY_UP:        case PUGL_KEY_PAD_UP:        return EVK_UP;
	case PUGL_KEY_RIGHT:     case PUGL_KEY_PAD_RIGHT:     return EVK_RIGHT;
	case PUGL_KEY_DOWN:      case PUGL_KEY_PAD_DOWN:      return EVK_DOWN;
	case PUGL_KEY_INSERT:    case PUGL_KEY_PAD_INSERT:    return EVK_INSERT;
	case PUGL_KEY_DELETE:    case PUGL_KEY_PAD_DELETE:    return EVK_DELETE;
	case PUGL_KEY_PAD_CLEAR:                              return EVK_BEGIN;   // keypad 5, Num Lock off
	case PUGL_KEY_ESCAPE:    return EVK_ESCAPE;
	case PUGL_KEY_BACKSPACE: return EVK_BACKSPACE;
	case PUGL_KEY_PAUSE:     return EVK_PAUSE;
	case PUGL_KEY_CAPS_LOCK: return EVK_CAPITAL;
	case PUGL_KEY_SHIFT_L:   case PUGL_KEY_SHIFT_R: return EVK_SHIFT;
	case PUGL_KEY_CTRL_L:    case PUGL_KEY_CTRL_R:  return EVK_CONTROL;
	case PUGL_KEY_ALT_L:     case PUGL_KEY_ALT_R:   return EVK_ALT;
	case PUGL_KEY_TAB:       return (mods & PUGL_MOD_SHIFT) ? EVK_BACKTAB : 0;
	}
	return 0;
}

/***********************************************************************
**  The character of a key which has no name: its codepoint - and for
**  the keypad, the digit or operator printed on it. 0 for a key with
**  neither (Print Screen, Menu, Num Lock, Scroll Lock, Super...), which
**  is not reported, as in Rebol-GUI.
***********************************************************************/
static u32 Char_Of_Key(u32 key)
{
	if (key >= PUGL_KEY_PAD_0 && key <= PUGL_KEY_PAD_9) return '0' + (key - PUGL_KEY_PAD_0);
	switch (key) {
	case PUGL_KEY_PAD_ENTER:     return '\r';
	case PUGL_KEY_PAD_EQUAL:     return '=';
	case PUGL_KEY_PAD_MULTIPLY:  return '*';
	case PUGL_KEY_PAD_ADD:       return '+';
	case PUGL_KEY_PAD_SEPARATOR: return ',';
	case PUGL_KEY_PAD_SUBTRACT:  return '-';
	case PUGL_KEY_PAD_DECIMAL:   return '.';
	case PUGL_KEY_PAD_DIVIDE:    return '/';
	}
	if (key == 0 || (key >= 0xE000 && key <= 0xF8FF)) return 0;
	return key;
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
	double           k  = Scale_Of(pv);   // device pixels per unit

	// A pointer coordinate in units: the fraction for the hit test, and the
	// whole unit it is in for the event.
#define U(v)  ((double)(v) / k)
#define UI(v) ((REBINT)floor((double)(v) / k))

	switch (e->type) {
	case PUGL_BUTTON_PRESS:
	case PUGL_BUTTON_RELEASE: {
		// Primary, secondary, middle - nothing above is reported yet.
		REBCNT held = pv->buttons;
		if (e->button.button > 2) break;
		if (e->type == PUGL_BUTTON_PRESS) pv->buttons |=  (1u << e->button.button);
		else                              pv->buttons &= ~(1u << e->button.button);
		Hover_To(blk, at, pv, U(e->button.x), U(e->button.y), TRUE);
		// The first press takes the pointer for what is tracked under it;
		// the others, and every release, go where that one went.
		if (e->type == PUGL_BUTTON_PRESS && !held)
			pv->capture = Tracked_In((PUGLNODE*)pv->hover);
		Append_Event_Of(blk, at, Source_Of(pv, (PUGLNODE*)pv->capture),
			(e->type == PUGL_BUTTON_PRESS ? Down_Types : Up_Types)[e->button.button],
			HAS_XY | Modifier_Bits(e->button.state),
			XY_DATA(UI(e->button.x), UI(e->button.y)));
		if (!pv->buttons) pv->capture = NULL;
		break; }

	case PUGL_MOTION:
		// macOS sends the key window every move, the pointer inside it or
		// not (pugl sets acceptsMouseMovedEvents); Windows and X11 send
		// those only while a button is held - a drag going outside. Made
		// the same here: outside, and nothing held, is not reported.
		if (!pv->buttons
		 && (e->motion.x < 0 || e->motion.y < 0
		  || e->motion.x >= pv->w || e->motion.y >= pv->h)) break;
		Hover_To(blk, at, pv, U(e->motion.x), U(e->motion.y), TRUE);
		// A drag comes from what took the press; any other move from the
		// window - hovering is `enter` and `leave`.
		Append_Event_Of(blk, at, Source_Of(pv, pv->buttons ? (PUGLNODE*)pv->capture : NULL),
			EVT_MOVE,
			HAS_XY | Modifier_Bits(e->motion.state),
			XY_DATA(UI(e->motion.x), UI(e->motion.y)));
		break;

	// The window's own enter goes before an image's, and its leave after:
	// the pointer is inside the window whenever it is over an image.
	case PUGL_POINTER_IN:
		Append_Event(blk, at, pv, EVT_ENTER,
			HAS_XY, XY_DATA(UI(e->crossing.x), UI(e->crossing.y)));
		Hover_To(blk, at, pv, U(e->crossing.x), U(e->crossing.y), TRUE);
		break;

	case PUGL_POINTER_OUT:
		Hover_To(blk, at, pv, U(e->crossing.x), U(e->crossing.y), FALSE);
		Append_Event(blk, at, pv, EVT_LEAVE,
			HAS_XY, XY_DATA(UI(e->crossing.x), UI(e->crossing.y)));
		break;

	case PUGL_SCROLL: {
		// Vertical only, in whole lines, positive away from the user.
		// A smooth scroll smaller than a line is dropped for now.
		REBINT lines = (REBINT)(e->scroll.dy < 0 ? e->scroll.dy - 0.5 : e->scroll.dy + 0.5);
		if (lines == 0) break;
		// What is tracked under the pointer scrolls - or, during a drag,
		// what took the press.
		Append_Event_Of(blk, at,
			Source_Of(pv, pv->capture ? (PUGLNODE*)pv->capture : Tracked_In((PUGLNODE*)pv->hover)),
			EVT_SCROLL_LINE, HAS_CODE, (u32)lines);
		break; }

	case PUGL_KEY_PRESS:
	case PUGL_KEY_RELEASE: {
		// Pugl's key is the UNSHIFTED codepoint, or for a key without one
		// (F1, arrows...) a code of its own in the Private Use Area. Those
		// are the named keys; the rest is a character.
		REBOOL up    = (e->type == PUGL_KEY_RELEASE);
		REBCNT named = Named_Key_Of(e->key.key, e->key.state);
		u32    code;
		if (named) {
			Append_Event(blk, at, pv, up ? EVT_NAMED_KEY_UP : EVT_NAMED_KEY,
				HAS_CODE | Modifier_Bits(e->key.state), (u32)named);
			break;
		}
		code = Char_Of_Key(e->key.key);
		if (!code) break;   // no character, nor a name the core has
		Append_Event(blk, at, pv, up ? EVT_KEY_UP : EVT_KEY,
			HAS_CODE | Modifier_Bits(e->key.state), code);
		break; }

	case PUGL_FOCUS_IN:
	case PUGL_FOCUS_OUT:
		// A release can happen where this window does not see it - over
		// another one which took the focus - so nothing is held any more.
		if (e->type == PUGL_FOCUS_OUT) { pv->buttons = 0; pv->capture = NULL; }
		Append_Event(blk, at, pv,
			e->type == PUGL_FOCUS_IN ? EVT_ACTIVE : EVT_INACTIVE, HAS_XY, 0);
		break;

	case PUGL_CLOSE:
		// Only the request - closing is the script's to do.
		Append_Event(blk, at, pv, EVT_CLOSE, HAS_XY, 0);
		break;

	case PUGL_CONFIGURE: {
		const PuglConfigureEvent *c = &e->configure;
		// In units: moved to a screen of another scale, the same window
		// is another size in units - which is a `resize` too.
		REBINT uw = To_Units(c->width, k),  uh = To_Units(c->height, k);
		REBINT ux = To_Units(c->x, k),      uy = To_Units(c->y, k);
		pv->x = c->x;     pv->y = c->y;
		pv->w = c->width; pv->h = c->height;
		if (uw != pv->uw || uh != pv->uh) {
			pv->uw = uw;
			pv->uh = uh;
			Append_Event(blk, at, pv, EVT_RESIZE, HAS_XY, XY_DATA(uw, uh));
		}
		if (ux != pv->ux || uy != pv->uy) {
			pv->ux = ux;
			pv->uy = uy;
			Append_Event(blk, at, pv, EVT_OFFSET, HAS_XY, XY_DATA(ux, uy));
		}
		break; }

	default:
		// PUGL_TEXT and the rest are queued but not reported yet.
		break;
	}

	// What is under the pointer - or holds it - may have changed.
	switch (e->type) {
	case PUGL_BUTTON_PRESS: case PUGL_BUTTON_RELEASE: case PUGL_MOTION:
	case PUGL_POINTER_IN:   case PUGL_POINTER_OUT:    case PUGL_FOCUS_OUT:
		Update_Cursor(pv);
		break;
	default:
		break;
	}
#undef U
#undef UI
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
	double       k;

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
	// In units, so in device pixels at the scale of the screen it will be
	// on - as well as pugl can tell before it is there; checked again once
	// it is, below.
	k = Screen_Scale(view);
	puglSetSizeHint(view, PUGL_DEFAULT_SIZE, (unsigned)To_Pixels(w, k), (unsigned)To_Pixels(h, k));
	puglSetViewHint(view, PUGL_RESIZABLE, RXA_REF(frm, 7) ? PUGL_FALSE : PUGL_TRUE);

	if (RXA_REF(frm, 2)) Set_Window_Title(view, RXA_SERIES(frm, 3), RXA_INDEX(frm, 3));
	if (RXA_REF(frm, 4)) {
		puglSetPositionHint(view, PUGL_DEFAULT_POSITION,
			To_Pixels(RXA_PAIR(frm, 5).x, k), To_Pixels(RXA_PAIR(frm, 5).y, k));
	}

	if (puglRealize(view) != PUGL_SUCCESS) {
		puglSetHandle(view, NULL);
		puglFreeView(view);
		Pugl_Purge_Events(pv);
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_WINDOW);
	}

	// Realized on a screen of another scale than guessed: made the size
	// asked for, in units, there.
	if (Screen_Scale(view) != k) {
		k = Screen_Scale(view);
		puglSetSizeHint(view, PUGL_CURRENT_SIZE, (unsigned)To_Pixels(w, k), (unsigned)To_Pixels(h, k));
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
	// event several: leaves and enters of images and the groups around
	// them, then its own. The block grows if this is not enough.
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
**  Uploads an image's pixels again and shows them - or, given a window
**  or a group, every image in it. Needed after drawing into an image:
**  the window only holds a reference, and has no way of knowing the
**  pixels changed. One main loop iteration is run, so the new pixels are
**  normally on screen when this returns.
***********************************************************************/
COMMAND cmd_pugl_redraw(RXIFRM *frm, void *ctx)
{
	PUGLNODE *n = Frm_Node(frm, 1);
	PUGLWIN  *win;

	if (n) {
		if (!n->win) RETURN_ERROR(ERR_INVALID_IMAGE);
		win = (PUGLWIN*)n->win;
		// An image's texture is its image!'s, so every other handle showing
		// that image! is shown again too - they show the same pixels.
		if (n->group) Mark_Dirty(win, (PUGLNODE*)n->children);
		else if (Tex_Of(win, n)) Tex_Of(win, n)->dirty = TRUE;
	} else {
		win = Frm_Window(frm, 1);
		if (!win || !win->view) RETURN_ERROR(ERR_INVALID_HANDLE);
		Mark_Dirty(win, (PUGLNODE*)win->images);
	}
	Window_Changed(win);
	puglUpdate(Pugl_World, 0.0);
	return RXR_TRUE;
}


/***********************************************************************
**  Moves a node to place `at` (1-based) in its own list - past the end
**  is the end, so the top.
***********************************************************************/
static void Move_Node(PUGLNODE *n, REBINT at)
{
	PUGLNODE **list = Node_List((PUGLWIN*)n->win, (PUGLNODE*)n->parent);
	PUGLNODE **link;

	for (link = list; *link; link = (PUGLNODE**)&(*link)->next) {
		if (*link == n) { *link = (PUGLNODE*)n->next; break; }
	}
	for (link = list; *link && at > 1; link = (PUGLNODE**)&(*link)->next) at--;
	n->next = *link;
	*link = n;
}

/***********************************************************************
**  Appends a new node to the end of its list - drawn above everything
**  added there before it - and locks its handle: the list points at it.
***********************************************************************/
static void Link_Node(PUGLWIN *win, PUGLNODE *parent, PUGLNODE *n)
{
	PUGLNODE **link;

	n->win     = win;
	n->parent  = parent;
	n->visible = TRUE;
	n->sx      = 1.0;   // not turned, not scaled, opaque
	n->sy      = 1.0;
	n->opacity = 1.0;
	for (link = Node_List(win, parent); *link; link = (PUGLNODE**)&(*link)->next);
	*link = n;
	n->hob->flags |= HANDLE_CONTEXT_LOCKED;
}

/***********************************************************************
**  add-image target [handle!] image [image!] offset [pair!] /size sz
**
**  Frame: 1 target, 2 image, 3 offset, 4 /size, 5 sz
**
**  The window keeps a REFERENCE to the image, not a copy: drawing into
**  that same image and calling `redraw` is how it is animated. Added at
**  the end of the window's or the group's list, so it is drawn above
**  everything added there before it.
***********************************************************************/
COMMAND cmd_pugl_add_image(RXIFRM *frm, void *ctx)
{
	PUGLNODE  *parent;
	PUGLWIN   *win = Frm_Target(frm, 1, &parent);
	REBSER    *img = (REBSER*)RXA_IMAGE(frm, 2);
	REBHOB    *hob;
	REBSER    *slots;
	PUGLNODE  *im;
	REBINT     w = 0, h = 0;
	REBINT     part[4] = { 0, 0, 0, 0 };

	if (!win) RETURN_ERROR(ERR_INVALID_TARGET);
	if (!img || IMG_WIDE(img) == 0 || IMG_HIGH(img) == 0) RETURN_ERROR(ERR_BAD_IMAGE);
	if (RXA_REF(frm, 4)) {
		w = (REBINT)RXA_PAIR(frm, 5).x;
		h = (REBINT)RXA_PAIR(frm, 5).y;
		if (w < 0 || h < 0 || w > 10000 || h > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	}
	if (RXA_REF(frm, 6) && !Read_Part(RXA_SERIES(frm, 7), RXA_INDEX(frm, 7), img, part))
		RETURN_ERROR(ERR_BAD_PART);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglImage);
	if (!hob) RETURN_ERROR(ERR_NO_HANDLE);
	im = (PUGLNODE*)hob->data;
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

	im->slot = Tex_Use(win, img);
	if (!im->slot) {
		hob->series = NULL;
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_HANDLE);
	}
	im->image   = img;
	im->x       = (REBINT)RXA_PAIR(frm, 3).x;
	im->y       = (REBINT)RXA_PAIR(frm, 3).y;
	im->w       = w;
	im->h       = h;
	im->part_x  = part[0];
	im->part_y  = part[1];
	im->part_w  = part[2];
	im->part_h  = part[3];
	Link_Node(win, parent, im);
	Window_Changed(win);

	RETURN_HANDLE(hob);
}


/***********************************************************************
**  image-at window [handle!] point [pair!]
**
**  The very hit test the pointer events use - transforms, clipping and
**  visibility included; opacity and `track?` do not matter.
***********************************************************************/
COMMAND cmd_pugl_image_at(RXIFRM *frm, void *ctx)
{
	PUGLWIN  *win = Frm_Window(frm, 1);
	PUGLNODE *hit;

	if (!win || !win->view) RETURN_ERROR(ERR_INVALID_HANDLE);
	hit = Image_At((PUGLNODE*)win->images,
	               (double)RXA_PAIR(frm, 2).x, (double)RXA_PAIR(frm, 2).y);
	if (!hit || !hit->hob) return RXR_NONE;
	RETURN_HANDLE(hit->hob);
}


/***********************************************************************
**  A glyph's [offset size bearing advance] - the first four values of a
**  block at its index - inside an atlas of iw by ih. A size of 0x0 has
**  no pixels (a space): only its advance counts.
***********************************************************************/
static REBOOL Read_Glyph(REBSER *blk, REBCNT index, REBINT iw, REBINT ih, PUGLGLYPH *g)
{
	RXIARG off, size, bear, adv;
	int    t;

	if (RL_GET_VALUE(blk, index,     &off)  != RXT_PAIR) return FALSE;
	if (RL_GET_VALUE(blk, index + 1, &size) != RXT_PAIR) return FALSE;
	if (RL_GET_VALUE(blk, index + 2, &bear) != RXT_PAIR) return FALSE;
	t = RL_GET_VALUE(blk, index + 3, &adv);
	g->x  = (REBINT)off.pair.x;   g->y  = (REBINT)off.pair.y;
	g->w  = (REBINT)size.pair.x;  g->h  = (REBINT)size.pair.y;
	g->bx = (REBINT)bear.pair.x;  g->by = (REBINT)bear.pair.y;
	if      (t == RXT_INTEGER) g->advance = (REBINT)adv.int64;
	else if (t == RXT_DECIMAL) g->advance = (REBINT)adv.dec64;
	else return FALSE;
	if (g->w == 0 || g->h == 0) { g->w = g->h = 0; return TRUE; }
	return g->x >= 0 && g->y >= 0 && g->w > 0 && g->h > 0
	    && g->x + g->w <= iw && g->y + g->h <= ih;
}

static int Glyph_Order(const void *a, const void *b)
{
	u32 ca = ((const PUGLGLYPH*)a)->code, cb = ((const PUGLGLYPH*)b)->code;
	return ca < cb ? -1 : ca > cb;
}

/***********************************************************************
**  font-from atlas [image!] glyphs [block!] line-height [integer!]
**            fallback [block! none!]
**
**  Frame: 1 atlas, 2 glyphs, 3 line-height, 4 fallback
**
**  `make-font` calls it, with the glyphs of a map! as a block. They are
**  read once into a C table, sorted by character for a binary search -
**  a text is drawn and measured from it without the interpreter.
***********************************************************************/
COMMAND cmd_pugl_font_from(RXIFRM *frm, void *ctx)
{
	REBSER    *img = (REBSER*)RXA_IMAGE(frm, 1);
	REBSER    *blk = RXA_SERIES(frm, 2);
	REBCNT     at  = RXA_INDEX(frm, 2);
	REBINT     iw, ih;
	REBCNT     n = 0, i;
	PUGLGLYPH *glyphs;
	PUGLGLYPH  fallback;
	REBOOL     has_fallback = FALSE;
	REBHOB    *hob;
	REBSER    *slots;
	PUGLFONT  *f;
	RXIARG     key, val;

	if (!img || !(iw = (REBINT)IMG_WIDE(img)) || !(ih = (REBINT)IMG_HIGH(img)))
		RETURN_ERROR(ERR_BAD_IMAGE);
	if (RXA_INT64(frm, 3) < 1 || RXA_INT64(frm, 3) > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	if (RXA_TYPE(frm, 4) == RXT_BLOCK) {
		CLEARS(&fallback);
		if (!Read_Glyph(RXA_SERIES(frm, 4), RXA_INDEX(frm, 4), iw, ih, &fallback))
			RETURN_ERROR(ERR_BAD_GLYPH);
		has_fallback = TRUE;
	}

	// char [glyph] pairs: as many glyphs as half the values, at most.
	for (i = at; RL_GET_VALUE(blk, i, &key); i += 2) n++;
	glyphs = (PUGLGLYPH*)MAKE_MEM((n ? n : 1) * sizeof(PUGLGLYPH));
	if (!glyphs) RETURN_ERROR(ERR_NO_HANDLE);
	n = 0;
	for (i = at; RL_GET_VALUE(blk, i, &key); i += 2) {
		if (RL_GET_VALUE(blk, i, &key) != RXT_CHAR
		 || RL_GET_VALUE(blk, i + 1, &val) != RXT_BLOCK
		 || !Read_Glyph((REBSER*)val.series, val.index, iw, ih, &glyphs[n])) {
			FREE_MEM(glyphs);
			RETURN_ERROR(ERR_BAD_GLYPH);
		}
		glyphs[n++].code = (u32)key.int32a;
	}
	qsort(glyphs, n, sizeof(PUGLGLYPH), Glyph_Order);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglFont);
	if (!hob) { FREE_MEM(glyphs); RETURN_ERROR(ERR_NO_HANDLE); }
	f = (PUGLFONT*)hob->data;
	CLEARS(f);
	f->hob = hob;

	// The atlas, as it came, in the slot the GC marks.
	slots = (REBSER*)RL_MAKE_BLOCK(1);
	if (!slots) {
		FREE_MEM(glyphs);
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_HANDLE);
	}
	hob->series = slots;
	RL_SET_VALUE(slots, 0, RXA_ARG(frm, 1), RXT_IMAGE);

	f->image        = img;
	f->glyphs       = glyphs;
	f->count        = n;
	f->line_height  = (REBINT)RXA_INT64(frm, 3);
	f->has_fallback = has_fallback;
	if (has_fallback) f->fallback = fallback;

	RETURN_HANDLE(hob);
}

/***********************************************************************
**  add-text target [handle!] font [handle!] text [string!] offset [pair!]
**
**  Frame: 1 target, 2 font, 3 text, 4 offset
**
**  One node, its glyphs drawn from the font's atlas - whose texture it
**  shares with anything else showing the atlas.
***********************************************************************/
COMMAND cmd_pugl_add_text(RXIFRM *frm, void *ctx)
{
	PUGLNODE *parent;
	PUGLWIN  *win = Frm_Target(frm, 1, &parent);
	PUGLFONT *f   = Frm_Font(frm, 2);
	REBHOB   *hob;
	REBSER   *slots;
	PUGLNODE *t;
	u32      *chars;
	REBCNT    count;

	if (!win) RETURN_ERROR(ERR_INVALID_TARGET);
	if (!f)   RETURN_ERROR(ERR_INVALID_FONT);
	if (!Text_Chars(RXA_SERIES(frm, 3), RXA_INDEX(frm, 3), &chars, &count))
		RETURN_ERROR(ERR_BAD_TEXT);

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglText);
	if (!hob) { if (chars) FREE_MEM(chars); RETURN_ERROR(ERR_NO_HANDLE); }
	t = (PUGLNODE*)hob->data;
	CLEARS(t);
	t->hob = hob;

	// The font's handle, in the slot the GC marks - which keeps it alive
	// while the text shows it.
	slots = (REBSER*)RL_MAKE_BLOCK(1);
	if (!slots) {
		if (chars) FREE_MEM(chars);
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_HANDLE);
	}
	hob->series = slots;
	RL_SET_VALUE(slots, 0, RXA_ARG(frm, 2), RXT_HANDLE);

	t->slot = Tex_Use(win, (REBSER*)f->image);
	if (!t->slot) {
		if (chars) FREE_MEM(chars);
		hob->series = NULL;
		RL_FREE_HANDLE_CONTEXT(hob);
		RETURN_ERROR(ERR_NO_HANDLE);
	}
	t->is_text = TRUE;
	t->font    = f;
	t->x       = (REBINT)RXA_PAIR(frm, 4).x;
	t->y       = (REBINT)RXA_PAIR(frm, 4).y;
	Set_Text_Chars(t, chars, count);
	Font_Use(f, +1);
	Link_Node(win, parent, t);
	Window_Changed(win);

	RETURN_HANDLE(hob);
}

/***********************************************************************
**  text-size font [handle!] text [string!]
***********************************************************************/
COMMAND cmd_pugl_text_size(RXIFRM *frm, void *ctx)
{
	PUGLFONT *f = Frm_Font(frm, 1);
	u32      *chars;
	REBCNT    count;
	REBINT    w, h;

	if (!f) RETURN_ERROR(ERR_INVALID_FONT);
	if (!Text_Chars(RXA_SERIES(frm, 2), RXA_INDEX(frm, 2), &chars, &count))
		RETURN_ERROR(ERR_BAD_TEXT);
	Pugl_Text_Size(f, chars, count, &w, &h);
	if (chars) FREE_MEM(chars);

	RXA_PAIR(frm, 1).x = (float)w;
	RXA_PAIR(frm, 1).y = (float)h;
	RXA_TYPE(frm, 1)   = RXT_PAIR;
	return RXR_VALUE;
}


// Removing an image which is no longer shown is not an error - its window
// may have been closed, or its group removed, which removes everything in
// it. A group goes with all that is in it.
COMMAND cmd_pugl_remove_image(RXIFRM *frm, void *ctx)
{
	PUGLNODE *n = Frm_Node(frm, 1);
	if (!n) RETURN_ERROR(ERR_INVALID_IMAGE);
	Detach_Node(n);
	return RXR_TRUE;
}


/***********************************************************************
**  add-group target [handle!] offset [pair!] /size sz
**
**  Frame: 1 target, 2 offset, 3 /size, 4 sz
**
**  An empty group, at the end of the window's or the group's list. What
**  is added to it later is drawn where the group is in that list - and,
**  with a size, only inside it.
***********************************************************************/
COMMAND cmd_pugl_add_group(RXIFRM *frm, void *ctx)
{
	PUGLNODE *parent;
	PUGLWIN  *win = Frm_Target(frm, 1, &parent);
	REBHOB   *hob;
	PUGLNODE *grp;
	REBINT    w = 0, h = 0;

	if (!win) RETURN_ERROR(ERR_INVALID_TARGET);
	if (RXA_REF(frm, 3)) {
		w = (REBINT)RXA_PAIR(frm, 4).x;
		h = (REBINT)RXA_PAIR(frm, 4).y;
		if (w < 0 || h < 0 || w > 10000 || h > 10000) RETURN_ERROR(ERR_BAD_SIZE);
	}

	hob = RL_MAKE_HANDLE_CONTEXT(Handle_PuglGroup);
	if (!hob) RETURN_ERROR(ERR_NO_HANDLE);
	grp = (PUGLNODE*)hob->data;
	CLEARS(grp);
	grp->hob   = hob;
	grp->group = TRUE;
	grp->x     = (REBINT)RXA_PAIR(frm, 2).x;
	grp->y     = (REBINT)RXA_PAIR(frm, 2).y;
	grp->w     = w;
	grp->h     = h;
	Link_Node(win, parent, grp);
	// Nothing to draw yet - only what is added to it is.

	RETURN_HANDLE(hob);
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
		double   k = Scale_Of(pv);
		arg->pair.x = (float)To_Units(a.width, k);
		arg->pair.y = (float)To_Units(a.height, k);
		*type = RXT_PAIR;
		break; }

	case W_PUGL_ARG_OFFSET: {
		PuglPoint p = puglGetPositionHint(view, PUGL_CURRENT_POSITION);
		double    k = Scale_Of(pv);
		arg->pair.x = (float)To_Units(p.x, k);
		arg->pair.y = (float)To_Units(p.y, k);
		*type = RXT_PAIR;
		break; }

	case W_PUGL_ARG_SCALE:
		arg->dec64 = Scale_Of(pv);
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

	case W_PUGL_ARG_TEXTURES: {
		REBCNT n, count = 0;
		for (n = 0; n < pv->tex_size; n++) if (pv->tex[n].refs) count++;
		arg->int64 = count;
		*type = RXT_INTEGER;
		break; }

	// A new block each time, in drawing order - its top level only.
	case W_PUGL_ARG_IMAGES:
		*type = Nodes_Block((PUGLNODE*)pv->images, arg) ? RXT_BLOCK : RXT_NONE;
		break;

	case W_PUGL_ARG_CURSOR:
		arg->int32a = (int)Pugl_cursor_words[pv->cursor ? pv->cursor : W_PUGL_CURSOR_ARROW];
		*type = RXT_WORD;
		break;

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
		        (unsigned)To_Pixels(arg->pair.x, Scale_Of(pv)),
		        (unsigned)To_Pixels(arg->pair.y, Scale_Of(pv))) != PUGL_SUCCESS)
			return PE_BAD_SET;
		break;

	case W_PUGL_ARG_OFFSET:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		if (puglSetPositionHint(view, PUGL_CURRENT_POSITION,
		        To_Pixels(arg->pair.x, Scale_Of(pv)),
		        To_Pixels(arg->pair.y, Scale_Of(pv))) != PUGL_SUCCESS)
			return PE_BAD_SET;
		break;

	case W_PUGL_ARG_CURSOR: {
		REBCNT w = Cursor_Word(type, arg);
		if (!w) return *type == RXT_WORD ? PE_BAD_SET : PE_BAD_SET_TYPE;
		pv->cursor = w;
		Update_Cursor(pv);
		break; }

	// A zoom: the window keeps its size on the screen, all in it is drawn
	// at the new scale - so its size in units changes. A configure is
	// queued for it, as if pugl had sent one, so that it is reported as
	// a `resize`, the same as any other change of the size in units.
	case W_PUGL_ARG_SCALE: {
		double    k;
		PuglEvent ev;
		PuglArea  a;
		PuglPoint p;
		if      (*type == RXT_NONE)    k = 0.0;
		else if (*type == RXT_DECIMAL) k = arg->dec64;
		else if (*type == RXT_INTEGER) k = (double)arg->int64;
		else return PE_BAD_SET_TYPE;
		if (*type != RXT_NONE && (k <= 0.0 || k > 16.0)) return PE_BAD_RANGE;
		pv->scale = k;

		a = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
		p = puglGetPositionHint(view, PUGL_CURRENT_POSITION);
		memset(&ev, 0, sizeof(ev));
		ev.configure.type   = PUGL_CONFIGURE;
		ev.configure.x      = p.x;
		ev.configure.y      = p.y;
		ev.configure.width  = a.width;
		ev.configure.height = a.height;
		Pugl_On_Event(view, &ev);   // queued, and the view redrawn
		Update_Cursor(pv);
		break; }

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
		double   k = Scale_Of(pv);
		APPEND_STRING(str, "0#%lx %dx%d",
			(unsigned long)puglGetNativeView((PuglView*)pv->view),
			(int)To_Units(a.width, k), (int)To_Units(a.height, k));
	} else {
		APPEND_STRING(str, "%s", "closed");
	}
	return len;
}


//== image and group handle callbacks =========================================
//
// The same callbacks for both handle types - the context says which it is.

// Whether a word is an accessor of this kind of node. Those of the other
// kind are refused like unknown ones.
static REBOOL Node_Has(PUGLNODE *n, REBCNT word)
{
	switch (word) {
	case W_PUGL_ARG_IMAGE:
	case W_PUGL_ARG_PART:
	case W_PUGL_ARG_FILL:
	case W_PUGL_ARG_NINE_SCALE: return !n->group && !n->is_text;
	case W_PUGL_ARG_IMAGES:  return n->group ? TRUE : FALSE;
	case W_PUGL_ARG_TEXT:
	case W_PUGL_ARG_FONT:
	case W_PUGL_ARG_ALIGN:   return n->is_text ? TRUE : FALSE;
	case W_PUGL_ARG_SIZE:
	case W_PUGL_ARG_OFFSET:
	case W_PUGL_ARG_VISIBLEQ:
	case W_PUGL_ARG_TRACKQ:
	case W_PUGL_ARG_HOVERQ:
	case W_PUGL_ARG_WINDOW:
	case W_PUGL_ARG_PARENT:
	case W_PUGL_ARG_ROTATION:
	case W_PUGL_ARG_SCALE:
	case W_PUGL_ARG_PIVOT:
	case W_PUGL_ARG_OPACITY:
	case W_PUGL_ARG_BLEND:
	case W_PUGL_ARG_TINT:
	case W_PUGL_ARG_CURSOR:
	case W_PUGL_ARG_FILTER:
	case W_PUGL_ARG_INDEX:   return TRUE;
	}
	return FALSE;
}

// Reached through an explicit `release`, or at shutdown - a shown image or
// group is locked against the GC, and its list holds a pointer to it.
int PuglImage_free(void *hndl)
{
	REBHOB   *hob = (REBHOB*)hndl;
	PUGLNODE *im;

	if (!hob) return 0;
	im = (PUGLNODE*)hob->data;
	if (im) {
		Detach_Node(im);
		CLEARS(im);
	}
	UNMARK_HOB(hob);
	return 0;
}


int PuglImage_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLNODE *im = (PUGLNODE*)hob->data;
	RXIARG    val;

	word = RL_FIND_WORD(Pugl_arg_words, word);

	// Unknown words are refused, so PD_Handle can still answer `type`;
	// a removed image or group answers none for everything else.
	if (!Node_Has(im, word)) return PE_BAD_SELECT;
	if (!im->win) {
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

	// What it is drawn at, a zero axis resolved to the image's own - for a
	// group what it clips to, as set - and for a text what it takes.
	case W_PUGL_ARG_SIZE:
		if (im->is_text) {
			arg->pair.x = (float)im->text_w;
			arg->pair.y = (float)im->text_h;
			*type = RXT_PAIR;
			break;
		}
		if (im->group) {
			arg->pair.x = (float)im->w;
			arg->pair.y = (float)im->h;
			*type = RXT_PAIR;
			break;
		}
		{
			REBINT dw, dh;
			Pugl_Drawn_Size(im, &dw, &dh);
			arg->pair.x = (float)dw;
			arg->pair.y = (float)dh;
		}
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

	// The hovered image, and every group it is in.
	case W_PUGL_ARG_HOVERQ:
		arg->int32a = In_Chain((PUGLNODE*)((PUGLWIN*)im->win)->hover, im) ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	case W_PUGL_ARG_WINDOW:
		Set_Handle_Arg(arg, ((PUGLWIN*)im->win)->hob);
		*type = RXT_HANDLE;
		break;

	case W_PUGL_ARG_PARENT:
		if (!im->parent) { *type = RXT_NONE; break; }
		Set_Handle_Arg(arg, ((PUGLNODE*)im->parent)->hob);
		*type = RXT_HANDLE;
		break;

	case W_PUGL_ARG_IMAGES:
		*type = Nodes_Block((PUGLNODE*)im->children, arg) ? RXT_BLOCK : RXT_NONE;
		break;

	case W_PUGL_ARG_ROTATION:
		arg->dec64 = im->rot;
		*type = RXT_DECIMAL;
		break;

	// One number while both axes are the same, which is how it is usually
	// set - a pair! only once they differ.
	case W_PUGL_ARG_SCALE:
		if (im->sx == im->sy) {
			arg->dec64 = im->sx;
			*type = RXT_DECIMAL;
		} else {
			arg->pair.x = (float)im->sx;
			arg->pair.y = (float)im->sy;
			*type = RXT_PAIR;
		}
		break;

	case W_PUGL_ARG_PIVOT:
		arg->pair.x = (float)im->px;
		arg->pair.y = (float)im->py;
		*type = RXT_PAIR;
		break;

	case W_PUGL_ARG_OPACITY:
		arg->dec64 = im->opacity;
		*type = RXT_PERCENT;
		break;

	// A new string each time, from its characters - through UTF-8 and
	// RL_DECODE_UTF_STRING, as the window's title is.
	case W_PUGL_ARG_TEXT: {
		REBYTE *utf8 = (REBYTE*)MAKE_MEM(im->nchars * 4 + 1);
		REBCNT  i, n = 0;
		if (!utf8) { *type = RXT_NONE; break; }
		for (i = 0; i < im->nchars; i++) n += UTF8_Of(im->chars[i], utf8 + n);
		arg->series = RL_DECODE_UTF_STRING(utf8, n, 8, FALSE, FALSE);
		FREE_MEM(utf8);
		if (!arg->series) { *type = RXT_NONE; break; }
		arg->index = 0;
		*type = RXT_STRING;
		break; }

	case W_PUGL_ARG_FONT:
		Set_Handle_Arg(arg, ((PUGLFONT*)im->font)->hob);
		*type = RXT_HANDLE;
		break;

	case W_PUGL_ARG_ALIGN:
		arg->int32a = (int)Pugl_align_words[im->align ? im->align : W_PUGL_ALIGN_LEFT];
		*type = RXT_WORD;
		break;

	// A new block each time: [offset size], or none for the whole image.
	case W_PUGL_ARG_PART:
		*type = (im->part_w && Box_Block(im->part_x, im->part_y, im->part_w, im->part_h, arg))
		      ? RXT_BLOCK : RXT_NONE;
		break;

	case W_PUGL_ARG_FILL:
		arg->int32a = (int)Pugl_fill_words[im->fill ? im->fill : W_PUGL_FILL_SCALE];
		*type = RXT_WORD;
		break;

	case W_PUGL_ARG_NINE_SCALE:
		*type = (im->nine && Box_Block(im->nine_x, im->nine_y, im->nine_w, im->nine_h, arg))
		      ? RXT_BLOCK : RXT_NONE;
		break;

	// 1-based, in drawing order - like a series index.
	case W_PUGL_ARG_INDEX: {
		PUGLNODE *n = *Node_List((PUGLWIN*)im->win, (PUGLNODE*)im->parent);
		REBINT    at = 1;
		for (; n && n != im; n = (PUGLNODE*)n->next) at++;
		arg->int64 = at;
		*type = RXT_INTEGER;
		break; }

	case W_PUGL_ARG_FILTER:
		if (!im->filter) { *type = RXT_NONE; break; }
		arg->int32a = (int)Pugl_filter_words[im->filter];
		*type = RXT_WORD;
		break;

	case W_PUGL_ARG_CURSOR:
		if (!im->cursor) { *type = RXT_NONE; break; }
		arg->int32a = (int)Pugl_cursor_words[im->cursor];
		*type = RXT_WORD;
		break;

	// As it was set - three values or four.
	case W_PUGL_ARG_TINT:
		if (!im->tint_len) { *type = RXT_NONE; break; }
		CLEARS(arg);
		arg->tuple_len = (REBYTE)im->tint_len;
		COPY_MEM(arg->tuple_bytes, im->tint, im->tint_len);
		*type = RXT_TUPLE;
		break;

	// Its own - none when it goes by its group's.
	case W_PUGL_ARG_BLEND:
		if (!im->blend) { *type = RXT_NONE; break; }
		arg->int32a = (int)Pugl_blend_words[im->blend];
		*type = RXT_WORD;
		break;

	default:
		return PE_BAD_SELECT;
	}
	return PE_USE;
}


int PuglImage_set_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLNODE *im = (PUGLNODE*)hob->data;

	if (!im->win) return PE_BAD_SET; // removed images are read-only
	word = RL_FIND_WORD(Pugl_arg_words, word);
	if (!Node_Has(im, word)) return PE_BAD_SET;

	switch (word) {
	// Swapping the image is swapping the reference the GC marks, and the
	// texture slot: the new image!'s - shared if another handle shows it -
	// taken before the old one is let go, so the same image! set again
	// keeps its texture. It is uploaded again at the next draw either way.
	case W_PUGL_ARG_IMAGE: {
		REBSER  *img;
		PUGLWIN *win = (PUGLWIN*)im->win;
		REBCNT   slot;
		if (*type != RXT_IMAGE) return PE_BAD_SET_TYPE;
		img = (REBSER*)arg->image;
		if (!img || IMG_WIDE(img) == 0 || IMG_HIGH(img) == 0) return PE_BAD_SET;
		// A part must still be inside - another atlas of the same size is
		// fine, a smaller image is refused.
		if (im->part_w && (im->part_x + im->part_w > (REBINT)IMG_WIDE(img)
		                || im->part_y + im->part_h > (REBINT)IMG_HIGH(img)))
			return PE_BAD_RANGE;
		slot = Tex_Use(win, img);
		if (!slot) return PE_BAD_SET;
		Tex_Drop(win, im->slot);
		im->slot = slot;
		win->tex[slot - 1].dirty = TRUE;
		RL_SET_VALUE(hob->series, SLOT_IMAGE, *arg, RXT_IMAGE);
		im->image = img;
		break; }

	case W_PUGL_ARG_OFFSET:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		im->x = (REBINT)arg->pair.x;
		im->y = (REBINT)arg->pair.y;
		break;

	// A zero axis is the image's own, so `0x0` undoes a scaling - and for
	// a group it is not clipped, so `0x0` stops clipping. A text's is what
	// its text takes, and is not set.
	case W_PUGL_ARG_SIZE:
		if (im->is_text) return PE_BAD_SET;
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

	case W_PUGL_ARG_ROTATION:
		if      (*type == RXT_DECIMAL) im->rot = arg->dec64;
		else if (*type == RXT_INTEGER) im->rot = (double)arg->int64;
		else return PE_BAD_SET_TYPE;
		break;

	// A number for both axes, or a pair for each. Negative mirrors it;
	// zero makes it nothing - not drawn, and nothing for the pointer.
	case W_PUGL_ARG_SCALE:
		if (*type == RXT_DECIMAL) {
			im->sx = im->sy = arg->dec64;
		} else if (*type == RXT_INTEGER) {
			im->sx = im->sy = (double)arg->int64;
		} else if (*type == RXT_PAIR) {
			im->sx = arg->pair.x;
			im->sy = arg->pair.y;
		} else return PE_BAD_SET_TYPE;
		break;

	case W_PUGL_ARG_PIVOT:
		if (*type != RXT_PAIR) return PE_BAD_SET_TYPE;
		im->px = arg->pair.x;
		im->py = arg->pair.y;
		break;

	// A percent! is a decimal! underneath, so both arrive the same way. An
	// integer is there for 0 and 1, which is what sums like `1 - (i / 10)`
	// end at.
	case W_PUGL_ARG_OPACITY: {
		double o;
		if      (*type == RXT_PERCENT || *type == RXT_DECIMAL) o = arg->dec64;
		else if (*type == RXT_INTEGER) o = (double)arg->int64;
		else return PE_BAD_SET_TYPE;
		if (o < 0.0 || o > 1.0) return PE_BAD_RANGE;
		im->opacity = o;
		break; }

	case W_PUGL_ARG_FILTER: {
		REBCNT mode = 0;
		if (*type != RXT_NONE) {
			if (*type != RXT_WORD) return PE_BAD_SET_TYPE;
			mode = RL_FIND_WORD(Pugl_filter_words, (REBCNT)arg->int32a);
			if (!mode) return PE_BAD_SET;
		}
		im->filter = mode;
		break; }

	// Shown at once if the pointer is over it, or over something in it.
	case W_PUGL_ARG_CURSOR: {
		REBCNT w;
		if (*type == RXT_NONE) w = 0;
		else if (!(w = Cursor_Word(type, arg))) return *type == RXT_WORD ? PE_BAD_SET : PE_BAD_SET_TYPE;
		im->cursor = w;
		Update_Cursor((PUGLWIN*)im->win);
		return PE_OK;   // nothing to redraw
	}

	// Red, green and blue - and alpha, when there is a fourth value; the
	// rest of a longer tuple is not colour, and is refused.
	case W_PUGL_ARG_TINT:
		if (*type == RXT_NONE) { im->tint_len = 0; break; }
		if (*type != RXT_TUPLE) return PE_BAD_SET_TYPE;
		if (arg->tuple_len < 3 || arg->tuple_len > 4) return PE_BAD_SET;
		im->tint_len = arg->tuple_len;
		COPY_MEM(im->tint, arg->tuple_bytes, im->tint_len);
		break;

	case W_PUGL_ARG_FILL: {
		REBCNT mode;
		if (*type != RXT_WORD) return PE_BAD_SET_TYPE;
		mode = RL_FIND_WORD(Pugl_fill_words, (REBCNT)arg->int32a);
		if (!mode) return PE_BAD_SET;
		im->fill = mode;
		break; }

	// The middle box, inside its own size as it is now - a middle of zero
	// width or height is fine: the edges then meet. Kept as it is when the
	// part or the image changes later; drawn whole while it does not fit.
	case W_PUGL_ARG_NINE_SCALE: {
		REBINT box[4], ow, oh;
		if (*type == RXT_NONE) { im->nine = FALSE; break; }
		if (*type != RXT_BLOCK) return PE_BAD_SET_TYPE;
		Pugl_Own_Size(im, &ow, &oh);
		if (!Read_Box((REBSER*)arg->series, arg->index, ow, oh, 0, box)) return PE_BAD_SET;
		im->nine   = TRUE;
		im->nine_x = box[0];
		im->nine_y = box[1];
		im->nine_w = box[2];
		im->nine_h = box[3];
		break; }

	// A new text: its characters, measured again - the same texture.
	case W_PUGL_ARG_TEXT: {
		u32   *chars;
		REBCNT count;
		if (*type != RXT_STRING) return PE_BAD_SET_TYPE;
		if (!Text_Chars((REBSER*)arg->series, arg->index, &chars, &count)) return PE_BAD_SET;
		Set_Text_Chars(im, chars, count);
		break; }

	// Another font: its atlas's texture, and the text measured in it.
	case W_PUGL_ARG_FONT: {
		PUGLWIN  *win = (PUGLWIN*)im->win;
		PUGLFONT *f;
		REBCNT    slot;
		if (*type != RXT_HANDLE) return PE_BAD_SET_TYPE;
		if (arg->handle.type != Handle_PuglFont || !IS_USED_HOB(arg->handle.hob)) return PE_BAD_SET;
		f = (PUGLFONT*)arg->handle.hob->data;
		if (!f || !f->glyphs) return PE_BAD_SET;
		slot = Tex_Use(win, (REBSER*)f->image);
		if (!slot) return PE_BAD_SET;
		Tex_Drop(win, im->slot);
		im->slot = slot;
		Font_Use(f, +1);
		Font_Use((PUGLFONT*)im->font, -1);
		im->font = f;
		RL_SET_VALUE(hob->series, 0, *arg, RXT_HANDLE);   // the font handle, for the GC
		Pugl_Text_Size(f, im->chars, im->nchars, &im->text_w, &im->text_h);
		break; }

	case W_PUGL_ARG_ALIGN: {
		REBCNT mode;
		if (*type != RXT_WORD) return PE_BAD_SET_TYPE;
		mode = RL_FIND_WORD(Pugl_align_words, (REBCNT)arg->int32a);
		if (!mode) return PE_BAD_SET;
		im->align = mode;
		break; }

	// Only the part shown: the same texture, other texture coordinates -
	// stepping it is how a sprite is animated, at no upload.
	case W_PUGL_ARG_PART: {
		REBINT part[4];
		if (*type == RXT_NONE) {
			im->part_x = im->part_y = im->part_w = im->part_h = 0;
			break;
		}
		if (*type != RXT_BLOCK) return PE_BAD_SET_TYPE;
		if (!Read_Part((REBSER*)arg->series, arg->index, (REBSER*)im->image, part))
			return PE_BAD_SET;
		im->part_x = part[0];
		im->part_y = part[1];
		im->part_w = part[2];
		im->part_h = part[3];
		break; }

	// Moved within its list: out and back in at the place asked for. The
	// pointer finds what is now on top at its next move.
	case W_PUGL_ARG_INDEX: {
		REBINT at;
		if (*type == RXT_INTEGER) {
			at = arg->int64 < 1 ? 1 : (arg->int64 > 0x7FFFFFFF ? 0x7FFFFFFF : (REBINT)arg->int64);
		} else if (*type == RXT_WORD) {
			switch (RL_FIND_WORD(Pugl_place_words, (REBCNT)arg->int32a)) {
			case W_PUGL_PLACE_TOP:    at = 0x7FFFFFFF; break;
			case W_PUGL_PLACE_BOTTOM: at = 1;          break;
			default: return PE_BAD_SET;
			}
		} else return PE_BAD_SET_TYPE;
		Move_Node(im, at);
		break; }

	case W_PUGL_ARG_BLEND: {
		REBCNT mode;
		if (*type == RXT_NONE) { im->blend = 0; break; }
		if (*type != RXT_WORD) return PE_BAD_SET_TYPE;
		mode = RL_FIND_WORD(Pugl_blend_words, (REBCNT)arg->int32a);
		if (!mode) return PE_BAD_SET;   // not one of the modes
		im->blend = mode;
		break; }

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
	int       len;
	char      text[96];
	PUGLNODE *im;

	if (!str || !hob || !(im = (PUGLNODE*)hob->data)) return 0;

	// The pointer part first, like a window's - an image or a group has no
	// native object, so it is the context's, which lives as long as the
	// handle does: it stays once removed, and tells two handles apart.
	//
	// Formatted whole, then appended ONCE: the core takes the returned
	// `len` as the length of the mold, and APPEND_STRING sets it to what
	// its own call appended - nor is that macro a single statement.
	if (im->win && im->group) {
		REBCNT    count = 0;
		PUGLNODE *c;
		for (c = (PUGLNODE*)im->children; c; c = (PUGLNODE*)c->next) count++;
		if (im->w > 0 || im->h > 0) {
			snprintf(text, sizeof(text), "0#%lx %u at %dx%d clip %dx%d",
				(unsigned long)(REBUPT)im, (unsigned)count,
				(int)im->x, (int)im->y, (int)im->w, (int)im->h);
		} else {
			snprintf(text, sizeof(text), "0#%lx %u at %dx%d",
				(unsigned long)(REBUPT)im, (unsigned)count, (int)im->x, (int)im->y);
		}
	} else if (im->win && im->is_text) {
		snprintf(text, sizeof(text), "0#%lx %u chars %dx%d at %dx%d",
			(unsigned long)(REBUPT)im, (unsigned)im->nchars,
			(int)im->text_w, (int)im->text_h, (int)im->x, (int)im->y);
	} else if (im->win && im->image) {
		REBINT dw, dh;
		Pugl_Drawn_Size(im, &dw, &dh);
		snprintf(text, sizeof(text), "0#%lx %dx%d at %dx%d",
			(unsigned long)(REBUPT)im, (int)dw, (int)dh, (int)im->x, (int)im->y);
	} else {
		snprintf(text, sizeof(text), "0#%lx removed", (unsigned long)(REBUPT)im);
	}

	SERIES_TAIL(str) = 0;
	APPEND_STRING(str, "%s", text);
	return len;
}


//== font handle callbacks ====================================================

// A font in use is locked against the GC - by the texts showing it - so
// this is reached once none does, or through an explicit `release`.
int PuglFont_free(void *hndl)
{
	REBHOB   *hob = (REBHOB*)hndl;
	PUGLFONT *f;

	if (!hob) return 0;
	f = (PUGLFONT*)hob->data;
	if (f) {
		if (f->glyphs) FREE_MEM(f->glyphs);
		CLEARS(f);
	}
	UNMARK_HOB(hob);
	return 0;
}


int PuglFont_get_path(REBHOB *hob, REBCNT word, REBCNT *type, RXIARG *arg)
{
	PUGLFONT *f = (PUGLFONT*)hob->data;
	RXIARG    val;

	word = RL_FIND_WORD(Pugl_arg_words, word);
	if (!f || !f->glyphs) {
		if (!word) return PE_BAD_SELECT;
		*type = RXT_NONE;
		return PE_USE;
	}
	switch (word) {
	case W_PUGL_ARG_LINE_HEIGHT:
		arg->int64 = f->line_height;
		*type = RXT_INTEGER;
		break;

	case W_PUGL_ARG_GLYPHS:
		arg->int64 = f->count;
		*type = RXT_INTEGER;
		break;

	case W_PUGL_ARG_ATLAS:
		if (!hob->series || RL_GET_VALUE(hob->series, 0, &val) != RXT_IMAGE) {
			*type = RXT_NONE;
			break;
		}
		Set_Image_Arg(arg, (REBSER*)val.image);
		*type = RXT_IMAGE;
		break;

	case W_PUGL_ARG_FALLBACKQ:
		arg->int32a = f->has_fallback ? 1 : 0;
		*type = RXT_LOGIC;
		break;

	default:
		return PE_BAD_SELECT;
	}
	return PE_USE;
}


int PuglFont_mold(REBHOB *hob, REBSER *str)
{
	int       len;
	char      text[64];
	PUGLFONT *f;

	if (!str || !hob || !(f = (PUGLFONT*)hob->data)) return 0;
	if (f->glyphs) {
		snprintf(text, sizeof(text), "0#%lx %u glyphs %d high",
			(unsigned long)(REBUPT)f, (unsigned)f->count, (int)f->line_height);
	} else {
		snprintf(text, sizeof(text), "0#%lx released", (unsigned long)(REBUPT)f);
	}
	SERIES_TAIL(str) = 0;
	APPEND_STRING(str, "%s", text);
	return len;
}
