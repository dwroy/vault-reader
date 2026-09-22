#!/usr/bin/env swift
// Original vector artwork. Run from the repository root with Swift on macOS.
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("VaultReader/Assets.xcassets")
let artwork = root.appendingPathComponent("artwork")
let info: [String: Any] = ["author": "xcode", "version": 1]

enum Command {
    case m(CGFloat, CGFloat), l(CGFloat, CGFloat)
    case c(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)
    case q(CGFloat, CGFloat, CGFloat, CGFloat), z
    var svg: String {
        func n(_ v: CGFloat) -> String { String(Int(v)) }
        switch self {
        case let .m(x,y): return "M\(n(x)) \(n(y))"
        case let .l(x,y): return "L\(n(x)) \(n(y))"
        case let .c(a,b,c,d,e,f): return "C\(n(a)) \(n(b)) \(n(c)) \(n(d)) \(n(e)) \(n(f))"
        case let .q(a,b,c,d): return "Q\(n(a)) \(n(b)) \(n(c)) \(n(d))"
        case .z: return "Z"
        }
    }
}
let left: [Command] = [.m(244,276), .c(329,280,421,312,487,365), .l(487,745), .c(418,690,330,663,244,658), .q(228,657,228,641), .l(228,294), .q(228,275,244,276), .z]
let right: [Command] = [.m(537,365), .c(604,312,695,280,780,276), .q(796,275,796,294), .l(796,641), .q(796,657,780,658), .c(694,663,606,690,537,745), .z]
// The notch echoes a saved place, while the two page edges form a quiet V.
let bookmark: [Command] = [.m(674,302), .q(697,292,720,286), .l(720,433), .l(697,416), .l(674,442), .z]
let line1: [Command] = [.m(294,385), .c(342,391,387,408,427,432)]
let line2: [Command] = [.m(294,452), .c(342,458,387,475,427,499)]

struct Palette {
    let background: String, page: String, bookmark: String, ink: String
}
let regular = Palette(background:"24755A", page:"FFF9EB", bookmark:"DDC17C", ink:"D2DED0")
let dark = Palette(background:"102D25", page:"BDE6D1", bookmark:"D9BE7A", ink:"659E83")
let tinted = Palette(background:"202020", page:"EEEEEE", bookmark:"AAAAAA", ink:"A0A0A0")

func color(_ hex: String) -> CGColor {
    let rgb = UInt32(hex, radix:16)!
    return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components:[CGFloat((rgb >> 16) & 255)/255, CGFloat((rgb >> 8) & 255)/255, CGFloat(rgb & 255)/255, 1])!
}
func path(_ commands:[Command]) -> CGPath {
    let p=CGMutablePath()
    for command in commands {
        switch command {
        case let .m(x,y): p.move(to:CGPoint(x:x,y:y))
        case let .l(x,y): p.addLine(to:CGPoint(x:x,y:y))
        case let .c(a,b,c,d,e,f): p.addCurve(to:CGPoint(x:e,y:f),control1:CGPoint(x:a,y:b),control2:CGPoint(x:c,y:d))
        case let .q(a,b,c,d): p.addQuadCurve(to:CGPoint(x:c,y:d),control:CGPoint(x:a,y:b))
        case .z: p.closeSubpath()
        }
    }
    return p
}
func draw(_ ctx:CGContext, _ palette:Palette, background:Bool) {
    if background { ctx.setFillColor(color(palette.background)); ctx.fill(CGRect(x:0,y:0,width:1024,height:1024)) }
    for p in [left,right] { ctx.addPath(path(p)); ctx.setFillColor(color(palette.page)); ctx.fillPath() }
    ctx.addPath(path(bookmark)); ctx.setFillColor(color(palette.bookmark)); ctx.fillPath()
    ctx.setLineWidth(17); ctx.setLineCap(.round); ctx.setStrokeColor(color(palette.ink))
    for p in [line1,line2] { ctx.addPath(path(p)); ctx.strokePath() }
}
func writeJSON(_ value:Any, to url:URL) throws {
    try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
    let data=try JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes])
    try data.write(to:url)
}
func png(_ name:String,_ palette:Palette) throws {
    let url=assets.appendingPathComponent("AppIcon.appiconset/\(name).png")
    let ctx=CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x:0,y:1024); ctx.scaleBy(x:1,y:-1)
    draw(ctx,palette,background:true)
    let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
    CGImageDestinationAddImage(destination,ctx.makeImage()!,nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG export failed") }
}
func pdf(_ name:String,_ palette:Palette) throws {
    let url=assets.appendingPathComponent("BrandMark.imageset/\(name).pdf")
    var bounds=CGRect(x:0,y:0,width:600,height:500)
    let ctx=CGContext(url as CFURL,mediaBox:&bounds,nil)!
    ctx.beginPDFPage(nil); ctx.translateBy(x:-212,y:760); ctx.scaleBy(x:1,y:-1)
    draw(ctx,palette,background:false)
    ctx.endPDFPage(); ctx.closePDF()
}
func svg(_ name:String,_ palette:Palette,background:Bool) throws {
    let viewBox=background ? "0 0 1024 1024" : "212 260 600 500"
    var elements = background ? ["<rect width=\"1024\" height=\"1024\" fill=\"#\(palette.background)\"/>"] : []
    for p in [left,right] { elements.append("<path d=\"\(p.map(\.svg).joined(separator:" "))\" fill=\"#\(palette.page)\"/>") }
    elements.append("<path d=\"\(bookmark.map(\.svg).joined(separator:" "))\" fill=\"#\(palette.bookmark)\"/>")
    for p in [line1,line2] { elements.append("<path d=\"\(p.map(\.svg).joined(separator:" "))\" fill=\"none\" stroke=\"#\(palette.ink)\" stroke-width=\"17\" stroke-linecap=\"round\"/>") }
    let content="<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(viewBox)\" role=\"img\" aria-label=\"Vault Reader\">\n" + elements.joined(separator:"\n") + "\n</svg>\n"
    try content.write(to:artwork.appendingPathComponent(name),atomically:true,encoding:.utf8)
}
try FileManager.default.createDirectory(at:artwork,withIntermediateDirectories:true)
try writeJSON(["info":info],to:assets.appendingPathComponent("Contents.json"))
try writeJSON(["info":info,"images":[
    ["filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"],
    ["filename":"AppIcon-dark.png","idiom":"universal","platform":"ios","size":"1024x1024","appearances":[["appearance":"luminosity","value":"dark"]]],
    ["filename":"AppIcon-tinted.png","idiom":"universal","platform":"ios","size":"1024x1024","appearances":[["appearance":"luminosity","value":"tinted"]]]
]],to:assets.appendingPathComponent("AppIcon.appiconset/Contents.json"))
try writeJSON(["info":info,"images":[
    ["filename":"BrandMark.pdf","idiom":"universal"],
    ["filename":"BrandMark-dark.pdf","idiom":"universal","appearances":[["appearance":"luminosity","value":"dark"]]]
],"properties":["preserves-vector-representation":true]],to:assets.appendingPathComponent("BrandMark.imageset/Contents.json"))
let logo=Palette(background:"FFFFFF",page:"24755A",bookmark:"DDC17C",ink:"A7CBBA")
try png("AppIcon",regular); try png("AppIcon-dark",dark); try png("AppIcon-tinted",tinted)
try pdf("BrandMark",logo); try pdf("BrandMark-dark",dark)
try svg("app-icon.svg",regular,background:true); try svg("logo.svg",logo,background:false)
print("Generated original SVG artwork, vector logo PDFs and three opaque 1024px icon appearances.")
