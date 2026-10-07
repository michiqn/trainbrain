//
//  vocTests.swift
//  vocTests
//
//  Created by Michael Kuhn on 09.04.25.
//

import Foundation
import Testing
@testable import voc

/// Records what would have been sent to the E-ink display.
private final class FakeDisplay: DisplayDevice {
    var isConnected = false
    private(set) var modes: [DeviceMode] = []
    private(set) var screens: [[String]] = []

    func setDeviceMode(_ mode: DeviceMode) {
        modes.append(mode)
    }

    func showOnDisplay(line1: String, line2: String, line3: String) {
        screens.append([line1, line2, line3])
    }
}

/// A fresh, empty UserDefaults so tests don't touch the app's real data.
private func makeDefaults() throws -> UserDefaults {
    let name = "VocTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defaults.removePersistentDomain(forName: name)
    return defaults
}

// MARK: - DisplayText

struct DisplayTextTests {
    @Test func shortTextIsUnchanged() {
        #expect(DisplayText.fitting("PUSH-UPS: 12", maxBytes: 32) == "PUSH-UPS: 12")
    }

    @Test func limitCountsBytesNotCharacters() {
        // "ä" is 2 bytes in UTF-8, so only 16 fit into 32 bytes.
        let result = DisplayText.fitting(String(repeating: "ä", count: 20), maxBytes: 32)
        #expect(result.count == 16)
        #expect(result.utf8.count == 32)
    }

    @Test func doesNotSplitMultiByteCharacters() {
        // 4 bytes of room: "a" (1) + "ä" (2) fit, the next "ä" (2 more) doesn't.
        #expect(DisplayText.fitting("aää", maxBytes: 4) == "aä")
    }

    @Test func longSentenceIsCutAtWordBoundary() {
        let sentence = String(repeating: "Wort ", count: 40)
        let result = DisplayText.sentenceFitting(sentence, maxBytes: 100)

        #expect(result.utf8.count <= 100)
        #expect(result.hasSuffix("Wort..."))
    }
}

// MARK: - WorkoutManager

struct WorkoutManagerTests {
    @Test func countsNeverGoBelowZero() throws {
        let manager = WorkoutManager(defaults: try makeDefaults())
        manager.decrement(.pushUps)
        #expect(manager.pushUps == 0)
    }

    @Test func emptySessionIsNotSaved() throws {
        let manager = WorkoutManager(defaults: try makeDefaults())
        #expect(manager.saveSession() == false)
        #expect(manager.history.isEmpty)
    }

    @Test func savingPersistsAndResetsCounters() throws {
        let defaults = try makeDefaults()
        let manager = WorkoutManager(defaults: defaults)
        manager.increment(.pushUps)
        manager.increment(.pullUps)
        manager.increment(.pullUps)

        #expect(manager.saveSession())
        #expect(manager.pushUps == 0 && manager.pullUps == 0)

        let reloaded = WorkoutManager(defaults: defaults)
        #expect(reloaded.history.count == 1)
        #expect(reloaded.history.first?.pullUps == 2)
    }

    @Test func deletingFromSortedListRemovesTheRightSession() throws {
        let manager = WorkoutManager(defaults: try makeDefaults())
        manager.increment(.pushUps)
        manager.saveSession(date: Date(timeIntervalSince1970: 1_000))
        manager.increment(.pullUps)
        manager.saveSession(date: Date(timeIntervalSince1970: 2_000))

        // The list shows newest first; delete its first row.
        let newest = manager.historyNewestFirst[0]
        manager.deleteSessions(withIDs: [newest.id])

        #expect(manager.history.count == 1)
        #expect(manager.history.first?.pushUps == 1)
    }

    @Test func displayLinesShowCurrentCounts() throws {
        let manager = WorkoutManager(defaults: try makeDefaults())
        manager.increment(.pushUps)
        #expect(manager.displayLines.line1 == "PUSH-UPS: 1")
        #expect(manager.displayLines.line2 == "PULL-UPS: 0")
    }
}

// MARK: - VocabularyManager

