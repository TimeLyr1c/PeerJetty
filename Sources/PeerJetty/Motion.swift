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
    private let reduceTransparency: () -> Bool
    private let reduceMotion: () -> Bool
    private var observer: NSObjectProtocol?
    var allowed: Bool { enabled && !reduceMotion() }
    var trailsAllowed: Bool { allowed && !reduceTransparency() }
    init(reduceMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }, reduceTransparency: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }) {
        self.reduceMotion = reduceMotion; self.reduceTransparency = reduceTransparency
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
    var ringFlip: Double { success * 0.9 }
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

/// Shared physical units. Calibrate once per effect using the native settling estimate;
/// changing the time scale preserves mass, damping ratio and normalized launch speed.
struct SpringParameters {
    let frequency: Double
    static let ratio = 0.72
    init(frequency: Double) { self.frequency = frequency }
    init(duration: Double) {
        let unit = CASpringAnimation(keyPath:"transform.scale")
        unit.mass = 1; unit.stiffness = 1; unit.damping = 2 * Self.ratio
        unit.fromValue = 0; unit.toValue = 1
        unit.initialVelocity = Self.ratio
        frequency = unit.settlingDuration / max(0.01,duration)
    }
    func animation(keyPath: String, from: Double, to: Double = 1, velocity: Double? = nil) -> CASpringAnimation {
        let animation = CASpringAnimation(keyPath:keyPath)
        animation.mass = 1; animation.stiffness = frequency * frequency
        animation.damping = 2 * Self.ratio * frequency
        animation.fromValue = from; animation.toValue = to
        let delta = to-from
        animation.initialVelocity = abs(delta) > 1e-10 ? (velocity ?? (delta * Self.ratio * frequency))/delta : 0
        animation.duration = animation.settlingDuration
        animation.timingFunction = .init(name:.linear)
        return animation
    }
}

/// Analytic state is sampled only on interruption/testing, never every frame.
/// Rendering itself belongs to CASpringAnimation.
struct SpringMotion {
    let from: Double, target: Double, velocity: Double, parameters: SpringParameters, started: Double
    func sample(at time: Double) -> (value: Double, velocity: Double) {
        let t = max(0,time-started), w = parameters.frequency
        let decay = SpringParameters.ratio*w, oscillation = w*sqrt(1-SpringParameters.ratio*SpringParameters.ratio)
        let a = from-target, b = (velocity+decay*a)/oscillation
        let c = cos(oscillation*t), sn = sin(oscillation*t), envelope = exp(-decay*t)
        return (target+envelope*(a*c+b*sn), envelope*((-decay*a+oscillation*b)*c+(-decay*b-oscillation*a)*sn))
    }
}

struct CardSpringState {
    let x: SpringMotion, y: SpringMotion, duration: Double
    func sample(at time: Double) -> (x: Double, y: Double, vx: Double, vy: Double) {
        let a=x.sample(at:time), b=y.sample(at:time)
        return (a.value,b.value,a.velocity,b.velocity)
    }
}

/// A captured, finite completion timeline shared by production and native previews.
struct FileSuccessSequence {
    let fill: Double, flip: Double, draw: Double, settle: Double
    var checkStart: Double { fill + flip }
    var settleStart: Double { checkStart + draw }
    var duration: Double { settleStart + settle }
    init(profile: MotionProfile, progressDuration: Double) {
        fill = max(progressDuration, profile.success * 0.25)
        flip = profile.ringFlip
        draw = profile.success * 0.60
        settle = MotionEffects.spring(duration:profile.success * 0.15,from:0.985).duration
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
        SpringParameters(duration:duration).animation(keyPath:"transform.scale",from:from)
    }
    @discardableResult
    static func appear(_ view: NSView, duration: Double = appearDuration, previous: SpringMotion? = nil) -> SpringMotion {
        view.wantsLayer = true
        let now=CACurrentMediaTime(), parameters=SpringParameters(duration:duration)
        let current=previous?.sample(at:now), from=current?.value ?? 0.97
        let velocity=current?.velocity ?? ((1-from)*SpringParameters.ratio*parameters.frequency)
        add(parameters.animation(keyPath:"transform.scale",from:from,velocity:velocity),to:view.layer,key:"PeerJetty.appear",startTime:now)
        return SpringMotion(from:from,target:1,velocity:velocity,parameters:parameters,started:now)
    }
    @discardableResult
    static func cardAppear(_ view: NSView, duration: Double, previous: CardSpringState? = nil) -> CardSpringState {
        view.wantsLayer = true
        let epoch = CACurrentMediaTime(), parameters = SpringParameters(duration:duration)
        let current = previous?.sample(at:epoch)
        let presentation = view.layer?.presentation()
        let startX = previous == nil ? 0.92 : (presentation.map { Double($0.transform.m11) } ?? current!.x)
        let startY = previous == nil ? 0.82 : (presentation.map { Double($0.transform.m22) } ?? current!.y)
        let vx = current?.vx ?? ((1-startX)*SpringParameters.ratio*parameters.frequency)
        let vy = current?.vy ?? ((1-startY)*SpringParameters.ratio*parameters.frequency)
        let anchor = view.layer?.anchorPoint ?? CGPoint(x:0.5,y:0.5)
        let center = CGPoint(x:view.bounds.width*(0.5-anchor.x),y:view.bounds.height*(0.5-anchor.y))
        let shape = CAAnimationGroup(); shape.timingFunction = .init(name:.linear)
        let x=parameters.animation(keyPath:"transform.scale.x",from:startX,velocity:vx)
        let y=parameters.animation(keyPath:"transform.scale.y",from:startY,velocity:vy)
        // Compensate AppKit's layer anchor without changing physical bounds/position.
        let tx=parameters.animation(keyPath:"transform.translation.x",from:center.x*(1-startX),to:0,velocity:-center.x*vx)
        let ty=parameters.animation(keyPath:"transform.translation.y",from:center.y*(1-startY),to:0,velocity:-center.y*vy)
        shape.animations=[x,y,tx,ty]; shape.duration=max(x.duration,y.duration,tx.duration,ty.duration)
        add(shape,to:view.layer,key:"PeerJetty.cardShape",startTime:epoch)
        let opacity = CABasicAnimation(keyPath:"opacity")
        opacity.fromValue = previous == nil ? 0.35 : (presentation?.opacity ?? 1)
        opacity.toValue = 1; opacity.duration = duration*0.18
        opacity.timingFunction = .init(name:.easeInEaseOut)
        add(opacity,to:view.layer,key:"PeerJetty.cardReveal",startTime:epoch)
        return CardSpringState(x:SpringMotion(from:startX,target:1,velocity:vx,parameters:parameters,started:epoch),
                               y:SpringMotion(from:startY,target:1,velocity:vy,parameters:parameters,started:epoch),duration:shape.duration)
    }
    static func pulse(_ view: NSView, policy: MotionPolicy = .shared) {
        guard policy.allowed, view.window?.isVisible == true else { return }
        view.wantsLayer = true
        let now=CACurrentMediaTime(), layer=view.layer
        let old=layer?.animation(forKey:"PeerJetty.feedback") as? CASpringAnimation
        var start = old == nil ? 0.97 : (layer?.presentation()?.value(forKeyPath:"transform.scale") as? NSNumber)?.doubleValue ?? 1
        let parameters=SpringParameters(duration:policy.profile.success)
        var velocity: Double?
        if let old, let from=(old.fromValue as? NSNumber)?.doubleValue, let target=(old.toValue as? NSNumber)?.doubleValue {
            let prior=SpringMotion(from:from,target:target,velocity:old.initialVelocity*(target-from),
                                   parameters:SpringParameters(frequency:sqrt(old.stiffness/old.mass)),started:old.beginTime)
            let state=prior.sample(at:layer?.convertTime(now,from:nil) ?? now)
            start=state.value; velocity=state.velocity
        }
        add(parameters.animation(keyPath:"transform.scale",from:start,velocity:velocity),to:layer,key:"PeerJetty.feedback",startTime:now)
    }

    static func add(_ animation: CAAnimation, to layer: CALayer?, key: String, delay: Double = 0, startTime: Double? = nil) {
        guard let layer else { return }
        let epoch = startTime ?? CACurrentMediaTime()
        let token = layer.convertTime(epoch,from:nil) + delay
        animation.beginTime = token; layer.add(animation,forKey:key)
        DispatchQueue.main.asyncAfter(deadline:.now()+max(0,epoch+delay+animation.duration-CACurrentMediaTime())) { [weak layer] in
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
    private var cardState: CardSpringState?
    private var contentState: SpringMotion?
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
        // A repeated show must not restart an in-flight shape. A pending dismissal
        // instead resumes the captured physical state and cancels its old completion.
        if window.isVisible, completion == nil { order(); return }
        let reopening = completion != nil
        revision += 1; let token = revision; completion = nil
        if !cardAppearance, let content = window.contentView { MotionEffects.clear(content) }
        appearing = policy.allowed && !immediately
        if fresh { window.alphaValue = appearing ? 0 : 1 }
        order()
        let duration = policy.profile.appear
        if policy.allowed, fresh || reopening, let content = window.contentView {
            if cardAppearance { cardState = MotionEffects.cardAppear(content,duration:policy.profile.cardAppear,previous:reopening ? cardState : nil) }
            else if !immediately || animateImmediateContent { contentState = MotionEffects.appear(content,duration:duration,previous:reopening ? contentState : nil) }
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
    func snapAppearance() { if appearing { revision += 1; appearing = false; makeInteractive() } }
    func finishImmediately() {
        revision += 1; let token = revision; appearing = false
        let action = completion; completion = nil
        cardState = nil; contentState = nil
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
