//
//  VocabularyModels.swift
//  voc
//

import Foundation
import Observation

struct VocabularyEntry: Identifiable, Codable {
    var id = UUID()
    var word: String
    var translation: String
    var sentence: String
    var timestamp: Date
    var reviewCount = 0
    var lastReviewDate: Date?
}

extension VocabularyEntry {
    private enum CodingKeys: String, CodingKey {
        case id, word, translation, sentence, timestamp, reviewCount, lastReviewDate
    }

    /// Also decodes entries saved before example sentences existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        translation = try container.decode(String.self, forKey: .translation)
        sentence = try container.decodeIfPresent(String.self, forKey: .sentence) ?? ""
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        reviewCount = try container.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        lastReviewDate = try container.decodeIfPresent(Date.self, forKey: .lastReviewDate)
    }
}

enum QuizMode {
    case inactive
    /// Only the word is shown.
    case wordOnly
    /// The translation and example sentence are shown too.
    case translation
}

/// Keeps the vocabulary list and runs the quiz.
@Observable
final class VocabularyManager {
    static let shared = VocabularyManager()

    private static let vocabularyKey = "savedVocabulary"

    private(set) var vocabulary: [VocabularyEntry] = []
    private(set) var quizMode: QuizMode = .inactive
    /// Shuffled entry IDs for the running quiz. `vocabulary` itself keeps its order.
    private(set) var quizOrder: [UUID] = []
    private(set) var quizPosition = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let display: DisplayDevice

    var isQuizActive: Bool { quizMode != .inactive }

    var currentWord: VocabularyEntry? {
        guard isQuizActive, quizOrder.indices.contains(quizPosition) else { return nil }
        let id = quizOrder[quizPosition]
        return vocabulary.first { $0.id == id }
    }

    /// Entries sorted newest first, the order the dictionary shows.
    var entriesNewestFirst: [VocabularyEntry] {
        vocabulary.sorted { $0.timestamp > $1.timestamp }
    }

    init(defaults: UserDefaults = .standard, display: DisplayDevice = BLEManager.shared) {
        self.defaults = defaults
        self.display = display

        if let data = defaults.data(forKey: Self.vocabularyKey),
           let decoded = try? JSONDecoder().decode([VocabularyEntry].self, from: data) {
            vocabulary = decoded
        }
    }

    // MARK: - Editing

    func addEntry(word: String, translation: String, sentence: String, date: Date = .now) {
        vocabulary.append(VocabularyEntry(word: word, translation: translation, sentence: sentence, timestamp: date))
        persist()
    }

    func updateEntry(id: UUID, word: String, translation: String, sentence: String) {
        guard let index = vocabulary.firstIndex(where: { $0.id == id }) else { return }

        vocabulary[index].word = word
        vocabulary[index].translation = translation
        vocabulary[index].sentence = sentence
        persist()
    }

    func deleteEntries(withIDs ids: Set<UUID>) {
        vocabulary.removeAll { ids.contains($0.id) }
        persist()

        guard isQuizActive else { return }
        quizOrder.removeAll { ids.contains($0) }
        if quizOrder.isEmpty {
            stopQuiz()
        } else {
            quizPosition = min(quizPosition, quizOrder.count - 1)
            showCurrentWordOnDisplay()
        }
    }

    // MARK: - Quiz

    func startQuiz() {
        guard !vocabulary.isEmpty else { return }

        quizOrder = vocabulary.map(\.id).shuffled()
        quizPosition = 0
        quizMode = .wordOnly

        display.setDeviceMode(.vocabularyTrainer)
        showCurrentWordOnDisplay()

        if display.isConnected {
            NotificationService.shared.show(
                title: "Quiz Started",
                body: "First word is being displayed. Turn the knob left to see the answer."
            )
        }
    }

    func revealTranslation() {
        guard quizMode == .wordOnly, let entry = currentWord else { return }

        quizMode = .translation
        markReviewed(entry.id)
        showCurrentWordOnDisplay()
    }

    func showNextWord() {
        guard isQuizActive, !quizOrder.isEmpty else { return }

        quizPosition = (quizPosition + 1) % quizOrder.count
        quizMode = .wordOnly
        showCurrentWordOnDisplay()
    }

    /// Ends the quiz. Pass `resetDisplay: false` when the caller is about to show something else.
    func stopQuiz(resetDisplay: Bool = true) {
        guard isQuizActive else { return }

        quizMode = .inactive
        quizOrder = []
        quizPosition = 0

        if resetDisplay {
            display.setDeviceMode(.vocabularyTrainer)
            // An empty line 1 makes the firmware show its default vocabulary screen.
            display.showOnDisplay(line1: "", line2: "", line3: "")
        }
    }

    /// Handles the knob while the vocabulary trainer is open: pressing starts or stops the quiz,
    /// turning left shows the translation, turning right shows the next word.
    /// Turning the knob also starts a quiz if none is running.
    func handleDeviceInput(_ input: DeviceInput) {
        guard isQuizActive else {
            startQuiz()
            return
        }

        switch input {
        case .press: stopQuiz()
        case .rotateLeft: revealTranslation()
        case .rotateRight: showNextWord()
        }
    }

    // MARK: - Private

    private func showCurrentWordOnDisplay() {
        guard let entry = currentWord else { return }

        let isRevealed = quizMode == .translation
        display.showOnDisplay(
            line1: entry.word,
            line2: isRevealed ? entry.translation : "?",
            line3: isRevealed ? entry.sentence : ""
        )
    }

    private func markReviewed(_ id: UUID) {
        guard let index = vocabulary.firstIndex(where: { $0.id == id }) else { return }

        vocabulary[index].reviewCount += 1
        vocabulary[index].lastReviewDate = .now
        persist()
    }

    private func persist() {
        if let encoded = try? JSONEncoder().encode(vocabulary) {
            defaults.set(encoded, forKey: Self.vocabularyKey)
        }
    }
}
