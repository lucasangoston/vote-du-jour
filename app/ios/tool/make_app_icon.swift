// Génère les icônes Perchoir (#36) : logo « hémicycle en bandes » (deux arcs
// #F3F4F5 et un demi-disque #4FB08F) sur fond graphite #15181C.
// - iOS : toutes les tailles de AppIcon.appiconset, opaques, carré plein ;
// - Android : les PNG legacy (mipmap-*/ic_launcher.png), carré arrondi sur
//   fond transparent. L'icône adaptative, elle, est en vecteur
//   (drawable/ic_launcher_foreground.xml et ic_launcher_monochrome.xml).
//
// Depuis app/ios : swift tool/make_app_icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let iconSet = URL(fileURLWithPath: "Runner/Assets.xcassets/AppIcon.appiconset")
let androidRes = URL(fileURLWithPath: "../android/app/src/main/res")

func rgb(_ hex: UInt32) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// Logo dans la grille de 120 des maquettes (Main.dc.html) : arcs de rayon 46
/// et 28 centrés en (60, 86), épaisseur 12, bouts droits ; demi-disque de
/// rayon 12. Dessiné dans `square` (côté = 120 unités), y vers le bas comme en
/// SVG puis retourné pour CoreGraphics.
func drawLogo(in ctx: CGContext, square: CGRect) {
  let unit = square.width / 120
  ctx.saveGState()
  ctx.translateBy(x: square.minX, y: square.maxY)
  ctx.scaleBy(x: unit, y: -unit)
  // Maquette : logo de 96 dans une icône de 120 (échelle 0,8, centré).
  ctx.translateBy(x: 12, y: 12)
  ctx.scaleBy(x: 0.8, y: 0.8)
  ctx.setStrokeColor(rgb(0xF3F4F5))
  ctx.setLineWidth(12)
  ctx.setLineCap(.butt)
  for radius in [46.0, 28.0] {
    ctx.beginPath()
    // En repère SVG (y vers le bas), de π à 2π passe par le haut.
    ctx.addArc(center: CGPoint(x: 60, y: 86), radius: radius, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
  }
  ctx.setFillColor(rgb(0x4FB08F))
  ctx.beginPath()
  ctx.addArc(center: CGPoint(x: 60, y: 86), radius: 12, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
  ctx.closePath()
  ctx.fillPath()
  ctx.restoreGState()
}

func context(size: Int, opaque: Bool) -> CGContext {
  CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : .premultipliedLast).rawValue)!
}

/// iOS : carré plein et opaque, le système applique le masque.
func renderIOS(size: Int) -> CGImage {
  let ctx = context(size: size, opaque: true)
  let full = CGRect(x: 0, y: 0, width: size, height: size)
  ctx.setFillColor(rgb(0x15181C))
  ctx.fill(full)
  drawLogo(in: ctx, square: full)
  return ctx.makeImage()!
}

/// Android legacy : carré arrondi (marge 1/24, rayon 23 %), coins transparents.
func renderAndroidLegacy(size: Int) -> CGImage {
  let ctx = context(size: size, opaque: false)
  let side = CGFloat(size)
  let tile = CGRect(x: 0, y: 0, width: side, height: side).insetBy(dx: side / 24, dy: side / 24)
  ctx.setFillColor(rgb(0x15181C))
  ctx.addPath(
    CGPath(roundedRect: tile, cornerWidth: tile.width * 0.23, cornerHeight: tile.width * 0.23, transform: nil))
  ctx.fillPath()
  drawLogo(in: ctx, square: tile)
  return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(dest, image, nil)
  precondition(CGImageDestinationFinalize(dest), "écriture de \(url.path)")
}

// iOS, fichiers attendus par Contents.json : (nom, côté en pixels).
let data = try Data(contentsOf: iconSet.appendingPathComponent("Contents.json"))
let contents = try JSONSerialization.jsonObject(with: data) as! [String: Any]
for image in contents["images"] as! [[String: Any]] {
  guard let filename = image["filename"] as? String,
    let size = (image["size"] as? String)?.split(separator: "x").first.flatMap({ Double($0) }),
    let scale = (image["scale"] as? String).flatMap({ Double($0.dropLast()) })
  else { continue }
  let pixels = Int((size * scale).rounded())
  write(renderIOS(size: pixels), to: iconSet.appendingPathComponent(filename))
  print("\(filename) \(pixels) px")
}

// Android legacy : 48 dp par densité.
for (density, pixels) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
  let url = androidRes.appendingPathComponent("mipmap-\(density)/ic_launcher.png")
  write(renderAndroidLegacy(size: pixels), to: url)
  print("mipmap-\(density)/ic_launcher.png \(pixels) px")
}
