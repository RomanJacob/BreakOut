import Cocoa
import SpriteKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    
    nonisolated override init() { super.init() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 900, height: 700)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "Roman's Breakout"
        win.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.19, alpha: 1.0)
        win.minSize = NSSize(width: 800, height: 600)
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.fullScreenPrimary]
        
        let skView = SKView(frame: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        skView.autoresizingMask = [.width, .height]
        
        let scene = GameScene(size: size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
        
        win.contentView = skView
        win.makeKeyAndOrderFront(nil)
        win.makeMain()
        win.orderFrontRegardless()
        self.window = win
        
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.window.makeKeyAndOrderFront(nil)
            // Skjul trafiklys EFTER vinduet er vist - ellers blinker det væk i Xcode 26
            self.window.standardWindowButton(.closeButton)?.isHidden = true
            self.window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            self.window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: - Menu
    func setupMenu() {
        let mainMenu = NSMenu()
        
        // 1. App Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About Roman's Breakout", action: #selector(showAbout), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Roman's Breakout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        
        // 2. Game Menu
        let gameMenuItem = NSMenuItem()
        let gameMenu = NSMenu(title: "Game")
        gameMenu.addItem(NSMenuItem(title: "Change Level...", action: #selector(changeLevel), keyEquivalent: "l"))
        gameMenu.addItem(NSMenuItem(title: "Change Speed %...", action: #selector(changeSpeed), keyEquivalent: "s"))
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(NSMenuItem(title: "Restart Level", action: #selector(restartLevel), keyEquivalent: "r"))
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(NSMenuItem(title: "Reset All Progress", action: #selector(resetAll), keyEquivalent: "R"))
        gameMenuItem.submenu = gameMenu
        mainMenu.addItem(gameMenuItem)
        
        // 3. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        windowMenu.addItem(NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        
        // 4. Help Menu - VIGTIG: Så den ikke siger "Help is not available"
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "Roman's Breakout Help", action: #selector(showHelp), keyEquivalent: "?"))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }
    
    func getGameScene() -> GameScene? { (window?.contentView as? SKView)?.scene as? GameScene }
    
    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let credits = "Created by Roman Dogonowski november 2026 & Meta AI\nVersion \(version)\n\nBreakout-style game for Apple Silicon"
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Roman's Breakout",
            .applicationVersion: version,
            .credits: NSAttributedString(string: credits)
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
    
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Roman's Breakout - Help"
        alert.informativeText = """
        HOW TO PLAY:
        • Move mouse to move paddle
        • Ball must hit paddle first to arm bricks
        • +1 point on paddle hit, -5 when ball falls
        • Break all bricks to go to NEXT WAVE

        CONTROLS:
        • Space = Start / Pause / Resume
        • Mouse = Move paddle
        • Click Level box = Change Level 1-99
        • Click Speed % = Change start speed 50-300%
        • Click Speaker = Sound ON/OFF

        MENU:
        • Game > Change Level (Cmd+L)
        • Game > Change Speed (Cmd+S)
        • Game > Restart Level (Cmd+R)
        • Game > Reset All Progress (Cmd+Shift+R)

        SCORE:
        • Start at 25 points
        • Game Over at 0
        • Speed +5% per 10 points above 25

        Created by Roman Dogonowski november 2026 & Meta AI
        Version 3.00 06.11.2026
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func changeLevel() { getGameScene()?.promptForLevel() }
    @objc func changeSpeed() { getGameScene()?.promptForSpeed() }
    @objc func restartLevel() { getGameScene()?.restartGame() }
    @objc func resetAll() { getGameScene()?.confirmResetAll() }
}

