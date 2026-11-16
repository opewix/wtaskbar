import AppKit

let app = NSApplication.shared
if let path = DumpWindows.path { DumpWindows.run(into: path) }
let delegate = AppDelegate()
app.delegate = delegate
// Ни значка в Dock, ни строки меню: панель задач — фоновая программа.
app.setActivationPolicy(.accessory)
app.run()
