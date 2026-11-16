// FilmGrain: real 35mm film grain over an app's whole UI, at the screen's own
// pixels, the same amount at every tone.
//
//     import FilmGrain
//     FilmGrain.install()          // once, at launch: covers every window the app shows
//
// The grain is FilmGrain.png in the app's bundle, written by
// `film-grain --overlay` (bkazez/bin): a gray picture of one scanned 35mm
// negative, 128 where there is no grain, one level of 255 per step. It is
// laid over each window as two layers, one adding the grain's light half
// (plus-lighter) and one taking away its dark half (plus-darker), so every
// pixel moves by the grain alone, near black as much as near white. One grain
// pixel is one screen pixel, never scaled. The layers sit above everything in
// the window, sheets included, and take no touches.
import UIKit

@MainActor
public enum FilmGrain {
    private static var halves: (light: CGImage, dark: CGImage)?
    private static let watcher = Watcher()
    private static var installed = false
    private static let name = "FilmGrain"

    public static func install(bundle: Bundle = .main) {
        guard !installed,
              let url = bundle.url(forResource: name, withExtension: "png"),
              let source = UIImage(contentsOfFile: url.path)?.cgImage,
              let made = split(source) else { return }
        halves = made
        installed = true
        // Covered as the window appears, so no frame of it is shown without grain.
        NotificationCenter.default.addObserver(watcher, selector: #selector(Watcher.windowBecameVisible(_:)),
                                               name: UIWindow.didBecomeVisibleNotification, object: nil)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(cover)
        }
    }

    fileprivate static func cover(_ window: UIWindow) {
        guard let halves, let screen = window.windowScene?.screen,
              window.layer.sublayers?.contains(where: { $0.name == name }) != true else { return }
        let scale = screen.scale
        // A square as wide as the screen is long, so turning the device needs no redraw.
        let points = max(screen.bounds.width, screen.bounds.height)
        let pixels = Int((points * scale).rounded(.up))
        for (half, filter) in [(halves.light, "plusL"), (halves.dark, "plusD")] {
            let layer = CALayer()
            layer.name = name
            layer.contents = mirrored(half, to: pixels)
            layer.contentsScale = scale
            layer.contentsGravity = .topLeft
            layer.frame = CGRect(x: 0, y: 0, width: points, height: points)
            layer.compositingFilter = filter
            layer.zPosition = .greatestFiniteMagnitude
            window.layer.addSublayer(layer)
        }
    }

    /// The light and dark halves of the 128-centered grain: the first adds what
    /// is above 128, the second (white less what is below 128) takes it away.
    private static func split(_ image: CGImage) -> (light: CGImage, dark: CGImage)? {
        let w = image.width, h = image.height
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let light = gray.map { $0 > 128 ? $0 - 128 : 0 }
        let dark = gray.map { $0 < 128 ? 255 - (128 - $0) : 255 }
        func picture(_ bytes: [UInt8]) -> CGImage? {
            CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                    provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard let l = picture(light), let d = picture(dark) else { return nil }
        return (l, d)
    }

    /// IMAGE run on past its edges mirrored, to SIDE pixels square, as the
    /// negative would continue.
    private static func mirrored(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        let w = image.width, h = image.height
        for row in 0..<(side + h - 1) / h {
            for col in 0..<(side + w - 1) / w {
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(col * w + (col % 2 == 1 ? w : 0)), y: CGFloat(side - row * h - (row % 2 == 1 ? 0 : h)))
                ctx.scaleBy(x: col % 2 == 1 ? -1 : 1, y: row % 2 == 1 ? -1 : 1)
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
                ctx.restoreGState()
            }
        }
        return ctx.makeImage()
    }
}

@MainActor
private final class Watcher: NSObject {
    @objc func windowBecameVisible(_ note: Notification) {
        (note.object as? UIWindow).map(FilmGrain.cover)
    }
}
