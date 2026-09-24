// wrec <windowID> <secondes> <dossier> <largeur en points>
//
// Filme une seule fenêtre via ScreenCaptureKit : filtre d'écran restreint à
// cette fenêtre (ni fond d'écran ni barre des menus), fond transparent, bande
// centrée sur la fenêtre. Une image PNG par rafraîchissement, nommée d'après
// son horodatage en millisecondes.
import Foundation
import ScreenCaptureKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
let wid = CGWindowID(args[1])!, seconds = Double(args[2])!, out = URL(fileURLWithPath: args[3])
let cropW = CGFloat(Double(args[4])!)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

final class Sink: NSObject, SCStreamOutput {
    let ctx = CIContext()
    let q = DispatchQueue(label: "w", qos: .userInitiated)
    var start: CMTime?
    var n = 0
    func stream(_ s: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let att = (CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
              let raw = att[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pb = CMSampleBufferGetImageBuffer(sb) else { return }
        let t = CMSampleBufferGetPresentationTimeStamp(sb)
        if start == nil { start = t }
        let ms = Int((CMTimeGetSeconds(t) - CMTimeGetSeconds(start!)) * 1000)
        let ci = CIImage(cvPixelBuffer: pb)
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return }
        n += 1
        let url = out.appendingPathComponent(String(format: "f_%07d.png", ms))
        q.async {
            guard let d = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(d, cg, nil); CGImageDestinationFinalize(d)
        }
    }
}

let sink = Sink()
Task {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let w = content.windows.first(where: { $0.windowID == wid }) else { print("window not found"); exit(1) }
    guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: w.frame.midX, y: w.frame.minY + 1)) }) else { print("no display"); exit(1) }
    let filter = SCContentFilter(display: display, including: [w])
    let cfg = SCStreamConfiguration()
    let f = w.frame
    let dx = (w.frame.midX - display.frame.minX) - cropW / 2
    cfg.sourceRect = CGRect(x: dx, y: 0, width: cropW, height: f.height)
    cfg.width = Int(cropW * 2); cfg.height = Int(f.height * 2)
    cfg.backgroundColor = .clear
    cfg.pixelFormat = kCVPixelFormatType_32BGRA
    cfg.showsCursor = false
    cfg.ignoreShadowsSingleWindow = false
    cfg.shouldBeOpaque = false
    cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
    cfg.queueDepth = 8
    let stream = SCStream(filter: filter, configuration: cfg, delegate: nil)
    try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: DispatchQueue(label: "s"))
    try await stream.startCapture()
    print("recording"); fflush(stdout)
    try await Task.sleep(for: .seconds(seconds))
    try await stream.stopCapture()
    sink.q.sync {}
    print("frames", sink.n)
    exit(0)
}
RunLoop.main.run()
