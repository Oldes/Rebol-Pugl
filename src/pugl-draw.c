//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// Drawing: the OpenGL backend and the expose handler.
//
// Kept apart so that only this file includes the GL headers - on Windows
// <pugl/gl.h> pulls in windows.h, which the Rebol headers are better off
// without. It is included first, before the Rebol headers.
//
// The fixed-function pipeline is used on purpose: a 2.1 compatibility
// context, one texture and one quad, the same on Windows, macOS and X11.
//

#include <pugl/gl.h>

// On Windows <pugl/gl.h> brings in windows.h, whose winerror.h defines
// IS_ERROR too - and the embedded build's sys-value.h wants Rebol's.
#undef IS_ERROR

#include "gen-pugl.h"
#include "rebol-pugl.h"
#include <stdlib.h> // MAKE_MEM / FREE_MEM

// Not in the GL 1.1 headers Windows ships with.
#ifndef GL_BGRA
#define GL_BGRA 0x80E1
#endif
#ifndef GL_CLAMP_TO_EDGE
#define GL_CLAMP_TO_EDGE 0x812F
#endif

PuglStatus Pugl_Setup_Backend(PuglView *view)
{
	puglSetViewHint(view, PUGL_CONTEXT_API,           PUGL_OPENGL_API);
	puglSetViewHint(view, PUGL_CONTEXT_VERSION_MAJOR, 2);
	puglSetViewHint(view, PUGL_CONTEXT_VERSION_MINOR, 1);
	puglSetViewHint(view, PUGL_CONTEXT_PROFILE,       PUGL_OPENGL_COMPATIBILITY_PROFILE);
	puglSetViewHint(view, PUGL_DOUBLE_BUFFER,         PUGL_TRUE);
	// Clipping is done with the stencil: a box turned with its group is no
	// box the scissor can cut. Without one, nothing is clipped.
	puglSetViewHint(view, PUGL_STENCIL_BITS,          8);
	return puglSetBackend(view, puglGlBackend());
}

/***********************************************************************
**  The pixels premultiplied by their alpha, in a buffer kept for the
**  next upload. Premultiplied, every blend mode is one glBlendFunc and
**  right with alpha - with straight alpha, `multiply` and `screen` would
**  ignore it. NULL if there is no memory for it.
***********************************************************************/
static REBYTE *Premultiplied(const REBYTE *bgra, REBINT w, REBINT h)
{
	static REBYTE *buf  = NULL;
	static REBCNT  size = 0;
	REBCNT need = (REBCNT)w * (REBCNT)h * 4, n;

	if (need > size) {
		REBYTE *grown = (REBYTE*)MAKE_MEM(need);
		if (!grown) return NULL;
		if (buf) FREE_MEM(buf);
		buf  = grown;
		size = need;
	}
	for (n = 0; n < need; n += 4) {
		REBCNT a = bgra[n + 3];
		// (x * a + 127) / 255 - rounded, so 255 keeps 255 and 0 gives 0.
		buf[n]     = (REBYTE)((bgra[n]     * a + 127) / 255);
		buf[n + 1] = (REBYTE)((bgra[n + 1] * a + 127) / 255);
		buf[n + 2] = (REBYTE)((bgra[n + 2] * a + 127) / 255);
		buf[n + 3] = (REBYTE)a;
	}
	return buf;
}

