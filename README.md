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


#### `open-view` `:size`
Creates a top-level view and returns its handle
* `size` `[pair!]` Size of the view
* `/title`
* `text` `[string!]` Text shown in the title bar
* `/at`
* `offset` `[pair!]` Position of the top-left corner on the screen
* `/hidden` Creates the view without showing it
* `/fixed` The user cannot resize it

#### `close-view` `:view`
Destroys the view
* `view` `[handle!]`

#### `show-view` `:view`
Makes the view visible
* `view` `[handle!]`

#### `hide-view` `:view`
Hides the view without destroying it
* `view` `[handle!]`

#### `poll-events`
Runs one Pugl main loop iteration and returns the collected events

#### `redraw` `:view`
Shows the view's image again - use after drawing into it
* `view` `[handle!]`


## Used handles and its getters / setters

#### __VIEW__ - Pugl view handle - a top-level window

```rebol
;Refinement       Gets                Sets                          Description
/title            string!             string!                       "Text shown in the title bar"
/size             pair!               pair!                         "Size of the view"
/offset           pair!               pair!                         "Position of the top-left corner on the screen"
/scale            decimal!            none                          "Scale factor - 1.0 at standard DPI, 2.0 on a Retina display"
/id               integer!            none                          "Native view handle (HWND / NSView* / X11 Window) as an integer"
/visible?         logic!              none                          "Whether the view is currently visible"
/open?            logic!              none                          "False once the view has been closed"
/image            image!              [image! none!]                "Image shown at its own size, centered in the view; none for nothing. Kept by reference - draw into it and call `redraw`"
/icon             image!              [image! none!]                "Icon of the view - its title bar and taskbar entry; on macOS the application's Dock icon, which the last one set wins; none for the default. Copied when set: drawing into the image changes it only when it is set again"
```


## Other extension values:
```rebol
do-events: function [
	"Pumps view events until the given view is closed"
	view    [handle!]
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
			;; so any view's close would match
			if all [evt/type = 'close  evt/source == view] [
				close-view view
			]
			unless view/open? [break]
		]
		unless view/open? [exit]
		wait delay
	]
]
```
