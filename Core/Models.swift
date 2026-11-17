import Foundation

struct Nutrients: Codable, Equatable {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    // Only known quantities are stored. Missing is never silently treated as measured zero.
    var micro: [String: Double] = [:]
    func scaled(_ factor: Double) -> Nutrients {
        Nutrients(calories: calories * factor, protein: protein * factor,
                  carbs: carbs * factor, fat: fat * factor, micro: micro.mapValues { $0 * factor })
    }
    static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        var result = Nutrients(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein,
                               carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat, micro: lhs.micro)
        for (key, value) in rhs.micro { result.micro[key, default: 0] += value }
        return result
    }
    static let units = ["fiber_g": "g", "sugar_g": "g", "saturated_fat_g": "g", "sodium_mg": "mg",
                        "potassium_mg": "mg", "calcium_mg": "mg", "iron_mg": "mg", "vitamin_d_mcg": "mcg",
                        "vitamin_c_mg": "mg", "cholesterol_mg": "mg"]
    static func label(_ key: String) -> String {
        key.replacingOccurrences(of: "_mcg", with: "").replacingOccurrences(of: "_mg", with: "")
            .replacingOccurrences(of: "_g", with: "").replacingOccurrences(of: "_", with: " ").capitalized
    }
}
struct Food: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var serving: String
    var nutrients: Nutrients
    var source: String = "Custom"
    var sourceURL: String? = nil
    var fetchedAt: Date? = nil
}
struct MealEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var meal = "Breakfast"
    var food: Food // Snapshot: later catalog edits never rewrite yesterday's intake.
    var servings: Double = 1
    var total: Nutrients { food.nutrients.scaled(servings) }
}
struct ExercisePlan: Codable, Identifiable {
    var id = UUID()
    var name: String = "Bench press"
    var sets: Int = 3
    var targetReps: Int = 8
    var restSeconds: Int = 120
    var incrementKg: Double = 2.26796185
    var note: String = ""
}
struct WorkoutTemplate: Codable, Identifiable {
    var id = UUID()
    var name = "New workout"
    var exercises: [ExercisePlan] = [ExercisePlan()]
    var note = ""
}
struct TrainingSet: Codable, Identifiable {
    var id = UUID()
    var weightKg: Double = 0
    var reps: Int = 8
    var warmup = false
    var failure = false
    var completedAt: Date? = nil
    var restBefore: Double? = nil
    var startedAt: Date? = nil
    var done: Bool { completedAt != nil }
    var estimated1RM: Double { reps == 1 ? weightKg : (reps <= 12 ? weightKg * (1 + Double(reps) / 30) : 0) }
}
struct WorkoutExercise: Codable, Identifiable {
    var id = UUID()
    var plan: ExercisePlan
    var sets: [TrainingSet]
    var note = ""
}
struct Workout: Codable, Identifiable {
    var id = UUID()
    var name: String
    var startedAt = Date()
    var endedAt: Date? = nil
    var exercises: [WorkoutExercise]
    var note = ""
    var restUntil: Date? = nil
    var workingSets: [TrainingSet] { exercises.flatMap(\.sets).filter { $0.done && !$0.warmup } }
    var volumeKg: Double { workingSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) } }
}
struct DayRecord: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var weightKg: Double? = nil
    var sleepHours: Double? = nil
    var activeCalories: Double? = nil
    var restingCalories: Double? = nil
    var note = ""
    var healthWeightKg: Double? = nil
    var healthSyncedAt: Date? = nil
    var weight: Double? { weightKg ?? healthWeightKg }
    var totalBurn: Double? {
        guard let activeCalories, let restingCalories else { return nil }
        return activeCalories + restingCalories
    }
}
struct Settings: Codable {
    var name = "Noah"
    var calorieGoal: Double = 3000
    var proteinPercent: Double = 25
    var carbPercent: Double = 45
    var fatPercent: Double { 100 - proteinPercent - carbPercent }
    var usePounds = true
    var appearance = "Dark"
    var accent = "Mint"
    var restTimers = true
    var restAlerts = false
    var liveActivities = true
    var autoUMass = false
    var locationID = "01"
    var progressionPercent: Double = 5
    var mealNames = ["Breakfast", "Lunch", "Dinner", "Snacks"]
    func displayWeight(_ kg: Double) -> Double { usePounds ? kg * 2.2046226218 : kg }
    func kilograms(_ display: Double) -> Double { usePounds ? display / 2.2046226218 : display }
    var weightUnit: String { usePounds ? "lb" : "kg" }
}
struct AppData: Codable {
    var version = 1
    var foods: [Food] = []
    var meals: [MealEntry] = []
    var templates: [WorkoutTemplate] = []
    var workouts: [Workout] = []
    var activeWorkout: Workout? = nil
    var days: [DayRecord] = []
    var settings = Settings()
    var lastUMassSync: Date? = nil
}
extension Date {
    var day: Date { Calendar.current.startOfDay(for: self) }
    func sameDay(_ other: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: other) }
}
extension Double {
    var compact: String { formatted(.number.precision(.fractionLength(0...1))) }
}
struct AppFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
