#include "SkyLightBridge.h"
#include <CoreFoundation/CoreFoundation.h>

// --- Private SkyLight / CoreGraphicsServices prototypes (resolved by linking SkyLight) ---
extern int SLSMainConnectionID(void);
extern CGError CGSNewRegionWithRect(CGRect *rect, CFTypeRef *outRegion);

extern CGError SLSNewWindow(int cid, int type, float x, float y, CFTypeRef region, uint32_t *wid);
extern CGError SLSReleaseWindow(int cid, uint32_t wid);
extern CGContextRef SLWindowContextCreate(int cid, uint32_t wid, CFDictionaryRef options);
extern CGError SLSSetWindowShape(int cid, uint32_t wid, float x, float y, CFTypeRef shape);
extern CGError SLSSetWindowResolution(int cid, uint32_t wid, double res);
extern CGError SLSSetWindowOpacity(int cid, uint32_t wid, bool isOpaque);
extern CGError SLSSetWindowTags(int cid, uint32_t wid, uint64_t *tags, int tag_size);
extern CGError SLSClearWindowTags(int cid, uint32_t wid, uint64_t *tags, int tag_size);
extern CGError SLSFlushWindowContentRegion(int cid, uint32_t wid, void *dirty);

extern CFTypeRef SLSTransactionCreate(int cid);
extern CGError SLSTransactionCommit(CFTypeRef transaction, int synchronous);
extern CGError SLSTransactionMoveWindowWithGroup(CFTypeRef transaction, uint32_t wid, CGPoint origin);
extern CGError SLSTransactionSetWindowLevel(CFTypeRef transaction, uint32_t wid, int level);
extern CGError SLSTransactionSetWindowSubLevel(CFTypeRef transaction, uint32_t wid, int level);
extern CGError SLSTransactionOrderWindow(CFTypeRef transaction, uint32_t wid, int order, uint32_t rel_wid);

extern CGError SLSWindowThaw(int cid, uint32_t wid);
extern CGError SLSWindowSetShadowProperties(uint32_t wid, CFDictionaryRef properties);
extern CFArrayRef SLSCopySpacesForWindows(int cid, int selector, CFArrayRef window_list);
extern CGError SLSMoveWindowsToManagedSpace(int cid, CFArrayRef window_list, uint64_t sid);
extern CFArrayRef SLSCopyWindowsWithOptionsAndTags(int cid, uint32_t owner, CFArrayRef spaces,
                                                   uint32_t options, uint64_t *set_tags, uint64_t *clear_tags);
