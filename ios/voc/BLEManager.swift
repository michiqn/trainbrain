//
//  BLEManager.swift
//  voc
//
//  Created by Michael Kuhn on 11.04.25.
//

import CoreBluetooth
import Observation
import os
import UIKit

/// The part of the E-ink display the feature managers use. Tests can supply a fake.
protocol DisplayDevice: AnyObject {
    var isConnected: Bool { get }
    func setDeviceMode(_ mode: DeviceMode)
    func showOnDisplay(line1: String, line2: String, line3: String)
}

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "voc", category: "BLE")

/// Owns the Bluetooth connection to the E-ink display and the protocol for talking to it.
///
/// Commands run one at a time. Each write waits for the device's response before the next
/// one is sent, so line updates always reach the device before the refresh that draws them.
@Observable
final class BLEManager: NSObject, DisplayDevice {
    static let shared = BLEManager()

    enum ConnectionState {
        case disconnected
        /// Connecting, or connected and still looking up the display's characteristics.
        case connecting
        /// Every characteristic was found and the display can be used.
        case connected
    }

    private(set) var connectionState: ConnectionState = .disconnected
    private(set) var isScanning = false
    private(set) var discoveredPeripherals: [CBPeripheral] = []
    /// Signal strength from 0 to 100.
    private(set) var connectionStrength = 0

    var isConnected: Bool { connectionState == .connected }

    /// Called on the main thread when the knob on the device is turned or pressed.
    @ObservationIgnored var onDeviceInput: ((DeviceInput) -> Void)?

    // MARK: Configuration

    private static let connectionTimeout: TimeInterval = 10
    private static let maxConnectionAttempts = 3
    private static let scanDuration: TimeInterval = 5
    private static let rssiInterval: TimeInterval = 2
    private static let backgroundDisconnectDelay: TimeInterval = 300
    /// Time the firmware needs to switch screens after a mode change.
    private static let modeChangePause: TimeInterval = 0.5
    /// Move on if the device never answers a write, so the queue can't get stuck.
    private static let writeResponseTimeout: TimeInterval = 10

    // MARK: Connection

    @ObservationIgnored private lazy var centralManager = CBCentralManager(delegate: self, queue: nil)
    /// The current device, kept after a disconnect so we can reconnect to it.
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var characteristics: DisplayCharacteristics?
    /// Text last written to lines 1–3. The firmware redraws on every line write,
    /// so unchanged lines are skipped. `nil` means unknown, so the line is always written.
    @ObservationIgnored private var lastWrittenLines: [String?] = [nil, nil, nil]
    /// True from `didConnect` until the link drops. Disconnect callbacks outside this window
    /// come from connections we cancelled ourselves, so they're ignored.
    @ObservationIgnored private var isLinkEstablished = false
    @ObservationIgnored private var connectionAttempt = 0
    @ObservationIgnored private var connectionTimer: Timer?
    @ObservationIgnored private var scanTimer: Timer?
    @ObservationIgnored private var rssiTimer: Timer?
    @ObservationIgnored private var backgroundTimer: Timer?

    // MARK: Command queue

    private enum Command {
        case write(Data, CBCharacteristic)
        case pause(TimeInterval)
    }

    @ObservationIgnored private var pendingCommands: [Command] = []
    @ObservationIgnored private var isExecutingCommand = false
    /// The characteristic whose write response we're waiting for.
    @ObservationIgnored private var awaitedWrite: CBUUID?
    /// Fires when a pause ends or a write response is overdue.
    @ObservationIgnored private var commandTimer: Timer?

    private override init() {
        super.init()
        _ = centralManager // Create the manager now so Bluetooth state updates start arriving.

        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    // MARK: - App Lifecycle

    @objc private func appDidEnterBackground() {
        backgroundTimer?.invalidate()
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: Self.backgroundDisconnectDelay, repeats: false) { [weak self] _ in
            self?.disconnect()
        }
    }

    @objc private func appWillEnterForeground() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil

