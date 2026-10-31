[![Rebol-Pugl CI](https://github.com/Oldes/Rebol-Pugl/actions/workflows/main.yml/badge.svg)](https://github.com/Oldes/Rebol-Pugl/actions/workflows/main.yml)

# Rebol/Pugl

[Pugl](https://github.com/lv2/pugl) extension for [Rebol3](https://github.com/Oldes/Rebol3) (version 3.20.5 and higher)

Pugl (PlUgin Graphics Library) is a minimal, portable API for embeddable GUIs. It supports
Windows (Win32), macOS (Cocoa) and Linux (X11), with stub (native) and OpenGL drawing backends.

> **Status:** work in progress, the API is not stable yet.

## Building

The project is built using [Siskin Builder](https://github.com/Siskin-framework/Builder/).
Pugl sources are fetched automatically from GitHub into the `pugl/` directory.

```
siskin Rebol-Pugl.nest
```

Running it without arguments lists the available eggs (build targets):

* `Rebol Pugl extension` – the Rebol extension itself (with the stub backend)
* `Example: ...` – original Pugl examples, useful to verify that Pugl itself builds and runs on the platform

### Dependencies

* **Windows:** no extra dependencies (links with `dwmapi`, `gdi32`, `shell32`, `shlwapi`, `user32`; `opengl32` for GL)
* **Linux:** X11 development packages, for example on Debian/Ubuntu:
  ```
  sudo apt install libx11-dev libxcursor-dev libxrandr-dev libxext-dev libgl-dev
  ```
* **macOS:** Xcode command line tools (Cocoa, CoreVideo and OpenGL frameworks)

## Usage

```rebol
pugl: import %pugl.rebx
```

## License

* Rebol/Pugl extension: MIT
* [Pugl](https://github.com/lv2/pugl): ISC, Copyright 2012-2026 David Robillard

## Extension commands:


#### `open-window` `:size`
Creates a top-level window and returns its handle
* `size` `[pair!]` Size of the window, in units - device pixels / scale
* `/title`
* `text` `[string!]` Text shown in the title bar
* `/at`
* `offset` `[pair!]` Position of the top-left corner on the screen, in units
* `/hidden` Creates the window without showing it
* `/fixed` The user cannot resize it

#### `close-window` `:window`
Destroys the window
* `window` `[handle!]`

#### `show-window` `:window`
Makes the window visible
* `window` `[handle!]`

#### `hide-window` `:window`
Hides the window without destroying it
* `window` `[handle!]`

#### `poll-events`
Runs one Pugl main loop iteration and returns the collected events

#### `redraw` `:target`
Shows images again - use after drawing into them
* `target` `[handle!]` A window or a group (all the images in it) or one image

#### `add-image` `:target` `:image` `:offset`
Shows an image in a window or a group and returns its handle
* `target` `[handle!]` A window, or a group - then the offset is relative to it
* `image` `[image!]` Shown as is; the window keeps a reference, not a copy
* `offset` `[pair!]` Position of its top-left corner in the window
* `/size`
* `sz` `[pair!]` Scales it to this size (default: the image's own)
* `/part`
* `rect` `[block!]` Shows only this part of the image: [offset size] in its pixels - the first two values, so a block of many parts can be walked

#### `remove-image` `:image`
Takes an image out of its window - or a group, with all that is in it
* `image` `[handle!]` An image or a group

#### `add-group` `:target` `:offset`
Makes a group in a window or a group and returns its handle
* `target` `[handle!]` A window, or a group
* `offset` `[pair!]` Position of its origin - what is added to it is placed relative to it
* `/size`
* `sz` `[pair!]` Clips what is in it to this size (default: not clipped)

#### `image-at` `:window` `:point`
The topmost visible image at a point of the window, or none - where it is drawn, turned and clipped
* `window` `[handle!]`
* `point` `[pair!]` In the window, as an event's offset


## Used handles and its getters / setters

#### __WINDOW__ - Pugl window handle - a top-level window with an OpenGL view

```rebol
;Refinement       Gets                Sets                          Description
/title            string!             string!                       "Text shown in the title bar"
/size             pair!               pair!                         "Size of the window, in units"
/offset           pair!               pair!                         "Position of the top-left corner on the screen, in units"
/scale            decimal!            [decimal! integer! none!]     "Device pixels per unit - the screen's, 1.0 at standard DPI and 2.0 on a Retina display, until set (up to 16); none follows the screen again. Everything is in units: sizes, offsets, events, images - drawn this many times bigger. Setting it zooms: the window keeps its size on the screen, so its size in units changes, reported as `resize`"
/id               integer!            none                          "Native view handle (HWND / NSView* / X11 Window) as an integer"
/visible?         logic!              none                          "Whether the window is currently visible"
/open?            logic!              none                          "False once the window has been closed"
/images           block!              none                          "Images and groups added to it, in drawing order - the first one at the bottom"
/textures         integer!            none                          "How many textures it holds - one per image! shown, however many image handles show it"
/cursor           word!               word!                         "The pointer's shape over it, where nothing under the pointer has its own: arrow (default), caret, crosshair, hand, no, left-right, up-down, up-left-down-right, up-right-down-left or all-scroll"
/icon             image!              [image! none!]                "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
```

#### __IMAGE__ - Pugl image handle - an image! shown in a window

```rebol
;Refinement       Gets                Sets                          Description
/image            image!              image!                        "The image shown - kept by reference: draw into it and call `redraw`"
/fill             word!               word!                         "How it fills a size other than its own - scale (default); tile: repeated at its own size, the last ones cut; round: repeated a whole number of times, each scaled to fit. Not nine-scaled, it is a pattern: one shape, the texture repeated by the GPU - a part gets a copy of its own for it. With nine-scale, its edges and middle are repeated"
/nine-scale       block!              [block! none!]                "Scales it in nine pieces - [offset size] of the middle box, in its own pixels; the corners keep their size and the edges stretch one way only; none (default) scales it whole"
/part             block!              [block! none!]                "The part of the image shown - [offset size] in its pixels, a frame of an atlas; none (default) for all of it. Set, only the first two values are used, so a block of many parts can be walked"
/offset           pair!               pair!                         "Position of its top-left corner in the window - or in its group"
/size             pair!               pair!                         "Size it is drawn at - scaled to it; a zero axis is the image's own, or its part's"
/visible?         logic!              logic!                        "Whether it is drawn"
/track?           logic!              logic!                        "Whether it reports the pointer itself, as the event source: enter and leave, presses - and their release and drag, wherever the pointer goes - and scrolls over it; off by default"
/hover?           logic!              none                          "Whether the pointer is over it - the topmost visible image under the pointer, as of the last `poll-events`"
/window           handle!             none                          "The window it is shown in; none once removed"
/parent           handle!             none                          "The group it is in; none at the window's top level"
/rotation         decimal!            [decimal! integer!]           "Degrees it is turned around its pivot, clockwise (default 0.0)"
/scale            [decimal! pair!]    [decimal! integer! pair!]     "Scale around its pivot - one for both axes, or a pair for each (default 1.0); a pair! only while the two differ"
/pivot            pair!               pair!                         "Point it is turned and scaled around, in its own units from its top-left (default 0x0)"
/opacity          percent!            [percent! decimal! integer!]  "How opaque it is, 0% to 100% (default 100%); still there for the pointer at 0%"
/blend            word!               [word! none!]                 "How it is drawn over what is below: normal, add, multiply or screen; none (default) for its group's"
/filter           word!               [word! none!]                 "How it is sampled when not drawn 1:1 - nearest: sharp pixels, or linear: smooth; none (default) for its group's, nearest at the top. An atlas drawn linear wants a gap between its frames"
/cursor           word!               [word! none!]                 "The pointer's shape over it - one of the window's cursor words; none (default) for its group's, or the window's"
/tint             tuple!              [tuple! none!]                "A colour its own is multiplied by - a fourth value is alpha, 255 opaque, multiplied with its opacity; none (default) for none"
/index            integer!            [integer! word!]              "Its place in its window's or group's list, 1 at the bottom; set a number (clamped) or top or bottom to move it"
```

#### __GROUP__ - Pugl group handle - images and groups moved, hidden and hovered together

```rebol
;Refinement       Gets                Sets                          Description
/offset           pair!               pair!                         "Position of its origin in the window - or in its group; what is in it is placed relative to it"
/size             pair!               pair!                         "Size of the box from its origin which what is in it is clipped to - drawn and hit only inside; a zero axis is not clipped (default 0x0)"
/visible?         logic!              logic!                        "Whether what is in it is drawn"
/track?           logic!              logic!                        "Whether it reports the pointer itself, as a whole, as the event source: enter and leave, and presses and scrolls over any of its images which do not track it themselves; off by default"
/hover?           logic!              none                          "Whether the pointer is over one of its images, as of the last `poll-events`"
/images           block!              none                          "Images and groups added to it, in drawing order"
/window           handle!             none                          "The window it is shown in; none once removed"
/parent           handle!             none                          "The group it is in; none at the window's top level"
/rotation         decimal!            [decimal! integer!]           "Degrees it - and all in it - is turned around its pivot, clockwise (default 0.0)"
/scale            [decimal! pair!]    [decimal! integer! pair!]     "Scale around its pivot, of all in it - one for both axes, or a pair for each (default 1.0)"
/pivot            pair!               pair!                         "Point it is turned and scaled around, in its own units from its origin (default 0x0)"
/opacity          percent!            [percent! decimal! integer!]  "How opaque all in it is, 0% to 100% (default 100%), multiplied with their own"
/blend            word!               [word! none!]                 "How what is in it is drawn, where it does not say itself: normal, add, multiply or screen; none (default) for its own group's"
/filter           word!               [word! none!]                 "How all in it is sampled, where it does not say itself - nearest or linear; none (default) for its own group's"
/cursor           word!               [word! none!]                 "The pointer's shape over all in it which does not have its own; none (default) for its group's, or the window's"
/tint             tuple!              [tuple! none!]                "A colour all in it is multiplied by, on top of their own tint - a fourth value is alpha; none (default) for none"
/index            integer!            [integer! word!]              "Its place in its window's or group's list, 1 at the bottom; set a number (clamped) or top or bottom to move it, with all in it"
```


## Other extension values:
```rebol
do-events: function [
	"Pumps window events until the given window is closed"
	window  [handle!]
	handler [any-function!] "Called with one event! for each event"
	/rate delay [number!] {Longest it may sleep with nothing to do (default: 0.02)}
][
	;; `wait` does the sleeping, and the device pumps Pugl from inside
	;; it. There is no doorbell port yet, so an event is noticed at the
	;; end of the delay at the latest.
	delay: any [delay 0.02]
	forever [
		foreach evt poll-events [
			handler evt
			;; `close` only reports the request - closing is ours to do
			;; `==`, not `=`: on handles `=` compares only the type,
			;; so any window's close would match
			if all [evt/type = 'close  evt/source == window] [
				close-window window
			]
			unless window/open? [break]
		]
		unless window/open? [exit]
		wait delay
	]
]
```