extern CFTypeRef SLSWindowQueryWindows(int cid, CFArrayRef windows, int count);
extern CFTypeRef SLSWindowQueryResultCopyWindows(CFTypeRef query);
extern int  SLSWindowIteratorGetCount(CFTypeRef iterator);
extern bool SLSWindowIteratorAdvance(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetWindowID(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetTags(CFTypeRef iterator);
extern uint64_t SLSWindowIteratorGetAttributes(CFTypeRef iterator);
extern uint32_t SLSWindowIteratorGetParentID(CFTypeRef iterator);
extern int  SLSWindowIteratorGetLevel(CFTypeRef iterator);

// Window tag bits (yabai/JankyBorders naming).
#define WINDOW_TAG_DOCUMENT      (1ULL << 0)
#define WINDOW_TAG_FLOATING      (1ULL << 1)
#define WINDOW_TAG_ATTACHED      (1ULL << 7)
#define WINDOW_TAG_IGNORES_CYCLE (1ULL << 18)
#define WINDOW_TAG_MODAL         (1ULL << 31)

// A window is border-worthy if it is a real, top-level document (or a modal floating panel):
// no parent, standard attributes, not attached/ignored, and document- or modal-floating-tagged.
// This is what excludes menus, tooltips, sheets and sub-windows.
static bool window_suitable(CFTypeRef it) {
    uint64_t tags       = SLSWindowIteratorGetTags(it);
    uint64_t attributes = SLSWindowIteratorGetAttributes(it);
    uint32_t parent     = SLSWindowIteratorGetParentID(it);
    return (parent == 0)
        && ((attributes & 0x2) || (tags & 0x0400000000000000ULL))
        && !(tags & WINDOW_TAG_ATTACHED)
        && !(tags & WINDOW_TAG_IGNORES_CYCLE)
        && ((tags & WINDOW_TAG_DOCUMENT)
            || ((tags & WINDOW_TAG_FLOATING) && (tags & WINDOW_TAG_MODAL)));
}

int skb_filter_windows(const uint32_t *candidates, int n,
                       uint32_t *out_wid, int *out_level, int cap) {
    if (n <= 0) return 0;
    int cid = SLSMainConnectionID();
    CFMutableArrayRef arr = CFArrayCreateMutable(NULL, n, &kCFTypeArrayCallBacks);
    for (int i = 0; i < n; i++) {
        CFNumberRef num = CFNumberCreate(NULL, kCFNumberSInt32Type, &candidates[i]);
        CFArrayAppendValue(arr, num);
        CFRelease(num);
    }
    int out = 0;
    CFTypeRef query = SLSWindowQueryWindows(cid, arr, 0);
    if (query) {
        CFTypeRef it = SLSWindowQueryResultCopyWindows(query);
        if (it) {
            while (out < cap && SLSWindowIteratorAdvance(it)) {
                if (window_suitable(it)) {
                    out_wid[out]   = SLSWindowIteratorGetWindowID(it);
                    out_level[out] = SLSWindowIteratorGetLevel(it);
                    out++;
                }
            }
            CFRelease(it);
        }
        CFRelease(query);
    }
    CFRelease(arr);
    return out;
}

CGContextRef skb_create(float w, float h, bool hidpi, uint32_t *out_wid) {
    int cid = SLSMainConnectionID();
    CGRect frame = CGRectMake(0, 0, w, h);
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&frame, &region);
    if (!region) { *out_wid = 0; return NULL; }

    uint64_t set_tags = (1ULL << 1) | (1ULL << 9);   // floating + no-shadow (JankyBorders' set)
    uint64_t clear_tags = 0;
    uint32_t wid = 0;
    SLSNewWindow(cid, 2 /* kCGBackingStoreBuffered */, -9999, -9999, region, &wid);
    CFRelease(region);
    if (wid == 0) { *out_wid = 0; return NULL; }

    SLSSetWindowResolution(cid, wid, hidpi ? 2.0 : 1.0);
    SLSSetWindowTags(cid, wid, &set_tags, 64);
    SLSClearWindowTags(cid, wid, &clear_tags, 64);
    SLSSetWindowOpacity(cid, wid, false);

    // Kill the window shadow — otherwise the ring casts a shadow inward over the target window.
    CFIndex density = 0;
    CFNumberRef density_cf = CFNumberCreate(NULL, kCFNumberCFIndexType, &density);
    const void *keys[1] = { CFSTR("com.apple.WindowShadowDensity") };
    const void *vals[1] = { density_cf };
    CFDictionaryRef shadow = CFDictionaryCreate(NULL, keys, vals, 1,
                                                &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SLSWindowSetShadowProperties(wid, shadow);
    CFRelease(density_cf);
    CFRelease(shadow);

    CGContextRef ctx = SLWindowContextCreate(cid, wid, NULL);
    if (ctx) CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
    *out_wid = wid;
    return ctx;   // retained (create rule); released by ARC on the Swift side
}

void skb_set_frame(uint32_t wid, float x, float y, float w, float h) {
    if (wid == 0) return;
    int cid = SLSMainConnectionID();
    CGRect frame = CGRectMake(0, 0, w, h);
    CFTypeRef region = NULL;
    CGSNewRegionWithRect(&frame, &region);
    if (!region) return;
    SLSSetWindowShape(cid, wid, x, y, region);
    CFRelease(region);
}

void skb_move(uint32_t wid, float x, float y) {
    if (wid == 0) return;
    int cid = SLSMainConnectionID();
    CFTypeRef t = SLSTransactionCreate(cid);
    if (!t) return;
    SLSTransactionMoveWindowWithGroup(t, wid, CGPointMake(x, y));
    SLSTransactionCommit(t, 0);
    CFRelease(t);
}

uint64_t skb_send_to_space(uint32_t wid, uint32_t target) {
    if (wid == 0 || target == 0) return 0;
    int cid = SLSMainConnectionID();
    uint64_t sid = 0;
    CFNumberRef tn = CFNumberCreate(NULL, kCFNumberSInt32Type, &target);
    const void *tvals[1] = { tn };
    CFArrayRef tlist = CFArrayCreate(NULL, tvals, 1, &kCFTypeArrayCallBacks);
    CFArrayRef spaces = SLSCopySpacesForWindows(cid, 0x7, tlist);
    if (spaces) {
        if (CFArrayGetCount(spaces) > 0) {
            CFNumberRef sn = (CFNumberRef)CFArrayGetValueAtIndex(spaces, 0);
            CFNumberGetValue(sn, CFNumberGetType(sn), &sid);
        }
        CFRelease(spaces);
    }
    CFRelease(tlist);
    CFRelease(tn);
    if (sid == 0) return 0;
    CFNumberRef bn = CFNumberCreate(NULL, kCFNumberSInt32Type, &wid);
    const void *bvals[1] = { bn };
    CFArrayRef blist = CFArrayCreate(NULL, bvals, 1, &kCFTypeArrayCallBacks);
    SLSMoveWindowsToManagedSpace(cid, blist, sid);
    CFRelease(blist);
    CFRelease(bn);
    return sid;
}

void skb_order(uint32_t wid, int level, uint32_t target) {
    if (wid == 0) return;
    int cid = SLSMainConnectionID();
    CFTypeRef t = SLSTransactionCreate(cid);
    if (!t) return;
    SLSTransactionSetWindowLevel(t, wid, level);
    SLSTransactionSetWindowSubLevel(t, wid, 0);
    SLSTransactionOrderWindow(t, wid, 1 /* above */, target);
    SLSTransactionCommit(t, 0);
    CFRelease(t);
}

void skb_flush(uint32_t wid, CGContextRef ctx) {
    if (ctx) CGContextFlush(ctx);
    if (wid) {
        int cid = SLSMainConnectionID();
        SLSFlushWindowContentRegion(cid, wid, NULL);
        SLSWindowThaw(cid, wid);
    }
}

void skb_destroy(uint32_t wid) {
    if (wid) SLSReleaseWindow(SLSMainConnectionID(), wid);
}
