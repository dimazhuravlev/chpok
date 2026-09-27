import SwiftUI

/// Global shake detection (spec 32). Overriding `motionEnded` on `UIWindow`
/// catches the shake gesture regardless of what's currently first responder
/// or on screen — the SpriteKit scene never has to give up focus for this to
/// work, and it works the same whether the game or the game-over screen is
/// showing. `UIResponder`'s default `motionEnded` implementation forwards to
/// `next`, so with nothing else in the chain overriding it, the event
/// naturally bubbles all the way up to the window.
extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
        // Only the shake itself is acted on here; every motion type (shake
        // included) is still forwarded to `super`, so nothing else that
        // might rely on it is intercepted.
        super.motionEnded(motion, with: event)
    }
}

/// Attaches a shake handler to any view: `.onShake { ... }`.
private struct ShakeDetectingModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            action()
        }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        modifier(ShakeDetectingModifier(action: action))
    }
}
