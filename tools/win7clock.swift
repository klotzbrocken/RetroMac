import AppKit

let S: CGFloat = 256
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/win7_clock.png"

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.setShouldAntialias(true)
ctx.interpolationQuality = .high

let c = CGPoint(x: S/2, y: S/2)
let R: CGFloat = S/2 - 8
let sp = CGColorSpaceCreateDeviceRGB()
func col(_ r: CGFloat,_ g: CGFloat,_ b: CGFloat,_ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: sp, components: [r,g,b,a])! }

// Drop shadow under the whole clock
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: col(0,0,0,0.35))
ctx.setFillColor(col(0.2,0.2,0.2,1))
ctx.fillEllipse(in: CGRect(x: c.x-R, y: c.y-R, width: 2*R, height: 2*R))
ctx.restoreGState()

// Metallic bezel: vertical gradient ring (light top -> dark bottom)
let bezel = CGGradient(colorsSpace: sp, colors: [
    col(0.97,0.98,0.99), col(0.78,0.82,0.86), col(0.55,0.60,0.66), col(0.80,0.84,0.88)] as CFArray,
    locations: [0, 0.45, 0.55, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x-R, y: c.y-R, width: 2*R, height: 2*R))
ctx.clip()
ctx.drawLinearGradient(bezel, start: CGPoint(x: c.x, y: c.y+R), end: CGPoint(x: c.x, y: c.y-R), options: [])
ctx.restoreGState()
// thin dark rim
ctx.setLineWidth(1.5); ctx.setStrokeColor(col(0.35,0.38,0.42,1))
ctx.strokeEllipse(in: CGRect(x: c.x-R, y: c.y-R, width: 2*R, height: 2*R))

// Face
let fr = R - 16
let face = CGGradient(colorsSpace: sp, colors: [col(1,1,1), col(0.90,0.93,0.96)] as CFArray, locations: [0,1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: c.x-fr, y: c.y-fr, width: 2*fr, height: 2*fr))
ctx.clip()
ctx.drawRadialGradient(face, startCenter: CGPoint(x: c.x, y: c.y+fr*0.3), startRadius: 0, endCenter: c, endRadius: fr, options: [])
ctx.restoreGState()
ctx.setLineWidth(1); ctx.setStrokeColor(col(0.6,0.64,0.68,1))
ctx.strokeEllipse(in: CGRect(x: c.x-fr, y: c.y-fr, width: 2*fr, height: 2*fr))

// Tick marks
func pt(_ phi: CGFloat, _ rad: CGFloat) -> CGPoint { CGPoint(x: c.x + rad*sin(phi), y: c.y + rad*cos(phi)) }
for i in 0..<60 {
    let phi = CGFloat(i)/60 * 2 * .pi
    let major = i % 5 == 0
    ctx.setStrokeColor(col(0.15,0.17,0.2,1))
    ctx.setLineWidth(major ? 3 : 1)
    let r0 = fr - (major ? 14 : 8)
    ctx.move(to: pt(phi, r0)); ctx.addLine(to: pt(phi, fr - 3)); ctx.strokePath()
}

// Hands at a classic 10:10 pose
func hand(valueFrac: CGFloat, length: CGFloat, width: CGFloat, color: CGColor, tail: CGFloat = 0) {
    let phi = valueFrac * 2 * .pi
    ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round)
    ctx.move(to: pt(phi + .pi, tail)); ctx.addLine(to: pt(phi, length)); ctx.strokePath()
}
let h: CGFloat = 10, m: CGFloat = 10, s: CGFloat = 37
hand(valueFrac: (h + m/60)/12, length: fr*0.52, width: 7, color: col(0.1,0.1,0.12,1))   // hour
hand(valueFrac: m/60,          length: fr*0.78, width: 5, color: col(0.1,0.1,0.12,1))   // minute
hand(valueFrac: s/60,          length: fr*0.82, width: 1.8, color: col(0.85,0.1,0.1,1), tail: fr*0.2) // second (red)
// hub
ctx.setFillColor(col(0.1,0.1,0.12,1)); ctx.fillEllipse(in: CGRect(x: c.x-6, y: c.y-6, width: 12, height: 12))
ctx.setFillColor(col(0.85,0.1,0.1,1)); ctx.fillEllipse(in: CGRect(x: c.x-2.5, y: c.y-2.5, width: 5, height: 5))

// Aero glass highlight over the top
let gloss = CGGradient(colorsSpace: sp, colors: [col(1,1,1,0.55), col(1,1,1,0.0)] as CFArray, locations: [0,1])!
ctx.saveGState()
let gr = fr - 2
ctx.addEllipse(in: CGRect(x: c.x-gr, y: c.y-gr, width: 2*gr, height: 2*gr)); ctx.clip()
ctx.addEllipse(in: CGRect(x: c.x-gr*0.95, y: c.y+gr*0.05, width: gr*1.9, height: gr*1.5)); ctx.clip()
ctx.drawLinearGradient(gloss, start: CGPoint(x: c.x, y: c.y+gr), end: CGPoint(x: c.x, y: c.y-gr*0.2), options: [])
ctx.restoreGState()

img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
