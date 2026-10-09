import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let frame = NSScreen.main!.frame
let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
window.backgroundColor = .black
window.level = .normal
window.makeKeyAndOrderFront(nil)
app.run()