/***********************************************************************
**  Uploads an image!'s pixels into its texture, when they are new or
**  `dirty` (set by `redraw` and by assigning `image`) - so an expose
**  from the OS, the window uncovered say, draws what it already has.
**  The texture is shared by every handle showing the image!, so it is
**  uploaded once a draw at most, by the first of them drawn.
**
**  The image! layout is B G R A in memory with straight alpha, 255
**  opaque: GL_BGRA / GL_UNSIGNED_BYTE, premultiplied on the way.
***********************************************************************/
static void Upload(PUGLTEX *t, REBSER *img, REBINT w, REBINT h)
{
	GLuint  tex;
	REBYTE *pixels;

	if (!t->texture) {
		glGenTextures(1, &tex);
		t->texture = (REBCNT)tex;
		t->w = t->h = 0;
		t->dirty = TRUE;
	}
	glBindTexture(GL_TEXTURE_2D, (GLuint)t->texture);
	if (!t->dirty) return;

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
	pixels = Premultiplied((const REBYTE*)IMG_DATA(img), w, h);
	if (!pixels) return;   // stays dirty, and is tried again next time
	// Same size: replace the pixels in place; otherwise a new texture.
	if (w == t->w && h == t->h) {
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h,
		                GL_BGRA, GL_UNSIGNED_BYTE, pixels);
	} else {
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0,
		             GL_BGRA, GL_UNSIGNED_BYTE, pixels);
		t->w = w;
		t->h = h;
	}
	t->dirty = FALSE;
}

/***********************************************************************
**  Loads a transform as the modelview matrix - each node's whole one,
**  computed on the CPU, so nesting is not limited by GL's matrix stack.
***********************************************************************/
static void Load_Xform(const PUGLXFORM *m)
{
	GLfloat g[16] = {
		(GLfloat)m->a, (GLfloat)m->b, 0, 0,
		(GLfloat)m->c, (GLfloat)m->d, 0, 0,
		0,             0,             1, 0,
		(GLfloat)m->e, (GLfloat)m->f, 0, 1
	};
	glLoadMatrixf(g);
}

// A quad of w by h, showing the texture from u0,v0 to u1,v1.
static void Quad_Of(float w, float h, float u0, float v0, float u1, float v1)
{
	glBegin(GL_QUADS);
	glTexCoord2f(u0, v0); glVertex2f(0.0f, 0.0f);
	glTexCoord2f(u1, v0); glVertex2f(w,    0.0f);
	glTexCoord2f(u1, v1); glVertex2f(w,    h);
	glTexCoord2f(u0, v1); glVertex2f(0.0f, h);
	glEnd();
}

static void Quad(float w, float h)
{
	Quad_Of(w, h, 0.0f, 0.0f, 1.0f, 1.0f);
}

/***********************************************************************
**  One axis of a nine-scale: where its three pieces start and end, in
**  its own pixels (src) and as drawn (dst). The two outer pieces keep
**  their size; drawn smaller than both together, they shrink alike and
**  the middle is gone.
***********************************************************************/
static void Nine_Axis(REBINT own, REBINT at, REBINT mid, REBINT drawn,
                      float src[4], float dst[4])
{
	float lo = (float)at, hi = (float)(own - at - mid);

	if (lo + hi > (float)drawn && lo + hi > 0.0f) {
		float k = (float)drawn / (lo + hi);
		lo *= k;
		hi *= k;
	}
	src[0] = 0.0f;  src[1] = (float)at;  src[2] = (float)(at + mid);  src[3] = (float)own;
	dst[0] = 0.0f;  dst[1] = lo;         dst[2] = (float)drawn - hi;  dst[3] = (float)drawn;
}

// More tiles than this along an axis, and that axis is scaled instead: a
// pixel-sized tile over a big image would be millions of quads.
#define PUGL_MAX_TILES 1024

/***********************************************************************
**  How many times a source of `src` repeats over `dst` - or 0 for not
**  at all (scaled): `tile` as many as start inside, the last one cut;
**  `round` the nearest whole number, at least one, each scaled to fit.
***********************************************************************/
static REBINT Repeats(REBCNT mode, float dst, float src)
{
	float n;
	if (src <= 0.0f || dst <= 0.0f) return 0;
	n = dst / src;
	if (n > PUGL_MAX_TILES) return 0;
	if (mode == W_PUGL_FILL_TILE)  return (REBINT)ceil(n);
	if (mode == W_PUGL_FILL_ROUND) return n < 1.5f ? 1 : (REBINT)(n + 0.5f);
	return 0;
}

