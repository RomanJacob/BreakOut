import Cocoa

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.regular)
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)

