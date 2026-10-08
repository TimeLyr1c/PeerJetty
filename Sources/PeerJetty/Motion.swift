import AppKit
import QuartzCore

/// Local preference plus the live system accessibility policy. No polling or private defaults.
final class MotionPolicy {
    static let changed = Notification.Name("PeerJetty.MotionPolicyChanged")
    static let shared = MotionPolicy()
    var enabled = true { didSet { if enabled != oldValue { notify() } } }
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

enum MotionEffects {
    static let appearDuration = 0.24, disappearDuration = 0.16, statusDuration = 0.12, successDuration = 0.22
    static let smooth = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
    static let exit = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.6, 1)
    static func transition(_ view: NSView, policy: MotionPolicy = .shared) {
        guard policy.allowed, view.window?.isVisible == true else { return }
        view.wantsLayer = true
        let fade = CATransition(); fade.type = .fade; fade.duration = statusDuration; fade.timingFunction = .init(name: .easeInEaseOut)
        view.layer?.add(fade, forKey: "PeerJetty.status")
    }
    static func appear(_ view: NSView) {
        view.wantsLayer = true
        let spring = CASpringAnimation(keyPath: "transform.scale")
        spring.fromValue = 0.98
        spring.toValue = 1; spring.mass = 1; spring.stiffness = 520; spring.damping = 36
        spring.duration = appearDuration
        view.layer?.add(spring, forKey: "PeerJetty.appear")
    }
    static func pulse(_ view: NSView, policy: MotionPolicy = .shared) {
        guard policy.allowed, view.window?.isVisible == true else { return }
        view.wantsLayer = true
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        let start = (view.layer?.presentation()?.value(forKeyPath: "transform.scale") as? NSNumber)?.doubleValue ?? 1
        scale.values = [start, 1.065, 0.995, 1]; scale.keyTimes = [0, 0.42, 0.78, 1]
        scale.timingFunctions = [smooth, .init(name: .easeInEaseOut), smooth]; scale.duration = successDuration
        scale.beginTime = view.layer?.convertTime(CACurrentMediaTime(), from: nil) ?? CACurrentMediaTime()
        view.layer?.add(scale, forKey: "PeerJetty.feedback")
    }
    static func clear(_ view: NSView) {
        for key in view.layer?.animationKeys() ?? [] where key.hasPrefix("PeerJetty.") { view.layer?.removeAnimation(forKey: key) }
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
    func reveal(immediately: Bool = false, order: () -> Void) {
        guard let window else { return }
        let fresh = !window.isVisible
        revision += 1; let token = revision; completion = nil
        if let content = window.contentView { MotionEffects.clear(content) }
        appearing = policy.allowed && !immediately
        if fresh { window.alphaValue = appearing ? 0 : 1 }
        order()
        if appearing, fresh, let content = window.contentView { MotionEffects.appear(content) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = self.appearing ? MotionEffects.appearDuration : 0; context.timingFunction = MotionEffects.smooth
            window.animator().alphaValue = 1
        } completionHandler: { [weak self] in if self?.revision == token { self?.appearing = false } }
    }
    func dismiss(_ action: @escaping () -> Void) {
        guard completion == nil else { return }
        guard let window, window.isVisible, policy.allowed else { finishImmediately(); action(); return }
        revision += 1; let token = revision; completion = action; appearing = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MotionEffects.disappearDuration; context.timingFunction = MotionEffects.exit
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.revision == token else { return }; self.finishImmediately()
        }
    }
    func snapAppearance() { if appearing { reveal(immediately: true) {} } }
    func finishImmediately() {
        revision += 1; appearing = false
        if let window {
            NSAnimationContext.runAnimationGroup { context in context.duration = 0; window.animator().alphaValue = 1 }
            if let content = window.contentView { MotionEffects.clear(content) }
        }
        let action = completion; completion = nil; action?()
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
