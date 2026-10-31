//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The screens on X11: the XRandR monitors (RandR 1.5), each named by its
// connector - DP-1, HDMI-2 - which stays the same while it is connected.
// Every question asks the server again and matches by name.
//
// The scale is Pugl's own for X11 - Xft.dpi / 96, one for the whole
// display - so a window on any of them reports the same.
//
// The work area is _NET_WORKAREA of the current desktop, which the window
// manager gives for the whole desktop at once: each monitor's is that,
// cut to the monitor. Without a window manager which sets it, the work
// area is the whole monitor.
//
// Without RandR 1.5 the screen of the display is one monitor, "default".
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xresource.h>
#include <X11/extensions/Xrandr.h>

#include "pugl-screen.h"

typedef struct {
	char key[PUGL_SCREEN_KEY];
	int  x, y, w, h;
	int  primary;
	RROutput output;   // its first output, for the EDID; 0 for none
} MONITOR;

#define MAX_MONITORS 16

static Display *Display_Of(PuglWorld *world)
{
	return world ? (Display*)puglGetNativeWorld(world) : NULL;
}

// The monitors, primary first. Returns how many.
static int Monitors(Display *dpy, MONITOR *out, int max)
{
	Window        root = DefaultRootWindow(dpy);
	int           event, error, major = 0, minor = 0, n = 0, count = 0, pass, i;
	XRRMonitorInfo *mons = NULL;

	if (XRRQueryExtension(dpy, &event, &error)
	    && XRRQueryVersion(dpy, &major, &minor)
	    && (major > 1 || (major == 1 && minor >= 5)))
		mons = XRRGetMonitors(dpy, root, True, &n);

	if (!mons || n <= 0) {
		if (mons) XRRFreeMonitors(mons);
		if (max < 1) return 1;
		memset(&out[0], 0, sizeof(MONITOR));
		strcpy(out[0].key, "default");
		out[0].w = DisplayWidth(dpy, DefaultScreen(dpy));
		out[0].h = DisplayHeight(dpy, DefaultScreen(dpy));
		out[0].primary = 1;
		return 1;
	}

	// Two passes: the primary first, then the rest in the server's order.
	// With none marked primary, the first is.
	{
		int has_primary = 0;
		for (i = 0; i < n; i++) if (mons[i].primary) has_primary = 1;
		for (pass = 0; pass < 2; pass++) {
			for (i = 0; i < n; i++) {
				int primary = has_primary ? mons[i].primary : (i == 0);
				char *name;
				if ((primary != 0) != (pass == 0)) continue;
				if (count < max) {
					MONITOR *m = &out[count];
					memset(m, 0, sizeof(MONITOR));
					name = XGetAtomName(dpy, mons[i].name);
					snprintf(m->key, PUGL_SCREEN_KEY, "%s", name ? name : "monitor");
					if (name) XFree(name);
					m->x = mons[i].x;     m->y = mons[i].y;
					m->w = mons[i].width; m->h = mons[i].height;
					m->primary = primary;
					m->output  = mons[i].noutput > 0 ? mons[i].outputs[0] : 0;
				}
				count++;
			}
		}
	}
	XRRFreeMonitors(mons);
	return count;
}

static int Find(Display *dpy, const char *key, MONITOR *found)
{
	MONITOR mons[MAX_MONITORS];
	int     n, i;

	if (!dpy || !key) return 0;
	n = Monitors(dpy, mons, MAX_MONITORS);
	if (n > MAX_MONITORS) n = MAX_MONITORS;
	for (i = 0; i < n; i++) {
		if (strcmp(mons[i].key, key) == 0) {
			*found = mons[i];
			return 1;
		}
	}
	return 0;
}

// The same as Pugl's puglX11GetDisplayScaleFactor - so that a screen's
// scale is what a window on it reports.
static double Display_Scale(Display *dpy)
{
	double      dpi = 96.0;
	const char *rms = XResourceManagerString(dpy);
	if (rms) {
		XrmDatabase db = XrmGetStringDatabase(rms);
		if (db) {
			XrmValue value = {0U, NULL};
			char    *type  = NULL;
			if (XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &type, &value)) {
				if (!type || !strcmp(type, "String")) {
					char  *end = NULL;
					double d   = strtod(value.addr, &end);
					if (d > 0.0 && d < HUGE_VAL) dpi = d;
				}
			}
			XrmDestroyDatabase(db);
		}
	}
	return dpi / 96.0;
}

// _NET_WORKAREA of the current desktop, cut to the monitor. 0 when the
// window manager gives none, or it misses the monitor.
static int Work_Area(Display *dpy, const MONITOR *m, int *x, int *y, int *w, int *h)
{
	Window         root = DefaultRootWindow(dpy);
	Atom           type;
	int            format, ok = 0;
	unsigned long  items, after, desk = 0;
	unsigned char *data = NULL;
	Atom           current = XInternAtom(dpy, "_NET_CURRENT_DESKTOP", True);
	Atom           area    = XInternAtom(dpy, "_NET_WORKAREA", True);

	if (area == None) return 0;
	if (current != None
	    && XGetWindowProperty(dpy, root, current, 0, 1, False, XA_CARDINAL, &type,
	                          &format, &items, &after, &data) == Success
	    && data && items == 1 && format == 32)
		desk = ((unsigned long*)data)[0];
	if (data) { XFree(data); data = NULL; }

	if (XGetWindowProperty(dpy, root, area, 0, 1024, False, XA_CARDINAL, &type,
	                       &format, &items, &after, &data) == Success
	    && data && format == 32 && items >= 4) {
		// Format 32 comes as C longs, whatever their size.
		long *v = (long*)data;
		long  ax, ay, ar, ab, l, t, r, b;
		if (desk * 4 + 4 > items) desk = 0;
		ax = v[desk * 4];     ay = v[desk * 4 + 1];
		ar = ax + v[desk * 4 + 2];
		ab = ay + v[desk * 4 + 3];
		l = m->x > ax ? m->x : ax;
		t = m->y > ay ? m->y : ay;
		r = (m->x + m->w) < ar ? (m->x + m->w) : ar;
		b = (m->y + m->h) < ab ? (m->y + m->h) : ab;
		if (r > l && b > t) {
			*x = (int)l; *y = (int)t; *w = (int)(r - l); *h = (int)(b - t);
			ok = 1;
		}
	}
	if (data) XFree(data);
	return ok;
}

