import Foundation

enum FoodCSV {
    static let header = ["name", "serving", "calories", "protein_g", "carbs_g", "fat_g"]
    static func rows(_ text: String) throws -> [[String]] {
        let chars = Array(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        var result: [[String]] = [], row: [String] = [], field = "", quoted = false, i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else { quoted.toggle() }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field); if row.contains(where: { !$0.isEmpty }) { result.append(row) }; row = []; field = ""
            } else { field.append(c) }
            i += 1
        }
        guard !quoted else { throw AppFailure(message: "CSV has an unclosed quoted field.") }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { result.append(row) }
        return result
    }
    static func parse(_ text: String) throws -> [Food] {
        let table = try rows(text)
        guard let first = table.first else { throw AppFailure(message: "CSV is empty.") }
        let keys = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(keys).count == keys.count, header.allSatisfy(keys.contains) else {
            throw AppFailure(message: "Required unique columns: \(header.joined(separator: ", ")).")
        }
        var foods: [Food] = []
        for (offset, row) in table.dropFirst().enumerated() {
            guard row.count == keys.count else { throw AppFailure(message: "CSV row \(offset + 2) has the wrong number of columns.") }
            let cells = Dictionary(uniqueKeysWithValues: zip(keys, row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
            func number(_ key: String, optional: Bool = false) throws -> Double? {
                let raw = cells[key] ?? ""
                if optional && raw.isEmpty { return nil }
                guard let n = Double(raw), n.isFinite, n >= 0 else { throw AppFailure(message: "CSV row \(offset + 2): invalid \(key). Use a nonnegative number, with no unit suffix.") }
                return n
            }
            guard let name = cells["name"], !name.isEmpty, let serving = cells["serving"], !serving.isEmpty else { throw AppFailure(message: "Row \(offset + 2) needs a food name and serving.") }
            var n = Nutrients(calories: try number("calories")!, protein: try number("protein_g")!, carbs: try number("carbs_g")!, fat: try number("fat_g")!)
            for key in Nutrients.units.keys { if let v = try number(key, optional: true) { n.micro[key] = v } }
            foods.append(Food(name: name, serving: serving, nutrients: n, source: cells["source"].flatMap { $0.isEmpty ? nil : $0 } ?? "CSV"))
        }
        guard !foods.isEmpty else { throw AppFailure(message: "No food rows in CSV.") }; return foods
    }
}
enum Seed {
    static func initial() -> AppData {
        var d = AppData()
        if let url = Bundle.main.url(forResource: "common-foods", withExtension: "csv"), let text = try? String(contentsOf: url, encoding: .utf8) { d.foods = (try? FoodCSV.parse(text)) ?? [] }
        d.templates = [
            WorkoutTemplate(name: "Push", exercises: [ExercisePlan(name: "Bench press"), ExercisePlan(name: "Incline dumbbell press"), ExercisePlan(name: "Lateral raise", targetReps: 12), ExercisePlan(name: "Triceps pushdown", targetReps: 12)]),
            WorkoutTemplate(name: "Pull", exercises: [ExercisePlan(name: "Lat pulldown"), ExercisePlan(name: "Cable row"), ExercisePlan(name: "Rear delt fly", targetReps: 12), ExercisePlan(name: "Dumbbell curl", targetReps: 10)]),
            WorkoutTemplate(name: "Legs", exercises: [ExercisePlan(name: "Squat"), ExercisePlan(name: "Romanian deadlift"), ExercisePlan(name: "Leg curl", targetReps: 12), ExercisePlan(name: "Calf raise", targetReps: 12)])
        ]; return d
    }
}
