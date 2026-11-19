// Converts levellord's lvl.pointers_AOS4 (v1.1, CC BY-SA 4.0, amiga-look.org/node/782) into
// RetroMac's cursor set Resources/Cursors/AmigaOS4: one PNG per slot at twice the size (the
// private cursor API wants Retina density) and a manifest with the hotspots, read from each
// pointer's icOn chunk (XOFFSET / YOFFSET).
//   swift Scripts/amiga-pointers.swift <unpacked archive>/20px/Red_Set
import AppKit

let src = URL(fileURLWithPath: CommandLine.arguments[1])
let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Resources/Cursors/AmigaOS4")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// RetroMac's slots, each from the AmigaOS 4 pointer that does that job.
let slots: [(String, String)] = [
    ("arrow", "def_pointer"), ("ibeam", "def_textpointer"), ("wait", "def_busypointer"),
    ("pointingHand", "def_linkpointer"), ("crosshair", "def_crosspointer"), ("move", "def_scrollallpointer"),
    ("notAllowed", "def_notallowedpointer"), ("help", "def_helppointer"),
    ("resizeEW", "def_eastwestresizepointer"), ("resizeNS", "def_northsouthresizepointer"),
    ("resizeNESW", "def_northeastsouthwestresizepointer"),
]
func offset(_ data: Data, _ key: String) -> Double {
    guard let r = data.range(of: Data((key + "=").utf8)) else { return 0 }
    let digits = data[r.upperBound...].prefix { $0 >= 48 && $0 <= 57 }
    return Double(String(decoding: digits, as: UTF8.self)) ?? 0
}
var manifest: [String: Any] = [:]
for (slot, name) in slots {
    let file = src.appendingPathComponent(name + ".info")
    guard let data = try? Data(contentsOf: file), let img = NSBitmapImageRep(data: data)?.cgImage else { print("missing", name); continue }
    let w = img.width, h = img.height
    let ctx = CGContext(data: nil, width: w * 2, height: h * 2, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .none   // hard pixels, as the pointer is drawn
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w * 2, height: h * 2))
    try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
        .write(to: out.appendingPathComponent(slot + ".png"))
    manifest[slot] = ["frameCount": 1, "dur": 0, "size": [Double(w), Double(h)],
                      "hotspot": [offset(data, "XOFFSET"), offset(data, "YOFFSET")]]
    print(slot, "←", name, "\(w)x\(h)", manifest[slot]!)
}
let json = try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("manifest.json"))
