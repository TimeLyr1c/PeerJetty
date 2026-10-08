import AppKit
import Darwin
@testable import PeerCore

private func check(_ value: Bool, _ message: String) { precondition(value, message) }
private func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
private func customAnimations(_ view:NSView) -> Int {
    var visited = Set<ObjectIdentifier>()
    func count(_ layer:CALayer) -> Int {
        guard visited.insert(ObjectIdentifier(layer)).inserted else { return 0 }
        return (layer.animationKeys() ?? []).filter {$0.hasPrefix("PeerJetty.")}.count + (layer.sublayers ?? []).reduce(0) {$0 + count($1)}
    }
    return descendants(view).reduce(0) {$0 + ($1.layer.map(count) ?? 0)}
}
private func cpu() -> Double { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 }

@main struct MotionTests {
    static func main() throws {
        _ = NSApplication.shared
        let preview = Bundle.main.bundleIdentifier == "app.peerjetty.isolated-glass-preview"
        NSApp.setActivationPolicy(preview ? .regular : .prohibited)
        if CommandLine.arguments.contains("--benchmark") { benchmark(); return }
        #if !BASELINE
        if preview {
            let menu = NSMenu(), appItem = NSMenuItem(), appMenu = NSMenu()
            appMenu.addItem(withTitle: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
            showPreview(); NSApp.run()
        } else { try tests() }
        #endif
    }
    static func benchmark() {
        let view = DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76))
        let panel = NSPanel(contentRect:NSRect(x:100,y:250,width:320,height:76),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        #if !BASELINE || HOST_BASELINE
        panel.hasShadow = false; panel.contentView = DropCardHost(card:view); panel.setFrame(DropCardHost.windowFrame(panel.frame),display:false); panel.contentView?.layoutSubtreeIfNeeded()
        #else
        panel.contentView = view
        #endif
        panel.orderFrontRegardless(); wait(0.4)
        let idleStart = cpu(); wait(1); let idle = cpu()-idleStart
        let activeStart = cpu()
        let transfer = UUID()
        for index in 0..<30 {
            view.transfer(TransferUpdate(id:transfer,peerName:"MacBook Air",receiving:false,completed:Int64(index+1),total:30,status:"State \(index)",finished:index == 29,succeeded:index == 29)); wait(0.02)
        }
        wait(1.1); let active = cpu()-activeStart
        panel.orderOut(nil); wait(0.4)
        check(customAnimations(view) == 0,"no retained custom animations after settlement")
        let hiddenStart = cpu(); wait(1); let hidden = cpu()-hiddenStart
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        print(String(format:"idle CPU %.4fs/1s; 30 state changes CPU %.4fs; hidden CPU %.4fs/1s; peak resident %.1f MiB; retained custom animations 0", idle,active,hidden,Double(usage.ru_maxrss)/1048576))
    }
    #if !BASELINE
    static func tests() throws {
        try ringTests()
        cardShapeTests()
        progressRateTests()
        flipTests()
        let legacy = Data(#"{"name":"test","receivePath":"/tmp","peers":[],"onboardingComplete":true}"#.utf8)
        var configuration = try JSONDecoder().decode(Configuration.self,from:legacy)
        check(configuration.animationsEnabled,"legacy defaults to animations enabled")
        let location = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-motion-\(UUID())/config.json")
        defer { try? FileManager.default.removeItem(at:location.deletingLastPathComponent()) }
        let store = try ConfigurationStore(url:location,fallback:configuration); try store.update {$0.animationsEnabled=false}
        configuration = try ConfigurationStore(url:location,fallback:configuration).snapshot
        check(!configuration.animationsEnabled && configuration.name == "test" && configuration.peers.isEmpty,"preference persists without identity changes")
        var reduced = false; let policy = MotionPolicy(reduceMotion:{reduced})
        check(policy.allowed,"normal policy"); reduced=true; check(!policy.allowed && policy.enabled,"reduce motion overrides without changing choice"); reduced=false
        let panel = NSPanel(contentRect:NSRect(x:80,y:300,width:320,height:76),styleMask:[.borderless],backing:.buffered,defer:false)
        let view = DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76)); panel.contentView=DropCardHost(card:view); panel.setFrame(DropCardHost.windowFrame(panel.frame), display:false); panel.contentView?.layoutSubtreeIfNeeded(); panel.isOpaque=false; panel.hasShadow=false; panel.backgroundColor = .clear
        if #available(macOS 26.0, *) { check(view.usesNativeGlass,"native glass available") }
        let fallback = DropZoneView(frame:view.frame, forceLegacyMaterial:true)
        check(!fallback.usesNativeGlass && descendants(fallback).contains {$0 is NSVisualEffectView}, "macOS 15 material fallback")
        let host = panel.contentView as! DropCardHost
        check(view.frame.size == NSSize(width:320,height:76) && view.frame.origin == NSPoint(x:32,y:32), "shadow padding preserves card dimensions")
        check(host.hitTest(NSPoint(x:4,y:4)) == nil && host.hitTest(NSPoint(x:150,y:65)) != nil,"transparent border is not interactive")
        check(host.shadowLayer.shadowRadius == 16 && host.shadowLayer.shadowOffset == NSSize(width:0,height:-6) && host.shadowLayer.shadowPath != nil,"single static rounded shadow")
        host.appearance = NSAppearance(named:.aqua); host.viewDidChangeEffectiveAppearance()
        check(abs((host.shadowLayer.shadowOpacity) - 0.24) < 0.001,"light shadow opacity")
        host.appearance = NSAppearance(named:.darkAqua); host.viewDidChangeEffectiveAppearance()
        check(abs((host.shadowLayer.shadowOpacity) - 0.38) < 0.001,"dark shadow opacity")
        if CommandLine.arguments.contains("--static-checks") {
            print("PASS: native/fallback material, unchanged card geometry, noninteractive padding, static shadow radius/offset and light/dark opacity")
            return
        }
        let motion = WindowMotion(panel,policy:policy,cardAppearance:true); let frame=panel.frame
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        check(panel.alphaValue == 1 && panel.frame == frame && customAnimations(view) == 0,"drag target is immediate and stationary")
        wait(0.4) // Let AppKit attach the newly ordered layer tree before sampling feedback.
        MotionEffects.pulse(descendants(view).compactMap {$0 as? NSImageView}.first!,policy:policy); check(customAnimations(view)==1,"single bounded feedback animation")
        MotionEffects.pulse(descendants(view).compactMap {$0 as? NSImageView}.first!,policy:policy); check(customAnimations(view)==1,"feedback replaces rather than stacks")
        wait(MotionPolicy.shared.profile.success + 0.10); check(customAnimations(view)==0,"feedback settles and is removed")
        let transferID=UUID()
        view.transfer(TransferUpdate(id:transferID,peerName:"Test",receiving:false,completed:10,total:10,status:"Confirmed",finished:true,succeeded:true))
        check(view.progress.isSuccess && !view.progress.isHidden,"confirmed success uses vector check")
        wait(view.progress.successDuration + 0.10)
        view.transfer(TransferUpdate(id:transferID,peerName:"Test",receiving:false,completed:10,total:10,status:"Confirmed",finished:true,succeeded:true))
        check(customAnimations(view.progress) == 0,"duplicate success never restarts feedback")
        view.transfer(TransferUpdate(id:UUID(),peerName:"Test",receiving:false,completed:0,total:10,status:"Failed",finished:true,succeeded:false))
        check(!view.progress.isSuccess && view.progress.isHidden,"failure has no success feedback")
        var opacityAtRemoval:CGFloat = 1
        motion.dismiss { opacityAtRemoval=panel.alphaValue;panel.orderOut(nil) }
        wait(MotionPolicy.shared.profile.success + 0.10)
        check(opacityAtRemoval < 0.01 && !panel.isVisible && panel.alphaValue == 1, "dismiss hides before restoring opacity, without final-frame flash")
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        var closed=false
        motion.dismiss {closed=true;panel.orderOut(nil)}
        wait(0.04); motion.reveal {panel.orderFrontRegardless()}; wait(MotionPolicy.shared.profile.appear + 0.12)
        check(!closed && panel.isVisible && panel.frame == frame,"interrupted dismissal cannot hide a reopened window")
        motion.dismiss {closed=true;panel.orderOut(nil)}; policy.enabled=false
        check(closed && !panel.isVisible && customAnimations(view)==0,"switch disabled during dismissal settles immediately")
        motion.reveal {panel.orderFrontRegardless()}; check(panel.alphaValue == 1 && customAnimations(view)==0,"disabled appearance is immediate")
        panel.orderOut(nil); policy.enabled=true; reduced=true; policy.notify()
        motion.reveal {panel.orderFrontRegardless()}; check(panel.alphaValue==1 && customAnimations(view)==0,"reduced motion appearance is immediate")
        panel.orderOut(nil)
        print("PASS: configuration migration/persistence, live reduction override, fixed immediate drag target, bounded feedback, retargeted dismissal and toggle mid-animation")
        MotionPolicy.shared.enabled=false
        let composer=TextComposer(); composer.present(); check(composer.window?.firstResponder === composer.editor,"focus available immediately")
        composer.editor.string="中文🙂 draft"; composer.close(); wait(0.01); check(composer.editor.string=="中文🙂 draft","close preserves draft")
        MotionPolicy.shared.enabled=true
        composer.present(); composer.close(); wait(0.04); composer.present(); wait(MotionPolicy.shared.profile.appear + 0.12)
        check(composer.window?.isVisible == true && composer.window?.firstResponder === composer.editor && composer.editor.string == "中文🙂 draft", "animated close/reopen preserves focus and draft")
        MotionPolicy.shared.enabled=false; composer.close(); MotionPolicy.shared.enabled=true
    }
    static func cardShapeTests() {
        for speed in AnimationSpeed.allCases {
            let profile=MotionProfile(speed), parameters=SpringParameters(duration:profile.cardAppear,dampingRatio:SpringParameters.cardRatio)
            let start=CACurrentMediaTime()
            let y=SpringMotion(from:0.82,target:1,velocity:0.18*parameters.dampingRatio*parameters.frequency,parameters:parameters,started:start)
            let samples=(0...1000).map { y.sample(at:start+Double($0)*profile.cardAppear/1000) }
            check(abs(samples[0].value-0.82)<1e-9 && samples[0].velocity>0,"spring starts compressed with initial velocity")
            check(samples.map(\.value).max()! <= 1.035 && samples.map(\.value).max()! > 1.023,"physical rebound remains bounded")
            check(abs(samples.last!.value-1)<0.001 && abs(samples.last!.velocity)<0.02,"native-duration tail is already settled")
            let animation=parameters.animation(keyPath:"transform.scale.y",from:0.82)
            check(abs(animation.duration-profile.cardAppear)<0.01 && animation.duration == animation.settlingDuration,"native settling duration follows each speed without truncation")
            let time=start+profile.cardAppear*0.18, state=y.sample(at:time)
            let retarget=SpringMotion(from:state.value,target:1,velocity:state.velocity,parameters:parameters,started:time)
            check(abs(retarget.sample(at:time).velocity-state.velocity)<1e-8,"retarget preserves physical velocity")
            check(abs(retarget.sample(at:time+0.04).value-y.sample(at:time+0.04).value)<1e-8,"retarget continues same physical trajectory")
        }
        let host=DropCardHost(card:DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76)))
        let frame=host.card.frame
        let state=MotionEffects.cardAppear(host,duration:MotionProfile(.natural).cardAppear)
        let animation=host.layer?.animation(forKey:"PeerJetty.cardShape") as? CAAnimationGroup
        let springs=animation!.animations as! [CASpringAnimation]
        check(springs.count == 4 && springs.allSatisfy {$0.duration == $0.settlingDuration},"native axis/anchor springs run to settlement")
        let anchor=host.layer!.anchorPoint, center=CGPoint(x:host.bounds.width*(0.5-anchor.x),y:host.bounds.height*(0.5-anchor.y))
        check(abs(center.x*0.92+(springs[2].fromValue as! Double)-center.x)<0.001 && abs(center.y*0.82+(springs[3].fromValue as! Double)-center.y)<0.001,"visual center is preserved with AppKit anchor")
        check(state.duration == animation!.duration && host.card.frame == frame && host.hitTest(NSPoint(x:4,y:4)) == nil,"physical card and transparent target boundary stay fixed")
        check(host.layer?.opacity == 1 && CATransform3DIsIdentity(host.layer!.transform),"model stays ready for input and cancellation")
        let panel=NSPanel(contentRect:NSRect(x:100,y:150,width:384,height:140),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.contentView=host
        let policy=MotionPolicy(reduceMotion:{false}), motion=WindowMotion(panel,policy:policy,cardAppearance:true)
        MotionEffects.clear(host);motion.reveal(immediately:true) {panel.orderFrontRegardless()};wait(0.04)
        let native=host.layer!.presentation()!.transform
        check(native.m22 > 0.82 && native.m22 < 1.035,"native early spring frame remains bounded")
        check(abs(center.x*native.m11+native.m41-center.x)<0.01 && abs(center.y*native.m22+native.m42-center.y)<0.01,"native presentation center is stationary")
        let begin=host.layer!.animation(forKey:"PeerJetty.cardShape")!.beginTime
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        check(host.layer!.animation(forKey:"PeerJetty.cardShape")!.beginTime == begin,"repeated reveal does not restart spring")
        var hidden=false;motion.dismiss {hidden=true;panel.orderOut(nil)};wait(0.04)
        let before=host.layer!.presentation()!.transform
        motion.reveal(immediately:true) {panel.orderFrontRegardless()};wait(0.005)
        let after=host.layer!.presentation()!.transform
        check(abs(before.m22-after.m22)<0.04,"dismiss/reopen has no shape reset")
        wait(1.1);check(!hidden && panel.isVisible && customAnimations(host)==0,"old dismiss cannot hide reopened card; springs are finite")
        panel.orderOut(nil);motion.finishImmediately()
        MotionEffects.clear(host); check(customAnimations(host) == 0,"disabling/hiding removes shape and reveal together")
        let points=TransferGlyph.checkPoints, left=points[0], corner=points[1], right=points[2]
        let a=CGPoint(x:left.x-corner.x,y:left.y-corner.y), b=CGPoint(x:right.x-corner.x,y:right.y-corner.y)
        let angle=acos((a.x*b.x+a.y*b.y)/(hypot(a.x,a.y)*hypot(b.x,b.y))) * 180 / .pi
        check(angle > 74 && angle < 78,"compact check has sharper comfortable elbow")
        for point in points { check(12-hypot((point.x-0.5)*30,(point.y-0.5)*30)-2.2 > 2.5,"stroked check keeps breathing room inside the ring") }
        check(TransferGlyph.shortStrokeFraction > 0.34 && TransferGlyph.shortStrokeFraction < 0.35,"two stroke timing uses actual segment-length boundary")
        print("PASS: native physical springs, three settling durations, continuous retarget, bounded unequal-axis overshoot, stationary hit area and inset sharp check geometry")
    }
    static func progressRateTests() {
        for rate in [1.0,1.5,3.0] {
            for delta in [0.0001,0.001,0.01,0.1,0.5,1.0] {
                for velocity in [0,rate*0.25,rate*0.75,rate] {
                    let motion=ProgressMotion(from:0,target:delta,velocity:velocity,rate:rate,minimum:0.18,started:0)
                    var previous=0.0
                    for index in 0...200 {
                        let sample=motion.sample(at:motion.duration*Double(index)/200)
                        check(sample.value+1e-9 >= previous && sample.value <= delta+1e-9,"rate-limited trajectory never retreats or overshoots actual progress")
                        check(sample.velocity <= rate+1e-8,"derivative obeys maximum visual speed even for small updates")
                        previous=sample.value
                    }
                }
            }
            var motion=ProgressMotion(from:0,target:0.02,velocity:0,rate:rate,minimum:0.18,started:0)
            for index in 1...100 {
                let now=Double(index)*0.01, current=motion.sample(at:now), target=min(1,Double(index)/100)
                let next=ProgressMotion(from:current.value,target:target,velocity:current.velocity,rate:rate,minimum:0.18,started:now)
                check(abs(next.sample(at:now).value-current.value)<1e-9 && abs(next.sample(at:now).velocity-current.velocity)<1e-8,"bursty updates preserve visible position and velocity")
                motion=next
            }
            check(motion.sample(at:10).value == 1 && motion.sample(at:10).velocity == 0,"finite catch-up settles after updates stop")
        }
        let saved=MotionPolicy.shared.enabled
        MotionPolicy.shared.enabled = true
        let card=DropPanelController(), id=UUID()
        card.presentTransfer(TransferUpdate(id:id,peerName:"Instant",receiving:false,completed:0,total:100,status:"Sending",finished:false,succeeded:false))
        card.presentTransfer(TransferUpdate(id:id,peerName:"Instant",receiving:false,completed:100,total:100,status:"Done",finished:true,succeeded:true))
        let duration=card.view.progress.successDuration
        check(duration >= MotionPolicy.shared.profile.success,"instant success still respects the visual ring speed limit")
        card.hide(after:0)
        wait(MotionPolicy.shared.profile.success+0.05)
        if duration > MotionPolicy.shared.profile.success+0.1 { check(card.isVisible,"nominal deadline cannot hide an extended successful fill") }
        wait(max(0,duration-MotionPolicy.shared.profile.success)+0.05)
        check(card.feedbackRemaining > MotionPolicy.shared.profile.hold-0.3,"hold starts after extended fill and check finish")
        card.resetFeedback(); card.hide(); MotionPolicy.shared.enabled=saved
        print("PASS: visual rate cap, tiny/bursty updates, continuous position/velocity, finite catch-up and extended success hold")
    }
    static func flipTests() {
        for lag in [0.0,0.045,0.09,0.135] {
            var previous=0.0
            for index in 0...100 {
                let angle=TransferGlyph.flipAngle(at:Double(index)/100,lag:lag)
                check(angle >= previous && angle <= 4 * .pi,"two turns are finite and forward-only")
                previous=angle
            }
            check(abs(previous-4 * .pi)<1e-9,"ring and ghosts finish front-facing together")
        }
        let epsilon = 0.0001
        check(TransferGlyph.flipAngle(at:epsilon)/epsilon < 0.1, "flip starts continuously from rest")
        check((4 * .pi-TransferGlyph.flipAngle(at:1-epsilon))/epsilon < 0.1, "flip ends with no abrupt velocity cutoff")
        for speed in AnimationSpeed.allCases {
            let profile = MotionProfile(speed)
            let sequence = FileSuccessSequence(profile:profile,progressDuration:2)
            check(sequence.fill == 2 && sequence.checkStart == sequence.fill+sequence.flip && sequence.duration == sequence.settleStart+sequence.settle, "one captured timeline includes visual catch-up and all completion stages")
        }
        var reducedTransparency=false
        let policy=MotionPolicy(reduceMotion:{false},reduceTransparency:{reducedTransparency}); policy.speed = .fast
        let glyph=TransferGlyph(policy:policy); glyph.setFrameSize(NSSize(width:30,height:30)); glyph.layoutSubtreeIfNeeded()
        var finished=0; glyph.succeed(id:UUID()) { finished += 1 }
        let layers=glyph.layer!.sublayers!
        check(layers.first!.opacity == 0,"stationary track disappears so only the completed ring flips")
        let ghosts=layers.filter {$0.animation(forKey:"PeerJetty.trailFade") != nil}
        check(ghosts.count == 3 && ghosts.allSatisfy {$0.opacity == 0},"three bounded ghosts leave no visible model residue")
        let ring=layers.first {$0.animation(forKey:"PeerJetty.progress") != nil}!
        let rotation=ring.animation(forKey:"PeerJetty.ringFlip")!, color=ring.animation(forKey:"PeerJetty.successColor")!
        let tick=layers.first {$0.animation(forKey:"PeerJetty.check") != nil}!.animation(forKey:"PeerJetty.check")!
        let strokes = tick as! CABasicAnimation
        check((strokes.fromValue as! Double) == 0 && (strokes.toValue as! Double) == 1 && strokes.timingFunction != nil,"one continuous easing crosses the elbow without segment restart")

        check(abs(rotation.duration-policy.profile.ringFlip)<1e-9 && abs(color.beginTime-rotation.beginTime)<0.01,"blue-to-green transition runs during finite rotation")
        check(tick.beginTime >= rotation.beginTime+rotation.duration-0.01,"check cannot start before the ring stops")
        check(customAnimations(glyph) <= 14,"fixed small number of shape effects")
        reducedTransparency=true; policy.notify()
        check(ghosts.allSatisfy {($0.animationKeys() ?? []).isEmpty && $0.opacity == 0} && ring.animation(forKey:"PeerJetty.ringFlip") != nil,"reduce transparency removes ghosts without disrupting success")
        policy.enabled=false
        check(finished == 1 && customAnimations(glyph) == 0,"reduce motion/disable settles exactly once and clears every trail")
        policy.enabled=true; reducedTransparency=false
        glyph.reset(); glyph.succeed(id:UUID()) {finished += 100}; let oldDuration=glyph.successDuration
        glyph.update(id:UUID(),completed:20,total:100)
        wait(oldDuration+0.05)
        check(finished == 1 && !glyph.isSuccess && customAnimations(glyph)==0,"new progress cancels old flips, trails and success callback")
        print("PASS: two vertical-axis turns, three fading trails, color timing, check-after-stop, accessibility and cancellation cleanup")
    }
    static func ringTests() throws {
        let legacy = Data(#"{"name":"test","receivePath":"/tmp","peers":[],"onboardingComplete":true,"animationSpeed":"unknown-future-value"}"#.utf8)
        check(try JSONDecoder().decode(Configuration.self,from:legacy).animationSpeed == .natural,"unknown speed falls back")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-speed-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let fallback = Configuration(name:"Test",receivePath:"/tmp")
        let url = folder.appendingPathComponent("config.json"), blocked = folder.appendingPathComponent("blocked")
        try Data().write(to:blocked)
        let failing = try ConfigurationStore(url:blocked.appendingPathComponent("config.json"),fallback:fallback)
        do { try failing.update {$0.animationSpeed = .fast}; preconditionFailure("must reject write") } catch {}
        check(failing.snapshot.animationSpeed == .natural,"save failure keeps preference")
        for speed in AnimationSpeed.allCases {
            let store = try ConfigurationStore(url:url,fallback:fallback); try store.update {$0.animationSpeed=speed}
            check(try ConfigurationStore(url:url,fallback:fallback).snapshot.animationSpeed == speed,"speed persists")
            let profile = MotionProfile(speed)
            let expected: [Double] = speed == .fast ? [0.22,0.10,0.65,1,0.16] : speed == .natural ? [0.34,0.18,1.20,1.8,0.24] : [0.48,0.24,1.75,2.8,0.32]
            check([profile.appear,profile.status,profile.success,profile.hold,profile.dismiss] == expected,"exact profile")
            check(profile.cardAppear == (speed == .fast ? 0.52 : speed == .natural ? 0.86 : 1.22),"slower card-specific speed profile")
            let spring = MotionEffects.spring(duration:profile.appear,from:0.97)
            check(abs(spring.damping/(2*sqrt(spring.stiffness*spring.mass))-0.72) < 0.00001,"constant damping ratio across speeds")
            let policy = MotionPolicy(reduceMotion:{false}); policy.speed=speed
            let glyph = TransferGlyph(policy:policy); glyph.setFrameSize(NSSize(width:30,height:30)); glyph.layoutSubtreeIfNeeded()
            let id=UUID(); glyph.update(id:id,completed:55,total:100); glyph.update(id:id,completed:30,total:100)
            check(glyph.fraction == 0.55 && !glyph.isSuccess,"real progress cannot retreat")
            glyph.update(id:id,completed:150,total:100); check(glyph.fraction == 1 && !glyph.isSuccess,"full bytes does not imply success")
            var completed = 0; glyph.succeed(id:id) {completed += 1}; glyph.succeed(id:id) {completed += 100}
            check(completed == 0 && glyph.isSuccess,"success sequence is bounded and deduplicated")
            policy.speed = .fast // Snapshot of the in-flight sequence must remain unchanged.
            wait(glyph.successDuration + 0.10)
            check(completed == 1 && customAnimations(glyph) == 0,"sequence settles once at captured speed")
            glyph.reset(); glyph.succeed(id:UUID()) {completed += 100}; let oldDuration = glyph.successDuration; glyph.update(id:UUID(),completed:20,total:100)
            wait(oldDuration+0.10)
            check(completed == 1 && glyph.fraction == 0.2 && !glyph.isSuccess,"old completion cannot replace newer progress")
            glyph.reset(); glyph.succeed(id:UUID()) {completed += 1}; policy.enabled=false
            check(completed == 2 && glyph.isSuccess && customAnimations(glyph) == 0,"disable settles success immediately")
        }
        var reduced=false
        let policy = MotionPolicy(reduceMotion:{reduced}); policy.speed = .fast
        let glyph=TransferGlyph(policy:policy); var settled=false
        glyph.succeed(id:UUID()) {settled=true}; reduced=true; policy.notify()
        check(settled && policy.enabled && policy.speed == .fast && customAnimations(glyph)==0,"reduced motion overrides without changing preferences")
        let savedSpeed=MotionPolicy.shared.speed, savedEnabled=MotionPolicy.shared.enabled
        defer { MotionPolicy.shared.speed=savedSpeed; MotionPolicy.shared.enabled=savedEnabled }
        MotionPolicy.shared.speed = .fast; MotionPolicy.shared.enabled = false
        let panel=DropPanelController(); let first=UUID(), second=UUID(), third=UUID()
        panel.presentTransfer(TransferUpdate(id:first,peerName:"One",receiving:false,completed:10,total:10,status:"Done",finished:true,succeeded:true))
        check(panel.currentFeedbackID == first && panel.feedbackRemaining > 0.8,"hold starts after final check")
        panel.hide(after:0) // Polling/status callbacks cannot shorten the success hold.
        check(panel.feedbackRemaining > 0.8,"ordinary hide preserves hold")
        panel.presentTransfer(TransferUpdate(id:second,peerName:"Two",receiving:false,completed:20,total:100,status:"Sending",finished:false,succeeded:false))
        panel.presentTransfer(TransferUpdate(id:first,peerName:"One",receiving:false,completed:10,total:10,status:"Done",finished:true,succeeded:true))
        check(panel.currentFeedbackID == nil && panel.view.progress.fraction == 0.2,"new transfer preempts success and stale duplicates")
        panel.presentTransfer(TransferUpdate(id:third,peerName:"Three",receiving:true,completed:0,total:0,status:"Preparing",finished:false,succeeded:false))
        check(panel.view.progress.isHidden,"unknown total has no fake percentage")
        panel.presentTransfer(TransferUpdate(id:third,peerName:"Three",receiving:true,completed:0,total:0,status:"Done",finished:true,succeeded:true))
        check(!panel.view.progress.isHidden && !panel.view.progress.isSuccess && panel.view.progress.fraction == 0.2,"parallel active transfer retains progress")
        panel.presentTransfer(TransferUpdate(id:second,peerName:"Two",receiving:false,completed:100,total:100,status:"Sending",finished:false,succeeded:false))
        check(!panel.view.progress.isSuccess && descendants(panel.view).compactMap {$0 as? NSTextField}.first?.stringValue == L10n.text("drop.waiting_confirmation"),"awaiting receipt remains distinct")
        panel.presentTransfer(TransferUpdate(id:second,peerName:"Two",receiving:false,completed:100,total:100,status:"Failed",finished:true,succeeded:false))
        check(panel.view.progress.isHidden && !panel.view.progress.isSuccess,"failure cannot draw check")
        panel.resetFeedback()
        let preview = MotionPreviewWindow()
        let previewCard = descendants(preview.window!.contentView!).compactMap {$0 as? DropZoneView}.first!
        check(previewCard.registeredDraggedTypes.isEmpty,"isolated preview refuses actual file drops")
        print("PASS: three speed profiles, migration/write failure, spring damping, monotonic ring, confirmation, deduplication, interruption, reduced motion, success hold and parallel transfer")
    }
    private static var retained: [AnyObject] = []
    static func showPreview() {
        let controller = MotionPreviewWindow(); retained.append(controller); controller.present()
    }
    #endif
}
