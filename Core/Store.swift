import Foundation
import Combine

@MainActor final class AppStore: ObservableObject {
    static let shared = AppStore()
    @Published var data: AppData { didSet { persist() } }
    @Published var error: String? = nil
    @Published var loadBlocked = false
    private var ready = false
    let fileURL: URL
    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = directory.appendingPathComponent("forma-v1.json")
        data = AppData()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Keep the app database out of automatic cloud/device backups. Explicit exports are user-controlled.
            var excluded = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                data = try Self.decoder.decode(AppData.self, from: Data(contentsOf: fileURL))
                try Self.validate(data)
            } else { data = Seed.initial() }
        } catch {
            loadBlocked = true
            self.error = "Data could not be opened. The original file has been preserved. Restore a valid backup in Settings. \(error.localizedDescription)"
        }
        ready = true
        if !loadBlocked { persist() }
    }
    func persist() {
        guard ready, !loadBlocked else { return }
        do { try Self.encoder.encode(data).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { self.error = "Could not save changes: \(error.localizedDescription). Export a backup before closing." }
    }
    func total(on date: Date) -> Nutrients { data.meals.filter { $0.date.sameDay(date) }.reduce(Nutrients()) { $0 + $1.total } }
    func day(_ date: Date) -> DayRecord { data.days.first { $0.date.sameDay(date) } ?? DayRecord(date: date.day) }
    func saveDay(_ value: DayRecord) {
        if let index = data.days.firstIndex(where: { $0.date.sameDay(value.date) }) { data.days[index] = value }
        else { data.days.append(value) }
    }
    func start(_ template: WorkoutTemplate) {
        guard data.activeWorkout == nil, !loadBlocked else { return }
        let exercises = template.exercises.map { plan -> WorkoutExercise in
            let last = TrainingAnalysis.history(plan.name, in: data.workouts).first?.sets.filter { $0.done && !$0.warmup } ?? []
            let sets = (0..<plan.sets).map { index -> TrainingSet in
                let old = index < last.count ? last[index] : last.last
                return TrainingSet(weightKg: old?.weightKg ?? 0, reps: old?.reps ?? plan.targetReps)
            }
            return WorkoutExercise(plan: plan, sets: sets, note: plan.note)
        }
        data.activeWorkout = Workout(name: template.name, exercises: exercises, note: template.note)
        refreshLive()
    }
    func editActive(_ edit: (inout Workout) -> Void) {
        guard var active = data.activeWorkout else { return }; edit(&active); data.activeWorkout = active
    }
    func startSet(exerciseID: UUID, setID: UUID) {
        editActive { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }), !workout.exercises[e].sets[s].done, workout.exercises[e].sets[s].startedAt == nil else { return }
            let previous = workout.exercises.flatMap(\.sets).compactMap(\.completedAt).max()
            workout.exercises[e].sets[s].startedAt = Date()
            workout.exercises[e].sets[s].restBefore = previous.map { max(0, Date().timeIntervalSince($0)) }
            workout.restUntil = nil
        }
        RestNotifications.cancel(); refreshLive()
    }
    func complete(exerciseID: UUID, setID: UUID) {
        var rest = 0
        let enabled = data.settings.restTimers
        editActive { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }), !workout.exercises[e].sets[s].done else { return }
            guard workout.exercises[e].sets[s].weightKg.isFinite, workout.exercises[e].sets[s].weightKg >= 0, workout.exercises[e].sets[s].reps > 0 else { return }
            workout.exercises[e].sets[s].completedAt = Date()
            rest = enabled ? workout.exercises[e].plan.restSeconds : 0
            workout.restUntil = rest > 0 ? Date().addingTimeInterval(Double(rest)) : nil
        }
        if data.settings.restAlerts && rest > 0 { RestNotifications.schedule(seconds: rest) }
        refreshLive()
    }
    func finish() -> Workout? {
        guard var active = data.activeWorkout else { return nil }
        active.endedAt = Date(); active.restUntil = nil
        data.workouts.append(active); data.activeWorkout = nil
        RestNotifications.cancel(); refreshLive(); return active
    }
    func discard() { data.activeWorkout = nil; RestNotifications.cancel(); refreshLive() }
    func refreshLive() { Task { await LiveCoordinator.shared.sync(workout: data.activeWorkout, settings: data.settings) } }
    func mergeFoods(_ foods: [Food]) {
        var catalog = data.foods
        for food in foods {
            if let index = catalog.firstIndex(where: { $0.name.caseInsensitiveCompare(food.name) == .orderedSame && $0.serving == food.serving && $0.source == food.source }) {
                var replacement = food; replacement.id = catalog[index].id; catalog[index] = replacement
            } else { catalog.append(food) }
        }
        data.foods = catalog
    }
    func restore(_ bytes: Data) throws {
        let restored = try Self.decoder.decode(AppData.self, from: bytes)
        try Self.validate(restored)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let recovery = fileURL.deletingLastPathComponent().appendingPathComponent("before-restore-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: fileURL, to: recovery)
        }
        try Self.encoder.encode(restored).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        loadBlocked = false; data = restored; RestNotifications.cancel(); refreshLive()
    }
    static func validate(_ value: AppData) throws {
        func require(_ test: Bool) throws { if !test { throw AppFailure(message: "Invalid or unsupported backup data.") } }
        try require(value.version == 1)
        let s = value.settings
        try require(s.calorieGoal.isFinite && s.calorieGoal > 0 && s.proteinPercent >= 0 && s.carbPercent >= 0 && s.fatPercent >= 0)
        try require(s.progressionPercent.isFinite && (2...10).contains(s.progressionPercent))
        try require(!s.mealNames.isEmpty && s.mealNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && Set(s.mealNames).count == s.mealNames.count)
        try require(Set(value.templates.map(\.id)).count == value.templates.count)
        try require(Set(value.workouts.map(\.id)).count == value.workouts.count)
        try require(Set(value.days.map { $0.date.day }).count == value.days.count)
        for f in value.foods + value.meals.map(\.food) {
            try require(!f.name.isEmpty && [f.nutrients.calories, f.nutrients.protein, f.nutrients.carbs, f.nutrients.fat].allSatisfy { $0.isFinite && $0 >= 0 })
            try require(f.nutrients.micro.values.allSatisfy { $0.isFinite && $0 >= 0 })
        }
        for m in value.meals { try require(m.servings.isFinite && m.servings > 0) }
        for t in value.templates {
            try require(!t.exercises.isEmpty && Set(t.exercises.map(\.id)).count == t.exercises.count)
            for e in t.exercises { try require(e.sets > 0 && e.sets <= 30 && e.targetReps > 0 && e.incrementKg > 0 && e.restSeconds >= 0) }
        }
        for w in value.workouts + (value.activeWorkout.map { [$0] } ?? []) {
            try require(Set(w.exercises.map(\.id)).count == w.exercises.count)
            for e in w.exercises {
                try require(Set(e.sets.map(\.id)).count == e.sets.count && e.plan.incrementKg.isFinite && e.plan.incrementKg > 0 && e.plan.restSeconds >= 0)
                for s in e.sets { try require(s.weightKg.isFinite && s.weightKg >= 0 && s.reps > 0 && s.reps <= 999 && (s.restBefore ?? 0) >= 0) }
            }
        }
        for d in value.days {
            for n in [d.weightKg, d.healthWeightKg, d.sleepHours, d.activeCalories, d.restingCalories].compactMap({ $0 }) { try require(n.isFinite && n >= 0) }
            try require((d.sleepHours ?? 0) <= 24)
        }
        try require(Set(value.foods.map(\.id)).count == value.foods.count && Set(value.meals.map(\.id)).count == value.meals.count)
    }
}
