//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The window icon - Pugl has no API for it, so it is done natively, one
// source per platform:
//
//   pugl-icon-win.c ... WM_SETICON with two HICONs (title bar, taskbar)
//   pugl-icon-x11.c ... the _NET_WM_ICON property
//   pugl-icon-mac.m ... the application's Dock icon (a Mac window has none)
//
// Deliberately free of the Rebol headers, so that windows.h, Xlib.h and
// AppKit never meet them. Plain C types only.
//

#ifndef PUGL_ICON_H
#define PUGL_ICON_H

#include <pugl/pugl.h>

// `bgra` is w x h pixels of 4 bytes, B G R A in memory with straight alpha
// - the image! layout. The pixels are COPIED; the caller's may move once
// this returns. NULL (or a zero size) puts the default icon back.
//
// `icons` is two slots the platform may keep native objects in (Windows'
// HICONs); they are freed by Pugl_Free_Native_Icon(), which must be called
// once the view is gone. Returns 1 on success, 0 on failure.
int  Pugl_Set_Native_Icon(PuglView *view, void **icons,
                          const unsigned char *bgra, int w, int h);
void Pugl_Free_Native_Icon(void **icons);

#endif
