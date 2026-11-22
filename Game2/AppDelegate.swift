import Cocoa
import SpriteKit

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    
    nonisolated override init() { super.init() }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ingen "Enter Full Screen" i menuerne (macOS tilføjer den ellers automatisk)
        UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
        NSApp.setActivationPolicy(.regular)
        setupMenu()
    }

    // MARK: - Display / Window size
    // Finder hvilket display Mac'en har og bygger vindue efter det
    func displayInfo() -> String {
        var info = ""
        for screen in NSScreen.screens {
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            let pixelW = CGDisplayPixelsWide(number)
            let pixelH = CGDisplayPixelsHigh(number)
            let scale = screen.backingScaleFactor
            let retina = scale >= 2.0 ? "Retina" : "Ikke-Retina"
            let visible = screen.visibleFrame
            info += "Skærm \(number): \(pixelW)x\(pixelH) px, \(Int(visible.width))x\(Int(visible.height)) pt, scale \(scale) (\(retina))\n"
        }
        return info
    }

    func optimalWindowSize(for screen: NSScreen) -> NSSize {
        // visibleFrame = skærm minus menubar + Dock
        let visible = screen.visibleFrame
        // Vi vil max bruge 85% af skærmen, så vinduet altid kan være der
        let maxW = visible.width * 0.85
        let maxH = visible.height * 0.85

        // Ønsket størrelse på stor skærm (som nu)
        var w: CGFloat = 900
        var h: CGFloat = 700

        // Skaler ned hvis skærmen er lille (f.eks. 13" Air 1440x900, gammel 1280x800)
        if w > maxW {
            w = maxW
            h = w * 700 / 900
        }
        if h > maxH {
            h = maxH
            w = h * 900 / 700
        }
        // Cap på meget store skærme (4K/5K) så spillet ikke bliver kæmpe
        w = min(w, 1100)
        h = min(h, 850)
        // Minimum så HUD ikke klemmes
        w = max(w, 640)
        h = max(h, 480)
        return NSSize(width: round(w), height: round(h))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Print display info i Xcode console - så du kan se hvilken Mac der kører
        print("=== DISPLAY INFO ===\n\(displayInfo())")
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let size = optimalWindowSize(for: screen)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.center()
        win.title = "Roman's Breakout"
        win.backgroundColor = NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.19, alpha: 1.0)
        win.minSize = NSSize(width: 640, height: 480)
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.fullScreenNone]
        
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
        win.delegate = self
        win.makeFirstResponder(skView)

        // Mellemrum = Start / Pause / Fortsæt – virker uanset hvilket view der har fokus
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49, !event.isARepeat else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, NSApp.keyWindow === self.window, let scene = self.getGameScene() else { return false }
                scene.handleStatusToggle()
                return true
            }
            return handled ? nil : event
        }
        
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
        gameMenu.addItem(NSMenuItem(title: "Change Player...", action: #selector(changePlayer), keyEquivalent: "p"))
        gameMenu.addItem(NSMenuItem(title: "High Scores...", action: #selector(showHighScores), keyEquivalent: "j"))
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(NSMenuItem(title: "Change Level...", action: #selector(changeLevel), keyEquivalent: "l"))
        gameMenu.addItem(NSMenuItem(title: "Change Speed %...", action: #selector(changeSpeed), keyEquivalent: "s"))
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(NSMenuItem(title: "Restart Level", action: #selector(restartLevel), keyEquivalent: "r"))
        gameMenu.addItem(NSMenuItem.separator())
        gameMenu.addItem(NSMenuItem(title: "Reset All Progress", action: #selector(resetAll), keyEquivalent: "R"))
        gameMenuItem.submenu = gameMenu
        mainMenu.addItem(gameMenuItem)
        
        // (Ingen Window-menu – kun Game-menu, ingen zoom eller fuld skærm)
        
        // 4. Help Menu - VIGTIG: Så den ikke siger "Help is not available"
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(NSMenuItem(title: "Roman's Breakout Help", action: #selector(showHelp), keyEquivalent: "?"))
        helpMenu.addItem(NSMenuItem.separator())
        helpMenu.addItem(NSMenuItem(title: "Show Display Info", action: #selector(showDisplayInfo), keyEquivalent: ""))
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        
        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }
    
    // Ingen zoom (heller ikke ved dobbeltklik på titellinjen)
    func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool { false }

    func getGameScene() -> GameScene? { (window?.contentView as? SKView)?.scene as? GameScene }
    
    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let credits = "Created by Roman Jakub Dogonowski, October–November 2026\nVersion \(version)\n\nBreakout-style game for Apple Silicon\n\nNew: multi-ball levels (1 → 2 → 3 balls), x3 points with 3 balls, triangle and vertical bricks, explosions, a 3D look and power-ups (wide paddle, slow ball, laser, shield)."
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Roman's Breakout",
            .applicationVersion: version,
            .credits: NSAttributedString(string: credits)
        ]
        NSApplication.shared.orderFrontStandardAboutPanel(options: options)
    }
    
    @objc func showHelp() {
        // Sæt spillet på pause først – så bliver musepilen låst op og vist igen,
        // ellers er pilen skjult og fanget i spillet og man kan ikke klikke OK
        if let scene = getGameScene() {
            if scene.isPlaying || (scene.inTransition && !scene.gamePaused) { scene.handleStatusToggle() }
            scene.showCursorNow()
        }
        let alert = NSAlert()
        alert.messageText = "Roman's Breakout - Help"
        alert.informativeText = "Scroll to read everything. Press Return or click OK to close."
        let helpText = """
        HOW TO PLAY:
        • Move the mouse to move the paddle
        • A ball must hit the paddle before it can break bricks
          (grey = not ready, coloured = ready)
        • Only a ball coming from below breaks a brick
        • Break all bricks to reach the NEXT WAVE / next level

        BALLS:
        • Levels cycle 1 → 2 → 3 balls, then start over
        • Missing one or two balls costs nothing
        • -5 points only when ALL balls are missed;
          then all balls come back
        • The ball turns flat on the paddle, oval when falling,
          and changes colour on every paddle hit
        • If 2 or 3 balls crash into each other: BIG explosion,
          an EXTRA ball and +100 points!
          (never more than 4 balls on the field at once)
        • …and the paddle turns into an ELASTIC OVAL for 20 seconds:
          it wobbles when it hits the ball and changes colour

        POWER-UPS:
        • Broken bricks often drop a capsule – catch it
          with the paddle (+5 points)
        • W  WIDE PADDLE – 50% wider paddle for 15 seconds
        • S  SLOW BALL – balls move slower for 10 seconds
        • L  LASER – the paddle shoots by itself for 10 seconds
        • +  SHIELD – a shield at the bottom saves one ball
        • Active power-ups are shown in the bottom-left corner
        • The slowest the balls ever go is 150% speed
        • A new game removes all power-ups

        POINTS:
        • +1 per paddle hit, +2 per brick
        • x3 POINTS while all 3 balls are in play
          (shown as "x3" in the score box)
        • Start at 25 points, Game Over at 0
        • Speed +5% per 10 points above 25

        BRICKS:
        • Every level is built at random – a new pattern every time
        • Row types: classic bricks, ▲▼ triangles, ▶◀ triangles,
          ◆ diamonds (45° bricks with triangles above and below)
          and ⬢ hexagons (honeycomb)
        • Some levels have random standing bricks
        • Hit bricks explode and tumble down as 3D blocks
        • Watch out: some falling bricks (random) fly back to
          their place if they land on your paddle!
        • BANK SHOT: if the ball hits a side wall and then a brick,
          the brick falls – from any side (+3 points)
        • From level 2 some bricks have a silver rim and a number:
          they need 3 hits (ball or laser) before they break
        • Clear a level for fanfare and fireworks!

        PLAYERS:
        • Click the player box (👤) or Game > Change Player (Cmd+P)
          to choose who is playing or add a new player
        • Every player has their own high score
        • Click the High box or Game > High Scores (Cmd+J)
          to see everyone's best score

        CONTROLS:
        • Space = Start / Pause / Resume
        • Esc or P = Pause / Resume
        • Click Level box = Change Level 1-99
        • Click Speed % = Change start speed 150-300%
        • Click Speaker = Sound ON/OFF

        MENU:
        • Game > Change Level (Cmd+L)
        • Game > Change Speed (Cmd+S)
        • Game > Restart Level (Cmd+R)
        • Game > Change Player (Cmd+P)
        • Game > High Scores (Cmd+J)
        • Game > Reset All Progress (Cmd+Shift+R)

        Created by Roman Dogonowski, October–November 2026
        """
        // Hjælpeteksten i en rulle-boks med fast højde, så OK-knappen altid er synlig på skærmen
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 470, height: 380))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: scroll.contentSize.height))
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = helpText
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc func showDisplayInfo() {
        if let scene = getGameScene() {
            if scene.isPlaying || (scene.inTransition && !scene.gamePaused) { scene.handleStatusToggle() }
            scene.showCursorNow()
        }
        let alert = NSAlert()
        alert.messageText = "Display Info"
        alert.informativeText = displayInfo() + "\nWindow: \(Int(window?.frame.width ?? 0))x\(Int(window?.frame.height ?? 0)) pt"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func changeLevel() { getGameScene()?.promptForLevel() }
    @objc func changeSpeed() { getGameScene()?.promptForSpeed() }
    @objc func changePlayer() { getGameScene()?.promptForPlayer() }
    @objc func showHighScores() { getGameScene()?.showHighScores() }
    @objc func restartLevel() { getGameScene()?.restartGame() }
    @objc func resetAll() { getGameScene()?.confirmResetAll() }
}
