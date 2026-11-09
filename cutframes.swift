// 用法：cutframes <輸入資料夾 (frame_*.png)> <輸出資料夾> <輸出高度px>
// 每格用 Vision 去背；整段取同一個外框（所有格的聯集），腳底對齊同一條線，輸出透明 PNG
import Vision; import CoreImage; import AppKit
let a = CommandLine.arguments
let inDir = URL(fileURLWithPath: a[1]), outDir = URL(fileURLWithPath: a[2]); let outH = CGFloat(Double(a[3]) ?? 360)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let files = try FileManager.default.contentsOfDirectory(at: inDir, includingPropertiesForKeys: nil)
  .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
var masked: [CIImage] = []; var union = CGRect.null
let ctx = CIContext()
for f in files {
  let ci = CIImage(contentsOf: f)!
  let req = VNGenerateForegroundInstanceMaskRequest(); let h = VNImageRequestHandler(ciImage: ci)
  try h.perform([req])
  guard let r = req.results?.first else { masked.append(CIImage.empty().cropped(to: ci.extent)); continue }
  let buf = try r.generateMaskedImage(ofInstances: r.allInstances, from: h, croppedToInstancesExtent: false)
  let m = CIImage(cvPixelBuffer: buf); masked.append(m)
  // 外框：用 alpha 找
  let cg = ctx.createCGImage(m, from: m.extent)!
  let w = cg.width, hgt = cg.height
  var data = [UInt8](repeating: 0, count: w*hgt*4)
  let bctx = CGContext(data: &data, width: w, height: hgt, bitsPerComponent: 8, bytesPerRow: w*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
  bctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: hgt))
  var minX = w, minY = hgt, maxX = 0, maxY = 0
  for y in stride(from: 0, to: hgt, by: 2) { for x in stride(from: 0, to: w, by: 2) where data[(y*w+x)*4+3] > 40 {
    minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y) } }
  if maxX > minX { union = union.union(CGRect(x: minX, y: hgt-maxY, width: maxX-minX, height: maxY-minY)) } // CG y 翻轉
}
union = union.insetBy(dx: -6, dy: -6).intersection(masked[0].extent)
let scale = outH / union.height
for (i, m) in masked.enumerated() {
  let out = m.cropped(to: union).transformed(by: CGAffineTransform(translationX: -union.minX, y: -union.minY)).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
  try ctx.writePNGRepresentation(of: out, to: outDir.appendingPathComponent(String(format: "%03d.png", i)), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
}
print("frames \(masked.count) box \(union) -> \(Int(union.width*scale))x\(Int(outH))")
