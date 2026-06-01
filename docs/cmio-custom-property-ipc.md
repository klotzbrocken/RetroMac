# Cross-user IPC for a CMIOExtension virtual camera via a custom CMIO property

Goal: pass a **global IOSurface integer ID** from the host app (console user) to a
sandboxed CMIOExtension camera extension (running as `_cmiodalassistants`).
App Group / UserDefaults fails because containers are per-user. A **custom CMIO
property** on the extension's device works because the classic CoreMediaIO C API
(`CMIOObjectSetPropertyData`) routes the write across the user boundary through the
DAL assistant. The host then only needs to ship the integer surface ID; the
extension calls `IOSurfaceLookupFromMachPort`/`IOSurfaceLookup` (global lookup works
cross-user).

---

## 1. Custom property key-string format (the load-bearing detail)

`CMIOExtensionProperty` is `typedef NSString *CMIOExtensionProperty`. A **custom**
property's `rawValue` string MUST follow this exact 4-token, underscore-separated
format (this is what `CMIO_DAL_CMIOExtension_*.mm` parses internally):

```
4cc_<selector>_<scope>_<element>
```

- `4cc_`        — literal required prefix.
- `<selector>`  — a 4-character FourCharCode (e.g. `sfid`). Exactly 4 chars.
- `<scope>`     — 4-char code for the scope. **Global scope is the literal `glob`**
                  (the FourCharCode of `kCMIOObjectPropertyScopeGlobal` == `'glob'`).
- `<element>`   — 4-char zero-padded element. **Main element is the literal `0000`**
                  (`kCMIOObjectPropertyElementMain` == 0, printed as 4 hex/zero digits).

Concrete valid key for selector `sfid` (surface id), global scope, main element:

```swift
let kSurfaceIDProperty = CMIOExtensionProperty(rawValue: "4cc_sfid_glob_0000")
```

Verified examples seen in the wild / Apple template: `"4cc_cust_glob_0000"`,
`"4cc_just_glob_0000"`, `"4cc_dust_glob_0000"`, `"4cc_back_glob_0000"`.

> NOTE: The `wrong 4cc format for key 4cc_..._...` log line that appears at
> get/set time is **misleading** — per Apple staff (DrXibber) it actually means the
> **value type** (`CMIOExtensionPropertyState` payload) is unsupported, NOT that the
> key string is malformed. See gotchas.

---

## 2. Extension side (CMIOExtensionDeviceSource)

Declare the key, advertise it in `availableProperties`, and read/write it in the
`deviceProperties(forProperties:)` getter and `setDeviceProperties(_:)` setter.

Allowed value types for `CMIOExtensionPropertyState(value:)`: **`NSNumber`,
`NSString`, `NSData`** (these reliably round-trip). `NSDictionary` / `NSArray` do
**not** work (fail in `GetPropertyDataSize`). For an integer ID, prefer `NSString`
for maximum OS-version compatibility (see the macOS 12.x `NSNumber` bug in gotchas).

```swift
import CoreMediaIO
import Foundation
import os.log

let kSurfaceIDProperty = CMIOExtensionProperty(rawValue: "4cc_sfid_glob_0000")

final class CameraDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!

    // Backing store for the surface id pushed from the host.
    private(set) var surfaceID: IOSurfaceID = 0

    init(localizedName: String) {
        super.init()
        // deviceID is the UUID the host matches against (see host §3b).
        let deviceID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
        self.device = CMIOExtensionDevice(localizedName: localizedName,
                                          deviceID: deviceID,
                                          legacyDeviceID: nil,
                                          source: self)
    }

    // 1. Advertise the custom property alongside the standard ones.
    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceTransportType, .deviceModel, kSurfaceIDProperty]
    }

    // 2. GETTER — return current value wrapped in CMIOExtensionPropertyState.
    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>)
        throws -> CMIOExtensionDeviceProperties {

        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])

        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(kSurfaceIDProperty) {
            // Store as NSString for 12.x-safety; parse back to UInt32 on read.
            let value = NSString(string: String(self.surfaceID))
            deviceProperties.setPropertyState(
                CMIOExtensionPropertyState(value: value),
                forProperty: kSurfaceIDProperty)
        }
        return deviceProperties
    }

    // 3. SETTER — host writes land here (cross-user, via the DAL assistant).
    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        if let state = deviceProperties.propertiesDictionary[kSurfaceIDProperty] {
            // state.value is the bridged CFType. We sent an NSString.
            if let s = state.value as? String, let id = UInt32(s) {
                self.surfaceID = IOSurfaceID(id)
                os_log(.info, "host pushed surfaceID=%{public}u", self.surfaceID)
                // Now do the cross-user lookup (global surfaces resolve cross-user):
                // let surface = IOSurfaceLookup(self.surfaceID)
            } else if let n = state.value as? NSNumber {   // macOS 13+/14+ path
                self.surfaceID = IOSurfaceID(n.uint32Value)
            }
        }
    }
}
```

