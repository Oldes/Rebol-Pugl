# Rebol/Pugl

[Pugl](https://github.com/lv2/pugl) extension for [Rebol3](https://github.com/Oldes/Rebol3) (version 3.22.10 and higher)

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
* `size` `[pair!]` Size of the window
* `/title`
* `text` `[string!]` Text shown in the title bar
* `/at`
* `offset` `[pair!]` Position of the top-left corner on the screen
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
* `target` `[handle!]` A window (all its images) or one image

#### `add-image` `:window` `:image` `:offset`
Shows an image in a window and returns its handle
* `window` `[handle!]`
* `image` `[image!]` Shown as is; the window keeps a reference, not a copy
* `offset` `[pair!]` Position of its top-left corner in the window
* `/size`
* `sz` `[pair!]` Scales it to this size (default: the image's own)

#### `remove-image` `:image`
Takes an image out of its window
* `image` `[handle!]`


## Used handles and its getters / setters

#### __WINDOW__ - Pugl window handle - a top-level window with an OpenGL view

```rebol
;Refinement       Gets                Sets                          Description
/title            string!             string!                       "Text shown in the title bar"
/size             pair!               pair!                         "Size of the window"
/offset           pair!               pair!                         "Position of the top-left corner on the screen"
/scale            decimal!            none                          "Scale factor - 1.0 at standard DPI, 2.0 on a Retina display"
/id               integer!            none                          "Native view handle (HWND / NSView* / X11 Window) as an integer"
/visible?         logic!              none                          "Whether the window is currently visible"
/open?            logic!              none                          "False once the window has been closed"
/images           block!              none                          "Images added with `add-image`, in drawing order - the first one at the bottom"
/icon             image!              [image! none!]                "Icon of the window - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
```

#### __IMAGE__ - Pugl image handle - an image! shown in a window

```rebol
;Refinement       Gets                Sets                          Description
/image            image!              image!                        "The image shown - kept by reference: draw into it and call `redraw`"
/offset           pair!               pair!                         "Position of its top-left corner in the window"
/size             pair!               pair!                         "Size it is drawn at - scaled to it; a zero axis is the image's own"
/visible?         logic!              logic!                        "Whether it is drawn"
/track?           logic!              logic!                        "Whether `enter` and `leave` are reported for it, with the image as the source; off by default"
/hover?           logic!              none                          "Whether the pointer is over it - the topmost visible image under the pointer, as of the last `poll-events`"
/window           handle!             none                          "The window it is shown in; none once removed"
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
