// RetroMac Virtual Camera — CoreMediaIO DAL Plugin
// Provides a virtual camera device ("RetroMac Cam") that reads processed frames
// from a shared IOSurface published by the main RetroMac app.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

#import <CoreMediaIO/CMIOHardwarePlugIn.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <IOSurface/IOSurface.h>
#import <Foundation/Foundation.h>

#pragma mark - Constants

static const int kWidth = 1280;
static const int kHeight = 720;
static const int kFPS = 30;

#define kPluginFactoryUUID CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR("9E6A4A30-1B5E-4E3A-9F2C-8D7B6C5A4E31"))
#define kPluginTypeUUID    CFUUIDCreateFromString(kCFAllocatorDefault, CFSTR("30010C1C-93BF-11D8-8B5B-000A95AF9C6A"))

#pragma mark - Forward Declarations

static HRESULT  _QueryInterface(void *self, REFIID uuid, LPVOID *interface);
static ULONG    _AddRef(void *self);
static ULONG    _Release(void *self);
static OSStatus _Initialize(CMIOHardwarePlugInRef self);
static OSStatus _InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
static OSStatus _Teardown(CMIOHardwarePlugInRef self);
static void     _ObjectShow(CMIOHardwarePlugInRef self, CMIOObjectID objectID);
static Boolean  _ObjectHasProperty(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress *address);
static OSStatus _ObjectIsPropertySettable(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress *address, Boolean *isSettable);
static OSStatus _ObjectGetPropertyDataSize(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress *address, UInt32 qds, const void *qd, UInt32 *dataSize);
static OSStatus _ObjectGetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress *address, UInt32 qds, const void *qd, UInt32 dataSize, UInt32 *dataUsed, void *data);
static OSStatus _ObjectSetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID objectID, const CMIOObjectPropertyAddress *address, UInt32 qds, const void *qd, UInt32 dataSize, const void *data);
static OSStatus _DeviceSuspend(CMIOHardwarePlugInRef self, CMIODeviceID dev);
static OSStatus _DeviceResume(CMIOHardwarePlugInRef self, CMIODeviceID dev);
static OSStatus _DeviceStartStream(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIOStreamID sid);
static OSStatus _DeviceStopStream(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIOStreamID sid);
static OSStatus _DeviceProcessAVCCommand(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIODeviceAVCCommand *cmd);
static OSStatus _DeviceProcessRS422Command(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIODeviceRS422Command *cmd);
static OSStatus _StreamCopyBufferQueue(CMIOHardwarePlugInRef self, CMIOStreamID sid, CMIODeviceStreamQueueAlteredProc proc, void *refCon, CMSimpleQueueRef *queue);
static OSStatus _StreamDeckPlay(CMIOHardwarePlugInRef self, CMIOStreamID sid);
static OSStatus _StreamDeckStop(CMIOHardwarePlugInRef self, CMIOStreamID sid);
static OSStatus _StreamDeckJog(CMIOHardwarePlugInRef self, CMIOStreamID sid, SInt32 speed);
static OSStatus _StreamDeckCueTo(CMIOHardwarePlugInRef self, CMIOStreamID sid, Float64 t, Boolean p);

#pragma mark - Vtable

static CMIOHardwarePlugInInterface sPluginVtable = {
    NULL, // _reserved
    _QueryInterface,
    _AddRef,
    _Release,
    _Initialize,
    _InitializeWithObjectID,
    _Teardown,
    _ObjectShow,
    _ObjectHasProperty,
    _ObjectIsPropertySettable,
    _ObjectGetPropertyDataSize,
    _ObjectGetPropertyData,
    _ObjectSetPropertyData,
    _DeviceSuspend,
    _DeviceResume,
    _DeviceStartStream,
    _DeviceStopStream,
    _DeviceProcessAVCCommand,
    _DeviceProcessRS422Command,
    _StreamCopyBufferQueue,
    _StreamDeckPlay,
    _StreamDeckStop,
    _StreamDeckJog,
    _StreamDeckCueTo,
};

static CMIOHardwarePlugInInterface *sPluginRef = &sPluginVtable;

#pragma mark - State

static CMIOObjectID sPluginID = 0;
static CMIOObjectID sDeviceID = 0;
static CMIOObjectID sStreamID = 0;

static CMSimpleQueueRef sQueue = NULL;
static CMIODeviceStreamQueueAlteredProc sQueueAlteredProc = NULL;
static void *sQueueAlteredRefCon = NULL;

