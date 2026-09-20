import Foundation

/// A small JSON Schema validator covering the keywords `catalog.schema.json` uses. Test support
/// only — the app never validates at runtime. Errors carry the JSON-pointer-ish path of the
/// offending value so a failing catalog edit points at the entry.
struct MiniSchema {
    let root: [String: Any]
    init(_ schema: [String: Any]) { root = schema }

    func validate(_ doc: Any) -> [String] { var errs: [String] = []; check(doc, root, "", &errs); return errs }

    private func check(_ v: Any, _ s: [String: Any], _ at: String, _ errs: inout [String]) {
        if let ref = s["$ref"] as? String, let target = resolve(ref) { check(v, target, at, &errs); return }
        if let t = s["type"] as? String, !matches(v, t) { errs.append("\(at): expected \(t)"); return }
        if let c = s["const"], !equal(v, c) { errs.append("\(at): must be \(c)") }
        if let e = s["enum"] as? [Any], !e.contains(where: { equal(v, $0) }) { errs.append("\(at): not one of \(e)") }
        if let p = s["pattern"] as? String, let str = v as? String,
           str.range(of: p, options: .regularExpression) == nil { errs.append("\(at): does not match \(p)") }
        if let obj = v as? [String: Any] {
            for r in s["required"] as? [String] ?? [] where obj[r] == nil { errs.append("\(at): missing \(r)") }
            let props = s["properties"] as? [String: [String: Any]] ?? [:]
            for (k, sub) in props { if let x = obj[k] { check(x, sub, "\(at)/\(k)", &errs) } }
            if s["additionalProperties"] as? Bool == false {
                for k in obj.keys where props[k] == nil { errs.append("\(at): unknown field \(k)") }
            }
            for (k, needs) in s["dependentRequired"] as? [String: [String]] ?? [:] where obj[k] != nil {
                for n in needs where obj[n] == nil { errs.append("\(at): \(k) requires \(n)") }
            }
            for (k, sub) in s["dependentSchemas"] as? [String: [String: Any]] ?? [:] where obj[k] != nil {
                var e2: [String] = []; check(v, sub, at, &e2)
                errs += e2.map { "\($0) (because of \(k))" }
            }
        }
        if let arr = v as? [Any] {
            if let m = s["minItems"] as? Int, arr.count < m { errs.append("\(at): fewer than \(m) items") }
            if let items = s["items"] as? [String: Any] { for (i, x) in arr.enumerated() { check(x, items, "\(at)/\(i)", &errs) } }
        }
        if let any = s["anyOf"] as? [[String: Any]] {
            let ok = any.contains { var e2: [String] = []; check(v, $0, at, &e2); return e2.isEmpty }
            if !ok { errs.append("\(at): \(s["description"] as? String ?? "matches none of the alternatives")") }
        }
        if let n = s["not"] as? [String: Any] {
            var e2: [String] = []; check(v, n, at, &e2)
            if e2.isEmpty { errs.append("\(at): \(n["description"] as? String ?? "matches a forbidden shape")") }
        }
    }

    private func resolve(_ ref: String) -> [String: Any]? {
        guard ref.hasPrefix("#/") else { return nil }
        var node: Any = root
        for part in ref.dropFirst(2).split(separator: "/") {
            guard let d = node as? [String: Any], let next = d[String(part)] else { return nil }
            node = next
        }
        return node as? [String: Any]
    }

    private func matches(_ v: Any, _ t: String) -> Bool {
        switch t {
        case "object":  return v is [String: Any]
        case "array":   return v is [Any]
        case "string":  return v is String
        case "boolean": return (v as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        case "integer": return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() && Double($0.doubleValue) == Double(Int($0.doubleValue)) } ?? false
        case "number":  return (v as? NSNumber).map { CFGetTypeID($0) != CFBooleanGetTypeID() } ?? false
        default:        return true
        }
    }

    private func equal(_ a: Any, _ b: Any) -> Bool {
        if let x = a as? String, let y = b as? String { return x == y }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        return false
    }
}
