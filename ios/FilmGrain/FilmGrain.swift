// FilmGrain: real 35mm film grain over an app's whole UI, at the screen's own
// pixels.
//
//     import FilmGrain
//     FilmGrain.install()          // once, at launch: covers every window the app shows
//
// The grain is FilmGrain.png in the app's bundle, written by
// `film-grain --overlay` (bkazez/bin): a gray picture of one scanned 35mm
// negative, 128 where there is no grain, one level of 255 per step. It is
// laid over each window as one ordinary translucent layer: white where the
// grain is light and black where it is dark, as opaque as the grain is far
// from 128. On black it lightens by the grain's full step and on white it
// darkens by it; in between each half moves a pixel part of the way. A
// blend mode such as plus-darker would move every tone alike, but it draws
// black wherever nothing is under it, and a device decides where that is.
// One grain pixel is one screen pixel, never scaled. The layer sits above
// everything in the window, sheets included, and takes no touches. Only the
// app's own windows are covered.
import UIKit

@MainActor
public enum FilmGrain {
    private static var grain: CGImage?
    /// The grain mirrored out to each size of window, made once and shared.
    private static var sheets: [Int: CGImage] = [:]
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
              let made = translucent(source) else { return }
        grain = made
        installed = true
        // Covered as the window appears, so no frame of it is shown without grain.
        NotificationCenter.default.addObserver(watcher, selector: #selector(Watcher.windowBecameVisible(_:)),
                                               name: UIWindow.didBecomeVisibleNotification, object: nil)
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.windows.forEach(cover)
        }
    }

    fileprivate static func cover(_ window: UIWindow) {
        guard let grain, isTheApps(window), let screen = window.windowScene?.screen,
              window.layer.sublayers?.contains(where: { $0.name == name }) != true else { return }
        let scale = screen.scale
        // A square as wide as the screen is long, so turning the device needs no redraw.
        let points = max(screen.bounds.width, screen.bounds.height)
        let pixels = Int((points * scale).rounded(.up))
        if sheets[pixels] == nil { sheets[pixels] = mirrored(grain, to: pixels) }
        guard let sheet = sheets[pixels] else { return }
        let layer = CALayer()
        layer.name = name
        layer.contents = sheet
        layer.contentsScale = scale
        layer.contentsGravity = .topLeft
        layer.frame = CGRect(x: 0, y: 0, width: points, height: points)
        layer.zPosition = above
        window.layer.addSublayer(layer)
    }

    /// A plain UIWindow, or one of a class that is not UIKit's own.
    static func isTheApps(_ window: UIWindow) -> Bool {
        let kind: AnyClass = type(of: window)
        return kind == UIWindow.self || Bundle(for: kind) != Bundle(for: UIWindow.self)
    }

    /// The 128-centered gray grain as premultiplied sRGB: white where it is
    /// above 128 and black where it is below, with alpha its distance from 128.
    private static func translucent(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        var gray = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(data: &gray, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for (i, g) in gray.enumerated() where g != 128 {
            let light = g > 128
            let alpha = light ? g - 128 : 128 - g
            let color = light ? alpha : 0
            rgba[4 * i] = color; rgba[4 * i + 1] = color; rgba[4 * i + 2] = color; rgba[4 * i + 3] = alpha
        }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: srgb, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(rgba) as CFData)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// IMAGE run on past its edges mirrored, to SIDE pixels square, as the
    /// negative would continue.
    private static func mirrored(_ image: CGImage, to side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
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