static dispatch_source_t sFrameTimer = NULL;
static dispatch_queue_t sTimerQueue = NULL;
static BOOL sIsStreaming = NO;

#pragma mark - Frame Generation

static CVPixelBufferRef CreateFrameFromIOSurface(void) {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.retromac.virtualcamera"];
    NSInteger surfaceID = [defaults integerForKey:@"ioSurfaceID"];
    if (surfaceID <= 0) return NULL;

    IOSurfaceRef surface = IOSurfaceLookup((IOSurfaceID)surfaceID);
    if (!surface) return NULL;

    CVPixelBufferRef pb = NULL;
    CVReturn r = CVPixelBufferCreateWithIOSurface(kCFAllocatorDefault, surface, NULL, &pb);
    CFRelease(surface);
    return (r == kCVReturnSuccess) ? pb : NULL;
}

static CVPixelBufferRef CreateBlackFrame(void) {
    NSDictionary *attrs = @{
        (NSString *)kCVPixelBufferWidthKey: @(kWidth),
        (NSString *)kCVPixelBufferHeightKey: @(kHeight),
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
    };
    CVPixelBufferRef pb = NULL;
    CVPixelBufferCreate(kCFAllocatorDefault, kWidth, kHeight, kCVPixelFormatType_32BGRA,
                        (__bridge CFDictionaryRef)attrs, &pb);
    if (pb) {
        CVPixelBufferLockBaseAddress(pb, 0);
        memset(CVPixelBufferGetBaseAddress(pb), 0, CVPixelBufferGetDataSize(pb));
        CVPixelBufferUnlockBaseAddress(pb, 0);
    }
    return pb;
}

static void EnqueueFrame(void) {
    if (!sQueue || !sIsStreaming) return;
    if (CMSimpleQueueGetCount(sQueue) >= CMSimpleQueueGetCapacity(sQueue)) return;

    CVPixelBufferRef pb = CreateFrameFromIOSurface();
    if (!pb) pb = CreateBlackFrame();
    if (!pb) return;

    CMVideoFormatDescriptionRef fmt = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(kCFAllocatorDefault, pb, &fmt);
    if (!fmt) { CVPixelBufferRelease(pb); return; }

    CMSampleTimingInfo timing = {
        .duration = CMTimeMake(1, kFPS),
        .presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock()),
        .decodeTimeStamp = kCMTimeInvalid,
    };

    CMSampleBufferRef sbuf = NULL;
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pb, true, NULL, NULL, fmt, &timing, &sbuf);
    CFRelease(fmt);
    CVPixelBufferRelease(pb);

    if (sbuf) {
        CMSimpleQueueEnqueue(sQueue, sbuf);
        if (sQueueAlteredProc) {
            sQueueAlteredProc(sStreamID, sbuf, sQueueAlteredRefCon);
        }
    }
}

static void StartFrameTimer(void) {
    if (sFrameTimer) return;
    sTimerQueue = dispatch_queue_create("com.retromac.dal.frames", DISPATCH_QUEUE_SERIAL);
    sFrameTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, sTimerQueue);
    dispatch_source_set_timer(sFrameTimer, dispatch_time(DISPATCH_TIME_NOW, 0),
                              (uint64_t)(NSEC_PER_SEC / kFPS), NSEC_PER_SEC / kFPS / 10);
    dispatch_source_set_event_handler(sFrameTimer, ^{ EnqueueFrame(); });
    dispatch_resume(sFrameTimer);
}

static void StopFrameTimer(void) {
    if (sFrameTimer) { dispatch_source_cancel(sFrameTimer); sFrameTimer = NULL; }
}

#pragma mark - IUnknown

static HRESULT _QueryInterface(void *self, REFIID uuid, LPVOID *interface) {
    CFUUIDRef req = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, uuid);
    CFUUIDRef iunk = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault,
        0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0xC0,0x00,0x00,0x00,0x00,0x00,0x00,0x46);
    CFUUIDRef ptype = kPluginTypeUUID;

    if (CFEqual(req, iunk) || CFEqual(req, ptype)) {
        *interface = &sPluginRef;
        CFRelease(req); CFRelease(ptype);
        return S_OK;
    }
    CFRelease(req); CFRelease(ptype);
    *interface = NULL;
    return E_NOINTERFACE;
}

static ULONG _AddRef(void *self) { return 1; }
static ULONG _Release(void *self) { return 1; }

