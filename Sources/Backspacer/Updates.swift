import Foundation

/// About → "Check for updates": one request to GitHub's releases API, on the user's click only,
/// compared against the running version. It answers with a link; it never downloads or installs.
enum Updates {
    static let latestURL = URL(string: "https://api.github.com/repos/anton-g-kulikov/backspacer/releases/latest")!

    struct Release: Equatable { let version: String; let page: String; let dmg: String? }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    static func parse(_ data: Data) throws -> Release {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String, let page = obj["html_url"] as? String
        else { throw Failure("GitHub's answer wasn't a release — try again later.") }
        let assets = obj["assets"] as? [[String: Any]] ?? []
        let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, page: page, dmg: dmg)
    }

    /// Numeric per component; a `-N-gHASH` suffix from `git describe` on a dev build is ignored,
    /// so a dev build of 0.8.1 is 0.8.1. Missing components are 0 ("1.0" == "1.0.0").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            let core = v.split(separator: "-", maxSplits: 1).first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let (a, b) = (parts(candidate), parts(current))
        for i in 0..<max(a.count, b.count) {
            let (x, y) = (i < a.count ? a[i] : 0, i < b.count ? b[i] : 0)
            if x != y { return x > y }
        }
        return false
    }

    /// The default fetcher: a plain GET with a short timeout, no cookies, no caching.
    static let systemFetch: @Sendable (URL) throws -> Data = { url in
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Backspacer (https://github.com/anton-g-kulikov/backspacer)", forHTTPHeaderField: "User-Agent")
        let box = ResultBox()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { box.result = .failure(error) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                box.result = .failure(Failure("GitHub answered \(http.statusCode) — try again later."))
            } else { box.result = .success(data ?? Data()) }
            done.signal()
        }.resume()
        done.wait()
        switch box.result {
        case .success(let data): return data
        case .failure(let e as Failure): throw e
        case .failure: throw Failure("Couldn't reach GitHub — are you online?")
        case .none: throw Failure("Couldn't reach GitHub — are you online?")
        }
    }
    private final class ResultBox: @unchecked Sendable { var result: Result<Data, Error>? }
}
