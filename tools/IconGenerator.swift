import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: IconGenerator output.png\n", stderr)
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

let outer = NSRect(x: 36, y: 36, width: 952, height: 952)
let shell = NSBezierPath(roundedRect: outer, xRadius: 218, yRadius: 218)
NSGradient(starting: NSColor(calibratedRed: 0.07, green: 0.23, blue: 0.34, alpha: 1),
           ending: NSColor(calibratedRed: 0.04, green: 0.64, blue: 0.61, alpha: 1))?.draw(in: shell, angle: -42)

NSColor(calibratedRed: 0.22, green: 0.82, blue: 0.78, alpha: 0.19).setFill()
let glow = NSBezierPath()
glow.move(to: NSPoint(x: 71, y: 562))
glow.curve(to: NSPoint(x: 655, y: 954), controlPoint1: NSPoint(x: 142, y: 786), controlPoint2: NSPoint(x: 376, y: 960))
glow.curve(to: NSPoint(x: 975, y: 808), controlPoint1: NSPoint(x: 815, y: 958), controlPoint2: NSPoint(x: 937, y: 870))
glow.curve(to: NSPoint(x: 644, y: 865), controlPoint1: NSPoint(x: 857, y: 898), controlPoint2: NSPoint(x: 753, y: 903))
glow.curve(to: NSPoint(x: 71, y: 562), controlPoint1: NSPoint(x: 352, y: 777), controlPoint2: NSPoint(x: 128, y: 645))
glow.fill()

// Main display
rounded(NSRect(x: 198, y: 409, width: 468, height: 370), radius: 42, color: NSColor(calibratedRed: 0.025, green: 0.16, blue: 0.25, alpha: 1))
let largeScreen = NSRect(x: 222, y: 465, width: 420, height: 290)
let largePath = NSBezierPath(roundedRect: largeScreen, xRadius: 25, yRadius: 25)
NSGradient(starting: NSColor(calibratedRed: 0.84, green: 1, blue: 0.98, alpha: 1), ending: NSColor(calibratedRed: 0.55, green: 0.91, blue: 0.87, alpha: 1))?.draw(in: largePath, angle: 90)
NSColor(calibratedRed: 0.28, green: 0.78, blue: 0.75, alpha: 0.82).setFill()
let hill = NSBezierPath()
hill.move(to: NSPoint(x: 222, y: 508)); hill.curve(to: NSPoint(x: 515, y: 519), controlPoint1: NSPoint(x: 311, y: 640), controlPoint2: NSPoint(x: 435, y: 604))
hill.curve(to: NSPoint(x: 642, y: 601), controlPoint1: NSPoint(x: 561, y: 480), controlPoint2: NSPoint(x: 608, y: 505))
hill.line(to: NSPoint(x: 642, y: 465)); hill.line(to: NSPoint(x: 222, y: 465)); hill.close(); hill.fill()
rounded(NSRect(x: 390, y: 355, width: 84, height: 54), radius: 12, color: NSColor(calibratedRed: 0.025, green: 0.16, blue: 0.25, alpha: 1))
rounded(NSRect(x: 326, y: 327, width: 212, height: 31), radius: 16, color: NSColor(calibratedRed: 0.025, green: 0.16, blue: 0.25, alpha: 1))

// Smaller display
let border = NSBezierPath(roundedRect: NSRect(x: 544, y: 373, width: 269, height: 304), xRadius: 34, yRadius: 34)
NSColor(calibratedRed: 0.035, green: 0.17, blue: 0.26, alpha: 1).setFill(); border.fill()
NSColor(calibratedRed: 0.56, green: 1, blue: 0.95, alpha: 1).setStroke(); border.lineWidth = 13; border.stroke()
let smallScreen = NSRect(x: 571, y: 444, width: 215, height: 205)
rounded(smallScreen, radius: 17, color: NSColor(calibratedRed: 0.84, green: 1, blue: 0.98, alpha: 1))
NSColor(calibratedRed: 0.32, green: 0.80, blue: 0.76, alpha: 1).setFill()
let smallHill = NSBezierPath(); smallHill.move(to: NSPoint(x: 571, y: 483)); smallHill.curve(to: NSPoint(x: 723, y: 506), controlPoint1: NSPoint(x: 630, y: 558), controlPoint2: NSPoint(x: 679, y: 575)); smallHill.curve(to: NSPoint(x: 786, y: 551), controlPoint1: NSPoint(x: 744, y: 489), controlPoint2: NSPoint(x: 765, y: 490)); smallHill.line(to: NSPoint(x: 786, y: 444)); smallHill.line(to: NSPoint(x: 571, y: 444)); smallHill.close(); smallHill.fill()
rounded(NSRect(x: 651, y: 328, width: 57, height: 45), radius: 10, color: NSColor(calibratedRed: 0.035, green: 0.17, blue: 0.26, alpha: 1))
rounded(NSRect(x: 606, y: 308, width: 147, height: 25), radius: 13, color: NSColor(calibratedRed: 0.035, green: 0.17, blue: 0.26, alpha: 1))

NSColor(calibratedRed: 0.71, green: 1, blue: 0.96, alpha: 0.96).setFill()
NSBezierPath(ovalIn: NSRect(x: 773, y: 759, width: 82, height: 82)).fill()
NSColor(calibratedRed: 0.03, green: 0.48, blue: 0.48, alpha: 1).setStroke()
let plus = NSBezierPath(); plus.lineWidth = 15; plus.lineCapStyle = .round
plus.move(to: NSPoint(x: 814, y: 780)); plus.line(to: NSPoint(x: 814, y: 820)); plus.move(to: NSPoint(x: 794, y: 800)); plus.line(to: NSPoint(x: 834, y: 800)); plus.stroke()

image.unlockFocus()
guard let data = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: data),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
