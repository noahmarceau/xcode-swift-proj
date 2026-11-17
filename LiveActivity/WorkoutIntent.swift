import AppIntents
import Foundation

struct WorkoutSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update workout set"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Workout") var workoutID: String
    @Parameter(title: "Exercise") var exerciseID: String
    @Parameter(title: "Set") var setID: String
    @Parameter(title: "Action") var action: String
    init() {}
    init(workoutID: String, exerciseID: String, setID: String, action: String) {
        self.workoutID = workoutID; self.exerciseID = exerciseID; self.setID = setID; self.action = action
    }
    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = AppStore.shared
        guard !store.loadBlocked, store.data.activeWorkout?.id.uuidString == workoutID,
              let e = UUID(uuidString: exerciseID), let s = UUID(uuidString: setID) else { return .result() }
        if action == "complete" { store.complete(exerciseID: e, setID: s) }
        else if action == "start" { store.startSet(exerciseID: e, setID: s) }
        else {
            store.editActive { w in
                guard let ei = w.exercises.firstIndex(where: { $0.id == e }), let si = w.exercises[ei].sets.firstIndex(where: { $0.id == s }), !w.exercises[ei].sets[si].done else { return }
                if action == "repUp" { w.exercises[ei].sets[si].reps = min(999, w.exercises[ei].sets[si].reps + 1) }
                if action == "repDown" { w.exercises[ei].sets[si].reps = max(1, w.exercises[ei].sets[si].reps - 1) }
                let increment = max(0.1, w.exercises[ei].plan.incrementKg)
                if action == "weightUp" { w.exercises[ei].sets[si].weightKg += increment }
                if action == "weightDown" { w.exercises[ei].sets[si].weightKg = max(0, w.exercises[ei].sets[si].weightKg - increment) }
            }
        }
        await LiveCoordinator.shared.sync(workout: store.data.activeWorkout, settings: store.data.settings)
        #endif
        return .result()
    }
}
