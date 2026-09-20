import Testing
@testable import Reclaimer

@Suite struct ShellTests {
    @Test("Q1 — plain path is single-quoted")
    func plain() { #expect(Shell.q("/Users/tester/Library/Caches") == "'/Users/tester/Library/Caches'") }

    @Test("Q2 — embedded single quote is closed, escaped, reopened")
    func quote() { #expect(Shell.q("a'b") == #"'a'\''b'"#) }

    @Test("Q4 — a newline in a path survives as one word")
    func newline() {
        let weird = "/tmp/odd\nname"
        let r = Shell.run("printf %s " + Shell.q(weird), timeout: 5, login: false)
        #expect(r.stdout == weird)
    }

    @Test("Q3 — other shell metacharacters are left inert inside the quotes")
    func metachars() { #expect(Shell.q("x y$z`;&|") == "'x y$z`;&|'") }
}