#pragma mark - Plugin Lifecycle

static OSStatus _Initialize(CMIOHardwarePlugInRef self) { return kCMIOHardwareNoError; }

static OSStatus _InitializeWithObjectID(CMIOHardwarePlugInRef self, CMIOObjectID objectID) {
    sPluginID = objectID;

    CMIOObjectID devID;
    OSStatus err = CMIOObjectCreate((CMIOHardwarePlugInRef)&sPluginRef, sPluginID, kCMIODeviceClassID, &devID);
    if (err != kCMIOHardwareNoError) return err;
    sDeviceID = devID;

    CMIOObjectID strID;
    err = CMIOObjectCreate((CMIOHardwarePlugInRef)&sPluginRef, sDeviceID, kCMIOStreamClassID, &strID);
    if (err != kCMIOHardwareNoError) return err;
    sStreamID = strID;

    err = CMIOObjectsPublishedAndDied((CMIOHardwarePlugInRef)&sPluginRef, sPluginID, 1, &sDeviceID, 0, NULL);
    if (err != kCMIOHardwareNoError) return err;

    return CMIOObjectsPublishedAndDied((CMIOHardwarePlugInRef)&sPluginRef, sDeviceID, 1, &sStreamID, 0, NULL);
}

static OSStatus _Teardown(CMIOHardwarePlugInRef self) {
    StopFrameTimer();
    if (sQueue) { CFRelease(sQueue); sQueue = NULL; }
    return kCMIOHardwareNoError;
}

static void _ObjectShow(CMIOHardwarePlugInRef self, CMIOObjectID objectID) {}

#pragma mark - Properties

static Boolean _ObjectHasProperty(CMIOHardwarePlugInRef self, CMIOObjectID oid, const CMIOObjectPropertyAddress *a) {
    UInt32 sel = a->mSelector;
    if (oid == sPluginID) return (sel == kCMIOObjectPropertyOwnedObjects);
    if (oid == sDeviceID) {
        switch (sel) {
            case kCMIOObjectPropertyName: case kCMIOObjectPropertyManufacturer:
            case kCMIOObjectPropertyOwnedObjects: case kCMIODevicePropertyDeviceUID:
            case kCMIODevicePropertyModelUID: case kCMIODevicePropertyTransportType:
            case kCMIODevicePropertyDeviceIsAlive: case kCMIODevicePropertyDeviceIsRunning:
            case kCMIODevicePropertyDeviceIsRunningSomewhere:
            case kCMIODevicePropertyDeviceCanBeDefaultDevice:
            case kCMIODevicePropertyHogMode: case kCMIODevicePropertyStreams:
            case kCMIODevicePropertyLatency: case kCMIODevicePropertyLinkedCoreAudioDeviceUID:
                return true;
            default: return false;
        }
    }
    if (oid == sStreamID) {
        switch (sel) {
            case kCMIOObjectPropertyName: case kCMIOStreamPropertyFormatDescription:
            case kCMIOStreamPropertyFormatDescriptions: case kCMIOStreamPropertyDirection:
            case kCMIOStreamPropertyFrameRate: case kCMIOStreamPropertyFrameRates:
            case kCMIOStreamPropertyMinimumFrameRate:
                return true;
            default: return false;
        }
    }
    return false;
}

static OSStatus _ObjectIsPropertySettable(CMIOHardwarePlugInRef self, CMIOObjectID oid, const CMIOObjectPropertyAddress *a, Boolean *s) {
    *s = false; return kCMIOHardwareNoError;
}

