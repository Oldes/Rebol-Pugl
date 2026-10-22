# Rebol/Pugl

[Pugl](https://github.com/lv2/pugl) extension for [Rebol3](https://github.com/Oldes/Rebol3) (version 3.20.10 and higher)

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
