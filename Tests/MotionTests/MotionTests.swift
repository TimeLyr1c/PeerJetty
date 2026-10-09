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
        for profile in [MotionProfile()] {
            let parameters=SpringParameters(duration:profile.cardAppear,dampingRatio:SpringParameters.cardRatio)
            let start=CACurrentMediaTime()
            let y=SpringMotion(from:0.82,target:1,velocity:0.18*parameters.dampingRatio*parameters.frequency,parameters:parameters,started:start)
            let samples=(0...1000).map { y.sample(at:start+Double($0)*profile.cardAppear/1000) }
            check(abs(samples[0].value-0.82)<1e-9 && samples[0].velocity>0,"spring starts compressed with initial velocity")
            let stages=CardSpringState(duration:profile.cardAppear,started:start)
            let peak=stages.switched, before=stages.y.sample(at:peak), after=stages.returnY.sample(at:peak)
            check(abs(before.value-after.value)<1e-8 && abs(before.velocity-after.velocity)<1e-8,"peak joins with continuous position and zero velocity")
            let offset=0.10/parameters.frequency
            check(abs(stages.returnY.sample(at:peak+offset).velocity)>abs(y.sample(at:peak+offset).velocity),"stronger return accelerates faster without changing outbound")
            for i in 0...1000 { let t=start+Double(i)*stages.duration/1000; check(stages.sample(at:t).y<=1.055,"two-stage rebound stays bounded") }
            let returning=(0...1000).map { stages.sample(at:peak+Double($0)*(stages.ends-peak)/1000).y }
            check(returning.min()! > 0.995,"stronger return damping avoids a visible secondary bounce")
            let resumed=stages.animations(at:peak+0.01,center:.zero) as! [CASpringAnimation]
            check(resumed.count==4 && abs(resumed[1].stiffness-stages.returnY.parameters.frequency*stages.returnY.parameters.frequency)<1e-8,"reopening during return does not multiply gain again")
            check(samples.map(\.value).max()! <= 1.055 && samples.map(\.value).max()! > 1.049,"physical rebound remains bounded")
            check(abs(samples.last!.value-1)<0.001 && abs(samples.last!.velocity)<0.02,"native-duration tail is already settled")
            let animation=parameters.animation(keyPath:"transform.scale.y",from:0.82)
            check(abs(animation.duration-profile.cardAppear)<0.01 && animation.duration == animation.settlingDuration,"native settling duration follows fixed timing without truncation")
            let time=start+profile.cardAppear*0.18, state=y.sample(at:time)
            let retarget=SpringMotion(from:state.value,target:1,velocity:state.velocity,parameters:parameters,started:time)
            check(abs(retarget.sample(at:time).velocity-state.velocity)<1e-8,"retarget preserves physical velocity")
            check(abs(retarget.sample(at:time+0.04).value-y.sample(at:time+0.04).value)<1e-8,"retarget continues same physical trajectory")
        }
        let host=DropCardHost(card:DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76)))
        let frame=host.card.frame
        let state=MotionEffects.cardAppear(host,duration:MotionProfile().cardAppear)
        let animation=host.layer?.animation(forKey:"PeerJetty.cardShape") as? CAAnimationGroup
        let springs=animation!.animations as! [CASpringAnimation]
        check(springs.count == 8 && abs(springs[4].stiffness/springs[0].stiffness-3.0625)<1e-8,"two finite spring stages strengthen return once")
        check(abs(springs[4].duration-springs[4].settlingDuration)<0.001,"return runs to native settlement")
        let anchor=host.layer!.anchorPoint, center=CGPoint(x:host.bounds.width*(0.5-anchor.x),y:host.bounds.height*(0.5-anchor.y))
        check(abs(center.x*0.92+(springs[2].fromValue as! Double)-center.x)<0.001 && abs(center.y*0.82+(springs[3].fromValue as! Double)-center.y)<0.001,"visual center is preserved with AppKit anchor")
        check(abs(state.duration-animation!.duration)<1e-8 && host.card.frame == frame && host.hitTest(NSPoint(x:4,y:4)) == nil,"physical card and transparent target boundary stay fixed")
        check(host.layer?.opacity == 1 && CATransform3DIsIdentity(host.layer!.transform),"model stays ready for input and cancellation")
        let panel=NSPanel(contentRect:NSRect(x:100,y:150,width:384,height:140),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.contentView=host
        let policy=MotionPolicy(reduceMotion:{false}), motion=WindowMotion(panel,policy:policy,cardAppearance:true)
        MotionEffects.clear(host);motion.reveal(immediately:true) {panel.orderFrontRegardless()};wait(0.04)
        let native=host.layer!.presentation()!.transform
        check(native.m22 > 0.82 && native.m22 < 1.055,"native early spring frame remains bounded")
        check(abs(center.x*native.m11+native.m41-center.x)<0.01 && abs(center.y*native.m22+native.m42-center.y)<0.01,"native presentation center is stationary")
        let begin=host.layer!.animation(forKey:"PeerJetty.cardShape")!.beginTime
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        check(host.layer!.animation(forKey:"PeerJetty.cardShape")!.beginTime == begin,"repeated reveal does not restart spring")
        let transition=CardSpringState(duration:policy.profile.cardAppear,started:begin).switched
        wait(max(0,transition-CACurrentMediaTime()-0.005))
        let beforePeak=host.layer!.presentation()!.transform.m22
        wait(0.015)
        let afterPeak=host.layer!.presentation()!.transform.m22
        check(beforePeak>1.01 && afterPeak>1.01 && abs(beforePeak-afterPeak)<0.015,"native stage join retains overshoot without snapping to identity")
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
        check(angle > 72 && angle < 75,"compact check has sharper comfortable elbow")
        for point in points { check(12-hypot(point.x*12,point.y*12)-2.10 > 2.5,"stroked check keeps breathing room inside the ring") }
        check(TransferGlyph.shortStrokeFraction > 0.33 && TransferGlyph.shortStrokeFraction < 0.34,"two stroke timing uses actual segment-length boundary")
        let referenceGaps=[0.623396,0.605876,0.478658]
        let referenceGlyph=TransferGlyph(policy:MotionPolicy(reduceMotion:{false}))
        for size in [NSSize(width:30,height:30),NSSize(width:60,height:30),NSSize(width:60,height:60)] {
            referenceGlyph.setFrameSize(size); referenceGlyph.layoutSubtreeIfNeeded()
            let radius=min(size.width,size.height)/2-3
            let tick=referenceGlyph.layer!.sublayers!.last! as! CAShapeLayer
            var actual:[CGPoint]=[]
            tick.path!.applyWithBlock { element in
                if element.pointee.type == .moveToPoint || element.pointee.type == .addLineToPoint { actual.append(element.pointee.points[0]) }
            }
            check(actual.count==3 && abs(tick.lineWidth/radius-0.175)<1e-9,"reference check scales with circular stroke width")
            for (index,point) in actual.enumerated() {
                let gap=1-hypot(point.x-size.width/2,point.y-size.height/2)/radius
                check(abs(gap-referenceGaps[index])<0.00001,"reference endpoint spacing survives resizing and rectangular bounds")
            }
        }
        print("PASS: native physical springs, fixed settling duration, continuous retarget, bounded unequal-axis overshoot, stationary hit area and inset sharp check geometry")
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
        check(abs(TransferGlyph.flipRadians-3 * .pi)<1e-9,"success rotates one and a half turns")
        for lag in [0.0,0.045,0.09,0.135] {
            var previous=0.0
            for index in 0...100 {
                let angle=TransferGlyph.flipAngle(at:Double(index)/100,lag:lag)
                check(angle >= previous && angle <= TransferGlyph.flipRadians,"one and a half turns is finite and forward-only")
                previous=angle
            }
            check(abs(previous-TransferGlyph.flipRadians)<1e-9,"ring and ghosts finish front-facing together")
        }
        let epsilon = 0.0001
        func speed(_ t:Double) -> Double { (TransferGlyph.flipAngle(at:t+epsilon)-TransferGlyph.flipAngle(at:t-epsilon))/(2*epsilon) }
        check(speed(0.5)/TransferGlyph.flipRadians>2.4 && speed(0.1)/TransferGlyph.flipRadians<0.05,"steeper middle speed peak with gentler ends")
        check(speed(0.5)>speed(0.25) && speed(0.25)>speed(0.1),"rotation accelerates toward middle")
        check(abs(speed(0.25)-speed(0.75))<1e-5 && speed(0.75)>speed(0.9),"rotation slows symmetrically after middle")
        check(TransferGlyph.flipAngle(at:epsilon)/epsilon < 0.1, "flip starts continuously from rest")
        check((TransferGlyph.flipRadians-TransferGlyph.flipAngle(at:1-epsilon))/epsilon < 0.1, "flip ends with no abrupt velocity cutoff")
        for profile in [MotionProfile()] {
            let sequence = FileSuccessSequence(profile:profile,progressDuration:2)
            check(sequence.fill == 2 && sequence.checkStart == sequence.fill+sequence.flip+sequence.pause-sequence.overlap && sequence.duration == sequence.settleStart+sequence.settle, "one captured timeline includes visual catch-up and all completion stages")
        }
        let fixed=MotionProfile()
        check(TransferGlyph.flipAngle(at:0.1/fixed.ringFlip)<TransferGlyph.flipAngle(at:0.1/0.62),"rotation starts gentler than the previous 620ms candidate")
        check(TransferGlyph.flipRadians-TransferGlyph.flipAngle(at:1-0.1/fixed.ringFlip)<TransferGlyph.flipRadians-TransferGlyph.flipAngle(at:1-0.1/0.62),"rotation settles gentler than the previous candidate")
        let primary=TransferGlyph.ringTransform(at:0.35,companion:false)
        let secondary=TransferGlyph.ringTransform(at:0.35,companion:true)
        check(abs(primary.m12-secondary.m12)>0.05 && abs(primary.m23-secondary.m23)>0.05,"two rings spin and flip on distinct tilted planes")
        check(TransferGlyph.ringTransform(at:0,companion:false).m11 == 1,"ring begins without a transform jump")
        var reducedTransparency=false
        let policy=MotionPolicy(reduceMotion:{false},reduceTransparency:{reducedTransparency})
        let glyph=TransferGlyph(policy:policy); glyph.setFrameSize(NSSize(width:30,height:30)); glyph.layoutSubtreeIfNeeded()
        let nativePanel=NSPanel(contentRect:NSRect(x:100,y:100,width:30,height:30),styleMask:[.borderless],backing:.buffered,defer:false)
        nativePanel.contentView=glyph;nativePanel.orderFrontRegardless();wait(0.02)
        defer {nativePanel.orderOut(nil)}
        var finished=0; glyph.succeed(id:UUID()) { finished += 1 }
        let layers=glyph.layer!.sublayers!
        check(layers.first!.opacity == 0,"stationary track disappears so only the completed ring flips")
        let ghosts=layers.filter {$0.animation(forKey:"PeerJetty.trailFade") != nil}
        check(ghosts.count == 1 && ghosts.allSatisfy {$0.opacity == 0},"exactly two rings with one finite companion")
        let ring=layers.first {$0.animation(forKey:"PeerJetty.progress") != nil}!
        let rotation=ring.animation(forKey:"PeerJetty.ringFlip")!, color=ring.animation(forKey:"PeerJetty.successColor")!
        let tick=layers.first {$0.animation(forKey:"PeerJetty.check") != nil}!.animation(forKey:"PeerJetty.check")!
        let strokes = tick as! CABasicAnimation
        check((strokes.fromValue as! Double) == 0 && (strokes.toValue as! Double) == 1 && strokes.timingFunction != nil,"one continuous easing crosses the elbow without segment restart")

        check(abs(rotation.duration-policy.profile.ringFlip)<1e-9 && abs(color.beginTime+color.duration-rotation.beginTime)<0.01,"blue-to-green transition completes before the two green rings rotate")
        check(abs(tick.beginTime-rotation.beginTime-rotation.duration-policy.profile.checkPause+0.17)<0.01,"check starts 170ms before rotation ends")
        reducedTransparency=true; policy.notify()
        check(ghosts.allSatisfy {($0.animationKeys() ?? []).isEmpty && $0.opacity == 0} && ring.animation(forKey:"PeerJetty.ringFlip") != nil,"reduce transparency removes ghosts without disrupting success")
        wait(max(0,rotation.beginTime+rotation.duration-0.05-CACurrentMediaTime()))
        let overlapStroke=(layers.first {$0.animation(forKey:"PeerJetty.check") != nil}!.presentation()! as! CAShapeLayer).strokeEnd
        check(overlapStroke>0 && ring.animation(forKey:"PeerJetty.ringFlip") != nil,"native check is already drawing during the final deceleration")
        wait(max(0,rotation.beginTime+rotation.duration+0.04-CACurrentMediaTime()))
        check(abs(ring.presentation()!.transform.m11-1)<0.01 && (layers.first {$0.animation(forKey:"PeerJetty.check") != nil}!.presentation()! as! CAShapeLayer).strokeEnd>0,"after rotation the ring is front-facing and the check is already drawing")
        check(ghosts.allSatisfy {($0.presentation()?.opacity ?? 0)<0.01},"companion is gone once rotation has ended")
        let green=NSColor(cgColor:(ring.presentation()! as! CAShapeLayer).strokeColor!)!.usingColorSpace(.deviceRGB)!
        let expectedGreen=NSColor(cgColor:(ring as! CAShapeLayer).strokeColor!)!.usingColorSpace(.deviceRGB)!
        check(abs(green.redComponent-expectedGreen.redComponent)<0.01 && abs(green.greenComponent-expectedGreen.greenComponent)<0.01 && abs(green.blueComponent-expectedGreen.blueComponent)<0.01,"check draws inside the final green ring")
        check(customAnimations(glyph) <= 14,"fixed small number of shape effects")
        policy.enabled=false
        check(finished == 1 && customAnimations(glyph) == 0,"reduce motion/disable settles one and a half turns and clears every trail")
        policy.enabled=true; reducedTransparency=false
        glyph.reset(); glyph.succeed(id:UUID()) {finished += 100}; let oldDuration=glyph.successDuration
        glyph.update(id:UUID(),completed:20,total:100)
        wait(oldDuration+0.05)
        check(finished == 1 && !glyph.isSuccess && customAnimations(glyph)==0,"new progress cancels old flips, trails and success callback")
        print("PASS: one and a half vertical-axis turns, two angled green rings, color timing, check-after-stop, accessibility and cancellation cleanup")
    }
    static func ringTests() throws {
        let legacy = Data(#"{"name":"test","receivePath":"/tmp","peers":[],"onboardingComplete":true,"animationSpeed":"unknown-future-value"}"#.utf8)
        check(try JSONDecoder().decode(Configuration.self,from:legacy).animationsEnabled,"obsolete speed field ignored")
        for value in ["fast", "natural", "relaxed", "future"] {
            let data=Data(String(data:legacy,encoding:.utf8)!.replacingOccurrences(of:"unknown-future-value",with:value).utf8)
            let decoded=try JSONDecoder().decode(Configuration.self,from:data)
            let encoded=String(data:try JSONEncoder().encode(decoded),encoding:.utf8)!
            check(!encoded.contains("animationSpeed"),"legacy speed does not persist or affect fixed profile")
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("PeerJetty-speed-\(UUID())")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let fallback = Configuration(name:"Test",receivePath:"/tmp")
        let blocked = folder.appendingPathComponent("blocked")
        try Data().write(to:blocked)
        let failing = try ConfigurationStore(url:blocked.appendingPathComponent("config.json"),fallback:fallback)
        do { try failing.update {$0.animationsEnabled = false}; preconditionFailure("must reject write") } catch {}
        check(failing.snapshot.animationsEnabled,"save failure keeps preference")
        for profile in [MotionProfile()] {
            let expected: [Double] = [0.34,0.18,1.20,1.8,0.24]
            check([profile.appear,profile.status,profile.success,profile.hold,profile.dismiss] == expected,"exact profile")
            check(profile.cardAppear == 1.22 && profile.ringFlip == 0.72 && profile.checkPause == 0,"fixed relaxed reveal and natural completion timing")
            let spring = MotionEffects.spring(duration:profile.appear,from:0.97)
            check(abs(spring.damping/(2*sqrt(spring.stiffness*spring.mass))-0.72) < 0.00001,"native feedback damping ratio")
            let policy = MotionPolicy(reduceMotion:{false})
            let glyph = TransferGlyph(policy:policy); glyph.setFrameSize(NSSize(width:30,height:30)); glyph.layoutSubtreeIfNeeded()
            let id=UUID(); glyph.update(id:id,completed:55,total:100); glyph.update(id:id,completed:30,total:100)
            check(glyph.fraction == 0.55 && !glyph.isSuccess,"real progress cannot retreat")
            glyph.update(id:id,completed:150,total:100); check(glyph.fraction == 1 && !glyph.isSuccess,"full bytes does not imply success")
            var completed = 0; glyph.succeed(id:id) {completed += 1}; glyph.succeed(id:id) {completed += 100}
            check(completed == 0 && glyph.isSuccess,"success sequence is bounded and deduplicated")
            wait(glyph.successDuration + 0.10)
            check(completed == 1 && customAnimations(glyph) == 0,"sequence settles once at captured speed")
            glyph.reset(); glyph.succeed(id:UUID()) {completed += 100}; let oldDuration = glyph.successDuration; glyph.update(id:UUID(),completed:20,total:100)
            wait(oldDuration+0.10)
            check(completed == 1 && glyph.fraction == 0.2 && !glyph.isSuccess,"old completion cannot replace newer progress")
            glyph.reset(); glyph.succeed(id:UUID()) {completed += 1}; policy.enabled=false
            check(completed == 2 && glyph.isSuccess && customAnimations(glyph) == 0,"disable settles success immediately")
        }
        var reduced=false
        let policy = MotionPolicy(reduceMotion:{reduced})
        let glyph=TransferGlyph(policy:policy); var settled=false
        glyph.succeed(id:UUID()) {settled=true}; reduced=true; policy.notify()
        check(settled && policy.enabled && customAnimations(glyph)==0,"reduced motion overrides without changing preferences")
        let savedEnabled=MotionPolicy.shared.enabled
        defer { MotionPolicy.shared.enabled=savedEnabled }
        MotionPolicy.shared.enabled = false
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
        print("PASS: fixed motion profile, migration/write failure, spring damping, monotonic ring, confirmation, deduplication, interruption, reduced motion, success hold and parallel transfer")
    }
    private static var retained: [AnyObject] = []
    static func showPreview() {
        let controller = MotionPreviewWindow(); retained.append(controller); controller.present()
    }
    #endif
}
