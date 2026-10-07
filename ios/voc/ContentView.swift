//
//  ContentView.swift
//  voc
//

import SwiftUI

/// Root view. Shows the launch screen until a mode is picked, then that mode's screen.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.isShowingLaunchScreen {
                LaunchScreen()
            } else {
                switch appState.currentMode {
                case .workoutCounter:
                    WorkoutCounterView()
                case .vocabularyTrainer:
                    VocabularyTrainerView()
                }
            }
        }
        .animation(.easeInOut, value: appState.isShowingLaunchScreen)
    }
}
