//
//  DeviceListView.swift
//  voc
//

import CoreBluetooth
import SwiftUI

struct DeviceListView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                scanHeader

                if bleManager.discoveredPeripherals.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    List(bleManager.discoveredPeripherals, id: \.identifier) { peripheral in
                        deviceRow(peripheral)
                            .listRowBackground(Color.vocCardBackground)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.vocPrimaryBackground)
            .navigationTitle("Available Devices")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: bleManager.startScanning)
        .onDisappear(perform: bleManager.stopScanning)
    }

    // MARK: - Components

    @ViewBuilder
    private var scanHeader: some View {
        if bleManager.isScanning {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Scanning...")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.vocTextSecondary)
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color.vocCardBackground)
        } else {
            Button(action: bleManager.startScanning) {
                Label("Scan for Devices", systemImage: "arrow.clockwise")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.vocPrimaryBlue)
                    .foregroundStyle(.white)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 50))
                .foregroundStyle(Color.vocTextSecondary)

            Text("No devices found")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.vocTextSecondary)

            Text("Make sure your Arduino device is powered on and nearby")
                .font(.system(size: 15))
                .foregroundStyle(Color.vocTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding()
    }

    private func deviceRow(_ peripheral: CBPeripheral) -> some View {
        Button {
            bleManager.connect(to: peripheral)
            dismiss()
        } label: {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.vocPrimaryBlue)
                    .frame(width: 40, height: 40)
                    .background(Color.vocPrimaryBlue.opacity(0.1), in: .circle)

                VStack(alignment: .leading, spacing: 4) {
                    Text(peripheral.name ?? "Unknown Device")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.vocTextPrimary)

                    Text(peripheral.identifier.uuidString.prefix(8) + "...")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.vocTextSecondary)
                }

                Spacer()

                Text("Connect")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.vocPrimaryBlue, in: .capsule)
            }
            .contentShape(.rect)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
