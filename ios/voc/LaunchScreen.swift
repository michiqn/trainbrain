//
//  LaunchScreen.swift
//  voc
//

import SwiftUI

/// Start screen: connect a device and pick a mode.
struct LaunchScreen: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(AppState.self) private var appState
    @State private var showingDeviceList = false
    @State private var logoScale = 1.0
    @State private var showingContent = false

    var body: some View {
        ZStack {
            Color.vocPrimaryBackground
                .ignoresSafeArea()

            VStack(spacing: 25) {
                logo
                    .opacity(showingContent ? 1 : 0)

                Spacer()

                connectionStatusView
                    .opacity(showingContent ? 1 : 0)

                Spacer()

                VStack(spacing: 20) {
                    Text("Choose Mode")
                        .font(.headline)
                        .foregroundStyle(Color.vocTextSecondary)

                    ForEach(AppMode.allCases) { mode in
                        modeSelectionCard(for: mode)
                    }
                }
                .padding(.horizontal)
                .opacity(showingContent ? 1 : 0)

                Spacer()
            }
            .padding(.vertical, 30)
        }
        .sheet(isPresented: $showingDeviceList) {
            DeviceListView()
        }
        .task {
            // Fade the content in shortly after the logo starts pulsing.
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeIn(duration: 0.6)) {
                showingContent = true
            }
        }
    }

    // MARK: - Components

    private var logo: some View {
        VStack(spacing: 15) {
            Image(systemName: "display")
                .font(.system(size: 60))
                .foregroundStyle(Color.vocPrimaryBlue)
                .padding()
                .scaleEffect(logoScale)
                .opacity(2 - logoScale)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: logoScale)
                .onAppear {
                    logoScale = 1.2
                }

            Text("TrainBrain")
                .font(.system(size: 28, weight: .medium, design: .rounded))
                .foregroundStyle(Color.vocTextPrimary)
        }
    }

    private var connectionStatusView: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: bleManager.isConnected ? "antenna.radiowaves.left.and.right" : "xmark.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(bleManager.isConnected ? Color.vocAccentGreen : Color.gray)
                    .frame(width: 30)

                Text(connectionTitle)
                    .font(.headline)
                    .foregroundStyle(bleManager.isConnected ? Color.vocTextPrimary : Color.vocTextSecondary)

                Spacer()

                if bleManager.isConnected {
                    SignalStrengthIndicator(strength: bleManager.connectionStrength)
                        .padding(.trailing, 5)
                }
            }

            Button {
                showingDeviceList = true
            } label: {
                Text(bleManager.isConnected ? "Change Device" : "Connect Device")
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.vocPrimaryBlue, in: .rect(cornerRadius: 12))
                    .shadow(color: Color.vocPrimaryBlue.opacity(0.3), radius: 5, x: 0, y: 3)
            }
        }
        .padding()
        .cardStyle(cornerRadius: 16)
        .padding(.horizontal)
    }

    private var connectionTitle: String {
        switch bleManager.connectionState {
        case .connected: "Connected to device"
        case .connecting: "Connecting…"
        case .disconnected: "Not Connected"
        }
    }

    private func modeSelectionCard(for mode: AppMode) -> some View {
        Button {
            appState.select(mode)
        } label: {
            HStack(spacing: 20) {
                Image(systemName: mode.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(mode.cardColor)
                    .frame(width: 60, height: 60)
                    .background(mode.cardColor.opacity(0.1), in: .circle)

                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.title)
                        .font(.headline)
                        .foregroundStyle(Color.vocTextPrimary)

                    Text(mode.summary)
                        .font(.subheadline)
                        .foregroundStyle(Color.vocTextSecondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(Color.vocTextSecondary)
                    .padding(.trailing, 5)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .cardStyle(cornerRadius: 16)
        }
        .buttonStyle(.plain)
    }
}

private extension AppMode {
    var cardColor: Color {
        switch self {
        case .workoutCounter: .vocPrimaryBlue
        case .vocabularyTrainer: .vocSecondaryPurple
        }
    }
}

#Preview {
    LaunchScreen()
        .environment(BLEManager.shared)
        .environment(AppState.shared)
}
