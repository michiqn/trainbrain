//
//  BLEIdentifiers.swift
//  voc
//
//  Created by Michael Kuhn on 27.03.25.
//
//  Protocol of the TrainBrain firmware
//  (Arduino/iOS Projekte/TrainBrain/TrainBrain.ino): rotary encoder with a push button.
//

import CoreBluetooth

/// UUIDs of the E-ink display's GATT service and its characteristics.
enum BLEIdentifiers {
    static let serviceUUID = CBUUID(string: "19B10000-E8F2-537E-4F6C-D104768A1214")
    static let line1CharacteristicUUID = CBUUID(string: "19B10001-E8F2-537E-4F6C-D104768A1214")
    static let line2CharacteristicUUID = CBUUID(string: "19B10002-E8F2-537E-4F6C-D104768A1214")
    static let line3CharacteristicUUID = CBUUID(string: "19B10003-E8F2-537E-4F6C-D104768A1214")
    static let refreshRegionCharacteristicUUID = CBUUID(string: "19B10004-E8F2-537E-4F6C-D104768A1214")
    /// Notifies 1 for a right turn and 2 for a left turn.
    static let rotaryCharacteristicUUID = CBUUID(string: "19B10005-E8F2-537E-4F6C-D104768A1214")
    /// Notifies 1 when the knob is pressed.
    static let buttonCharacteristicUUID = CBUUID(string: "19B10006-E8F2-537E-4F6C-D104768A1214")
    static let modeCharacteristicUUID = CBUUID(string: "19B10007-E8F2-537E-4F6C-D104768A1214")
}

/// Values the firmware understands on the mode characteristic.
enum DeviceMode: UInt8 {
    case workoutCounter = 0
    case vocabularyTrainer = 1
    /// Makes the firmware show its welcome screen.
    case homeScreen = 255
}

/// Input from the rotary encoder.
///
/// The firmware reacts to these on its own as well. In workout mode it counts and resets
/// its own counters, so the app mirrors exactly what the firmware does.
enum DeviceInput {
    /// Workout: push-up +1. Vocabulary: next word.
    case rotateRight
    /// Workout: pull-up +1. Vocabulary: show translation.
    case rotateLeft
    /// Workout: reset counters. Vocabulary: start or stop the quiz.
    case press
}
