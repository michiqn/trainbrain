//
//  ModeSelectionMenu.swift
//  voc
//
//  Created on 09.04.25.
//

import SwiftUI

/// Header menu for switching modes or going back to the launch screen.
struct ModeSelectionMenu: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            Section {
                ForEach(AppMode.allCases) { mode in
                    Button {
                        if mode != appState.currentMode {
                            appState.select(mode)
                        }
                    } label: {
                        Label(mode.title, systemImage: mode.icon)
                    }
                }
            }

            Section {
                Button(action: appState.returnToLaunchScreen) {
                    Label("Back to Home", systemImage: "house")
                }
            }
        } label: {
            HStack {
                Image(systemName: appState.currentMode.icon)
                    .font(.system(size: 18))

                Text(appState.currentMode.title)
                    .font(.system(size: 14))

                Image(systemName: "chevron.down")
                    .font(.system(size: 14))
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 8))
        }
    }
}
