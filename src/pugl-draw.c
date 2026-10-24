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
static void Upload(PUGLIMG *im, REBSER *img, REBINT w, REBINT h)
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
**  The expose handler - called with the window's GL context current,
**  and the buffers are swapped by the backend after it returns.
**
**  The window is cleared to black, and its images are drawn in the
**  order they were added, each at its offset and its size - scaled
**  with nearest neighbour, so a pixel stays a pixel - blended by their
**  alpha. One unit is one device pixel, origin at the top left.
**
**  Textures are not deleted when the window closes: they belong to its
**  GL context, which takes them with it. Those of images removed while
**  it is open are deleted here, the first time the context is current.
***********************************************************************/
void Pugl_Draw(PUGLWIN *pv, PuglView *view)
{
	PuglArea area = puglGetSizeHint(view, PUGL_CURRENT_SIZE);
	PUGLIMG *im;
	REBCNT   n;

	glViewport(0, 0, area.width, area.height);
	glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
	glClear(GL_COLOR_BUFFER_BIT);

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
	glLoadIdentity();

	glEnable(GL_TEXTURE_2D);
	glEnable(GL_BLEND);
	glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
	glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

	for (im = (PUGLIMG*)pv->images; im; im = (PUGLIMG*)im->next) {
		REBSER *img = (REBSER*)im->image;
		REBINT  iw, ih;
		float   x, y, w, h;

		if (!im->visible || !img) continue;
		iw = (REBINT)IMG_WIDE(img);
		ih = (REBINT)IMG_HIGH(img);
		if (iw <= 0 || ih <= 0) continue;

		Upload(im, img, iw, ih);

		x = (float)im->x;
		y = (float)im->y;
		w = (float)(im->w > 0 ? im->w : iw);
		h = (float)(im->h > 0 ? im->h : ih);

		glBegin(GL_QUADS);
		glTexCoord2f(0.0f, 0.0f); glVertex2f(x,     y);
		glTexCoord2f(1.0f, 0.0f); glVertex2f(x + w, y);
		glTexCoord2f(1.0f, 1.0f); glVertex2f(x + w, y + h);
		glTexCoord2f(0.0f, 1.0f); glVertex2f(x,     y + h);
		glEnd();
	}

	glDisable(GL_BLEND);
	glDisable(GL_TEXTURE_2D);
}
