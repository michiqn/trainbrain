//
//  WorkoutHistoryView.swift
//  voc
//

import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(WorkoutManager.self) private var workoutManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if workoutManager.history.isEmpty {
                    Text("No workout sessions saved yet")
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    let sessions = workoutManager.historyNewestFirst
                    ForEach(sessions) { session in
                        sessionRow(session)
                    }
                    .onDelete { offsets in
                        // The offsets index into the sorted list, so map them to IDs first.
                        workoutManager.deleteSessions(withIDs: Set(offsets.map { sessions[$0].id }))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Workout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(workoutManager.history.isEmpty)
                }
            }
        }
    }

    private func sessionRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(session.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.headline)

                Spacer()

                Text("Total: \(session.totalExercises)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 20) {
                Label("\(session.pushUps)", systemImage: "arrow.down.forward")
                    .foregroundStyle(.blue)

                Label("\(session.pullUps)", systemImage: "arrow.up")
                    .foregroundStyle(.green)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }
}
