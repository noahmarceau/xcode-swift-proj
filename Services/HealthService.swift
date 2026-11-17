import Foundation
#if HEALTHKIT_ENABLED
import HealthKit
#endif

@MainActor enum HealthService {
    static var available: Bool {
        #if HEALTHKIT_ENABLED
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }
    static func sync(into store: AppStore) async throws -> String {
        #if HEALTHKIT_ENABLED
        guard available else { throw AppFailure(message: "Health data is unavailable on this device.") }
        let health = HKHealthStore()
        let identifiers: [HKQuantityTypeIdentifier] = [.activeEnergyBurned, .basalEnergyBurned, .bodyMass]
        let types = Set(identifiers.compactMap { HKQuantityType.quantityType(forIdentifier: $0) })
        try await health.requestAuthorization(toShare: [], read: types)
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -89, to: Date().day)!
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        func energy(_ identifier: HKQuantityTypeIdentifier) async throws -> [Date: Double] {
            let type = HKQuantityType.quantityType(forIdentifier: identifier)!
            return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Date: Double], Error>) in
                let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                    options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
                query.initialResultsHandler = { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    var values: [Date: Double] = [:]
                    results?.enumerateStatistics(from: start, to: end) { stats, _ in
                        if let value = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) { values[stats.startDate.day] = value }
                    }
                    continuation.resume(returning: values)
                }; health.execute(query)
            }
        }
        let active = try await energy(.activeEnergyBurned)
        let basal = try await energy(.basalEnergyBurned)
        let weights: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKQuantityType.quantityType(forIdentifier: .bodyMass)!, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
                }; health.execute(query)
        }
        var weightByDay: [Date: Double] = [:]
        for sample in weights { weightByDay[sample.endDate.day] = sample.quantity.doubleValue(for: .gramUnit(with: .kilo)) }
        // Merge all days at once. A re-sync replaces, rather than adds, cumulative totals.
        var records = store.data.days
        for offset in 0..<90 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            var record = records.first { $0.date.sameDay(date) } ?? DayRecord(date: date)
            record.activeCalories = active[date]; record.restingCalories = basal[date]; record.healthWeightKg = weightByDay[date]
            record.healthSyncedAt = Date()
            if let i = records.firstIndex(where: { $0.date.sameDay(date) }) { records[i] = record } else { records.append(record) }
        }
        store.data.days = records
        return "Synced available data for 90 days. Missing values can mean no samples or denied access; Apple does not reveal read-denial status. Today's energy is partial."
        #else
        throw AppFailure(message: "This is the Local build. Select the Forma Health scheme and a signing profile that includes HealthKit to enable Health imports. Manual weight and sleep logging work in either build.")
        #endif
    }
}