struct VocabularyManagerTests {
    private func makeManager(words: [String] = ["Haus", "Baum", "Auto"]) throws -> (VocabularyManager, FakeDisplay) {
        let display = FakeDisplay()
        let manager = VocabularyManager(defaults: try makeDefaults(), display: display)
        for (index, word) in words.enumerated() {
            manager.addEntry(word: word, translation: "\(word)-en", sentence: "",
                             date: Date(timeIntervalSince1970: Double(index)))
        }
        return (manager, display)
    }

    @Test func deletingFromSortedListRemovesTheRightEntry() throws {
        let (manager, _) = try makeManager()

        // The dictionary shows newest first, so its first row is "Auto".
        let firstRow = manager.entriesNewestFirst[0]
        manager.deleteEntries(withIDs: [firstRow.id])

        #expect(manager.vocabulary.map(\.word) == ["Haus", "Baum"])
    }

    @Test func quizDoesNotReorderSavedVocabulary() throws {
        let (manager, _) = try makeManager()
        manager.startQuiz()
        #expect(manager.vocabulary.map(\.word) == ["Haus", "Baum", "Auto"])
        #expect(manager.quizOrder.count == 3)
    }

    @Test func quizHidesThenRevealsTranslation() throws {
        let (manager, display) = try makeManager(words: ["Haus"])

        manager.startQuiz()
        #expect(manager.quizMode == .wordOnly)
        #expect(display.modes == [.vocabularyTrainer])
        #expect(display.screens.last == ["Haus", "?", ""])

        manager.revealTranslation()
        #expect(manager.quizMode == .translation)
        #expect(display.screens.last == ["Haus", "Haus-en", ""])
        #expect(manager.vocabulary[0].reviewCount == 1)
    }

    @Test func nextWordWrapsAround() throws {
        let (manager, _) = try makeManager(words: ["Haus", "Baum"])
        manager.startQuiz()

        manager.showNextWord()
        #expect(manager.quizPosition == 1)
        manager.showNextWord()
        #expect(manager.quizPosition == 0)
        #expect(manager.quizMode == .wordOnly)
    }

    @Test(arguments: [DeviceInput.rotateLeft, .rotateRight, .press])
    func anyKnobInputStartsQuizWithoutRevealing(_ input: DeviceInput) throws {
        let (manager, _) = try makeManager()
        manager.handleDeviceInput(input)

        #expect(manager.isQuizActive)
        #expect(manager.quizMode == .wordOnly)
        #expect(manager.quizPosition == 0)
    }

    @Test func knobControlsRunningQuiz() throws {
        let (manager, _) = try makeManager(words: ["Haus", "Baum"])
        manager.startQuiz()

        manager.handleDeviceInput(.rotateLeft)
        #expect(manager.quizMode == .translation)

        manager.handleDeviceInput(.rotateRight)
        #expect(manager.quizPosition == 1)
        #expect(manager.quizMode == .wordOnly)

        manager.handleDeviceInput(.press)
        #expect(!manager.isQuizActive)
    }

    @Test func stoppingQuizShowsDefaultVocabularyScreen() throws {
        let (manager, display) = try makeManager()
        manager.startQuiz()
        manager.stopQuiz()

        #expect(!manager.isQuizActive)
        #expect(display.screens.last == ["", "", ""])
    }

    @Test func deletingLastQuizWordStopsQuiz() throws {
        let (manager, _) = try makeManager(words: ["Haus"])
        manager.startQuiz()
        manager.deleteEntries(withIDs: Set(manager.vocabulary.map(\.id)))

        #expect(!manager.isQuizActive)
        #expect(manager.currentWord == nil)
    }

    @Test func decodesEntriesSavedBeforeSentencesExisted() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","word":"Haus","translation":"house","timestamp":0,"reviewCount":2}]
        """
        let entries = try JSONDecoder().decode([VocabularyEntry].self, from: Data(json.utf8))

        #expect(entries.first?.sentence == "")
        #expect(entries.first?.reviewCount == 2)
    }
}
