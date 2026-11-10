import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Ни значка в Dock, ни строки меню: панель задач — фоновая программа.
app.setActivationPolicy(.accessory)
app.run()