`CMIOExtensionPropertyState(value:)` takes a `CMIOExtensionPropertyState` whose
`value` is `Any?` bridged to a CF property-list scalar. Read it back via
`state.value as? String` / `as? NSNumber` / `as? Data`.

---

## 3. Host side (classic CoreMediaIO C API, Swift)

### 3a. Device discovery / `kCMIOHardwarePropertyAllowScreenCaptureDevices`

This flag is **NOT required** for a `CMIOExtension` camera device — it is only
needed to surface legacy DAL *screen-capture* style devices. A CMIOExtension camera
appears in `kCMIOHardwarePropertyDevices` normally once the extension is activated.
(Many projects still set it defensively at startup; harmless, but not needed here.)

```swift
import CoreMediaIO

// Optional / defensive only — NOT needed for a CMIOExtension camera device.
func allowScreenCaptureDevices() {
    var prop = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var allow: UInt32 = 1
    CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil,
                              UInt32(MemoryLayout<UInt32>.size), &allow)
}
```

### 3b. Enumerate devices and match OUR device by its UID

The extension's `deviceID` UUID is exposed to the classic API as the device's UID
string via `kCMIODevicePropertyDeviceUID` (a `CFString`). Match against
`"A1B2C3D4-E5F6-7890-ABCD-EF1234567890"`.

```swift
func findOurDevice(uid wantedUID: String) -> CMIOObjectID? {
    // 1. Read the device list.
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    var dataSize: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject),
                                        &addr, 0, nil, &dataSize) == noErr else { return nil }

    let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
    var devices = [CMIOObjectID](repeating: 0, count: count)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject),
                                    &addr, 0, nil, dataSize, &used, &devices) == noErr
    else { return nil }

    // 2. For each device, read kCMIODevicePropertyDeviceUID (a CFString).
    var uidAddr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

    for dev in devices {
        var uidSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(dev, &uidAddr, 0, nil, &uidSize) == noErr,
              uidSize == UInt32(MemoryLayout<CFString?>.size) else { continue }

        var cfUID: Unmanaged<CFString>?
        var out: UInt32 = 0
        let st = withUnsafeMutablePointer(to: &cfUID) { ptr -> OSStatus in
            CMIOObjectGetPropertyData(dev, &uidAddr, 0, nil, uidSize, &out, ptr)
        }
        guard st == noErr, let uid = cfUID?.takeRetainedValue() as String? else { continue }
        if uid == wantedUID { return dev }
    }
    return nil
}
```

### 3c. Write the custom property — THE CRITICAL DATA-TYPE ANSWER

For a custom CMIOExtension property bridged to the classic API, the property's
classic data type is a **CoreFoundation property-list object pointer**, NOT a raw
scalar. The `data` argument to `CMIOObjectSetPropertyData` must point to a variable
holding a **`CFTypeRef` / `CFPropertyList` reference** (here a `CFString`), and
`dataSize` is the size of that *pointer* (`MemoryLayout<CFTypeRef>.size`, i.e. 8 on
64-bit), **not** the size of the integer itself. The DAL assistant un-bridges that
CF object into the extension's `CMIOExtensionPropertyState.value`.

So you do NOT pass a 4-byte `Int32`. You pass `&cfStringRef` (a pointer to a
pointer-sized CF reference).

```swift
let kSurfaceIDSelector: FourCharCode = {   // 'sfid' — must equal the <selector> token
    let s = "sfid".utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    return FourCharCode(s)
}()

func pushSurfaceID(_ surfaceID: IOSurfaceID, to device: CMIOObjectID) -> Bool {
    var addr = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kSurfaceIDSelector),         // 'sfid'
        mScope:    CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),// 'glob'
        mElement:  CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)) // 0

    // Property must exist and be settable.
    guard CMIOObjectHasProperty(device, &addr) else { return false }
    var settable: DarwinBoolean = false
    CMIOObjectIsPropertySettable(device, &addr, &settable)
    guard settable.boolValue else { return false }

    // Value is a CF property-list object (CFString). dataSize = size of the REFERENCE.
    let cfValue: CFString = String(surfaceID) as CFString
    var ref: CFTypeRef = cfValue
    let size = UInt32(MemoryLayout<CFTypeRef>.size)   // pointer size (8), NOT 4

    let status = withUnsafePointer(to: &ref) { ptr -> OSStatus in
        CMIOObjectSetPropertyData(device, &addr, 0, nil, size, ptr)
    }
    return status == noErr
}
```

