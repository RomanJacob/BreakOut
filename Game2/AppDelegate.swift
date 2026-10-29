import Cocoa
import SpriteKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        
        let windowSize = NSSize(width: 900, height: 700)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Roman's Breakout"
        window.backgroundColor = .black
        window.minSize = NSSize(width: 800, height: 600)
        window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
        window.isReleasedWhenClosed = false
        
        let skView = SKView(frame: window.contentView!.bounds)
        skView.autoresizingMask = [.width, .height]
        skView.wantsLayer = true
        
        let scene = GameScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        
        skView.presentScene(scene)
        window.contentView = skView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func setupMenu() {
        let mainMenu = NSMenu()
        
        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "About Roman's Breakout", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        appMenu.addItem(aboutItem)
        appMenu.addItem(NSMenuItem.separator())
        let quitItem = NSMenuItem(title: "Quit Roman's Breakout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // Game menu
        let gameMenuItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        let changeLevelItem = NSMenuItem(title: "Change Level...", action: #selector(changeLevel), keyEquivalent: "l")
        changeLevelItem.target = self
        gameMenu.addItem(changeLevelItem)
        let restartItem = NSMenuItem(title: "Restart Level", action: #selector(restartLevel), keyEquivalent: "r")
        restartItem.target = self
        gameMenu.addItem(restartItem)
        gameMenu.addItem(NSMenuItem.separator())
        let resetAllItem = NSMenuItem(title: "Reset All Progress", action: #selector(resetAll), keyEquivalent: "R")
        resetAllItem.target = self
        gameMenu.addItem(resetAllItem)
        gameMenuItem.submenu = gameMenu
        mainMenu.addItem(gameMenuItem)
        
        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        let helpItem = NSMenuItem(title: "Roman's Breakout Help", action: #selector(showHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
    }
    
    func getGameScene() -> GameScene? {
        guard let skView = window.contentView as? SKView else { return nil }
        return skView.scene as? GameScene
    }
    
    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Roman's Breakout",
            .applicationVersion: "Version \(version) (\(build))",
            .credits: NSAttributedString(string: "Created by Roman Dogonowski October 2026 & Meta AI\n\nVersion \(version)"),
            .applicationIcon: NSApp.applicationIconImage as Any
        ])
    }
    
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Roman's Breakout"
        alert.informativeText = """
        How to Play:
        • Space = Start / Pause
        • Mouse = Move paddle
        • Ball must hit paddle before it can break a brick
        • Click Level to change level (1-99)
        
        Levels:
        Level 1 = 1 row, Level 2 = 2 rows, etc.
        After 7 rows, extra rows appear as NEXT WAVE.
        
        Buttons:
        RESET ALL = Reset score, high score and level
        """
        alert.runModal()
    }
    
    @objc func changeLevel() { getGameScene()?.promptForLevel() }
    @objc func restartLevel() { getGameScene()?.restartGame() }
    @objc func resetAll() { getGameScene()?.confirmResetAll() }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { return true }
}
