import Cocoa
import SpriteKit

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
