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
	return puglSetBackend(view, puglGlBackend());
}

/***********************************************************************
**  The expose handler - called with the view's GL context current, and
**  the buffers are swapped by the backend after it returns.
**
**  The image is uploaded only when it is new or `dirty` (set by `redraw`
**  and by assigning `image`), so an expose from the OS - the window
**  uncovered, say - just draws the texture it already has.
**
**  The image! layout is B G R A in memory with straight alpha, 255
**  opaque, which GL takes as it is: GL_BGRA / GL_UNSIGNED_BYTE and
**  ordinary alpha blending. Drawn 1:1 in device pixels, centered in the
**  view; whatever it does not cover is cleared to black. The offset is
**  a whole number of pixels, so the image stays sharp, and an image
**  larger than the view is cropped equally on both sides.
**
**  The texture is not deleted when the view closes: it belongs to the
**  view's GL context, which takes its textures with it.
***********************************************************************/
void Pugl_Draw(PUGLVIEWCTX *pv, PuglView *view)
{
	PuglArea area = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
	REBSER  *img  = (REBSER*)pv->image;
	REBINT   w, h;
	float    x, y;
	GLuint   tex;

	glViewport(0, 0, area.width, area.height);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

	if (!img) return;
	w = (REBINT)IMG_WIDE(img);
	h = (REBINT)IMG_HIGH(img);
	if (w <= 0 || h <= 0) return;

	if (!pv->texture) {
		glGenTextures(1, &tex);
		pv->texture = (REBCNT)tex;
		pv->tex_w = pv->tex_h = 0;
		pv->dirty = TRUE;
	}
	glBindTexture(GL_TEXTURE_2D, (GLuint)pv->texture);

	if (pv->dirty) {
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
		glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
		// Same size: replace the pixels in place; otherwise a new texture.
		if (w == pv->tex_w && h == pv->tex_h) {
			glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, w, h,
			                GL_BGRA, GL_UNSIGNED_BYTE, IMG_DATA(img));
		} else {
			glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0,
			             GL_BGRA, GL_UNSIGNED_BYTE, IMG_DATA(img));
			pv->tex_w = w;
			pv->tex_h = h;
		}
		pv->dirty = FALSE;
	}

	// One unit is one device pixel, with the origin at the top left.
	glMatrixMode(GL_PROJECTION);
	glLoadIdentity();
	glOrtho(0, area.width, area.height, 0, -1, 1);
	glMatrixMode(GL_MODELVIEW);
	glLoadIdentity();

	glEnable(GL_TEXTURE_2D);
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

	// Centered; integer division keeps it on whole pixels.
	x = (float)(((REBINT)area.width  - w) / 2);
	y = (float)(((REBINT)area.height - h) / 2);

	glBegin(GL_QUADS);
	glTexCoord2f(0.0f, 0.0f); glVertex2f(x,            y);
	glTexCoord2f(1.0f, 0.0f); glVertex2f(x + (float)w, y);
	glTexCoord2f(1.0f, 1.0f); glVertex2f(x + (float)w, y + (float)h);
	glTexCoord2f(0.0f, 1.0f); glVertex2f(x,            y + (float)h);
	glEnd();

	glDisable(GL_BLEND);
	glDisable(GL_TEXTURE_2D);
}
