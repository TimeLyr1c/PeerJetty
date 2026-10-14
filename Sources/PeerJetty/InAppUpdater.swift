import AppKit
import Sparkle
import PeerCore

/// Standard Sparkle UI, with an admission barrier before the installation reply.
final class TransferAwareUpdateDriver: SPUStandardUserDriver {
    var prepareInstall: ((@escaping (Bool) -> Void) -> Void)?
    private(set) var installationAuthorized=false
    override func showUpdaterError(_ error:Error,acknowledgement:@escaping()->Void) {
        let alert=NSAlert();alert.messageText=L10n.text("updates.failed_help");alert.informativeText=error.localizedDescription
        alert.addButton(withTitle:L10n.text("text.close_action"));alert.addButton(withTitle:L10n.text("updates.open_release"))
        if alert.runModal() == .alertSecondButtonReturn {NSWorkspace.shared.open(UpdateResponse.releasesPage)}
        acknowledgement()
    }
    override func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        installationAuthorized=false
        super.showReady(toInstallAndRelaunch: { [weak self] choice in
            guard choice == .install else {reply(.skip);return} // Do not silently install on a later normal quit.
            guard let prepare=self?.prepareInstall else {reply(.skip);return}
            prepare { [weak self] allowed in self?.installationAuthorized=allowed;reply(allowed ? .install : .skip)}
        })
    }
}

final class InAppUpdater: NSObject, SPUUpdaterDelegate {
    private let driver: TransferAwareUpdateDriver
    private var updater: SPUUpdater!
    private var started=false
    var onAborted:(()->Void)?
    var prepareInstall: ((@escaping (Bool) -> Void) -> Void)?
    init(bundle: Bundle = .main) {
        UserDefaults.standard.register(defaults:["AppleLanguages":LanguagePreferences().selection.preferences(systemLanguages:Locale.preferredLanguages)])
        driver=TransferAwareUpdateDriver(hostBundle:bundle,delegate:nil)
        super.init()
        updater=SPUUpdater(hostBundle:bundle,applicationBundle:bundle,userDriver:driver,delegate:self)
        driver.prepareInstall = { [weak self] done in self?.prepareInstall?(done) }
    }
    static func isInstalled(_ url:URL,home:URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        let path=url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasSuffix(".app") && (path.hasPrefix("/Applications/") || path.hasPrefix(home.appendingPathComponent("Applications").path+"/")) && !path.contains("/AppTranslocation/")
    }
    var preventsOrdinaryQuit: Bool { updater.sessionInProgress && !driver.installationAuthorized }
    func focus() {driver.showUpdateInFocus()}
    func check() {
        guard Self.isInstalled(Bundle.main.bundleURL) else {alert(L10n.text("updates.install_location"));return}
        do {if !started {try updater.start();started=true};if updater.canCheckForUpdates {updater.checkForUpdates()} else {driver.showUpdateInFocus()}}
        catch {alert(error.localizedDescription)}
    }
    private func alert(_ text:String) {
        let alert=NSAlert();alert.messageText=L10n.text("updates.title");alert.informativeText=text
        alert.addButton(withTitle:L10n.text("text.close"));alert.addButton(withTitle:L10n.text("updates.open_release"))
        if alert.runModal() == .alertSecondButtonReturn {NSWorkspace.shared.open(UpdateResponse.releasesPage)}
    }
    func updater(_ updater:SPUUpdater, didAbortWithError error:Error) {
        onAborted?()
        // User driver shows one native diagnostic with a manual-download route.
    }
}
