// Reproduce the user's bank QR byte-for-byte; never invent a new payee code.
import Foundation
import CoreImage
import AppKit
let config = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: String]
let filter = CIFilter(name: "CIQRCodeGenerator")!
filter.setValue(Data(config["qrPayload"]!.utf8), forKey: "inputMessage")
filter.setValue("M", forKey: "inputCorrectionLevel")
let code = filter.outputImage!
let background = CIImage(color: CIColor.white).cropped(to: code.extent.insetBy(dx: -4, dy: -4))
let padded = code.composited(over: background)
let output = padded.transformed(by: CGAffineTransform(scaleX: 24, y: 24))
let context = CIContext(options: [.useSoftwareRenderer: true])
guard let cg = context.createCGImage(output, from: output.extent),
      let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { fatalError("Could not encode bank QR") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
