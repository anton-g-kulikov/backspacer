# Security

Reclaimer deletes folders. If you find a way it could remove something it
shouldn't — a catalog path that resolves outside the allowed roots, a way for
the page to name a path, a gate that lets a user-data folder through — please
email anton.g.kulikov@gmail.com rather than opening a public issue. You'll get
a reply within a few days and credit in the changelog if you want it.

What's already in place: every disk operation takes a catalog id, not a path;
`Bridge.isSafeToDelete` refuses home, `~/Library`, top-level user folders and
anything outside `~/`, `/Library/Developer/` and the staged-update folder;
per-item deletes are selectors validated against a fresh resolve; the tests
run the gate over every path in the shipped catalog (`SafetyGateTests` S7).
