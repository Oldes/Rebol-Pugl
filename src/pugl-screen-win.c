//
// Project: Rebol/Pugl extension
// SPDX-License-Identifier: MIT
// ===========================================================================
// The screens on Windows: the monitors, each named by its GDI device name
// ("\\.\DISPLAY1"), which stays the same while it is connected. An
// HMONITOR does not - it can be replaced whenever the configuration
// changes - so it is never kept: every question enumerates them again.
//
// Rectangles are desktop pixels as this process sees them, which is the
// space Pugl places windows in. The scale is worked out the way Pugl does
// it for a window (puglWinGetViewScaleFactor): the monitor's own when the
// process is DPI aware, else 1.0 - so a screen's scale is what a window on
// it reports.
//

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <string.h>
#include <stdio.h>

#include "pugl-screen.h"

#define MAX_MONITORS 16

typedef struct {
	MONITORINFOEXW info[MAX_MONITORS];
	HMONITOR       mon[MAX_MONITORS];
	int            count;
} MONITOR_LIST;

static BOOL CALLBACK Collect_Monitor(HMONITOR mon, HDC dc, LPRECT rect, LPARAM lp)
{
	MONITOR_LIST *list = (MONITOR_LIST*)lp;
	(void)dc; (void)rect;

	if (list->count >= MAX_MONITORS) return FALSE;
	ZeroMemory(&list->info[list->count], sizeof(MONITORINFOEXW));
	list->info[list->count].cbSize = sizeof(MONITORINFOEXW);
	if (GetMonitorInfoW(mon, (MONITORINFO*)&list->info[list->count])) {
		list->mon[list->count] = mon;
		list->count++;
	}
	return TRUE;
}

static void Monitor_Key(const MONITORINFOEXW *mi, char *key)
{
	int n = WideCharToMultiByte(CP_UTF8, 0, mi->szDevice, -1,
	                            key, PUGL_SCREEN_KEY, NULL, NULL);
	if (n <= 0) key[0] = 0;
	key[PUGL_SCREEN_KEY - 1] = 0;
}

static int Find_Monitor(const char *key, MONITORINFOEXW *out, HMONITOR *mon)
{
	MONITOR_LIST list;
	char         k[PUGL_SCREEN_KEY];
	int          n;

	if (!key) return 0;
	list.count = 0;
	EnumDisplayMonitors(NULL, NULL, Collect_Monitor, (LPARAM)&list);
	for (n = 0; n < list.count; n++) {
		Monitor_Key(&list.info[n], k);
		if (strcmp(k, key) == 0) {
			*out = list.info[n];
			if (mon) *mon = list.mon[n];
			return 1;
		}
	}
	return 0;
}

typedef HRESULT(WINAPI* PFN_GetProcessDpiAwareness)(HANDLE, DWORD*);
typedef HRESULT(WINAPI* PFN_GetScaleFactorForMonitor)(HMONITOR, DWORD*);

static double Monitor_Scale(HMONITOR mon)
{
	HMODULE shcore = LoadLibraryExW(L"Shcore.dll", NULL, LOAD_LIBRARY_SEARCH_SYSTEM32);
	PFN_GetProcessDpiAwareness   aware;
	PFN_GetScaleFactorForMonitor factor;
	DWORD dpiAware = 0, scale = 100;

	if (!shcore) return 1.0;
	aware  = (PFN_GetProcessDpiAwareness)(void*)GetProcAddress(shcore, "GetProcessDpiAwareness");
	factor = (PFN_GetScaleFactorForMonitor)(void*)GetProcAddress(shcore, "GetScaleFactorForMonitor");
	if (aware && factor && !aware(NULL, &dpiAware) && dpiAware) factor(mon, &scale);
	FreeLibrary(shcore);
	return (double)scale / 100.0;
}

int Pugl_Screen_Keys(PuglWorld *world, char (*keys)[PUGL_SCREEN_KEY], int max)
{
	MONITOR_LIST list;
	int          at = 0, pass, n;
	(void)world;

	list.count = 0;
	EnumDisplayMonitors(NULL, NULL, Collect_Monitor, (LPARAM)&list);

	// Two passes: the primary first, then the rest in the system's order.
	for (pass = 0; pass < 2; pass++) {
		for (n = 0; n < list.count; n++) {
			int primary = (list.info[n].dwFlags & MONITORINFOF_PRIMARY) != 0;
			if (primary != (pass == 0)) continue;
			if (at < max) Monitor_Key(&list.info[n], keys[at]);
			at++;
		}
	}
	return at;
}

int Pugl_Screen_Info(PuglWorld *world, const char *key, PuglScreenInfo *info)
{
	MONITORINFOEXW mi;
	HMONITOR       mon = NULL;
	(void)world;

	if (!info || !Find_Monitor(key, &mi, &mon)) return 0;
	info->x  = mi.rcMonitor.left;
	info->y  = mi.rcMonitor.top;
	info->w  = mi.rcMonitor.right  - mi.rcMonitor.left;
	info->h  = mi.rcMonitor.bottom - mi.rcMonitor.top;
	info->wx = mi.rcWork.left;
	info->wy = mi.rcWork.top;
	info->ww = mi.rcWork.right  - mi.rcWork.left;
	info->wh = mi.rcWork.bottom - mi.rcWork.top;
	info->scale   = Monitor_Scale(mon);
	info->primary = (mi.dwFlags & MONITORINFOF_PRIMARY) ? 1 : 0;
	return 1;
}

// What the monitor calls itself, as the display settings list it - asked
// of the MONITOR under the adapter output, whose own name is only the
// device path. Often a model name; on some systems only "Generic PnP
// Monitor". The device name when even that fails.
int Pugl_Screen_Name(PuglWorld *world, const char *key, char *name, int size)
{
	MONITORINFOEXW  mi;
	DISPLAY_DEVICEW dd;
	const WCHAR    *wide;
	int             n;
	(void)world;

	if (!name || size <= 0 || !Find_Monitor(key, &mi, NULL)) return 0;
	ZeroMemory(&dd, sizeof(dd));
	dd.cb = sizeof(dd);
	wide = (EnumDisplayDevicesW(mi.szDevice, 0, &dd, 0) && dd.DeviceString[0])
	     ? dd.DeviceString : mi.szDevice;
	n = WideCharToMultiByte(CP_UTF8, 0, wide, -1, name, size, NULL, NULL);
	if (n <= 0) name[0] = 0;
	name[size - 1] = 0;
	return 1;
}

int Pugl_View_Screen(PuglView *view, char *key)
{
	HWND           hwnd;
	HMONITOR       mon;
	MONITORINFOEXW mi;

	if (!view || !key || !(hwnd = (HWND)puglGetNativeView(view))) return 0;
	// The monitor holding most of the window - where Windows itself puts
	// it when maximised.
	mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONULL);
	if (!mon) return 0;
	ZeroMemory(&mi, sizeof(mi));
	mi.cbSize = sizeof(mi);
	if (!GetMonitorInfoW(mon, (MONITORINFO*)&mi)) return 0;
	Monitor_Key(&mi, key);
	return key[0] ? 1 : 0;
}
