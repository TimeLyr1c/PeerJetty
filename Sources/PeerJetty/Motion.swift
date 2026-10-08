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
    let cardAppear: Double
    let progressRate: Double
    let appear: Double, status: Double, success: Double, hold: Double, dismiss: Double
    init(_ speed: AnimationSpeed) {
        switch speed {
        case .fast: cardAppear = 0.38; progressRate = 3; (appear,status,success,hold,dismiss) = (0.22,0.10,0.65,1,0.16)
        case .natural: cardAppear = 0.62; progressRate = 1.5; (appear,status,success,hold,dismiss) = (0.34,0.18,1.20,1.8,0.24)
        case .relaxed: cardAppear = 0.88; progressRate = 1; (appear,status,success,hold,dismiss) = (0.48,0.24,1.75,2.8,0.32)
        }
    }
}

/// A monotonic cubic segment with continuous retargeting velocity and a bounded
/// derivative. Core Animation evaluates it; no timer or per-frame task is needed.
struct ProgressMotion {
    let from: Double, target: Double, initialVelocity: Double, duration: Double, started: Double
    init(from: Double, target: Double, velocity: Double, rate: Double, minimum: Double, started: Double) {
        self.from = from; self.target = max(from,target); self.started = started
        let delta = self.target-from, speed = min(rate,max(0,velocity))
        initialVelocity = speed
        if delta <= 0 { duration = 0; return }
        let proposed = max(minimum,1.5*delta/rate)
        duration = speed > 0 ? min(proposed,3*delta/speed) : proposed
    }
    var timing: CAMediaTimingFunction {
        let delta = target-from
        let control = delta > 0 ? initialVelocity*duration/(3*delta) : 0
        return CAMediaTimingFunction(controlPoints:1/3,Float(control),2/3,1)
    }
    func sample(at time: Double) -> (value: Double, velocity: Double) {
        guard duration > 0, time < started+duration else { return (target,0) }
        let t = max(0,(time-started)/duration), delta = target-from, v = initialVelocity
        let value = from + v*duration*t + (3*delta-2*v*duration)*t*t + (v*duration-2*delta)*t*t*t
        let speed = v+(6*delta/duration-4*v)*t+(3*v-6*delta/duration)*t*t
        return (min(target,max(from,value)),max(0,speed))
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
    // Sample a damped step response once, not in a display-link or rendering loop.
    // Unequal axes give the glass a compressed-to-stretched silhouette without moving its target.
    static func cardTransform(at time: Double) -> CATransform3D {
        guard time < 1 else { return CATransform3DIdentity }
        let t = max(0,time), damping = 0.68, frequency = 7.5
        let decay = damping * frequency, oscillation = frequency * sqrt(1-damping*damping)
        // Released with velocity toward equilibrium: fast while far away, slow near it.
        var residual = exp(-decay*t) * cos(oscillation*t)
        // Softly settle the small tail with zero endpoint velocity; don't truncate a spring.
        let tail = max(0,min(1,(t-0.78)/0.22))
        residual *= 1-tail*tail*(3-2*tail)
        return CATransform3DMakeScale(1-0.14*residual,1-0.38*residual,1)
    }
    static func cardAppear(_ view: NSView, duration: Double) {
        view.wantsLayer = true
        let shape = CAKeyframeAnimation(keyPath:"transform")
        let anchor = view.layer?.anchorPoint ?? CGPoint(x:0.5,y:0.5)
        let center = CGPoint(x:view.bounds.width*(0.5-anchor.x),y:view.bounds.height*(0.5-anchor.y))
        shape.values = (0...60).map {
            var transform = cardTransform(at:Double($0)/60)
            // AppKit-backed layers need not use a centered anchor. Compensate in the
            // presentation transform without changing anchorPoint, position or layout.
            transform.m41 = center.x*(1-transform.m11); transform.m42 = center.y*(1-transform.m22)
            return NSValue(caTransform3D:transform)
        }
        shape.keyTimes = (0...60).map { NSNumber(value:Double($0)/60) }
        shape.calculationMode = .linear; shape.duration = duration
        add(shape,to:view.layer,key:"PeerJetty.cardShape")
        let opacity = CABasicAnimation(keyPath:"opacity")
        opacity.fromValue = 0.35; opacity.toValue = 1; opacity.duration = duration*0.18
        opacity.timingFunction = .init(name:.easeInEaseOut)
        add(opacity,to:view.layer,key:"PeerJetty.cardReveal")
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
    private let cardAppearance: Bool
    private let policy: MotionPolicy
    private var revision = 0
    private var completion: (() -> Void)?
    private var observer: NSObjectProtocol?
    private(set) var appearing = false
    init(_ window: NSWindow, policy: MotionPolicy = .shared, cardAppearance: Bool = false) {
        self.window = window; self.policy = policy; self.cardAppearance = cardAppearance
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
        if policy.allowed, fresh, let content = window.contentView {
            if cardAppearance { MotionEffects.cardAppear(content,duration:policy.profile.cardAppear) }
            else if !immediately || animateImmediateContent { MotionEffects.appear(content,duration:duration) }
        }
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