        if connectionState == .disconnected, let peripheral {
            connect(to: peripheral)
        }
    }

    // MARK: - Scanning

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            logger.notice("Can't scan: Bluetooth is not powered on")
            return
        }

        discoveredPeripherals = []
        isScanning = true
        centralManager.scanForPeripherals(withServices: nil)

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: Self.scanDuration, repeats: false) { [weak self] _ in
            self?.stopScanning()
        }
    }

    func stopScanning() {
        scanTimer?.invalidate()
        scanTimer = nil

        guard isScanning else { return }
        centralManager.stopScan()
        isScanning = false
    }

    // MARK: - Connection

    func connect(to newPeripheral: CBPeripheral) {
        if newPeripheral.identifier == peripheral?.identifier, connectionState != .disconnected {
            return
        }

        disconnect()
        peripheral = newPeripheral
        newPeripheral.delegate = self
        connectionAttempt = 0
        startConnectionAttempt()
    }

    /// Ends the connection on purpose. The app reconnects when it next returns to the foreground.
    func disconnect() {
        guard let peripheral else { return }

        connectionTimer?.invalidate()
        tearDownLink()
        connectionState = .disconnected
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func startConnectionAttempt() {
        guard let peripheral else { return }

        connectionAttempt += 1
        connectionState = .connecting
        logger.info("Connecting to \(peripheral.name ?? "device"), attempt \(self.connectionAttempt)")
        centralManager.connect(peripheral)

        // The timeout covers connecting and looking up characteristics.
        connectionTimer?.invalidate()
        connectionTimer = Timer.scheduledTimer(withTimeInterval: Self.connectionTimeout, repeats: false) { [weak self] _ in
            self?.connectionAttemptFailed()
        }
    }

    /// Cancels the current attempt and retries, up to `maxConnectionAttempts` times in total.
    private func connectionAttemptFailed() {
        guard let peripheral else { return }

        connectionTimer?.invalidate()
        tearDownLink()
        centralManager.cancelPeripheralConnection(peripheral)

        if connectionAttempt < Self.maxConnectionAttempts {
            startConnectionAttempt()
        } else {
            connectionState = .disconnected
            logger.error("Connection failed after \(Self.maxConnectionAttempts) attempts")
        }
    }

    /// Gives up on a device that doesn't look like the E-ink display.
    private func abandonConnection(reason: String) {
        logger.error("Disconnecting: \(reason)")
        disconnect()
    }

    /// Resets everything tied to the current link. Keeps `peripheral` so we can reconnect.
    private func tearDownLink() {
        isLinkEstablished = false
        characteristics = nil
        lastWrittenLines = [nil, nil, nil]
        connectionStrength = 0
        rssiTimer?.invalidate()
        rssiTimer = nil
        resetCommandQueue()
    }

    private func connectionBecameReady(with found: DisplayCharacteristics, on peripheral: CBPeripheral) {
        characteristics = found
        peripheral.setNotifyValue(true, for: found.rotary)
        peripheral.setNotifyValue(true, for: found.button)

        connectionTimer?.invalidate()
        connectionAttempt = 0
        connectionState = .connected

        peripheral.readRSSI()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: Self.rssiInterval, repeats: true) { [weak self] _ in
            self?.peripheral?.readRSSI()
        }

        NotificationService.shared.show(
            title: "Device Connected",
            body: "Your E-ink display is now connected and ready to use"
        )
    }

    // MARK: - Display

    func setDeviceMode(_ mode: DeviceMode) {
        guard let characteristics else { return }
        enqueue(.write(Data([mode.rawValue]), characteristics.mode), .pause(Self.modeChangePause))
    }

    /// Writes the lines that changed.
    ///
    /// In vocabulary mode the firmware redraws the content area after every line write,
    /// so no separate refresh is needed. Lines 2 and 3 go first: on "next word" the old
    /// translation is hidden before the new word appears. In workout mode the firmware
    /// ignores the lines and shows its own counters.
    func showOnDisplay(line1: String, line2: String, line3: String = "") {
        guard let characteristics else { return }

        let lines = [
            (index: 1, text: DisplayText.fitting(line2, maxBytes: DisplayText.maxLineBytes), characteristic: characteristics.line2),
            (index: 2, text: DisplayText.sentenceFitting(line3), characteristic: characteristics.line3),
            (index: 0, text: DisplayText.fitting(line1, maxBytes: DisplayText.maxLineBytes), characteristic: characteristics.line1),
        ]
        for line in lines where lastWrittenLines[line.index] != line.text {
            lastWrittenLines[line.index] = line.text
            enqueue(.write(Data(line.text.utf8), line.characteristic))
        }
    }

    /// Shows the firmware's welcome screen. The firmware draws it as soon as it gets the mode.
    func showHomeScreen() {
        setDeviceMode(.homeScreen)
    }

    // MARK: - Command Queue

    private func enqueue(_ commands: Command...) {
        pendingCommands.append(contentsOf: commands)
        executeNextCommand()
    }

    private func executeNextCommand() {
        guard !isExecutingCommand, let peripheral, !pendingCommands.isEmpty else { return }
        isExecutingCommand = true

        switch pendingCommands.removeFirst() {
        case let .write(data, characteristic):
            awaitedWrite = characteristic.uuid
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            scheduleCommandTimer(after: Self.writeResponseTimeout)
        case let .pause(duration):
            scheduleCommandTimer(after: duration)
        }
    }

    private func scheduleCommandTimer(after interval: TimeInterval) {
        commandTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            if awaitedWrite != nil {
                logger.warning("No write response from device, continuing")
            }
            finishCommand()
        }
    }

    private func finishCommand() {
        commandTimer?.invalidate()
        commandTimer = nil
        awaitedWrite = nil
        isExecutingCommand = false
        executeNextCommand()
    }

    private func resetCommandQueue() {
        commandTimer?.invalidate()
        commandTimer = nil
        pendingCommands.removeAll()
        awaitedWrite = nil
        isExecutingCommand = false
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state != .poweredOn else { return }

        // In every other state, existing connections and scans are gone.
        connectionTimer?.invalidate()
        scanTimer?.invalidate()
        isScanning = false
        tearDownLink()
        connectionState = .disconnected

        switch central.state {
        case .poweredOff:
            NotificationService.shared.show(title: "Bluetooth Disconnected",
                                            body: "Please turn on Bluetooth to use this app")
        case .unauthorized:
            NotificationService.shared.show(title: "Bluetooth Access Required",
                                            body: "Please enable Bluetooth permissions in Settings")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }

        isLinkEstablished = true
        stopScanning()
        peripheral.discoverServices([BLEIdentifiers.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier else { return }

        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
        connectionAttemptFailed()
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral.identifier == self.peripheral?.identifier, isLinkEstablished else { return }

        let wasReady = isConnected
        tearDownLink()

        // No error means the connection was closed cleanly, so don't reconnect.
        guard let error else {
            connectionTimer?.invalidate()
            connectionState = .disconnected
            return
        }

        logger.error("Connection lost: \(error.localizedDescription)")
        if wasReady {
            NotificationService.shared.show(title: "Device Disconnected",
                                            body: "The connection to your E-ink display was lost")
            connectionAttempt = 0
            startConnectionAttempt()
        } else {
            connectionAttemptFailed()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            logger.error("Service discovery failed: \(error.localizedDescription)")
            connectionAttemptFailed()
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == BLEIdentifiers.serviceUUID }) else {
            abandonConnection(reason: "device has no E-ink display service")
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            logger.error("Characteristic discovery failed: \(error.localizedDescription)")
            connectionAttemptFailed()
            return
        }

        guard let found = DisplayCharacteristics(service.characteristics ?? []) else {
            abandonConnection(reason: "device is missing display characteristics")
            return
        }
        connectionBecameReady(with: found, on: peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == awaitedWrite else { return }

        if let error {
            logger.error("Write to \(characteristic.uuid) failed: \(error.localizedDescription)")
        }
        finishCommand()
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            logger.error("Characteristic update failed: \(error.localizedDescription)")
            return
        }

        let value = characteristic.value?.first

        switch (characteristic.uuid, value) {
        case (BLEIdentifiers.rotaryCharacteristicUUID, 1):
            onDeviceInput?(.rotateRight)
        case (BLEIdentifiers.rotaryCharacteristicUUID, 2):
            onDeviceInput?(.rotateLeft)
        case (BLEIdentifiers.buttonCharacteristicUUID, 1):
            onDeviceInput?(.press)
        default:
            // 0 is the firmware resetting the value after an input.
            break
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        if let error {
            logger.error("Reading RSSI failed: \(error.localizedDescription)")
            return
        }

        // RSSI is roughly -100 (weak) to -30 (strong) dBm; map it onto 0–100.
        connectionStrength = min(100, max(0, 100 + RSSI.intValue))
    }
}

// MARK: - DisplayCharacteristics

/// The characteristics the app needs. Can only be created when the device has all of them.
private struct DisplayCharacteristics {
    let line1: CBCharacteristic
    let line2: CBCharacteristic
    let line3: CBCharacteristic
    let refreshRegion: CBCharacteristic
    let rotary: CBCharacteristic
    let button: CBCharacteristic
    let mode: CBCharacteristic

    init?(_ characteristics: [CBCharacteristic]) {
        func find(_ uuid: CBUUID) -> CBCharacteristic? {
            characteristics.first { $0.uuid == uuid }
        }

        guard let line1 = find(BLEIdentifiers.line1CharacteristicUUID),
              let line2 = find(BLEIdentifiers.line2CharacteristicUUID),
              let line3 = find(BLEIdentifiers.line3CharacteristicUUID),
              let refreshRegion = find(BLEIdentifiers.refreshRegionCharacteristicUUID),
              let rotary = find(BLEIdentifiers.rotaryCharacteristicUUID),
              let button = find(BLEIdentifiers.buttonCharacteristicUUID),
              let mode = find(BLEIdentifiers.modeCharacteristicUUID) else {
            return nil
        }

        self.line1 = line1
        self.line2 = line2
        self.line3 = line3
        self.refreshRegion = refreshRegion
        self.rotary = rotary
        self.button = button
        self.mode = mode
    }
}
