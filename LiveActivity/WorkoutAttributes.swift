import ActivityKit
import Foundation

struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setLabel: String
        var weight: String
        var reps: Int
        var completed: Int
        var total: Int
        var restUntil: Date?
        var exerciseID: String
        var setID: String
        var hasNext: Bool
    }
    var workoutID: String
    var title: String
    var startedAt: Date
}