/***********************************************************************
**  One piece of an image, drawn from x0,y0 to x1,y1 (its units) from
**  its own pixels s0..s1 (relative to bx,by in the image!) - scaled, or
**  along an axis repeated by its `mode_*` fill: tiled at its own size,
**  the last tile cut, or rounded to a whole number of tiles scaled to
**  fit. Emits quads into an open glBegin(GL_QUADS).
***********************************************************************/
static void Piece(float x0, float x1, float y0, float y1,
                  float sx0, float sx1, float sy0, float sy1,
                  REBCNT mode_x, REBCNT mode_y,
                  REBINT bx, REBINT by, REBINT iw, REBINT ih)
{
	float  sw = sx1 - sx0, sh = sy1 - sy0;
	REBINT nx, ny, i, j;
	float  stepx, stepy;   // a tile as drawn
	REBOOL cutx, cuty;     // the last tile is cut, not scaled

	if (x1 <= x0 || y1 <= y0) return;
	nx = Repeats(mode_x, x1 - x0, sw);
	ny = Repeats(mode_y, y1 - y0, sh);
	cutx  = nx && mode_x == W_PUGL_FILL_TILE;
	cuty  = ny && mode_y == W_PUGL_FILL_TILE;
	stepx = nx ? (cutx ? sw : (x1 - x0) / nx) : (x1 - x0);
	stepy = ny ? (cuty ? sh : (y1 - y0) / ny) : (y1 - y0);
	if (!nx) nx = 1;
	if (!ny) ny = 1;

	for (j = 0; j < ny; j++) {
		float y  = y0 + j * stepy;
		float ye = (j == ny - 1) ? y1 : y + stepy;
		float v0 = (by + sy0) / ih;
		// Only a cut tile shows less than all of its source.
		float v1 = (by + (cuty ? sy0 + (ye - y) : sy1)) / ih;
		for (i = 0; i < nx; i++) {
			float x  = x0 + i * stepx;
			float xe = (i == nx - 1) ? x1 : x + stepx;
			float u0 = (bx + sx0) / iw;
			float u1 = (bx + (cutx ? sx0 + (xe - x) : sx1)) / iw;
			glTexCoord2f(u0, v0); glVertex2f(x,  y);
			glTexCoord2f(u1, v0); glVertex2f(xe, y);
			glTexCoord2f(u1, v1); glVertex2f(xe, ye);
			glTexCoord2f(u0, v1); glVertex2f(x,  ye);
		}
	}
}

/***********************************************************************
**  An image's quads, in its own units: the whole of it - or of its part
**  - or nine pieces when it is nine-scaled and the middle box still fits
**  its own size. With `fill` tile or round, what stretches is repeated:
**  the whole image, or the edges along their length and the middle;
**  corners never are. Texture coordinates are fractions of the whole
**  image!; with GL_NEAREST an atlas frame's neighbours do not bleed in
**  at whole-number scales.
***********************************************************************/
static void Image_Quads(const PUGLNODE *im, REBINT iw, REBINT ih)
{
	REBINT ow, oh, dw, dh, bx = 0, by = 0;
	REBCNT mode = im->fill;   // 0 and W_PUGL_FILL_SCALE both scale
	float  sx[4], sy[4], dx[4], dy[4];
	int    i, j;

	Pugl_Own_Size(im, &ow, &oh);
	Pugl_Drawn_Size(im, &dw, &dh);
	if (im->part_w > 0) {
		if (im->part_x + im->part_w > iw || im->part_y + im->part_h > ih) {
			ow = iw; oh = ih;   // the image! changed under it: the whole of it
		} else {
			bx = im->part_x;
			by = im->part_y;
		}
	}

	glBegin(GL_QUADS);
	if (!im->nine || im->nine_x + im->nine_w > ow || im->nine_y + im->nine_h > oh) {
		Piece(0.0f, (float)dw, 0.0f, (float)dh,
		      0.0f, (float)ow, 0.0f, (float)oh,
		      mode, mode, bx, by, iw, ih);
	} else {
		Nine_Axis(ow, im->nine_x, im->nine_w, dw, sx, dx);
		Nine_Axis(oh, im->nine_y, im->nine_h, dh, sy, dy);
		// The middle column stretches across, the middle row down.
		for (j = 0; j < 3; j++) {
			for (i = 0; i < 3; i++) {
				Piece(dx[i], dx[i + 1], dy[j], dy[j + 1],
				      sx[i], sx[i + 1], sy[j], sy[j + 1],
				      i == 1 ? mode : 0, j == 1 ? mode : 0, bx, by, iw, ih);
			}
		}
	}
	glEnd();
}

