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

#include <math.h>

/***********************************************************************
**  2D affine transforms - for drawing (pugl-draw.c) and for finding
**  what is under the pointer (pugl-commands.c), so the two always agree.
**
**      x' = a*x + c*y + e
**      y' = b*x + d*y + f
***********************************************************************/
typedef struct { double a, b, c, d, e, f; } PUGLXFORM;

static const PUGLXFORM Pugl_Identity = { 1.0, 0.0, 0.0, 1.0, 0.0, 0.0 };

// A node's own transform, from its units into its parent's: moved to its
// offset, then turned (clockwise on screen, as y points down) and scaled
// around its pivot.
static inline void Pugl_Node_Xform(const PUGLNODE *n, PUGLXFORM *m)
{
	double r  = n->rot * 3.14159265358979323846 / 180.0;
	double co = cos(r), si = sin(r);
	m->a =  co * n->sx;
	m->b =  si * n->sx;
	m->c = -si * n->sy;
	m->d =  co * n->sy;
	m->e = n->x + n->px - (m->a * n->px + m->c * n->py);
	m->f = n->y + n->py - (m->b * n->px + m->d * n->py);
}

// out = p * l - first l, then p. `out` may be `p`.
static inline void Pugl_Xform_Mul(PUGLXFORM *out, const PUGLXFORM *p, const PUGLXFORM *l)
{
	PUGLXFORM r;
	r.a = p->a * l->a + p->c * l->b;
	r.b = p->b * l->a + p->d * l->b;
	r.c = p->a * l->c + p->c * l->d;
	r.d = p->b * l->c + p->d * l->d;
	r.e = p->a * l->e + p->c * l->f + p->e;
	r.f = p->b * l->e + p->d * l->f + p->f;
	*out = r;
}

// A point back into the units the transform maps from. FALSE when it
// cannot be undone - something scaled to nothing has no point under it.
static inline int Pugl_Xform_Undo(const PUGLXFORM *m, double *x, double *y)
{
	double det = m->a * m->d - m->b * m->c;
	double dx  = *x - m->e, dy = *y - m->f;
	if (det == 0.0) return 0;
	*x = ( m->d * dx - m->c * dy) / det;
	*y = (-m->b * dx + m->a * dy) / det;
	return 1;
}

// An image node's own size: its part's, or the whole image!'s.
static inline void Pugl_Own_Size(const PUGLNODE *n, REBINT *w, REBINT *h)
{
	if (n->part_w > 0) { *w = n->part_w; *h = n->part_h; return; }
	*w = (REBINT)IMG_WIDE((REBSER*)n->image);
	*h = (REBINT)IMG_HIGH((REBSER*)n->image);
}

// The size it is drawn at: `size`, a zero axis taken from its own.
static inline void Pugl_Drawn_Size(const PUGLNODE *n, REBINT *w, REBINT *h)
{
	REBINT ow, oh;
	Pugl_Own_Size(n, &ow, &oh);
	*w = n->w > 0 ? n->w : ow;
	*h = n->h > 0 ? n->h : oh;
}

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
