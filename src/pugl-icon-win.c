//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The window icon on Windows.
//
// Made twice, at the two sizes Windows asks for - the small one for the
// title bar, the big one for Alt-Tab and the taskbar - each scaled down
// here with a box filter rather than left to Windows, whose stretching of
// an icon is nearest-neighbour and turns a 256 px picture into noise at
// 16. Colours are averaged weighted by their alpha, so a transparent
// pixel's colour does not bleed into its neighbours.
//
// A 32-bit icon takes straight (not premultiplied) alpha in a top-down
// BGRA DIB, which is the image! layout already; the AND mask is only there
// because CreateIconIndirect wants one, and is ignored for 32 bits.
//

// The nest defines these for pugl's own sources; this file needs the
// system metrics (the icon sizes) back.
#undef NOSYSMETRICS
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <string.h>

#include "pugl-icon.h"

static void Scale_BGRA(const unsigned char *src, int sw, int sh,
                       unsigned char *dst, int dw, int dh)
{
	int x, y, sx, sy;
	for (y = 0; y < dh; y++) {
		int y0 = y * sh / dh, y1 = (y + 1) * sh / dh;
		if (y1 <= y0) y1 = y0 + 1;
		for (x = 0; x < dw; x++) {
			int x0 = x * sw / dw, x1 = (x + 1) * sw / dw;
			double b = 0, g = 0, r = 0, a = 0, n = 0;
			unsigned char *d = dst + ((size_t)y * dw + x) * 4;
			if (x1 <= x0) x1 = x0 + 1;
			for (sy = y0; sy < y1; sy++) {
				const unsigned char *p = src + ((size_t)sy * sw + x0) * 4;
				for (sx = x0; sx < x1; sx++, p += 4) {
					double w = p[3];
					b += p[0] * w; g += p[1] * w; r += p[2] * w;
					a += w; n += 1;
				}
			}
			if (a > 0) {
				d[0] = (unsigned char)(b / a + 0.5);
				d[1] = (unsigned char)(g / a + 0.5);
				d[2] = (unsigned char)(r / a + 0.5);
			} else {
				d[0] = d[1] = d[2] = 0;
			}
			d[3] = (unsigned char)(a / n + 0.5);
		}
	}
}

static HICON Make_Icon(const unsigned char *bgra, int w, int h, int size)
{
	BITMAPV5HEADER bi;
	ICONINFO       ii;
	HBITMAP        color, mask;
	HICON          icon;
	void          *bits = NULL;
	HDC            dc;

	if (size < 1) size = 1;
	ZeroMemory(&bi, sizeof(bi));
	bi.bV5Size        = sizeof(bi);
	bi.bV5Width       = size;
	bi.bV5Height      = -size;          // top-down, as an image! is
	bi.bV5Planes      = 1;
	bi.bV5BitCount    = 32;
	bi.bV5Compression = BI_BITFIELDS;
	bi.bV5RedMask     = 0x00FF0000;
	bi.bV5GreenMask   = 0x0000FF00;
	bi.bV5BlueMask    = 0x000000FF;
	bi.bV5AlphaMask   = 0xFF000000;

	dc    = GetDC(NULL);
	color = CreateDIBSection(dc, (BITMAPINFO*)&bi, DIB_RGB_COLORS, &bits, NULL, 0);
	ReleaseDC(NULL, dc);
	if (!color || !bits) { if (color) DeleteObject(color); return NULL; }

	if (w == size && h == size) memcpy(bits, bgra, (size_t)size * size * 4);
	else Scale_BGRA(bgra, w, h, (unsigned char*)bits, size, size);

	mask = CreateBitmap(size, size, 1, 1, NULL);
	if (!mask) { DeleteObject(color); return NULL; }

	ZeroMemory(&ii, sizeof(ii));
	ii.fIcon    = TRUE;
	ii.hbmMask  = mask;
	ii.hbmColor = color;
	icon = CreateIconIndirect(&ii);   // copies both bitmaps
	DeleteObject(mask);
	DeleteObject(color);
	return icon;
}

void Pugl_Free_Native_Icon(void **icons)
{
	int i;
	if (!icons) return;
	for (i = 0; i < 2; i++) {
		if (icons[i]) DestroyIcon((HICON)icons[i]);
		icons[i] = NULL;
	}
}

int Pugl_Set_Native_Icon(PuglView *view, void **icons,
                         const unsigned char *bgra, int w, int h)
{
	HWND  hwnd = (HWND)puglGetNativeView(view);
	HICON big = NULL, little = NULL;   // not `small`: rpcndr.h defines it

	if (!hwnd || !icons) return 0;

	if (bgra && w > 0 && h > 0) {
		big    = Make_Icon(bgra, w, h, GetSystemMetrics(SM_CXICON));
		little = Make_Icon(bgra, w, h, GetSystemMetrics(SM_CXSMICON));
		if (!big || !little) {
			if (big)    DestroyIcon(big);
			if (little) DestroyIcon(little);
			return 0;
		}
	}
	// NULL for both puts the class's (the default) icon back. The old ones
	// are freed only once the window no longer uses them.
	SendMessageW(hwnd, WM_SETICON, ICON_BIG,   (LPARAM)big);
	SendMessageW(hwnd, WM_SETICON, ICON_SMALL, (LPARAM)little);
	Pugl_Free_Native_Icon(icons);
	icons[0] = big;
	icons[1] = little;
	return 1;
}
