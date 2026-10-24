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
**  Uploads an image's pixels into its texture, when they are new or
**  `dirty` (set by `redraw` and by assigning `image`) - so an expose
**  from the OS, the window uncovered say, draws what it already has.
**
**  The image! layout is B G R A in memory with straight alpha, 255
**  opaque, which GL takes as it is: GL_BGRA / GL_UNSIGNED_BYTE.
***********************************************************************/
static void Upload(PUGLNODE *im, REBSER *img, REBINT w, REBINT h)
{
	GLuint tex;

	if (!im->texture) {
		glGenTextures(1, &tex);
		im->texture = (REBCNT)tex;
		im->tex_w = im->tex_h = 0;
		im->dirty = TRUE;
	}
	glBindTexture(GL_TEXTURE_2D, (GLuint)im->texture);
	if (!im->dirty) return;

	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
	glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
	// Same size: replace the pixels in place; otherwise a new texture.
	if (w == im->tex_w && h == im->tex_h) {
		glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h,
		                GL_BGRA, GL_UNSIGNED_BYTE, IMG_DATA(img));
	} else {
		glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0,
		             GL_BGRA, GL_UNSIGNED_BYTE, IMG_DATA(img));
		im->tex_w = w;
		im->tex_h = h;
	}
	im->dirty = FALSE;
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

static void Quad(float w, float h)
{
	glBegin(GL_QUADS);
	glTexCoord2f(0.0f, 0.0f); glVertex2f(0.0f, 0.0f);
	glTexCoord2f(1.0f, 0.0f); glVertex2f(w,    0.0f);
	glTexCoord2f(1.0f, 1.0f); glVertex2f(w,    h);
	glTexCoord2f(0.0f, 1.0f); glVertex2f(0.0f, h);
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
**  A list of images under `parent` - the transform into window pixels -
**  at `alpha` opacity, drawn where the stencil is `level`: inside every
**  clipping group around it.
**
**  A group is drawn where it is in the list, its own list under its
**  transform and its opacity. A clipping group marks its box one level
**  up, draws what is in it at that level, and takes the mark back.
***********************************************************************/
static void Draw_List(PUGLNODE *im, const PUGLXFORM *parent, float alpha, GLint level,
                      float win_w, float win_h)
{
	for (; im; im = (PUGLNODE*)im->next) {
		REBSER   *img = (REBSER*)im->image;
		PUGLXFORM m;
		float     a;
		REBINT    iw, ih;

		if (!im->visible) continue;
		Pugl_Node_Xform(im, &m);
		Pugl_Xform_Mul(&m, parent, &m);
		a = alpha * (float)im->opacity;

		if (im->group) {
			REBOOL clips = (im->w > 0 || im->h > 0) && level < 255;
			if (!clips) {
				Draw_List((PUGLNODE*)im->children, &m, a, level, win_w, win_h);
				continue;
			}
			Stencil_Box(im, &m, level, +1, win_w, win_h);
			glStencilFunc(GL_EQUAL, level + 1, 0xFF);
			Draw_List((PUGLNODE*)im->children, &m, a, level + 1, win_w, win_h);
			Stencil_Box(im, &m, level + 1, -1, win_w, win_h);
			glStencilFunc(GL_EQUAL, level, 0xFF);
			continue;
		}

		if (!img) continue;
		iw = (REBINT)IMG_WIDE(img);
		ih = (REBINT)IMG_HIGH(img);
		if (iw <= 0 || ih <= 0) continue;

		Upload(im, img, iw, ih);
		if (a <= 0.0f) continue;   // uploaded all the same, for when it shows

		Load_Xform(&m);
		glColor4f(1.0f, 1.0f, 1.0f, a);   // modulates the texture's own alpha
		Quad((float)(im->w > 0 ? im->w : iw), (float)(im->h > 0 ? im->h : ih));
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
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

	// Level 0 is the whole window, until a clipping group says otherwise.
	glEnable(GL_STENCIL_TEST);
	glStencilFunc(GL_EQUAL, 0, 0xFF);
	glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

	Draw_List((PUGLNODE*)pv->images, &Pugl_Identity, 1.0f, 0,
	          (float)area.width, (float)area.height);

	glDisable(GL_STENCIL_TEST);
	glDisable(GL_BLEND);
	glDisable(GL_TEXTURE_2D);
	glLoadIdentity();
}