static OSStatus _ObjectGetPropertyDataSize(CMIOHardwarePlugInRef self, CMIOObjectID oid, const CMIOObjectPropertyAddress *a, UInt32 qds, const void *qd, UInt32 *ds) {
    UInt32 sel = a->mSelector;
    if (oid == sPluginID && sel == kCMIOObjectPropertyOwnedObjects) { *ds = sizeof(CMIOObjectID); return kCMIOHardwareNoError; }
    if (oid == sDeviceID) {
        switch (sel) {
            case kCMIOObjectPropertyName: case kCMIOObjectPropertyManufacturer:
            case kCMIODevicePropertyDeviceUID: case kCMIODevicePropertyModelUID:
            case kCMIODevicePropertyLinkedCoreAudioDeviceUID:
                *ds = sizeof(CFStringRef); return kCMIOHardwareNoError;
            case kCMIOObjectPropertyOwnedObjects: case kCMIODevicePropertyStreams:
                *ds = sizeof(CMIOObjectID); return kCMIOHardwareNoError;
            case kCMIODevicePropertyTransportType: case kCMIODevicePropertyDeviceIsAlive:
            case kCMIODevicePropertyDeviceIsRunning: case kCMIODevicePropertyDeviceIsRunningSomewhere:
            case kCMIODevicePropertyDeviceCanBeDefaultDevice: case kCMIODevicePropertyHogMode:
            case kCMIODevicePropertyLatency:
                *ds = sizeof(UInt32); return kCMIOHardwareNoError;
        }
    }
    if (oid == sStreamID) {
        switch (sel) {
            case kCMIOObjectPropertyName: *ds = sizeof(CFStringRef); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFormatDescription: *ds = sizeof(CMFormatDescriptionRef); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFormatDescriptions: *ds = sizeof(CFArrayRef); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyDirection: *ds = sizeof(UInt32); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFrameRate: case kCMIOStreamPropertyMinimumFrameRate: *ds = sizeof(Float64); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFrameRates: *ds = sizeof(CFArrayRef); return kCMIOHardwareNoError;
        }
    }
    return kCMIOHardwareUnknownPropertyError;
}

static OSStatus _ObjectGetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID oid, const CMIOObjectPropertyAddress *a, UInt32 qds, const void *qd, UInt32 dataSize, UInt32 *du, void *d) {
    UInt32 sel = a->mSelector;

    if (oid == sPluginID && sel == kCMIOObjectPropertyOwnedObjects) {
        *du = sizeof(CMIOObjectID); *(CMIOObjectID *)d = sDeviceID; return kCMIOHardwareNoError;
    }
    if (oid == sDeviceID) {
        switch (sel) {
            case kCMIOObjectPropertyName:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR("RetroMac Cam"); return kCMIOHardwareNoError;
            case kCMIOObjectPropertyManufacturer:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR("RetroMac"); return kCMIOHardwareNoError;
            case kCMIODevicePropertyDeviceUID:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR("RetroMac-VCam-UID"); return kCMIOHardwareNoError;
            case kCMIODevicePropertyModelUID:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR("RetroMac-VCam-Model"); return kCMIOHardwareNoError;
            case kCMIODevicePropertyLinkedCoreAudioDeviceUID:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR(""); return kCMIOHardwareNoError;
            case kCMIOObjectPropertyOwnedObjects: case kCMIODevicePropertyStreams:
                *du = sizeof(CMIOObjectID); *(CMIOObjectID *)d = sStreamID; return kCMIOHardwareNoError;
            case kCMIODevicePropertyTransportType:
                *du = sizeof(UInt32); *(UInt32 *)d = 'bltn'; return kCMIOHardwareNoError;
            case kCMIODevicePropertyDeviceIsAlive:
                *du = sizeof(UInt32); *(UInt32 *)d = 1; return kCMIOHardwareNoError;
            case kCMIODevicePropertyDeviceIsRunning: case kCMIODevicePropertyDeviceIsRunningSomewhere:
                *du = sizeof(UInt32); *(UInt32 *)d = sIsStreaming ? 1 : 0; return kCMIOHardwareNoError;
            case kCMIODevicePropertyDeviceCanBeDefaultDevice:
                *du = sizeof(UInt32); *(UInt32 *)d = 1; return kCMIOHardwareNoError;
            case kCMIODevicePropertyHogMode:
                *du = sizeof(UInt32); *(UInt32 *)d = (UInt32)-1; return kCMIOHardwareNoError;
            case kCMIODevicePropertyLatency:
                *du = sizeof(UInt32); *(UInt32 *)d = 0; return kCMIOHardwareNoError;
        }
    }
    if (oid == sStreamID) {
        switch (sel) {
            case kCMIOObjectPropertyName:
                *du = sizeof(CFStringRef); *(CFStringRef *)d = CFSTR("RetroMac Cam"); return kCMIOHardwareNoError;
            case kCMIOStreamPropertyDirection:
                *du = sizeof(UInt32); *(UInt32 *)d = 0; return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFormatDescription: {
                CMVideoFormatDescriptionRef fmt = NULL;
                CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_32BGRA, kWidth, kHeight, NULL, &fmt);
                *du = sizeof(CMFormatDescriptionRef); *(CMFormatDescriptionRef *)d = fmt; return kCMIOHardwareNoError;
            }
            case kCMIOStreamPropertyFormatDescriptions: {
                CMVideoFormatDescriptionRef fmt = NULL;
                CMVideoFormatDescriptionCreate(kCFAllocatorDefault, kCVPixelFormatType_32BGRA, kWidth, kHeight, NULL, &fmt);
                CFArrayRef arr = CFArrayCreate(kCFAllocatorDefault, (const void **)&fmt, 1, &kCFTypeArrayCallBacks);
                CFRelease(fmt);
                *du = sizeof(CFArrayRef); *(CFArrayRef *)d = arr; return kCMIOHardwareNoError;
            }
            case kCMIOStreamPropertyFrameRate: case kCMIOStreamPropertyMinimumFrameRate:
                *du = sizeof(Float64); *(Float64 *)d = (Float64)kFPS; return kCMIOHardwareNoError;
            case kCMIOStreamPropertyFrameRates: {
                Float64 r = (Float64)kFPS;
                CFNumberRef n = CFNumberCreate(kCFAllocatorDefault, kCFNumberFloat64Type, &r);
                CFArrayRef arr = CFArrayCreate(kCFAllocatorDefault, (const void **)&n, 1, &kCFTypeArrayCallBacks);
                CFRelease(n);
                *du = sizeof(CFArrayRef); *(CFArrayRef *)d = arr; return kCMIOHardwareNoError;
            }
        }
    }
    return kCMIOHardwareUnknownPropertyError;
}

