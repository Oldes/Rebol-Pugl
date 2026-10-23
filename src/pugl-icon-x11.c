//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The window icon on X11: the EWMH _NET_WM_ICON property.
//
// Its value is the width, the height and then the pixels, each in a 32-bit
// CARDINAL holding ARGB with straight alpha - which, read as a
// little-endian word, is exactly an image! pixel (B G R A in memory). But
// format 32 data is passed to Xlib as an array of C `long`, which is 64
// bits on LP64, so the pixels are copied into one rather than handed over.
//
// The window manager scales it as it likes; one size is enough. Under
// Wayland (XWayland) the compositor may ignore the property altogether.
//

#include <stdlib.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

#include "pugl-icon.h"

int Pugl_Set_Native_Icon(PuglView *view, void **icons,
                         const unsigned char *bgra, int w, int h)
{
	// The native world is the Display, the native view the top-level Window.
	Display       *dpy = (Display*)puglGetNativeWorld(puglGetWorld(view));
	Window         win = (Window)puglGetNativeView(view);
	Atom           prop;
	unsigned long *data;
	size_t         n, i;

	(void)icons;   // nothing native to keep: the property is the server's
	if (!dpy || !win) return 0;
	prop = XInternAtom(dpy, "_NET_WM_ICON", False);

	if (!bgra || w <= 0 || h <= 0) {
		XDeleteProperty(dpy, win, prop);
		XFlush(dpy);
		return 1;
	}

	n = (size_t)w * (size_t)h;
	data = (unsigned long*)malloc((n + 2) * sizeof(unsigned long));
	if (!data) return 0;
	data[0] = (unsigned long)w;
	data[1] = (unsigned long)h;
	for (i = 0; i < n; i++) {
		const unsigned char *p = bgra + i * 4;
		data[2 + i] = ((unsigned long)p[3] << 24) | ((unsigned long)p[2] << 16)
		            | ((unsigned long)p[1] <<  8) |  (unsigned long)p[0];
	}
	XChangeProperty(dpy, win, prop, XA_CARDINAL, 32, PropModeReplace,
	                (const unsigned char*)data, (int)(n + 2));
	XFlush(dpy);
	free(data);
	return 1;
}

void Pugl_Free_Native_Icon(void **icons)
{
	(void)icons;
}
