import AppKit
import CoreGraphics
// usage: swift gen-icon.swift <a|b|c|final> out.png   (the app uses "final")
// Then: mkdir AppIcon.iconset; for s in 16 32 128 256 512; do
//   sips -z $s $s out.png --out AppIcon.iconset/icon_${s}x${s}.png
//   sips -z $((s*2)) $((s*2)) out.png --out AppIcon.iconset/icon_${s}x${s}@2x.png; done
//   iconutil -c icns AppIcon.iconset -o AppIcon.icns
let S: CGFloat = 1024
let args = CommandLine.arguments
let variant = args[1], outPath = args[2]
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func C(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
  CGColor(colorSpace: cs, components: [CGFloat((h>>16)&255)/255, CGFloat((h>>8)&255)/255, CGFloat(h&255)/255, a])!
}
func grad(_ cols: [CGColor], _ locs: [CGFloat]) -> CGGradient { CGGradient(colorsSpace: cs, colors: cols as CFArray, locations: locs)! }
func squircle(_ r: CGRect, n: CGFloat = 5) -> CGPath {
  let p = CGMutablePath(); let a = r.width/2, b = r.height/2
  for i in 0...360 {
    let t = CGFloat(i) * .pi / 180
    let c = cos(t), s = sin(t)
    let x = r.midX + a * (c < 0 ? -1 : 1) * pow(abs(c), 2/n)
    let y = r.midY + b * (s < 0 ? -1 : 1) * pow(abs(s), 2/n)
    i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
  }
  p.closeSubpath(); return p
}
func rr(_ r: CGRect, _ rad: CGFloat) -> CGPath { CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil) }
let box = CGRect(x: 100, y: 100, width: 824, height: 824)
let mask = squircle(box)
// drop shadow under icon
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: C(0x000000, 0.45))
ctx.addPath(mask); ctx.setFillColor(C(0x0b2a30)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(mask); ctx.clip()
// background
let bgTop: UInt32 = variant == "b" ? 0x14606a : 0x12525c
ctx.drawLinearGradient(grad([C(bgTop), C(0x05181d)], [0, 1]), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
ctx.drawRadialGradient(grad([C(0x3fd0c0, 0.28), C(0x3fd0c0, 0)], [0, 1]), startCenter: CGPoint(x: 512, y: 780), startRadius: 0, endCenter: CGPoint(x: 512, y: 780), endRadius: 520, options: [])

let goldG = grad([C(0xffe9a0), C(0xf2b632), C(0xb9751a)], [0, 0.5, 1])
func goldFill(_ path: CGPath, glow: CGFloat = 0) {
  let bb = path.boundingBox
  ctx.saveGState()
  if glow > 0 { ctx.setShadow(offset: .zero, blur: glow, color: C(0xffc83a, 0.85)) }
  ctx.addPath(path); ctx.setFillColor(C(0xf2b632)); ctx.fillPath()
  ctx.restoreGState()
  ctx.saveGState(); ctx.addPath(path); ctx.clip()
  ctx.drawLinearGradient(goldG, start: CGPoint(x: bb.midX, y: bb.maxY), end: CGPoint(x: bb.midX, y: bb.minY), options: [])
  // top highlight
  ctx.drawLinearGradient(grad([C(0xffffff, 0.45), C(0xffffff, 0)], [0, 1]), start: CGPoint(x: bb.midX, y: bb.maxY), end: CGPoint(x: bb.midX, y: bb.midY), options: [])
  ctx.restoreGState()
}
func tealFill(_ path: CGPath, _ hi: UInt32, _ lo: UInt32) {
  let bb = path.boundingBox
  ctx.saveGState(); ctx.addPath(path); ctx.clip()
  ctx.drawLinearGradient(grad([C(hi), C(lo)], [0, 1]), start: CGPoint(x: bb.midX, y: bb.maxY), end: CGPoint(x: bb.midX, y: bb.minY), options: [])
  ctx.restoreGState()
}
func star(_ c: CGPoint, _ R: CGFloat, _ r: CGFloat) -> CGPath {
  let p = CGMutablePath()
  for i in 0..<10 {
    let ang = CGFloat(i) * .pi/5 + .pi/2
    let rad = i % 2 == 0 ? R : r
    let pt = CGPoint(x: c.x + cos(ang)*rad, y: c.y + sin(ang)*rad)
    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
  }
  p.closeSubpath(); return p
}
func arc(_ c: CGPoint, _ rad: CGFloat, _ a0: CGFloat, _ a1: CGFloat, _ w: CGFloat, _ col: CGColor, glow: CGFloat = 0) {
  ctx.saveGState()
  if glow > 0 { ctx.setShadow(offset: .zero, blur: glow, color: col) }
  ctx.setLineWidth(w); ctx.setLineCap(.round); ctx.setStrokeColor(col)
  ctx.addArc(center: c, radius: rad, startAngle: a0, endAngle: a1, clockwise: false); ctx.strokePath()
  ctx.restoreGState()
}

switch variant {
case "a": // leaderboard bars
  let x0: CGFloat = 230
  let widths: [CGFloat] = [560, 470, 380, 290]
  let h: CGFloat = 108, gap: CGFloat = 40
  let top: CGFloat = 770
  for i in 0..<4 {
    let y = top - CGFloat(i)*(h+gap) - h
    let r = CGRect(x: x0, y: y, width: widths[i], height: h)
    let p = rr(r, h/2)
    if i == 0 {
      goldFill(p, glow: 50)
      // rank dot
      ctx.setFillColor(C(0x5a3606)); ctx.fillEllipse(in: CGRect(x: x0+24, y: y+24, width: 60, height: 60))
      ctx.setFillColor(C(0xffe9a0)); ctx.addPath(star(CGPoint(x: x0+54, y: y+54), 26, 11)); ctx.fillPath()
    } else {
      tealFill(p, 0x5fd8cc, 0x2a8f94)
      ctx.setFillColor(C(0x06242a, 0.55)); ctx.fillEllipse(in: CGRect(x: x0+24, y: y+24, width: 60, height: 60))
    }
  }
case "b", "final": // bell + gauge arc
  let c = CGPoint(x: 512, y: 470)
  arc(c, 330, .pi*0.88, .pi*0.12 - 2 * .pi + 2 * .pi, 34, C(0x000000, 0.0)) // placeholder no-op
  arc(c, 335, .pi*0.15, .pi*0.85, 36, C(0x052a30, 0.8))
  arc(c, 335, .pi*0.50, .pi*0.85, 36, C(0x40e0d0), glow: 30)
  arc(c, 335, .pi*0.15, .pi*0.50, 36, C(0xf2b632), glow: 30)
  // bell
  let b = CGMutablePath()
  b.move(to: CGPoint(x: 330, y: 330))
  b.addCurve(to: CGPoint(x: 400, y: 520), control1: CGPoint(x: 330, y: 420), control2: CGPoint(x: 360, y: 470))
  b.addCurve(to: CGPoint(x: 512, y: 640), control1: CGPoint(x: 420, y: 570), control2: CGPoint(x: 512, y: 560))
  b.addCurve(to: CGPoint(x: 624, y: 520), control1: CGPoint(x: 512, y: 560), control2: CGPoint(x: 604, y: 570))
  b.addCurve(to: CGPoint(x: 694, y: 330), control1: CGPoint(x: 664, y: 470), control2: CGPoint(x: 694, y: 420))
  b.addLine(to: CGPoint(x: 750, y: 300)); b.addLine(to: CGPoint(x: 750, y: 260))
  b.addLine(to: CGPoint(x: 274, y: 260)); b.addLine(to: CGPoint(x: 274, y: 300)); b.addLine(to: CGPoint(x: 330, y: 330))
  b.closeSubpath()
  goldFill(b, glow: 40)
  if variant == "final" {
    // right-side shade + rim band + highlight for depth
    ctx.saveGState(); ctx.addPath(b); ctx.clip()
    ctx.drawLinearGradient(grad([C(0x7a3f00, 0), C(0x7a3f00, 0.35)], [0, 1]), start: CGPoint(x: 512, y: 0), end: CGPoint(x: 750, y: 0), options: [])
    ctx.setFillColor(C(0x8a4d08, 0.55)); ctx.fill(CGRect(x: 250, y: 260, width: 520, height: 34))
    ctx.setFillColor(C(0xffffff, 0.35)); ctx.addPath(rr(CGRect(x: 380, y: 400, width: 26, height: 150), 13)); ctx.fillPath()
    ctx.restoreGState()
  }
  // knob
  goldFill(CGPath(ellipseIn: CGRect(x: 472, y: 620, width: 80, height: 80), transform: nil))
  // clapper
  goldFill(CGPath(ellipseIn: CGRect(x: 462, y: 190, width: 100, height: 100), transform: nil))
case "c": // podium + medal + gauge
  let bw: CGFloat = 170
  let blocks: [(CGFloat, CGFloat, Bool)] = [(260, 240, false), (440, 380, true), (620, 180, false)]
  for (x, h, gold) in blocks {
    let r = CGRect(x: x - 0, y: 200, width: bw, height: h)
    let p = CGMutablePath(); p.addRoundedRect(in: r, cornerWidth: 22, cornerHeight: 22)
    if gold { goldFill(p, glow: 50) } else { tealFill(p, 0x5fd8cc, 0x2a8f94) }
  }
  // star medal above center block
  let cx: CGFloat = 525, cy: CGFloat = 640
  goldFill(star(CGPoint(x: cx, y: cy), 110, 46), glow: 40)
  // gauge arc
  arc(CGPoint(x: 512, y: 560), 330, .pi*0.18, .pi*0.82, 26, C(0x40e0d0, 0.9), glow: 24)
default: break
}
// inner rim highlight
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(mask); ctx.clip()
ctx.setLineWidth(5); ctx.setStrokeColor(C(0xffffff, 0.18))
ctx.addPath(squircle(box.insetBy(dx: 2.5, dy: 2.5))); ctx.strokePath()
ctx.restoreGState()

let img = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: img)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
