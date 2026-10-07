//
//  VocApp.swift
//  voc
//
//  Created by Michael Kuhn on 27.03.25.
//

import SwiftUI

@main
struct VocApp: App {
    private let appState = AppState.shared
    private let bleManager = BLEManager.shared
    private let workoutManager = WorkoutManager.shared
    private let vocabularyManager = VocabularyManager.shared

    init() {
        NotificationService.shared.setUp()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environment(bleManager)
                .environment(workoutManager)
                .environment(vocabularyManager)
        }
    }
}
