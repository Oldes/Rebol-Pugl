//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The screens on macOS: [NSScreen screens], each named by its
// CGDirectDisplayID, which stays the same while the display is connected.
// An NSScreen is not kept - AppKit replaces them when the configuration
// changes - so every question walks the list again and matches by id.
//
// Pugl gives a window's position in pixels: points times its screen's
// backing scale, with Y down from the top of [NSScreen mainScreen]. A
// screen is given the same way - flipped against the same screen, scaled
// by its own factor - so that once both are divided by their scale, a
// window's offset and its screen's are the same points.
//
// The primary screen is the first of the list: the one with the menu bar.
//

#import <Cocoa/Cocoa.h>
#include <stdio.h>
#include <string.h>

#include "pugl-screen.h"

static CGDirectDisplayID Display_Id(NSScreen *screen)
{
	NSNumber *num = [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
	return num ? (CGDirectDisplayID)[num unsignedIntValue] : 0;
}

static void Display_Key(NSScreen *screen, char *key)
{
	snprintf(key, PUGL_SCREEN_KEY, "%u", (unsigned)Display_Id(screen));
}

static NSScreen *Find_Screen(const char *key, int *primary)
{
	NSArray   *screens = [NSScreen screens];
	char       k[PUGL_SCREEN_KEY];
	NSUInteger n;

	if (!key) return nil;
	for (n = 0; n < [screens count]; n++) {
		NSScreen *screen = [screens objectAtIndex:n];
		Display_Key(screen, k);
		if (strcmp(k, key) == 0) {
			if (primary) *primary = (n == 0);
			return screen;
		}
	}
	return nil;
}

// A Cocoa rectangle (bottom-left origin, Y up, points) as Pugl's: Y down
// from the top of the main screen, in the screen's pixels.
static void To_Pixels(NSRect r, double k, int *x, int *y, int *w, int *h)
{
	NSScreen *main = [NSScreen mainScreen];
	double    top  = main ? [main frame].size.height : 0.0;

	*x = (int)(r.origin.x * k);
	*y = (int)((top - (r.origin.y + r.size.height)) * k);
	*w = (int)(r.size.width  * k);
	*h = (int)(r.size.height * k);
}

int Pugl_Screen_Keys(PuglWorld *world, char (*keys)[PUGL_SCREEN_KEY], int max)
{
	@autoreleasepool {
		NSArray   *screens = [NSScreen screens];
		NSUInteger n, count = [screens count];
		(void)world;

		// Already primary first: AppKit puts the menu-bar screen at 0.
		for (n = 0; n < count && (int)n < max; n++)
			Display_Key([screens objectAtIndex:n], keys[n]);
		return (int)count;
	}
}

int Pugl_Screen_Info(PuglWorld *world, const char *key, PuglScreenInfo *info)
{
	@autoreleasepool {
		int       primary = 0;
		NSScreen *screen;
		double    k;
		(void)world;

		if (!info || !(screen = Find_Screen(key, &primary))) return 0;
		k = [screen backingScaleFactor];
		To_Pixels([screen frame], k, &info->x, &info->y, &info->w, &info->h);
		// Without the menu bar and the Dock - where a window can go.
		To_Pixels([screen visibleFrame], k, &info->wx, &info->wy, &info->ww, &info->wh);
		info->scale   = k;
		info->primary = primary;
		return 1;
	}
}

// `localizedName` is macOS 10.15 and later, so it is asked for by selector;
// before it there is no public API for the name, and a display is called
// by its id.
int Pugl_Screen_Name(PuglWorld *world, const char *key, char *name, int size)
{
	@autoreleasepool {
		NSScreen *screen;
		NSString *str = nil;
		(void)world;

		if (!name || size <= 0 || !(screen = Find_Screen(key, NULL))) return 0;
		if ([screen respondsToSelector:@selector(localizedName)])
			str = [screen performSelector:@selector(localizedName)];
		if (!str) str = [NSString stringWithFormat:@"Display %s", key];
		snprintf(name, (size_t)size, "%s", [str UTF8String]);
		return 1;
	}
}

int Pugl_View_Screen(PuglView *view, char *key)
{
	@autoreleasepool {
		NSView   *ns;
		NSScreen *screen;

		if (!view || !key || !(ns = (NSView*)puglGetNativeView(view))) return 0;
		// The screen holding most of the window; nil while it is on none.
		screen = [[ns window] screen];
		if (!screen) return 0;
		Display_Key(screen, key);
		return 1;
	}
}
