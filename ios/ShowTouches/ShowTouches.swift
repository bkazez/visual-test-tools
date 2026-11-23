// ShowTouches: draw every touch on the screen, in the app itself, for screen
// recordings. `simctl io recordVideo` records what the app draws and nothing of
// the Simulator's own "Show Touches", so a film of a UI test shows buttons
// changing with no finger to say why. Start it in the app's capture mode only:
//
//     import ShowTouches
//
//     if ProcessInfo.processInfo.environment["CAPTURE"] != nil { ShowTouches.start() }
//
// Each touch is a translucent disc that follows the finger and fades as it
// lifts, in a window above everything the app draws that takes no touches of
// its own. It sees what reaches the app's windows; the keyboard is iOS's and
// draws its own keys pressed.

import UIKit

@MainActor
public enum ShowTouches {
    private static var started = false

    /// Starts drawing touches in every scene of the app, from now on.
    public static func start() {
        guard !started else { return }
        started = true
        guard let original = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))),
              let shown = class_getInstanceMethod(UIWindow.self, #selector(UIWindow.showTouches_sendEvent(_:))) else { return }
        method_exchangeImplementations(original, shown)
    }
}

extension UIWindow {
    /// The window's own sendEvent (the implementations are exchanged), then the touches drawn.
    @objc fileprivate func showTouches_sendEvent(_ event: UIEvent) {
        showTouches_sendEvent(event)
        guard event.type == .touches, !(self is TouchesWindow), let scene = windowScene else { return }
        TouchesWindow.over(scene).show(event.allTouches ?? [])
    }
}

private final class TouchesWindow: UIWindow {
    private static var windows: [ObjectIdentifier: TouchesWindow] = [:]
    private var discs: [ObjectIdentifier: UIView] = [:]

    static let diameter: CGFloat = 44

    static func over(_ scene: UIWindowScene) -> TouchesWindow {
        if let window = windows[ObjectIdentifier(scene)] { return window }
        let window = TouchesWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.isUserInteractionEnabled = false
        window.backgroundColor = .clear
        window.isHidden = false
        windows[ObjectIdentifier(scene)] = window
        return window
    }

    func show(_ touches: Set<UITouch>) {
        for touch in touches {
            let key = ObjectIdentifier(touch), at = touch.location(in: self)
            switch touch.phase {
            case .began:
                let disc = UIView(frame: CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
                disc.layer.cornerRadius = Self.diameter / 2
                disc.backgroundColor = UIColor(white: 0.5, alpha: 0.45)
                disc.layer.borderColor = UIColor(white: 1, alpha: 0.85).cgColor
                disc.layer.borderWidth = 2
                disc.center = at
                addSubview(disc)
                discs[key] = disc
            case .moved, .stationary:
                discs[key]?.center = at
            case .ended, .cancelled:
                guard let disc = discs.removeValue(forKey: key) else { continue }
                UIView.animate(withDuration: 0.35, animations: {
                    disc.alpha = 0
                    disc.transform = CGAffineTransform(scaleX: 1.4, y: 1.4)
                }, completion: { _ in disc.removeFromSuperview() })
            default:
                break
            }
        }
    }
}
