import AppKit

// Entry point. No storyboard, no nib — everything is built in code so the
// project stays a plain SwiftPM package that `scripts/build-app.sh` can
// wrap into a .app bundle.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
