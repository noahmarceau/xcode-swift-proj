import XCTest
@testable import Forma

final class FormaTests: XCTestCase {
    func testCSVQuotedNameAndUnknownMicro() throws {
        let text = "name,serving,calories,protein_g,carbs_g,fat_g,sodium_mg\r\n\"Rice, cooked\",1 cup,205,4,45,0.4,\r\n"
        let foods = try FoodCSV.parse(text)
        XCTAssertEqual(foods.first?.name, "Rice, cooked")
        XCTAssertNil(foods.first?.nutrients.micro["sodium_mg"])
        XCTAssertEqual(foods.first!.nutrients.scaled(0.5).calories, 102.5)
    }
    func testRejectsMalformedNutrition() {
        XCTAssertThrowsError(try FoodCSV.parse("name,serving,calories,protein_g,carbs_g,fat_g\na,b,-10,2,3,4"))
        XCTAssertThrowsError(try FoodCSV.parse("name,serving,calories,protein_g,carbs_g,fat_g\na,b,NaN,2,3,4"))
        XCTAssertThrowsError(try FoodCSV.rows("\"unclosed"))
    }
    func testProgressionRequiresTwoSessionsAndNoFailure() {
        let p = ExercisePlan(name: "Bench", sets: 2, targetReps: 8, incrementKg: 2.5)
        let sets = [TrainingSet(weightKg: 50, reps: 10, completedAt: Date()), TrainingSet(weightKg: 50, reps: 10, completedAt: Date())]
        let e = WorkoutExercise(plan: p, sets: sets)
        XCTAssertEqual(TrainingAnalysis.suggestion(plan: p, history: [e], percent: 5).0, 50)
        XCTAssertEqual(TrainingAnalysis.suggestion(plan: p, history: [e, e], percent: 5).0, 52.5)
        var failed = e; failed.sets[0].failure = true
        XCTAssertEqual(TrainingAnalysis.suggestion(plan: p, history: [failed, e], percent: 5).0, 50)
    }
    func testWarmupsDoNotCreatePRs() {
        let p = ExercisePlan(name: "Bench")
        let old = Workout(name: "Old", exercises: [WorkoutExercise(plan: p, sets: [TrainingSet(weightKg: 50, reps: 8, completedAt: Date())])])
        let current = Workout(name: "Now", exercises: [WorkoutExercise(plan: p, sets: [TrainingSet(weightKg: 100, reps: 8, warmup: true, completedAt: Date())])])
        XCTAssertTrue(TrainingAnalysis.records(for: current, previous: [old]).isEmpty)
        XCTAssertEqual(current.volumeKg, 0)
    }
    func testUnknownEnergyDoesNotBecomeZero() {
        var d = DayRecord(date: Date(), activeCalories: 400)
        XCTAssertNil(d.totalBurn)
        d.restingCalories = 1800
        XCTAssertEqual(d.totalBurn, 2200)
    }
    func testFoodproParserRequiresCompleteMacros() {
        let url = URL(string: "https://af-foodpro1.campus.ads.umass.edu/foodpro.net/nutrition.aspx?RecNum=1")!
        let fixture = "<p>Serving Size 1 cup</p><p>Amount Per Serving</p><p>Calories 200</p><p>Total Fat 4g</p><p>Total Carbohydrate 30g</p><p>Protein 10g</p><p>Sodium 100mg</p><p>Iron 8%</p>"
        let food = UMassDining.nutrition(fixture, name: "Fixture", url: url)
        XCTAssertEqual(food?.nutrients.calories, 200)
        XCTAssertEqual(food?.nutrients.micro["sodium_mg"], 100)
        XCTAssertNil(food?.nutrients.micro["iron_mg"], "Percent DV must not be interpreted as mg")
        XCTAssertNil(UMassDining.nutrition("Calories 200", name: "Bad", url: url))
    }
    @MainActor func testSnapshotAndBackupRoundTrip() throws {
        let food = Food(name: "Oats", serving: "40 g", nutrients: Nutrients(calories: 150))
        var data = AppData(); data.foods = [food]; data.meals = [MealEntry(food: food)]
        data.foods[0].nutrients.calories = 170
        XCTAssertEqual(data.meals[0].total.calories, 150)
        let decoded = try AppStore.decoder.decode(AppData.self, from: AppStore.encoder.encode(data))
        try AppStore.validate(decoded)
        XCTAssertEqual(decoded.meals[0].total.calories, 150)
        data.version = 99
        XCTAssertThrowsError(try AppStore.validate(data))
    }
}
