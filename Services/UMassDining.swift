import Foundation

struct DiningLocation: Identifiable { var id: String; var name: String; var url: URL }
struct DiningImport { var foods: [Food]; var warnings: Int; var date: Date }
enum UMassDining {
    static let root = URL(string: "https://af-foodpro1.campus.ads.umass.edu/foodpro.net/location.aspx")!
    static func matches(_ pattern: String, _ string: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return [] }
        return regex.matches(in: string, range: NSRange(string.startIndex..., in: string)).map { match in
            (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: string).map { String(string[$0]) } ?? "" }
        }
    }
    static func clean(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (from, to) in [("&nbsp;", " "), ("&amp;", "&"), ("&#39;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&#160;", " ")] { text = text.replacingOccurrences(of: from, with: to) }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func links(_ html: String, relativeTo url: URL) -> [(String, URL)] {
        matches("<a\\b[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", html).compactMap { match in
            guard let link = URL(string: match[1].replacingOccurrences(of: "&amp;", with: "&"), relativeTo: url)?.absoluteURL,
                  link.host == root.host, link.scheme == "https" else { return nil }
            return (clean(match[2]), link)
        }
    }
    static func fetch(_ url: URL) async throws -> String {
        var request = URLRequest(url: url); request.timeoutInterval = 25
        request.setValue("Forma personal nutrition tracker", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppFailure(message: "UMass dining returned a server error. Your cached foods are unchanged. Try again later or import a CSV.")
        }
        guard data.count < 5_000_000, let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) else { throw AppFailure(message: "Unreadable dining response.") }
        return html
    }
    static func locations() async throws -> [DiningLocation] {
        let html = try await fetch(root)
        return links(html, relativeTo: root).compactMap { name, url in
            guard url.lastPathComponent.lowercased() == "shortmenu.aspx",
                  let id = URLComponents(url: url, resolvingAgainstBaseURL: true)?.queryItems?.first(where: { $0.name.lowercased() == "locationnum" })?.value else { return nil }
            return DiningLocation(id: id, name: name, url: url)
        }
    }
    static func nutrition(_ html: String, name: String, url: URL) -> Food? {
        let text = clean(html)
        func quantity(_ label: String, unit: String = "") -> Double? {
            let pattern = "(?:" + label + ")\\s*:?\\s*([0-9]+(?:\\.[0-9]+)?)\\s*" + unit
            guard let raw = matches(pattern, text).first?[1], let value = Double(raw) else { return nil }; return value
        }
        guard let cal = quantity("Calories(?! from)"), let protein = quantity("Protein", unit: "g"),
              let carbs = quantity("Total Carbohydrate[s]?", unit: "g"), let fat = quantity("Total Fat", unit: "g"),
              let serving = matches("Serving Size\\s*:?\\s*(.*?)(?:Amount Per Serving|Calories|Nutrition Facts)", text).first?[1],
              !serving.isEmpty, serving.count < 150 else { return nil }
        var n = Nutrients(calories: cal, protein: protein, carbs: carbs, fat: fat)
        let fields = [("fiber_g", "Dietary Fiber", "g"), ("sugar_g", "(?:Total )?Sugars", "g"), ("saturated_fat_g", "Saturated Fat", "g"),
                      ("sodium_mg", "Sodium", "mg"), ("potassium_mg", "Potassium", "mg"), ("calcium_mg", "Calcium", "mg"),
                      ("iron_mg", "Iron", "mg"), ("vitamin_d_mcg", "Vitamin D", "mcg"), ("vitamin_c_mg", "Vitamin C", "mg"), ("cholesterol_mg", "Cholesterol", "mg")]
        for (key, label, unit) in fields { if let value = quantity(label, unit: unit) { n.micro[key] = value } }
        return Food(name: name, serving: clean(serving), nutrients: n, source: "UMass Dining", sourceURL: url.absoluteString, fetchedAt: Date())
    }
    static func sync(locationID: String, date: Date) async throws -> DiningImport {
        let locations = try await locations()
        guard let location = locations.first(where: { $0.id == locationID }) else { throw AppFailure(message: "Dining location not found on the UMass directory.") }
        var components = URLComponents(url: location.url, resolvingAgainstBaseURL: true)!
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "MM/dd/yyyy"
        var query = components.queryItems ?? []; query.removeAll { $0.name.lowercased() == "dtdate" }; query.append(URLQueryItem(name: "dtdate", value: f.string(from: date)))
        components.queryItems = query
        let menuURL = components.url!
        let first = try await fetch(menuURL)
        var pages: [(String, URL)] = [(first, menuURL)]
        let longLinks = links(first, relativeTo: menuURL).filter { $0.1.lastPathComponent.lowercased() == "longmenu.aspx" }
        for (_, url) in Array(Dictionary(grouping: longLinks, by: { $0.1.absoluteString }).values.compactMap(\.first).prefix(8)) {
            try Task.checkCancellation(); try await Task.sleep(nanoseconds: 200_000_000)
            pages.append((try await fetch(url), url))
        }
        var seen = Set<String>(), recipes: [(String, URL)] = []
        for (html, page) in pages {
            for (name, link) in links(html, relativeTo: page) where link.lastPathComponent.lowercased().contains("nutrition") {
                let parts = URLComponents(url: link, resolvingAgainstBaseURL: true)?.queryItems ?? []
                let key = parts.first(where: { $0.name.lowercased() == "recnum" })?.value ?? link.absoluteString
                if !name.isEmpty && seen.insert(key).inserted { recipes.append((name, link)) }
            }
        }
        guard !recipes.isEmpty else { throw AppFailure(message: "No nutrition links found for this menu/date. UMass may be closed or may have changed its page format. Cached foods are preserved.") }
        var foods: [Food] = [], failed = 0
        for (name, url) in recipes.prefix(250) {
            try Task.checkCancellation(); try await Task.sleep(nanoseconds: 200_000_000)
            do { if let food = nutrition(try await fetch(url), name: name, url: url) { foods.append(food) } else { failed += 1 } }
            catch is CancellationError { throw CancellationError() }
            catch { failed += 1 }
        }
        guard !foods.isEmpty else { throw AppFailure(message: "Nutrition pages could not be parsed safely. No foods were changed. Use CSV import until this source is available.") }
        return DiningImport(foods: foods, warnings: failed + max(0, recipes.count - 250), date: date)
    }
}
