//
//  AppState.swift
//  voc
//
//  Created on 09.04.25.
//

import Foundation
import Observation

enum AppMode: CaseIterable, Identifiable {
    case workoutCounter
    case vocabularyTrainer

    var id: Self { self }

    var title: String {
        switch self {
        case .workoutCounter: "Workout Counter"
        case .vocabularyTrainer: "Vocabulary Trainer"
        }
    }

    var summary: String {
        switch self {
        case .workoutCounter: "Track your push-ups and pull-ups"
        case .vocabularyTrainer: "Learn new words and phrases"
        }
    }

    var icon: String {
        switch self {
        case .workoutCounter: "figure.strengthtraining.traditional"
        case .vocabularyTrainer: "character.book.closed"
        }
    }

    var deviceMode: DeviceMode {
        switch self {
        case .workoutCounter: .workoutCounter
        case .vocabularyTrainer: .vocabularyTrainer
        }
    }
}

/// Holds the selected mode, the one source of truth for it. Coordinates the managers
/// when the mode changes and sends each device button press to the active feature.
@Observable
final class AppState {
    static let shared = AppState()

    private(set) var currentMode: AppMode = .workoutCounter
    /// Whether the launch screen (mode picker) is showing instead of the main app.
    private(set) var isShowingLaunchScreen = true

    @ObservationIgnored private let bleManager: BLEManager
    @ObservationIgnored private let workoutManager: WorkoutManager
    @ObservationIgnored private let vocabularyManager: VocabularyManager

    private init(bleManager: BLEManager = .shared,
                 workoutManager: WorkoutManager = .shared,
                 vocabularyManager: VocabularyManager = .shared) {
        self.bleManager = bleManager
        self.workoutManager = workoutManager
        self.vocabularyManager = vocabularyManager

        bleManager.onDeviceInput = { [weak self] input in
            self?.handleDeviceInput(input)
        }
    }

    /// Opens `mode`, ends whatever belonged to the previous mode, and puts the device in the same mode.
    func select(_ mode: AppMode) {
        if mode != .vocabularyTrainer {
            vocabularyManager.stopQuiz(resetDisplay: false)
        }

        currentMode = mode
        isShowingLaunchScreen = false

        bleManager.setDeviceMode(mode.deviceMode)
        switch mode {
        case .workoutCounter:
            let lines = workoutManager.displayLines
            bleManager.showOnDisplay(line1: lines.line1, line2: lines.line2)
        case .vocabularyTrainer:
            bleManager.showOnDisplay(line1: "", line2: "")
        }
    }

    /// Goes back to the launch screen and shows the device's welcome screen.
    func returnToLaunchScreen() {
        vocabularyManager.stopQuiz(resetDisplay: false)
        bleManager.showHomeScreen()
        isShowingLaunchScreen = true
    }

    private func handleDeviceInput(_ input: DeviceInput) {
        // On the launch screen no mode is selected yet. The firmware ignores input there too.
        guard !isShowingLaunchScreen else { return }

        switch currentMode {
        case .workoutCounter:
            // The firmware already did the same to its own counters.
            switch input {
            case .rotateRight: workoutManager.increment(.pushUps)
            case .rotateLeft: workoutManager.increment(.pullUps)
            case .press: workoutManager.resetCounters()
            }
        case .vocabularyTrainer:
            vocabularyManager.handleDeviceInput(input)
        }
    }
}
