import Foundation

enum TrainingAnalysis {
    static func history(_ name: String, in workouts: [Workout]) -> [WorkoutExercise] {
        workouts.sorted { $0.startedAt > $1.startedAt }.compactMap { workout in
            let matches = workout.exercises.filter { $0.plan.name.caseInsensitiveCompare(name) == .orderedSame }
            guard var combined = matches.first, matches.flatMap(\.sets).contains(where: { $0.done && !$0.warmup }) else { return nil }
            combined.sets = matches.flatMap(\.sets)
            return combined
        }
    }
    static func suggestion(plan: ExercisePlan, history: [WorkoutExercise], percent: Double) -> (Double?, String) {
        guard let last = history.first else { return (nil, "Choose a comfortable starting load.") }
        let work = last.sets.filter { $0.done && !$0.warmup }
        guard let base = work.map(\.weightKg).min(), base > 0 else { return (nil, "Bodyweight or first weighted session.") }
        let ready = history.count >= 2 && history.prefix(2).allSatisfy { exercise in
            let sets = exercise.sets.filter { $0.done && !$0.warmup }
            return sets.count >= plan.sets && sets.allSatisfy { $0.reps >= plan.targetReps + 2 && !$0.failure && $0.weightKg >= base }
        }
        guard ready else { return (base, "Repeat the load. Reach target + 2 reps on every working set in two sessions before increasing.") }
        let step = max(0.1, plan.incrementKg)
        let raw = base * (1 + min(10, max(2, percent)) / 100)
        let rounded = (raw / step).rounded(.down) * step
        guard rounded > base else { return (base, "Your next equipment increment exceeds the selected increase; repeat or use microplates.") }
        return (rounded, "Both recent sessions cleared the rep target. Optional \(percent.compact)% progression, rounded down to equipment increments.")
    }
    static func records(for workout: Workout, previous: [Workout]) -> [String] {
        workout.exercises.compactMap { exercise in
            let current = exercise.sets.filter { $0.done && !$0.warmup }
            guard !current.isEmpty else { return nil }
            let past = history(exercise.plan.name, in: previous).flatMap(\.sets).filter { $0.done && !$0.warmup }
            guard !past.isEmpty else { return "\(exercise.plan.name): first-session baseline" }
            let best = current.map(\.estimated1RM).max() ?? 0
            let old = past.map(\.estimated1RM).max() ?? 0
            if best > old { return "\(exercise.plan.name): estimated 1RM PR" }
            if (current.map(\.weightKg).max() ?? 0) > (past.map(\.weightKg).max() ?? 0) { return "\(exercise.plan.name): load PR" }
            return nil
        }
    }
}