Equivalent (and arguably cleaner) using the size that
`CMIOObjectGetPropertyDataSize` reports for the property — the assistant always
reports the pointer-sized CF reference for these custom properties:

```swift
var needed: UInt32 = 0
CMIOObjectGetPropertyDataSize(device, &addr, 0, nil, &needed) // returns MemoryLayout<CFTypeRef>.size
```

If you instead declared the extension value as `NSNumber` (macOS 13+ only), the
host still passes a `CFNumber` reference the same way (`var ref: CFTypeRef =
NSNumber(value: surfaceID) ... &ref`). The representation on the wire is always a
pointer to a CF object; only the concrete CF class changes.

---

## 4. Gotchas & confirmations

- **macOS 12.x `NSNumber` bug:** On macOS 12.x, an `NSNumber`-typed custom property
  silently fails (`wrong 4cc format for key ...` in the log). It works on 13.x/14.x.
  `NSString` works on **all** versions — so encode the surface ID as a decimal
  string. (Apple Developer Forums thread 762642.) This is why the code above uses
  `NSString`/`CFString`.
- **Misleading log:** `CMIO_DAL_CMIOExtension_*.mm: ... wrong 4cc format for key
  4cc_..._..._...` almost always means an **unsupported value type**, not a bad key.
- **Selector mapping is exact:** the FourCharCode you put in
  `CMIOObjectPropertyAddress.mSelector` on the host MUST equal the `<selector>`
  token of the extension's `rawValue`. `'sfid'` ↔ `"4cc_sfid_glob_0000"`. Likewise
  scope `'glob'` ↔ `kCMIOObjectPropertyScopeGlobal` and element `0`/`0000` ↔
  `kCMIOObjectPropertyElementMain`. Mismatched scope/element = property not found.
- **No special entitlement** is required on the host merely to *set* CMIO
  properties. The host does need **camera/TCC authorization** to open the CMIO
  subsystem at all, and it must be able to *see* the device (extension installed +
  activated). There is no separate "set property" entitlement.
- **Allowed value types:** `NSNumber`, `NSString`, `NSData` only. For anything
  richer, serialize to `NSData` (`NSKeyedArchiver` or JSON) — but for a single
  integer surface ID a decimal `NSString` is the simplest robust choice.
- **Supported types only resolve once both sides advertise the key**: the property
  must be in `availableProperties` on the device source, or the host's
  `CMIOObjectHasProperty` returns false.

---

## Sources

- Apple Developer Forums — "CoreMediaIO Camera Extension: custom properties?"
  https://developer.apple.com/forums/thread/708548
  (key format `4cc_cust_glob_0000`, `availableProperties`, host `CMIOObjectPropertyAddress`
  / `CMIOObjectSetPropertyData(devices[i], &propertyAddress, 0, nil, dataSize, &value)`,
  `NSString`/`NSData`/`NSNumber` value types, NSDictionary/NSArray failing, settable check.)
- Apple Developer Forums — "CMIO Custom Properties Don't Work With NSNumber under
  macOS 12.x (but do under macOS 14.x)" https://forums.developer.apple.com/forums/thread/762642
  (the macOS 12.x NSNumber bug; use NSString; misleading "wrong 4cc format" log.)
- ldenoue gist — Swift extension declaring custom string/data properties and
  reading them back via `state.value as? String` / `as? Data`
  https://gist.github.com/ldenoue/84210280853f0490c79473b6edd25e9d
- WWDC22 Session 10022 — "Create camera extensions with Core Media IO"
  https://developer.apple.com/videos/play/wwdc2022/10022/ (custom property concept, ~28:17)
- Apple — CFPropertyList (CFString/CFNumber/CFData are the valid plist scalar types
  that the classic API marshals across the user boundary)
  https://developer.apple.com/documentation/corefoundation/cfpropertylist
- Apple docs — CMIOExtensionProperty / CMIOExtensionDeviceProperties /
  CMIOExtensionPropertyState
  https://developer.apple.com/documentation/coremediaio/cmioextensionproperty
  https://developer.apple.com/documentation/coremediaio/cmioextensiondeviceproperties
