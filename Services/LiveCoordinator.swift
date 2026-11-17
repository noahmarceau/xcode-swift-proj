import ActivityKit
import Foundation

@MainActor final class LiveCoordinator {
    static let shared = LiveCoordinator()
    private var revision = 0
    func sync(workout: Workout?, settings: Settings) async {
        revision += 1; let token = revision
        guard let workout, settings.liveActivities else {
            for activity in Activity<WorkoutAttributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }; return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let nextExercise = workout.exercises.first { $0.sets.contains { !$0.done } }
        let nextSet = nextExercise?.sets.first { !$0.done }
        let index = nextExercise?.sets.firstIndex { !$0.done } ?? 0
        let state = WorkoutAttributes.ContentState(exercise: nextExercise?.plan.name ?? "All sets logged", setLabel: "Set \(index + 1)",
            weight: "\(settings.displayWeight(nextSet?.weightKg ?? 0).compact) \(settings.weightUnit)", reps: nextSet?.reps ?? 0,
            completed: workout.exercises.flatMap(\.sets).filter(\.done).count, total: workout.exercises.flatMap(\.sets).count,
            restUntil: settings.restTimers ? workout.restUntil : nil,
            exerciseID: nextExercise?.id.uuidString ?? "", setID: nextSet?.id.uuidString ?? "", hasNext: nextSet != nil)
        let content = ActivityContent(state: state, staleDate: nil)
        for activity in Activity<WorkoutAttributes>.activities where activity.attributes.workoutID != workout.id.uuidString {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard token == revision else { return }
        if let activity = Activity<WorkoutAttributes>.activities.first(where: { $0.attributes.workoutID == workout.id.uuidString }) { await activity.update(content) }
        else {
            do { _ = try Activity.request(attributes: WorkoutAttributes(workoutID: workout.id.uuidString, title: workout.name, startedAt: workout.startedAt), content: content, pushType: nil) }
            catch { AppStore.shared.error = "Workout is saved, but Live Activity could not start: \(error.localizedDescription)" }
        }
    }
}