/***********************************************************************
**  A clipping group's box, into the stencil only: `delta` +1 marks it,
**  -1 takes the mark back. Only where the clips around it already let
**  through (the stencil is `level`), so marked is inside all of them.
**  A zero axis is not clipped - "everywhere", as far as the window goes.
***********************************************************************/
static void Stencil_Box(const PUGLNODE *g, const PUGLXFORM *m, GLint level, int delta,
                        float win_w, float win_h)
{
	float w = g->w > 0 ? (float)g->w : 0.0f;
	float h = g->h > 0 ? (float)g->h : 0.0f;

	glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
	glDisable(GL_TEXTURE_2D);
	glStencilFunc(GL_EQUAL, level, 0xFF);
	glStencilOp(GL_KEEP, GL_KEEP, delta > 0 ? GL_INCR : GL_DECR);

	if (g->w > 0 && g->h > 0) {
		Load_Xform(m);
		Quad(w, h);
	} else {
		// One axis only: a band along the other, long enough to cross the
		// window whichever way it is turned.
		// Not `far`: windows.h defines it (empty), and <pugl/gl.h> brings it in.
		float reach = 4.0f * (win_w + win_h);
		Load_Xform(m);
		glBegin(GL_QUADS);
		if (g->w > 0) {
			glVertex2f(0, -reach); glVertex2f(w, -reach); glVertex2f(w, reach); glVertex2f(0, reach);
		} else {
			glVertex2f(-reach, 0); glVertex2f(reach, 0); glVertex2f(reach, h); glVertex2f(-reach, h);
		}
		glEnd();
	}

	glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);
	glEnable(GL_TEXTURE_2D);
	glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
}

/***********************************************************************
**  The blend function of a mode - for premultiplied colour, which is
**  what the textures hold and what glColor4f(a, a, a, a) keeps them.
***********************************************************************/
static const float White[3] = { 1.0f, 1.0f, 1.0f };   // no tint
static REBCNT Blend_Now;   // the mode set last, so it is set only on a change

static void Set_Blend(REBCNT mode)
{
	if (mode == Blend_Now) return;
	Blend_Now = mode;
	switch (mode) {
	case W_PUGL_BLEND_ADD:      glBlendFunc(GL_ONE,       GL_ONE);                 break;
	case W_PUGL_BLEND_MULTIPLY: glBlendFunc(GL_DST_COLOR, GL_ONE_MINUS_SRC_ALPHA); break;
	case W_PUGL_BLEND_SCREEN:   glBlendFunc(GL_ONE,       GL_ONE_MINUS_SRC_COLOR); break;
	default:                    glBlendFunc(GL_ONE,       GL_ONE_MINUS_SRC_ALPHA); break;
	}
}

