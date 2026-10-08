import AppKit
import Darwin
@testable import PeerCore

private func check(_ value: Bool, _ message: String) { precondition(value, message) }
private func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap { descendants($0) } }
private func customAnimations(_ view: NSView) -> Int { descendants(view).reduce(0) { $0 + ($1.layer?.animationKeys() ?? []).filter {$0.hasPrefix("PeerJetty.")}.count } }
private func cpu() -> Double { var usage = rusage(); getrusage(RUSAGE_SELF, &usage); return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000 }

@main struct MotionTests {
    static func main() throws {
        _ = NSApplication.shared
        let preview = Bundle.main.bundleIdentifier == "app.peerjetty.isolated-glass-preview"
        NSApp.setActivationPolicy(preview ? .regular : .prohibited)
        if CommandLine.arguments.contains("--benchmark") { benchmark(); return }
        #if !BASELINE
        if preview { showPreview(); NSApp.run() } else { try tests() }
        #endif
    }
    static func benchmark() {
        let view = DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76))
        let panel = NSPanel(contentRect:NSRect(x:100,y:250,width:320,height:76),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.contentView = view; panel.orderFrontRegardless(); wait(0.4)
        let idleStart = cpu(); wait(1); let idle = cpu()-idleStart
        let activeStart = cpu()
        for index in 0..<30 { view.show(title:"State \(index)",subtitle:"MacBook Air",symbol:"arrow.up.doc"); wait(0.02) }
        wait(0.4); let active = cpu()-activeStart
        panel.orderOut(nil); wait(0.4)
        check(customAnimations(view) == 0,"no retained custom animations after settlement")
        let hiddenStart = cpu(); wait(1); let hidden = cpu()-hiddenStart
        var usage = rusage(); getrusage(RUSAGE_SELF,&usage)
        print(String(format:"idle CPU %.4fs/1s; 30 state changes CPU %.4fs; hidden CPU %.4fs/1s; peak resident %.1f MiB; retained custom animations 0", idle,active,hidden,Double(usage.ru_maxrss)/1048576))
    }
    #if !BASELINE
    static func tests() throws {
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
        let motion = WindowMotion(panel,policy:policy); let frame=panel.frame
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        check(panel.alphaValue == 1 && panel.frame == frame && customAnimations(view) == 0,"drag target is immediate and stationary")
        wait(0.4) // Let AppKit attach the newly ordered layer tree before sampling feedback.
        MotionEffects.pulse(descendants(view).compactMap {$0 as? NSImageView}.first!,policy:policy); check(customAnimations(view)==1,"single bounded feedback animation")
        MotionEffects.pulse(descendants(view).compactMap {$0 as? NSImageView}.first!,policy:policy); check(customAnimations(view)==1,"feedback replaces rather than stacks")
        wait(0.3); check(customAnimations(view)==0,"feedback settles and is removed")
        let icon=descendants(view).compactMap {$0 as? NSImageView}.first!
        let transferID=UUID()
        view.transfer(TransferUpdate(id:transferID,peerName:"Test",receiving:false,completed:10,total:10,status:"Confirmed",finished:true,succeeded:true))
        check((icon.layer?.animation(forKey:"PeerJetty.feedback") != nil) == MotionPolicy.shared.allowed,"confirmed file success respects system motion policy")
        let feedbackStarted = icon.layer?.animation(forKey:"PeerJetty.feedback")?.beginTime ?? 0
        wait(0.3)
        view.transfer(TransferUpdate(id:transferID,peerName:"Test",receiving:false,completed:10,total:10,status:"Confirmed",finished:true,succeeded:true))
        check((icon.layer?.animation(forKey:"PeerJetty.feedback")?.beginTime ?? feedbackStarted) == feedbackStarted,"duplicate success never restarts feedback")
        view.transfer(TransferUpdate(id:UUID(),peerName:"Test",receiving:false,completed:0,total:10,status:"Failed",finished:true,succeeded:false))
        check(icon.layer?.animation(forKey:"PeerJetty.feedback") == nil,"failure has no success feedback")
        var opacityAtRemoval:CGFloat = 1
        motion.dismiss { opacityAtRemoval=panel.alphaValue;panel.orderOut(nil) }
        wait(0.3)
        check(opacityAtRemoval < 0.01 && !panel.isVisible && panel.alphaValue == 1, "dismiss hides before restoring opacity, without final-frame flash")
        motion.reveal(immediately:true) {panel.orderFrontRegardless()}
        var closed=false
        motion.dismiss {closed=true;panel.orderOut(nil)}
        wait(0.04); motion.reveal {panel.orderFrontRegardless()}; wait(0.35)
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
        composer.present(); composer.close(); wait(0.04); composer.present(); wait(0.35)
        check(composer.window?.isVisible == true && composer.window?.firstResponder === composer.editor && composer.editor.string == "中文🙂 draft", "animated close/reopen preserves focus and draft")
        MotionPolicy.shared.enabled=false; composer.close(); MotionPolicy.shared.enabled=true
    }
    private static var retained: [AnyObject] = []
    static func showPreview() {
        let controller = PreviewController(); retained.append(controller); controller.present()
    }
    #endif
}

