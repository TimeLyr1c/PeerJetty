import AppKit
import QuartzCore
import PeerCore

/// Local preference plus the live system accessibility policy. No polling or private defaults.
final class MotionPolicy {
    static let changed = Notification.Name("PeerJetty.MotionPolicyChanged")
    static let shared = MotionPolicy()
    var enabled = true { didSet { if enabled != oldValue { notify() } } }
    var speed: AnimationSpeed = .natural
    var profile: MotionProfile { MotionProfile(speed) }
    private let reduceMotion: () -> Bool
    private var observer: NSObjectProtocol?
    var allowed: Bool { enabled && !reduceMotion() }
    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }) {
        self.reduceMotion = reduceMotion
        observer = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.notify() }
    }
    func notify() { NotificationCenter.default.post(name: Self.changed, object: self) }
    deinit { if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) } }
}

extension AnimationSpeed {
    var localizedTitle: String {
        switch self {
        case .fast: return L10n.text("settings.speed_fast")
        case .natural: return L10n.text("settings.speed_natural")
        case .relaxed: return L10n.text("settings.speed_relaxed")
        }
    }
}

struct MotionProfile {
    let appear: Double, status: Double, success: Double, hold: Double, dismiss: Double
    init(_ speed: AnimationSpeed) {
        switch speed {
        case .fast: (appear,status,success,hold,dismiss) = (0.22,0.10,0.32,1,0.16)
        case .natural: (appear,status,success,hold,dismiss) = (0.34,0.18,0.65,1.8,0.24)
        case .relaxed: (appear,status,success,hold,dismiss) = (0.48,0.24,0.95,2.8,0.32)
        }
    }
}

enum MotionEffects {
    static var appearDuration: Double { MotionPolicy.shared.profile.appear }
    static var disappearDuration: Double { MotionPolicy.shared.profile.dismiss }
    static var statusDuration: Double { MotionPolicy.shared.profile.status }
    static var successDuration: Double { MotionPolicy.shared.profile.success }
    static let smooth = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    static let exit = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
    static func transition(_ view: NSView, policy: MotionPolicy = .shared) {
        guard policy.allowed, view.window?.isVisible == true else { return }
        view.wantsLayer = true
        let fade = CATransition(); fade.type = .fade; fade.duration = policy.profile.status; fade.timingFunction = .init(name: .easeInEaseOut)
        add(fade,to:view.layer,key:"PeerJetty.status")
    }
    static func spring(duration: Double, from: Double) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath:"transform.scale")
        let ratio = 0.72, frequency = 8 / (ratio * duration)
        spring.fromValue = from; spring.toValue = 1; spring.mass = 1
        spring.stiffness = frequency * frequency; spring.damping = 2 * ratio * frequency
        spring.duration = duration
        return spring
    }
    static func appear(_ view: NSView, duration: Double = appearDuration) {
        view.wantsLayer = true
        add(spring(duration:duration, from:0.97),to:view.layer,key:"PeerJetty.appear")
    }
    static func pulse(_ view: NSView, policy: MotionPolicy = .shared) {
        guard policy.allowed, view.window?.isVisible == true else { return }
        view.wantsLayer = true
        let interrupted = view.layer?.animation(forKey:"PeerJetty.feedback") != nil
        let start = interrupted ? (view.layer?.presentation()?.value(forKeyPath:"transform.scale") as? NSNumber)?.doubleValue ?? 1 : 0.97
        add(spring(duration:policy.profile.success,from:start),to:view.layer,key:"PeerJetty.feedback")
    }
    static func add(_ animation: CAAnimation, to layer: CALayer?, key: String, delay: Double = 0) {
        guard let layer else { return }
        let token = layer.convertTime(CACurrentMediaTime(),from:nil) + delay
        animation.beginTime = token; layer.add(animation,forKey:key)
        DispatchQueue.main.asyncAfter(deadline:.now()+delay+animation.duration) { [weak layer] in
            guard let layer, layer.animation(forKey:key)?.beginTime == token else { return }
            layer.removeAnimation(forKey:key)
        }
    }
    static func clear(_ view: NSView) {
        func clearLayer(_ layer: CALayer) {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("PeerJetty.") { layer.removeAnimation(forKey:key) }
            layer.sublayers?.forEach(clearLayer)
        }
        if let layer = view.layer { clearLayer(layer) }
        view.subviews.forEach(clear)
    }
}

/// Retarget native window fades, invalidate stale completions, and never animate window geometry.
final class WindowMotion {
    private weak var window: NSWindow?
    private let policy: MotionPolicy
    private var revision = 0
    private var completion: (() -> Void)?
    private var observer: NSObjectProtocol?
    private(set) var appearing = false
    init(_ window: NSWindow, policy: MotionPolicy = .shared) {
        self.window = window; self.policy = policy
        observer = NotificationCenter.default.addObserver(forName: MotionPolicy.changed, object: policy, queue: .main) { [weak self] _ in
            guard let self, !self.policy.allowed else { return }; self.finishImmediately()
        }
    }
    func reveal(immediately: Bool = false, animateImmediateContent: Bool = false, order: () -> Void) {
        guard let window else { return }
        let fresh = !window.isVisible
        revision += 1; let token = revision; completion = nil
        if let content = window.contentView { MotionEffects.clear(content) }
        appearing = policy.allowed && !immediately
        if fresh { window.alphaValue = appearing ? 0 : 1 }
        order()
        let duration = policy.profile.appear
        if policy.allowed, fresh, (!immediately || animateImmediateContent), let content = window.contentView { MotionEffects.appear(content, duration:duration) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = self.appearing ? duration : 0; context.timingFunction = MotionEffects.smooth
            window.animator().alphaValue = 1
        } completionHandler: { [weak self] in if self?.revision == token { self?.appearing = false } }
    }
    func dismiss(_ action: @escaping () -> Void) {
        guard completion == nil else { return }
        guard let window, window.isVisible, policy.allowed else { completion = action; finishImmediately(); return }
        revision += 1; let token = revision; completion = action; appearing = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = self.policy.profile.dismiss; context.timingFunction = MotionEffects.exit
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.revision == token else { return }; self.finishImmediately()
        }
    }
    func makeInteractive() {
        guard let window else { return }
        NSAnimationContext.runAnimationGroup { context in context.duration = 0; window.animator().alphaValue = 1 }
    }
    func snapAppearance() { if appearing { reveal(immediately: true) {} } }
    func finishImmediately() {
        revision += 1; let token = revision; appearing = false
        let action = completion; completion = nil
        if let content = window?.contentView { MotionEffects.clear(content) }
        // Hide/close while still faded. Resetting alpha before this callback flashes the card.
        action?()
        guard revision == token else { return }
        if let window {
            NSAnimationContext.runAnimationGroup { context in context.duration = 0; window.animator().alphaValue = 1 }
        }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
