//
//  SharedViews.swift
//  voc
//

import SwiftUI

/// Three bars that light up with the Bluetooth signal strength.
struct SignalStrengthIndicator: View {
    /// Signal strength from 0 to 100.
    let strength: Int

    private var activeBars: Int { min(3, strength / 33) }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "dot.radiowaves.right")
                    .font(.system(size: 18))
                    .foregroundStyle(index < activeBars ? Color.vocPrimaryBlue : Color.gray.opacity(0.3))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal strength \(activeBars) of 3")
    }
}

/// Connection state, with a button that opens the device list.
struct ConnectionStatusBar: View {
    @Environment(BLEManager.self) private var bleManager
    let onConnect: () -> Void

    var body: some View {
        HStack {
            Button(action: onConnect) {
                Image(systemName: bleManager.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(bleManager.isConnected ? Color.vocAccentGreen : Color.gray)
            }
            .padding(.trailing, 10)

            switch bleManager.connectionState {
            case .connected:
                Text("Connected")
                    .foregroundStyle(Color.vocTextSecondary)
                SignalStrengthIndicator(strength: bleManager.connectionStrength)
            case .connecting:
                Text("Connecting…")
                    .foregroundStyle(Color.vocTextSecondary)
                ProgressView()
                    .padding(.leading, 8)
            case .disconnected:
                Text("Disconnected")
                    .foregroundStyle(Color.vocTextSecondary)
                Button(action: onConnect) {
                    Text("Connect")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color.vocPrimaryBlue, in: .rect(cornerRadius: 8))
                }
                .padding(.leading, 8)
            }

            Spacer()
        }
    }
}

/// Full-width filled button that dims when disabled.
struct FilledButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        FilledButton(configuration: configuration, color: color)
    }

    private struct FilledButton: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: ButtonStyleConfiguration
        let color: Color

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(color.opacity(isEnabled ? 1 : 0.4), in: .rect(cornerRadius: 15))
                .shadow(color: color.opacity(isEnabled ? 0.3 : 0.1), radius: 5, x: 0, y: 3)
                .opacity(configuration.isPressed ? 0.8 : 1)
        }
    }
}

extension View {
    /// Card background with rounded corners and a soft shadow.
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        background(Color.vocCardBackground, in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    /// Small hint shown above a control, for example to explain why it's disabled.
    func hint(_ text: String, isVisible: Bool) -> some View {
        overlay {
            if isVisible {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(Color.vocTextSecondary)
                    .padding(6)
                    .background(Color.vocCardBackground.opacity(0.8), in: .rect(cornerRadius: 4))
                    .offset(y: -36)
            }
        }
    }
}