#if !BASELINE
/// Isolated, manually replayable native renderer: no engine, Keychain, file history or clipboard access.
private final class PreviewController: NSObject, NSWindowDelegate {
    private let window = NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:380),styleMask:[.titled,.closable],backing:.buffered,defer:false)
    private let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:320,height:76),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
    private let card = DropZoneView(frame:NSRect(x:0,y:0,width:320,height:76))
    private var motion: WindowMotion!
    private var replay = 0
    private let enabled = NSButton(checkboxWithTitle:"Animations / 动画",target:nil,action:nil)
    override init() {
        super.init(); window.delegate=self; window.title="PeerJetty · Isolated Glass & Motion Preview"; window.isReleasedWhenClosed=false; window.center()
        panel.isOpaque=false; panel.hasShadow=false; panel.backgroundColor = .clear; panel.level = .floating; panel.hasShadow=false; panel.contentView=DropCardHost(card:card)
        motion=WindowMotion(panel)
        let stack=NSStackView(); stack.orientation = .vertical; stack.spacing=14; stack.translatesAutoresizingMaskIntoConstraints=false
        let info=NSTextField(wrappingLabelWithString:"Native glass on this Mac. Drag targets stay fixed.\n原生玻璃预览；不连接设备、不读取日常数据。\nChange system glass/accessibility settings to compare live behavior.")
        stack.addArrangedSubview(info)
        enabled.state = .on; enabled.target=self; enabled.action=#selector(toggle); stack.addArrangedSubview(enabled)
        for (title,action) in [("Replay / 回放",#selector(play)),("Immediate drag target / 立即投放",#selector(drag)),("Text input / 文本输入",#selector(text)),("Light / 浅色",#selector(light)),("Dark / 深色",#selector(dark)),("Quit preview / 退出预览",#selector(quit))] {
            let button=NSButton(title:title,target:self,action:action); button.bezelStyle = .rounded; stack.addArrangedSubview(button)
        }
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:20)])
        card.targetName="MacBook Air · 中文🙂";card.idle()
    }
    func present() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true);position();play() }
    private func position() { panel.setFrame(DropCardHost.windowFrame(NSRect(x:window.frame.midX-160,y:window.frame.maxY+12,width:320,height:76)), display:true); panel.contentView?.layoutSubtreeIfNeeded() }
    func windowWillClose(_ notification: Notification) { quit() }
    @objc private func quit() { replay+=1; motion.finishImmediately();panel.orderOut(nil);NSApp.terminate(nil) }
    @objc private func toggle() { MotionPolicy.shared.enabled=enabled.state == .on }
    @objc private func light() { panel.appearance=NSAppearance(named:.aqua) }
    @objc private func dark() { panel.appearance=NSAppearance(named:.darkAqua) }
    @objc private func drag() { replay+=1;position();card.idle();motion.reveal(immediately:true){panel.orderFrontRegardless()} }
    @objc private func text() { let composer=TextComposer(); MotionTests.keep(composer); composer.present() }
    @objc private func play() {
        replay+=1;let token=replay;let transferID=UUID();position();card.idle();motion.reveal {panel.orderFrontRegardless()}
        for (delay,title,symbol) in [(0.5,"Release to send / 松开以发送","plus.circle.fill"),(1.0,"Sending… / 正在发送…","arrow.up.arrow.down.circle.fill"),(1.8,"Saved / 已保存","checkmark.circle.fill"),(2.8,"Failure example / 失败示例","exclamationmark.triangle.fill")] {
            DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
                guard let self,self.replay==token else{return}
                if symbol == "arrow.up.arrow.down.circle.fill" || symbol == "checkmark.circle.fill" {
                    let finished = symbol == "checkmark.circle.fill"
                    self.card.transfer(TransferUpdate(id:transferID,peerName:self.card.targetName,receiving:false,completed:finished ? 100 : 45,total:100,status:title,finished:finished,succeeded:finished))
                } else {
                    self.card.show(title:title,subtitle:self.card.targetName,symbol:symbol,color:.labelColor)
                    if symbol=="plus.circle.fill",let icon=descendants(self.card).compactMap({$0 as? NSImageView}).first {MotionEffects.pulse(icon)}
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+4) { [weak self] in guard let self,self.replay==token else{return};self.motion.dismiss { [weak self] in self?.panel.orderOut(nil) } }
    }
}
extension MotionTests { static func keep(_ value: AnyObject) { retained.append(value) } }
#endif
