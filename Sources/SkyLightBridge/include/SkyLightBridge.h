#ifndef SKYLIGHT_BRIDGE_H
#define SKYLIGHT_BRIDGE_H

#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include <stdbool.h>

// A thin C bridge over the private SkyLight WindowServer API, used to draw per-window borders
// the way JankyBorders does: our own server-side windows, filtered to real top-level windows,
// ordered directly above their target so the z-order stays correct. Technique/API reference only
// (function names, arguments, filter predicate); the implementation is our own.

// Filter `candidates` (CGWindowIDs) down to the ones that should get a border (real, top-level,
// document/modal-floating windows — excludes menus, tooltips, sheets, sub-windows). Writes the
// surviving window ids and their window-server level into the out arrays; returns the count.
int  skb_filter_windows(const uint32_t *candidates, int n,
                        uint32_t *out_wid, int *out_level, int cap);

// Create a transparent server window of size w x h. Returns its window id and, via the return
// value, a retained CGContext to draw the border into (release with skb_destroy). 0 on failure.
CGContextRef skb_create(float w, float h, bool hidpi, uint32_t *out_wid) __attribute__((cf_returns_retained));

// Resize (and reposition) the border window; `x`,`y` are top-left global (WindowServer) coords.
void skb_set_frame(uint32_t wid, float x, float y, float w, float h);
// Fast reposition only (no reshape) — for smooth dragging.
void skb_move(uint32_t wid, float x, float y);
// Move the border window onto the same space as its target (a fresh window is on no space).
// Returns the space id used (0 if the target's space could not be resolved).
uint64_t skb_send_to_space(uint32_t wid, uint32_t target);
// Place the border at `level`, directly above `target` in the global z-order.
void skb_order(uint32_t wid, int level, uint32_t target);
// Push the drawn content to the screen.
void skb_flush(uint32_t wid, CGContextRef ctx);
// Tear the border window down.
void skb_destroy(uint32_t wid);
// Order any window of this process out, from any thread (no AppKit involved).
void skb_order_out(uint32_t wid);

// Whether the Space showing on the display with this UUID is a full-screen app's Space.
// NSWindow.isOnActiveSpace cannot tell for a window that joins all Spaces (the dock's).
bool skb_display_shows_fullscreen_space(CFStringRef display_uuid);

// The uuid of the Space showing on that display, the one macOS keeps across restarts ("" for a
// first desktop that never got one). NULL when the window server does not say.
CFStringRef skb_copy_current_space_uuid(CFStringRef display_uuid) CF_RETURNS_RETAINED;
// The uuids of every Space that exists now, on every display. NULL when unknown.
CFArrayRef skb_copy_space_uuids(void) CF_RETURNS_RETAINED;

#endif
