import Foundation
import Testing
@testable import Reclaimer

@Suite struct SchemaTests {
    static let schemaURL = Fixture.repoRoot.appendingPathComponent("catalog.schema.json")
    let schema: [String: Any]
    let catalog: [String: Any]

    init() throws {
        schema = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Self.schemaURL)) as? [String: Any])
        catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: Fixture.catalogURL)) as? [String: Any])
    }

    func errors(_ doc: Any) -> [String] { MiniSchema(schema).validate(doc) }

    /// The catalog with its entries replaced by one hand-written entry.
    func withEntry(_ entry: [String: Any]) -> [String: Any] {
        var c = catalog; c["entries"] = [entry]; return c
    }
    let base: [String: Any] = ["id": "x", "group": "g", "bucket": "safe", "label": "L", "path": "~/x"]

    @Test("V1 — the shipped catalog validates")
    func shipped() {
        #expect(errors(catalog) == [], Comment(rawValue: errors(catalog).joined(separator: "\n")))
    }

    @Test("V2 — the schema rejects the mistakes that matter", arguments: [
        ("unknown field",                    ["typo": true]),
        ("unknown bucket",                   ["bucket": "maybe"]),
        ("id with spaces",                   ["id": "my entry"]),
        ("children without path",            ["path": nil, "glob": ["root": "~/x", "name": "n"], "children": true]),
        ("children alongside glob",          ["glob": ["root": "~/x", "name": "n"], "children": true]),
        ("itemsCmd without deleteItemCmd",   ["itemsCmd": "ls"]),
        ("deleteItemCmd without {key}",      ["itemsCmd": "ls", "deleteItemCmd": "rm it"]),
        ("childLabel without children",      ["childLabel": ["file": "f", "keys": ["k"]]]),
        ("no source at all",                 ["path": nil]),
        ("sudo with deleteCmd",              ["sudo": true, "deleteCmd": "rm -rf /"]),
        ("sudo with deleteItemCmd",          ["sudo": true, "itemsCmd": "ls", "deleteItemCmd": "rm {key}"]),
    ] as [(String, [String: Any?])])
    func rejects(_ name: String, _ patch: [String: Any?]) {
        var e = base
        for (k, v) in patch { if let v { e[k] = v } else { e.removeValue(forKey: k) } }
        let errs = errors(withEntry(e))
        #expect(!errs.isEmpty, Comment(rawValue: name))
        #expect(errs.allSatisfy { $0.contains("entries/0") }, Comment(rawValue: "\(name): \(errs)"))
    }

    @Test("V3 — the validator enforces its keywords")
    func validatorSanity() {
        let s = MiniSchema(["type": "object", "required": ["a"], "additionalProperties": false,
                            "properties": ["a": ["type": "string", "pattern": "^x"], "n": ["type": "integer", "enum": [1, 2]],
                                           "l": ["type": "array", "minItems": 1, "items": ["type": "string"]]],
                            "dependentRequired": ["n": ["l"]],
                            "not": ["required": ["forbidden"]]])
        #expect(s.validate(["a": "xy"]).isEmpty)
        #expect(!s.validate([:]).isEmpty)                                   // required
        #expect(!s.validate(["a": "y"]).isEmpty)                            // pattern
        #expect(!s.validate(["a": "x", "z": 1]).isEmpty)                    // additionalProperties
        #expect(!s.validate(["a": "x", "n": 3, "l": ["s"]]).isEmpty)        // enum
        #expect(!s.validate(["a": "x", "n": 1]).isEmpty)                    // dependentRequired
        #expect(!s.validate(["a": "x", "l": []]).isEmpty)                   // minItems
        #expect(!s.validate(["a": "x", "l": [1]]).isEmpty)                  // items type
        #expect(!s.validate(["a": "x", "forbidden": 1]).isEmpty)            // not
        #expect(s.validate(["a": "x", "n": 2, "l": ["s"]]).isEmpty)
    }
}
