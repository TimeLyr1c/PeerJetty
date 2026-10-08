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
        wait(MotionPolicy.shared.profile.success + 0.10)
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
        let samples = (0...100).map { MotionEffects.cardTransform(at:Double($0)/100) }
        check(samples[0].m11 == 0.86 && samples[0].m22 == 0.62,"card starts visibly compressed on unequal axes")
        check(samples[1].m22-samples[0].m22 < 0.01,"zero-velocity start provides initial buffering")
        check(samples.map(\.m22).max()! > 1.04 && samples.map(\.m22).max()! < 1.05,"bounded perceptible jelly overshoot")
        let peak = samples.indices.max { samples[$0].m22 < samples[$1].m22 }!
        check(peak >= 49 && peak <= 52 && samples[20].m22 < 0.9,"expansion uses the timeline instead of settling in its first few frames")
        check(CATransform3DIsIdentity(samples.last!) && abs(samples[99].m22-1) < 0.001,"shape settles before finite endpoint")
        let host=DropCardHost(card:DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76)))
        let frame=host.card.frame
        MotionEffects.cardAppear(host,duration:MotionProfile(.natural).cardAppear)
        let animation=host.layer?.animation(forKey:"PeerJetty.cardShape") as? CAKeyframeAnimation
        check(animation?.values?.count == 61 && animation?.duration == 0.62,"finite spring sampling and natural card duration")
        let transform=(animation!.values!.first as! NSValue).caTransform3DValue
        let anchor=host.layer!.anchorPoint, center=CGPoint(x:host.bounds.width*(0.5-anchor.x),y:host.bounds.height*(0.5-anchor.y))
        check(abs(center.x*transform.m11+transform.m41-center.x)<0.001 && abs(center.y*transform.m22+transform.m42-center.y)<0.001,"visual card center stays fixed with AppKit layer anchor")
        check(host.card.frame == frame && host.hitTest(NSPoint(x:4,y:4)) == nil,"visual deformation preserves physical card and transparent target boundary")
        check(host.layer?.opacity == 1 && CATransform3DIsIdentity(host.layer!.transform),"model appearance remains ready for input and motion cancellation")
        MotionEffects.clear(host); check(customAnimations(host) == 0,"disabling/hiding removes shape and reveal together")
        let points=TransferGlyph.checkPoints, left=points[0], corner=points[1], right=points[2]
        let a=CGPoint(x:left.x-corner.x,y:left.y-corner.y), b=CGPoint(x:right.x-corner.x,y:right.y-corner.y)
        let angle=acos((a.x*b.x+a.y*b.y)/(hypot(a.x,a.y)*hypot(b.x,b.y))) * 180 / .pi
        check(angle > 74 && angle < 78,"compact check has sharper comfortable elbow")
        for point in points { check(12-hypot((point.x-0.5)*30,(point.y-0.5)*30)-2.2 > 2.5,"stroked check keeps breathing room inside the ring") }
        check(TransferGlyph.shortStrokeFraction > 0.34 && TransferGlyph.shortStrokeFraction < 0.35,"two stroke timing uses actual segment-length boundary")
        print("PASS: buffered finite jelly curve, bounded unequal-axis overshoot, stationary hit area and inset sharp check geometry")
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
            let expected: [Double] = speed == .fast ? [0.22,0.10,0.32,1,0.16] : speed == .natural ? [0.34,0.18,0.65,1.8,0.24] : [0.48,0.24,0.95,2.8,0.32]
            check([profile.appear,profile.status,profile.success,profile.hold,profile.dismiss] == expected,"exact profile")
            check(profile.cardAppear == (speed == .fast ? 0.38 : speed == .natural ? 0.62 : 0.88),"slower card-specific speed profile")
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
            wait(profile.success + 0.10)
            check(completed == 1 && customAnimations(glyph) == 0,"sequence settles once at captured speed")
            glyph.reset(); glyph.succeed(id:UUID()) {completed += 100}; glyph.update(id:UUID(),completed:20,total:100)
            wait(MotionProfile(.fast).success+0.10)
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
