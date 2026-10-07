//
//  WorkoutCounterView.swift
//  voc
//

import SwiftUI

struct WorkoutCounterView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(WorkoutManager.self) private var workoutManager
    @State private var showingDeviceList = false
    @State private var showingHistory = false

    var body: some View {
        VStack(spacing: 20) {
            header
                .padding(.horizontal)

            ConnectionStatusBar { showingDeviceList = true }
                .padding(.horizontal)

            Spacer()

            CounterRow(exercise: .pushUps, color: .blue)
            CounterRow(exercise: .pullUps, color: .green)

            Spacer()

            HStack(spacing: 15) {
                Button {
                    showingHistory = true
                } label: {
                    OutlinedButtonLabel(title: "History", systemImage: "clock.arrow.circlepath", color: .purple)
                }

                Button(action: updateDisplay) {
                    Label("Update Display", systemImage: "arrow.up.doc.fill")
                }
                .buttonStyle(FilledButtonStyle(color: .vocPrimaryBlue))
                .disabled(!bleManager.isConnected)
                .hint("Connect a device first", isVisible: !bleManager.isConnected)
            }
            .padding(.horizontal, 20)

            Button(action: saveSession) {
                OutlinedButtonLabel(title: "Save Session", systemImage: "square.and.arrow.down", color: .blue)
            }
            .padding(.horizontal, 20)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showingDeviceList) {
            DeviceListView()
        }
        .sheet(isPresented: $showingHistory) {
            WorkoutHistoryView()
        }
    }

    private var header: some View {
        HStack {
            ModeSelectionMenu()

            Spacer()

            Text("Workout Counter")
                .font(.title2)
                .fontWeight(.medium)

            Spacer()

            Button(action: workoutManager.resetCounters) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Reset counters")
        }
    }

    // MARK: - Actions

    private func updateDisplay() {
        let lines = workoutManager.displayLines
        bleManager.showOnDisplay(line1: lines.line1, line2: lines.line2)
    }

    private func saveSession() {
        guard workoutManager.saveSession() else { return }

        NotificationService.shared.show(
            title: "Workout Saved",
            body: "Your workout session has been saved to history"
        )
    }
}

// MARK: - Components

/// One exercise's count, with buttons to change it.
private struct CounterRow: View {
    @Environment(WorkoutManager.self) private var workoutManager
    let exercise: Exercise
    let color: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(exercise.title)
                .font(.headline)
                .foregroundStyle(.secondary)

            HStack {
                stepButton(systemImage: "minus", label: "Decrease") {
                    workoutManager.decrement(exercise)
                }

                Spacer()

                Text("\(workoutManager.count(for: exercise))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())

                Spacer()

                stepButton(systemImage: "plus", label: "Increase") {
                    workoutManager.increment(exercise)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .outlinedBackground()
        }
        .padding(.horizontal, 20)
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1), in: .circle)
        }
        .accessibilityLabel("\(label) \(exercise.title.lowercased())")
    }
}

private struct OutlinedButtonLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .font(.system(size: 20))
            Text(title)
                .font(.headline)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .outlinedBackground()
    }
}

private extension View {
    func outlinedBackground() -> some View {
        background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.5), lineWidth: 1))
    }
}
