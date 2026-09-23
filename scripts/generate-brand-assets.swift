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
// An open book: the left page is a Markdown document being written (heading, prose, caret);
// the right page carries the sparkle of the agents that maintain it. Pages slant toward the spine.
let leftPage: [Command] = [.m(200,266), .q(200,240,225,248), .l(457,318), .q(482,325,482,351), .l(482,739), .q(482,765,457,758), .l(225,688), .q(200,680,200,654), .z]
let rightPage: [Command] = [.m(542,351), .q(542,325,567,318), .l(799,248), .q(824,240,824,266), .l(824,654), .q(824,680,799,688), .l(567,758), .q(542,765,542,739), .z]
let heading: [[Command]] = [[.m(281,326), .l(268,399)], [.m(316,336), .l(303,410)], [.m(253,341), .l(331,364)], [.m(253,371), .l(331,394)]]
let headingBar: [Command] = [.m(364,389), .l(436,411)]
let prose: [[Command]] = [[.m(252,446), .l(434,501)], [.m(252,526), .l(376,563)]]
let caret = CGRect(x:389, y:539, width:26, height:64)
let sparkle: [Command] = [.m(683,397), .c(690,466,719,495,788,502), .c(719,509,690,538,683,607), .c(676,538,647,509,578,502), .c(647,495,676,466,683,397), .z]

struct Palette {
    let background: String, page: String, ink: String, line: String, spark: String, caret: String
}
enum Layer {
    case fill([Command], KeyPath<Palette, String>)
    case stroke([Command], CGFloat, KeyPath<Palette, String>)
    case rounded(CGRect, CGFloat, KeyPath<Palette, String>)
}
let layers: [Layer] = [.fill(leftPage, \.page), .fill(rightPage, \.page)]
    + heading.map { .stroke($0, 18, \.ink) } + [.stroke(headingBar, 30, \.ink)]
    + prose.map { .stroke($0, 28, \.line) } + [.rounded(caret, 6, \.caret), .fill(sparkle, \.spark)]

let regular = Palette(background:"1B5E4B", page:"FFF9EB", ink:"1B5E4B", line:"C9D8CF", spark:"E8AE45", caret:"E8AE45")
let dark = Palette(background:"102D25", page:"BDE6D1", ink:"102D25", line:"8FBFA8", spark:"C28A2C", caret:"C28A2C")
let tinted = Palette(background:"202020", page:"EEEEEE", ink:"202020", line:"B4B4B4", spark:"6E6E6E", caret:"6E6E6E")
let logo = Palette(background:"FFFFFF", page:"1B5E4B", ink:"FFF9EB", line:"8DB8A5", spark:"E8AE45", caret:"E8AE45")

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
    ctx.setLineCap(.round)
    for layer in layers {
        switch layer {
        case let .fill(p, key): ctx.addPath(path(p)); ctx.setFillColor(color(palette[keyPath:key])); ctx.fillPath()
        case let .stroke(p, width, key): ctx.addPath(path(p)); ctx.setLineWidth(width); ctx.setStrokeColor(color(palette[keyPath:key])); ctx.strokePath()
        case let .rounded(rect, radius, key): ctx.addPath(CGPath(roundedRect:rect,cornerWidth:radius,cornerHeight:radius,transform:nil)); ctx.setFillColor(color(palette[keyPath:key])); ctx.fillPath()
        }
    }
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
// The standalone mark is cropped to a square around the open book.
let markBox = CGRect(x:182, y:172, width:660, height:660)
func pdf(_ name:String,_ palette:Palette) throws {
    let url=assets.appendingPathComponent("BrandMark.imageset/\(name).pdf")
    var bounds=CGRect(origin:.zero,size:markBox.size)
    let ctx=CGContext(url as CFURL,mediaBox:&bounds,nil)!
    ctx.beginPDFPage(nil); ctx.translateBy(x:-markBox.minX,y:markBox.maxY); ctx.scaleBy(x:1,y:-1)
    draw(ctx,palette,background:false)
    ctx.endPDFPage(); ctx.closePDF()
}
func svg(_ name:String,_ palette:Palette,background:Bool) throws {
    func n(_ v: CGFloat) -> String { String(Int(v)) }
    let viewBox=background ? "0 0 1024 1024" : "\(n(markBox.minX)) \(n(markBox.minY)) \(n(markBox.width)) \(n(markBox.height))"
    var elements = background ? ["<rect width=\"1024\" height=\"1024\" fill=\"#\(palette.background)\"/>"] : []
    for layer in layers {
        switch layer {
        case let .fill(p, key): elements.append("<path d=\"\(p.map(\.svg).joined(separator:" "))\" fill=\"#\(palette[keyPath:key])\"/>")
        case let .stroke(p, width, key): elements.append("<path d=\"\(p.map(\.svg).joined(separator:" "))\" fill=\"none\" stroke=\"#\(palette[keyPath:key])\" stroke-width=\"\(n(width))\" stroke-linecap=\"round\"/>")
        case let .rounded(r, radius, key): elements.append("<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" rx=\"\(n(radius))\" fill=\"#\(palette[keyPath:key])\"/>")
        }
    }
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
try png("AppIcon",regular); try png("AppIcon-dark",dark); try png("AppIcon-tinted",tinted)
try pdf("BrandMark",logo); try pdf("BrandMark-dark",dark)
try svg("app-icon.svg",regular,background:true); try svg("logo.svg",logo,background:false)
print("Generated original SVG artwork, vector logo PDFs and three opaque 1024px icon appearances.")
