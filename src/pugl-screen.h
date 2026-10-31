//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The screens - Pugl has no API for them, so they are asked of the system,
// one source per platform:
//
//   pugl-screen-win.c ... EnumDisplayMonitors
//   pugl-screen-x11.c ... XRandR monitors, and _NET_WORKAREA
//   pugl-screen-mac.m ... NSScreen
//
// Free of the Rebol headers, as pugl-icon.h is: plain C types only.
//
// A display is named by a KEY - a NUL-terminated string of at most
// PUGL_SCREEN_KEY bytes which the platform can find it by again: the
// device name on Windows, the connector on X11, the display id on macOS.
//
// COORDINATES ARE DEVICE PIXELS of the desktop, in the space Pugl places a
// window in - so a window's position and a screen's are in one space - and
// `scale` is what Pugl reports as the scale of a window on that screen.
// The extension divides by it: a screen is measured in its own units.
//

#ifndef PUGL_SCREEN_H
#define PUGL_SCREEN_H

#include <pugl/pugl.h>

#ifndef PUGL_SCREEN_KEY
#define PUGL_SCREEN_KEY 64
#endif

typedef struct {
	int    x, y, w, h;      // the whole display
	int    wx, wy, ww, wh;  // the part windows should use - no taskbar, Dock, panels
	double scale;           // device pixels per unit
	int    primary;         // 1 for the primary display
} PuglScreenInfo;

// Fills up to `max` keys, the PRIMARY FIRST, and returns how many displays
// there are.
int Pugl_Screen_Keys(PuglWorld *world, char (*keys)[PUGL_SCREEN_KEY], int max);

// 0 once the display is gone.
int Pugl_Screen_Info(PuglWorld *world, const char *key, PuglScreenInfo *info);

// What the system calls it, as UTF-8 into `name` (`size` bytes, NUL
// terminated). 0 once the display is gone.
int Pugl_Screen_Name(PuglWorld *world, const char *key, char *name, int size);

// The key of the display holding most of the view's window; 0 when it is
// on none (hidden, or off every display).
int Pugl_View_Screen(PuglView *view, char *key);

#endif