static OSStatus _ObjectSetPropertyData(CMIOHardwarePlugInRef self, CMIOObjectID oid, const CMIOObjectPropertyAddress *a, UInt32 qds, const void *qd, UInt32 ds, const void *d) {
    return kCMIOHardwareNoError;
}

#pragma mark - Device

static OSStatus _DeviceSuspend(CMIOHardwarePlugInRef self, CMIODeviceID dev) { return kCMIOHardwareNoError; }
static OSStatus _DeviceResume(CMIOHardwarePlugInRef self, CMIODeviceID dev) { return kCMIOHardwareNoError; }

static OSStatus _DeviceStartStream(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIOStreamID sid) {
    if (!sIsStreaming) { sIsStreaming = YES; StartFrameTimer(); }
    return kCMIOHardwareNoError;
}

static OSStatus _DeviceStopStream(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIOStreamID sid) {
    sIsStreaming = NO; StopFrameTimer();
    return kCMIOHardwareNoError;
}

static OSStatus _DeviceProcessAVCCommand(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIODeviceAVCCommand *cmd) { return kCMIOHardwareNoError; }
static OSStatus _DeviceProcessRS422Command(CMIOHardwarePlugInRef self, CMIODeviceID dev, CMIODeviceRS422Command *cmd) { return kCMIOHardwareNoError; }

#pragma mark - Stream

static OSStatus _StreamCopyBufferQueue(CMIOHardwarePlugInRef self, CMIOStreamID sid, CMIODeviceStreamQueueAlteredProc proc, void *refCon, CMSimpleQueueRef *queue) {
    if (sid != sStreamID) return kCMIOHardwareBadStreamError;
    sQueueAlteredProc = proc;
    sQueueAlteredRefCon = refCon;
    if (!sQueue) CMSimpleQueueCreate(kCFAllocatorDefault, 30, &sQueue);
    *queue = (CMSimpleQueueRef)CFRetain(sQueue);
    return kCMIOHardwareNoError;
}

static OSStatus _StreamDeckPlay(CMIOHardwarePlugInRef self, CMIOStreamID sid) { return kCMIOHardwareNoError; }
static OSStatus _StreamDeckStop(CMIOHardwarePlugInRef self, CMIOStreamID sid) { return kCMIOHardwareNoError; }
static OSStatus _StreamDeckJog(CMIOHardwarePlugInRef self, CMIOStreamID sid, SInt32 speed) { return kCMIOHardwareNoError; }
static OSStatus _StreamDeckCueTo(CMIOHardwarePlugInRef self, CMIOStreamID sid, Float64 t, Boolean p) { return kCMIOHardwareNoError; }

#pragma mark - Factory

__attribute__((visibility("default")))
void *RetroMacDALPluginFactory(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID) {
    CFUUIDRef expected = kPluginTypeUUID;
    if (CFEqual(requestedTypeUUID, expected)) {
        CFRelease(expected);
        return &sPluginRef;
    }
    CFRelease(expected);
    return NULL;
}

#pragma clang diagnostic pop