/***********************************************************************
**  A list of images under `parent` - the transform into window pixels -
**  at `alpha` opacity, by `blend` where they do not set their own, drawn
**  where the stencil is `level`: inside every clipping group around it.
**
**  A group is drawn where it is in the list, its own list under its
**  transform and its opacity. A clipping group marks its box one level
**  up, draws what is in it at that level, and takes the mark back.
***********************************************************************/
static void Draw_List(PUGLWIN *win, PUGLNODE *im, const PUGLXFORM *parent, float alpha,
                      const float tint[3], REBCNT blend, GLint level, float win_w, float win_h)
{
	for (; im; im = (PUGLNODE*)im->next) {
		REBSER   *img = (REBSER*)im->image;
		PUGLXFORM m;
		float     a, t[3];
		REBCNT    b;
		REBINT    iw, ih;

		if (!im->visible) continue;
		Pugl_Node_Xform(im, &m);
		Pugl_Xform_Mul(&m, parent, &m);
		a = alpha * (float)im->opacity;
		b = im->blend ? im->blend : blend;
		t[0] = tint[0]; t[1] = tint[1]; t[2] = tint[2];
		if (im->tint_len) {
			t[0] *= im->tint[0] / 255.0f;
			t[1] *= im->tint[1] / 255.0f;
			t[2] *= im->tint[2] / 255.0f;
			if (im->tint_len > 3) a *= im->tint[3] / 255.0f;
		}

		if (im->group) {
			REBOOL clips = (im->w > 0 || im->h > 0) && level < 255;
			if (!clips) {
				Draw_List(win, (PUGLNODE*)im->children, &m, a, t, b, level, win_w, win_h);
				continue;
			}
			Stencil_Box(im, &m, level, +1, win_w, win_h);
			glStencilFunc(GL_EQUAL, level + 1, 0xFF);
			Draw_List(win, (PUGLNODE*)im->children, &m, a, t, b, level + 1, win_w, win_h);
			Stencil_Box(im, &m, level + 1, -1, win_w, win_h);
			glStencilFunc(GL_EQUAL, level, 0xFF);
			continue;
		}

		if (!img || !im->slot || im->slot > win->tex_size) continue;
		iw = (REBINT)IMG_WIDE(img);
		ih = (REBINT)IMG_HIGH(img);
		if (iw <= 0 || ih <= 0) continue;

		Upload(&win->tex[im->slot - 1], img, iw, ih);
		if (a <= 0.0f) continue;   // uploaded all the same, for when it shows

		Load_Xform(&m);
		Set_Blend(b);
		// The colour is premultiplied, so it fades with the alpha - and the
		// tint multiplies it, premultiplied the same way.
		glColor4f(t[0] * a, t[1] * a, t[2] * a, a);
		Image_Quads(im, iw, ih);
	}
}

/***********************************************************************
**  The expose handler - called with the window's GL context current,
**  and the buffers are swapped by the backend after it returns.
**
**  The window is cleared to black, and its images are drawn in the
**  order they were added - those of a group where the group is, and
**  inside its size when it has one - each at its offset and its size,
**  turned, scaled and faded as set. Scaled with nearest neighbour, so a
**  pixel stays a pixel, and blended by their alpha. One unit is one
**  device pixel, origin at the top left.
**
**  Textures are not deleted when the window closes: they belong to its
**  GL context, which takes them with it. Those of images removed while
**  it is open are deleted here, the first time the context is current.
***********************************************************************/
void Pugl_Draw(PUGLWIN *pv, PuglView *view)
{
	PuglArea area = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
	REBCNT   n;

	glViewport(0, 0, area.width, area.height);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClearStencil(0);
	glClear(GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

	for (n = 0; n < pv->dead_count; n++) {
		GLuint tex = (GLuint)pv->dead[n];
		glDeleteTextures(1, &tex);
	}
	pv->dead_count = 0;

	if (!pv->images) return;

	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, area.width, area.height, 0, -1, 1);
	glMatrixMode(GL_MODELVIEW);

	glEnable(GL_TEXTURE_2D);
	glEnable(GL_BLEND);
	Blend_Now = (REBCNT)-1;   // whatever GL has, it is set at the first image

	// Level 0 is the whole window, until a clipping group says otherwise.
	glEnable(GL_STENCIL_TEST);
	glStencilFunc(GL_EQUAL, 0, 0xFF);
	glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

	Draw_List(pv, (PUGLNODE*)pv->images, &Pugl_Identity, 1.0f, White, W_PUGL_BLEND_NORMAL, 0,
	          (float)area.width, (float)area.height);

	glDisable(GL_STENCIL_TEST);
	glDisable(GL_BLEND);
	glDisable(GL_TEXTURE_2D);
	glLoadIdentity();
}
