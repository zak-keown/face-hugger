import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Centers genuine window captures, unscaled, on the opaque slate Store canvas.
// Usage: swift Scripts/Art/frame_screenshots.swift RAW.png OUT.png [RAW.png OUT.png ...]
let width = 2560, height = 1600
let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty, arguments.count % 2 == 0 else { fatalError("Pass RAW.png OUT.png pairs") }
for index in stride(from: 0, to: arguments.count, by: 2) {
    let (input, output) = (arguments[index], arguments[index + 1])
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: input) as CFURL, nil),
          let capture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Unreadable capture: \(input)") }
    guard capture.width <= width, capture.height <= height else { fatalError("\(input) is \(capture.width)×\(capture.height); capture a smaller window instead of scaling") }
    let canvas = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    canvas.interpolationQuality = .none
    canvas.setFillColor(CGColor(srgbRed:0x25/255.0,green:0x31/255.0,blue:0x3C/255.0,alpha:1))
    canvas.fill(CGRect(x:0,y:0,width:width,height:height))
    canvas.draw(capture, in:CGRect(x:(width - capture.width) / 2,y:(height - capture.height) / 2,width:capture.width,height:capture.height))
    let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: output) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, canvas.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(output)") }
    print("Framed \(input) → \(output)")
}
