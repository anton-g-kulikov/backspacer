import AppKit

// Entry point. No storyboard, no nib — everything is built in code so the
// project stays a plain SwiftPM package that `scripts/build-app.sh` can
// wrap into a .app bundle.

// Helper mode: `Backspacer --admin <command>` runs one privileged command and exits. Launched only
// by Shell.runAsAdmin from the app itself, so the password prompt names Backspacer while the app's
// own main thread stays responsive.
if CommandLine.arguments.count > 1, CommandLine.arguments[1] == Shell.adminFlag {
    exit(Shell.AdminHelper.main(Array(CommandLine.arguments.dropFirst())))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
