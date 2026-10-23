//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The icon on macOS. A Mac window has none of its own, so this is the
// application's - the Dock's - and whichever view set it last wins.
//
// The pixels are copied into a CFData the CGImage owns, since the image!
// series may move once this returns. An image! is B G R A in memory with
// straight alpha: a 32-bit little-endian ARGB word with the alpha first
// and NOT premultiplied, which a CGImage (unlike a bitmap context) may be.
//
// Manual retain/release, as the rest of the build.
//

#import <AppKit/AppKit.h>

#include "pugl-icon.h"

int Pugl_Set_Native_Icon(PuglView *view, void **icons,
                         const unsigned char *bgra, int w, int h)
{
	@autoreleasepool {
		CFDataRef         data;
		CGDataProviderRef provider;
		CGColorSpaceRef   space;
		CGImageRef        cg;
		NSImage          *icon;

		(void)view; (void)icons;
		if (![NSThread isMainThread]) return 0;

		if (!bgra || w <= 0 || h <= 0) {
			[NSApp setApplicationIconImage:nil];   // the bundle's own again
			return 1;
		}

		data = CFDataCreate(NULL, bgra, (CFIndex)w * (CFIndex)h * 4);
		if (!data) return 0;
		provider = CGDataProviderCreateWithCFData(data);
		CFRelease(data);   // the provider keeps it
		if (!provider) return 0;
		space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
		cg = CGImageCreate((size_t)w, (size_t)h, 8, 32, (size_t)w * 4, space,
		                   kCGImageAlphaFirst | kCGBitmapByteOrder32Little,
		                   provider, NULL, true, kCGRenderingIntentDefault);
		CGColorSpaceRelease(space);
		CGDataProviderRelease(provider);
		if (!cg) return 0;

		icon = [[[NSImage alloc] initWithCGImage:cg size:NSMakeSize((CGFloat)w, (CGFloat)h)]
			autorelease];
		CGImageRelease(cg);
		if (!icon) return 0;
		[NSApp setApplicationIconImage:icon];
		return 1;
	}
}

void Pugl_Free_Native_Icon(void **icons)
{
	(void)icons;
}
