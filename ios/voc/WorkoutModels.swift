//
//  WorkoutModels.swift
//  voc
//
//  Created on 09.04.25.
//

import Foundation
import Observation

/// A saved workout.
struct WorkoutSession: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var pushUps: Int
    var pullUps: Int

    var totalExercises: Int {
        pushUps + pullUps
    }
}

enum Exercise: CaseIterable {
    case pushUps
    case pullUps

    var title: String {
        switch self {
        case .pushUps: "PUSH-UPS"
        case .pullUps: "PULL-UPS"
        }
    }
}

/// Keeps the running counts and the saved workout history.
@Observable
final class WorkoutManager {
    static let shared = WorkoutManager()

    private static let historyKey = "workoutHistory"

    private(set) var pushUps = 0
    private(set) var pullUps = 0
    private(set) var history: [WorkoutSession] = []

    @ObservationIgnored private let defaults: UserDefaults

    /// History sorted newest first, the order the history list shows.
    var historyNewestFirst: [WorkoutSession] {
        history.sorted { $0.date > $1.date }
    }

    /// The counts as they appear on the E-ink display.
    var displayLines: (line1: String, line2: String) {
        ("\(Exercise.pushUps.title): \(pushUps)", "\(Exercise.pullUps.title): \(pullUps)")
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.historyKey),
           let decoded = try? JSONDecoder().decode([WorkoutSession].self, from: data) {
            history = decoded
        }
    }

    func count(for exercise: Exercise) -> Int {
        switch exercise {
        case .pushUps: pushUps
        case .pullUps: pullUps
        }
    }

    func increment(_ exercise: Exercise) {
        switch exercise {
        case .pushUps: pushUps += 1
        case .pullUps: pullUps += 1
        }
    }

    func decrement(_ exercise: Exercise) {
        switch exercise {
        case .pushUps: pushUps = max(0, pushUps - 1)
        case .pullUps: pullUps = max(0, pullUps - 1)
        }
    }

    func resetCounters() {
        pushUps = 0
        pullUps = 0
    }

    /// Saves the current counts as a session and resets them.
    /// Returns `false` and saves nothing when both counts are zero.
    @discardableResult
    func saveSession(date: Date = .now) -> Bool {
        guard pushUps > 0 || pullUps > 0 else { return false }

        history.append(WorkoutSession(date: date, pushUps: pushUps, pullUps: pullUps))
        persistHistory()
        resetCounters()
        return true
    }

    func deleteSessions(withIDs ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
        persistHistory()
    }

    private func persistHistory() {
        if let encoded = try? JSONEncoder().encode(history) {
            defaults.set(encoded, forKey: Self.historyKey)
        }
    }
}