int Pugl_Screen_Keys(PuglWorld *world, char (*keys)[PUGL_SCREEN_KEY], int max)
{
	Display *dpy = Display_Of(world);
	MONITOR  mons[MAX_MONITORS];
	int      n, i;

	if (!dpy) return 0;
	n = Monitors(dpy, mons, MAX_MONITORS);
	for (i = 0; i < n && i < max && i < MAX_MONITORS; i++)
		memcpy(keys[i], mons[i].key, PUGL_SCREEN_KEY);
	return n;
}

int Pugl_Screen_Info(PuglWorld *world, const char *key, PuglScreenInfo *info)
{
	Display *dpy = Display_Of(world);
	MONITOR  m;

	if (!info || !Find(dpy, key, &m)) return 0;
	info->x = m.x; info->y = m.y; info->w = m.w; info->h = m.h;
	if (!Work_Area(dpy, &m, &info->wx, &info->wy, &info->ww, &info->wh)) {
		info->wx = m.x; info->wy = m.y; info->ww = m.w; info->wh = m.h;
	}
	info->scale   = Display_Scale(dpy);
	info->primary = m.primary;
	return 1;
}

/***********************************************************************
**  The name: the model the monitor's EDID gives, with its connector -
**  "DELL U2720Q (DP-1)" - or the connector alone when it gives none.
**
**  EDID: four 18-byte descriptors from byte 54; the one tagged 0xFC is
**  the display's name, up to 13 characters ended by a newline.
***********************************************************************/
static int Edid_Name(Display *dpy, RROutput output, char *out, int size)
{
	Atom           edid = XInternAtom(dpy, "EDID", True), type;
	int            format, ok = 0, d;
	unsigned long  items, after;
	unsigned char *data = NULL;

	if (!output || edid == None) return 0;
	if (XRRGetOutputProperty(dpy, output, edid, 0, 64, False, False, AnyPropertyType,
	                         &type, &format, &items, &after, &data) != Success)
		return 0;
	if (data && format == 8 && items >= 128) {
		for (d = 54; d <= 108; d += 18) {
			const unsigned char *p = data + d;
			if (p[0] == 0 && p[1] == 0 && p[3] == 0xFC) {
				int n = 0;
				while (n < 13 && p[5 + n] != '\n' && p[5 + n] != 0) n++;
				while (n > 0 && p[5 + n - 1] == ' ') n--;
				if (n > 0 && n < size) {
					memcpy(out, p + 5, (size_t)n);
					out[n] = 0;
					ok = 1;
				}
				break;
			}
		}
	}
	if (data) XFree(data);
	return ok;
}

int Pugl_Screen_Name(PuglWorld *world, const char *key, char *name, int size)
{
	Display *dpy = Display_Of(world);
	MONITOR  m;
	char     model[32];

	if (!name || size <= 0 || !Find(dpy, key, &m)) return 0;
	if (Edid_Name(dpy, m.output, model, sizeof(model)))
		snprintf(name, (size_t)size, "%s (%s)", model, m.key);
	else
		snprintf(name, (size_t)size, "%s", m.key);
	return 1;
}

// The monitor holding most of the window - Windows' and macOS' own answer.
int Pugl_View_Screen(PuglView *view, char *key)
{
	Display          *dpy;
	Window            win, child;
	XWindowAttributes attr;
	MONITOR           mons[MAX_MONITORS];
	int               n, i, x, y, best = -1;
	long              best_area = 0;

	if (!view || !key) return 0;
	dpy = Display_Of(puglGetWorld(view));
	win = (Window)puglGetNativeView(view);
	if (!dpy || !win) return 0;
	if (!XGetWindowAttributes(dpy, win, &attr) || attr.map_state != IsViewable) return 0;
	if (!XTranslateCoordinates(dpy, win, DefaultRootWindow(dpy), 0, 0, &x, &y, &child))
		return 0;

	n = Monitors(dpy, mons, MAX_MONITORS);
	if (n > MAX_MONITORS) n = MAX_MONITORS;
	for (i = 0; i < n; i++) {
		long l = x > mons[i].x ? x : mons[i].x;
		long t = y > mons[i].y ? y : mons[i].y;
		long r = (x + attr.width)  < (mons[i].x + mons[i].w) ? (x + attr.width)  : (mons[i].x + mons[i].w);
		long b = (y + attr.height) < (mons[i].y + mons[i].h) ? (y + attr.height) : (mons[i].y + mons[i].h);
		long area = (r > l && b > t) ? (r - l) * (b - t) : 0;
		if (area > best_area) { best_area = area; best = i; }
	}
	if (best < 0) return 0;
	memcpy(key, mons[best].key, PUGL_SCREEN_KEY);
	return 1;
}
