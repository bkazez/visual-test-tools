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
    /// The halves mirrored out to each size of window, made once and shared.
    private static var sheets: [Int: [CGImage]] = [:]
    private static let watcher = Watcher()
    private static var installed = false
    private static let name = "FilmGrain"
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    /// Above every layer UIKit stacks in a window, sheets included. Finite:
    /// .greatestFiniteMagnitude reaches the render server's floats as infinity.
    private static let above: CGFloat = 1_000_000

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
        if sheets[pixels] == nil {
            let made = [halves.light, halves.dark].compactMap { mirrored($0, to: pixels) }
            guard made.count == 2 else { return }
            sheets[pixels] = made
        }
        for (sheet, filter) in zip(sheets[pixels]!, ["plusL", "plusD"]) {
            let layer = CALayer()
            layer.name = name
            layer.contents = sheet
            layer.contentsScale = scale
            layer.contentsGravity = .topLeft
            layer.frame = CGRect(x: 0, y: 0, width: points, height: points)
            layer.compositingFilter = filter
            layer.zPosition = above
            window.layer.addSublayer(layer)
        }
    }

    /// The light and dark halves of the 128-centered grain: the first adds what
    /// is above 128, the second (white less what is below 128) takes it away.
    /// Both are 8-bit RGB, the format every GPU samples alike, never one-channel gray.
    private static func split(_ image: CGImage) -> (light: CGImage, dark: CGImage)? {
        let w = image.width, h = image.height
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func picture(_ level: (UInt8) -> UInt8) -> CGImage? {
            var rgbx = [UInt8](repeating: 255, count: w * h * 4)
            for (i, g) in gray.enumerated() {
                let v = level(g)
                rgbx[4 * i] = v; rgbx[4 * i + 1] = v; rgbx[4 * i + 2] = v
            }
            return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                           space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                           provider: CGDataProvider(data: Data(rgbx) as CFData)!, decode: nil, shouldInterpolate: false,
                           intent: .defaultIntent)
        }
        guard let l = picture({ $0 > 128 ? $0 - 128 : 0 }),
              let d = picture({ $0 < 128 ? 255 - (128 - $0) : 255 }) else { return nil }
        return (l, d)
    }

    /// IMAGE run on past its edges mirrored, to SIDE pixels square, as the
    /// negative would continue.
    private static func mirrored(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
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
