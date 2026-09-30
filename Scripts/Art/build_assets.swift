import AppKit

// Mechanical asset packaging from the user-directed ImageGen master artwork.
// Regeneration requires only macOS and Swift; no image generation API is called.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = root.appendingPathComponent("Resources/Artwork/face-hugger-master.png")
guard let master = NSImage(contentsOf: masterURL) else { fatalError("Missing master artwork") }
func color(_ value: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
}
func render(size: Int, icon: Bool, path: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let transform = NSAffineTransform(); transform.scale(by:CGFloat(size)/1024); transform.concat()
    if icon {
        let tile = NSBezierPath(roundedRect:NSRect(x:64,y:64,width:896,height:896),xRadius:190,yRadius:190)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.17); shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width:0,height:-8); shadow.set()
        color(0xF8FAFB).setFill(); tile.fill(); NSShadow().set()
        NSGradient(starting:color(0xEBEFF2),ending:color(0xFFFFFF))!.draw(in:tile,angle:90)
        master.draw(in:NSRect(x:66,y:76,width:892,height:892),from:.zero,operation:.sourceOver,fraction:1)
    } else {
        master.draw(in:NSRect(x:0,y:0,width:1024,height:1024),from:.zero,operation:.sourceOver,fraction:1)
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(path))
}
func json(_ value:Any,_ path:String) throws {
    try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent(path))
}
let folder = "Resources/Assets.xcassets/AppIcon.appiconset"
var icons: [[String:String]] = []
for pointSize in [16,32,128,256,512] {
    for scale in [1,2] {
        let file = "icon_\(pointSize)x\(pointSize)@\(scale)x.png"
        try render(size:pointSize*scale,icon:true,path:"\(folder)/\(file)")
        icons.append(["idiom":"mac","size":"\(pointSize)x\(pointSize)","scale":"\(scale)x","filename":file])
    }
}
try json(["images":icons,"info":["author":"xcode","version":1]],"\(folder)/Contents.json")
try render(size:1024,icon:false,path:"Resources/Assets.xcassets/Hugger.imageset/hugger.png")
try json(["images":[["idiom":"universal","filename":"hugger.png"]],"info":["author":"xcode","version":1]],"Resources/Assets.xcassets/Hugger.imageset/Contents.json")
print("Built Face Hugger icon and mascot assets from the approved art direction.")
