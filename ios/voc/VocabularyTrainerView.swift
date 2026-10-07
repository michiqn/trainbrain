//
//  VocabularyTrainerView.swift
//  voc
//
//  Created on 09.04.25.
//

import SwiftUI

struct VocabularyTrainerView: View {
    @Environment(BLEManager.self) private var bleManager
    @Environment(VocabularyManager.self) private var vocabularyManager
    @AppStorage("hasSeenQuizInstructions") private var hasSeenQuizInstructions = false
    @State private var word = ""
    @State private var translation = ""
    @State private var sentence = ""
    @State private var showingDictionary = false
    @State private var showingQuizInstructions = false
    @State private var showingDeviceList = false

    private var trimmedWord: String { word.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedTranslation: String { translation.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSentence: String { sentence.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isFormComplete: Bool { !trimmedWord.isEmpty && !trimmedTranslation.isEmpty }

    var body: some View {
        ZStack {
            Color.vocPrimaryBackground
                .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                    .padding(.horizontal)

                ConnectionStatusBar { showingDeviceList = true }
                    .padding()
                    .cardStyle()
                    .padding(.horizontal)

                if vocabularyManager.isQuizActive {
                    quizStatusBanner
                        .padding(.horizontal)

                    quizModeView
                        .padding(.horizontal)
                        .padding(.top, 10)

                    Spacer()

                    quizControlButtons
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            vocabularyInputView
                                .padding(.horizontal, 20)
                                .padding(.top, 10)

                            startQuizButton
                                .padding(.horizontal, 40)
                                .padding(.vertical, 20)

                            HStack(spacing: 20) {
                                Button {
                                    showingDictionary = true
                                } label: {
                                    Label("Dictionary", systemImage: "book.fill")
                                }
                                .buttonStyle(FilledButtonStyle(color: .vocSecondaryPurple))

                                Button(action: showFormOnDisplay) {
                                    Label("Update Display", systemImage: "arrow.up.doc.fill")
                                }
                                .buttonStyle(FilledButtonStyle(color: .vocPrimaryBlue))
                                .disabled(!bleManager.isConnected)
                                .hint("Connect a device first", isVisible: !bleManager.isConnected)
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .sheet(isPresented: $showingDictionary) {
            VocabularyDictionaryView()
        }
        .sheet(isPresented: $showingQuizInstructions) {
            QuizInstructionsView()
        }
        .sheet(isPresented: $showingDeviceList) {
            DeviceListView()
        }
    }

    // MARK: - Components

    private var header: some View {
        HStack {
            ModeSelectionMenu()

            Spacer()

            Text("Vocabulary Trainer")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(Color.vocTextPrimary)

            Spacer()

            Button(action: resetForm) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.vocTextPrimary)
            }
            .accessibilityLabel("Clear form")
        }
    }

    private var quizStatusBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .foregroundStyle(Color.vocAccentGreen)

            Text("Quiz Active: \(vocabularyManager.quizPosition + 1)/\(vocabularyManager.quizOrder.count)")
                .foregroundStyle(Color.vocTextPrimary)
                .fontWeight(.medium)

            Spacer()

            Button {
                vocabularyManager.stopQuiz()
            } label: {
                Label("Stop", systemImage: "stop.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .cardStyle()
    }

    private var quizModeView: some View {
        VStack(spacing: 15) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.vocPrimaryBlue)
                    .font(.system(size: 26))

                Text("Quiz Mode Active")
                    .font(.headline)
                    .foregroundStyle(Color.vocTextPrimary)
            }
            .padding(.top)

            VStack(alignment: .leading, spacing: 12) {
                if bleManager.isConnected {
                    instructionRow(icon: "display", text: "Word is displayed on the E-ink screen")
                    instructionRow(icon: "arrow.counterclockwise", text: "Turn the knob left to see translation and sentence")
                    instructionRow(icon: "arrow.clockwise", text: "Turn the knob right to go to the next word")
                    instructionRow(icon: "stop.circle", text: "Press the knob to stop the quiz")
                } else {
                    instructionRow(icon: "exclamationmark.triangle", text: "Device not connected - using app-only mode")
                    instructionRow(icon: "hand.tap", text: "Tap Translation button to reveal answers")
                    instructionRow(icon: "arrow.right", text: "Tap Next Word button to continue")
                }
            }
            .padding(.horizontal)

            Spacer(minLength: 20)

            if let currentWord = vocabularyManager.currentWord {
                currentWordCard(currentWord)
            }

            Spacer()
        }
        .padding()
        .background(Color.vocCardBackground.opacity(0.7), in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }

    private func currentWordCard(_ entry: VocabularyEntry) -> some View {
        VStack(spacing: 10) {
            Text("Current Word:")
                .font(.subheadline)
                .foregroundStyle(Color.vocTextSecondary)

            Text(entry.word)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(Color.vocTextPrimary)

            if vocabularyManager.quizMode == .translation {
                Text(entry.translation)
                    .font(.headline)
                    .foregroundStyle(Color.vocPrimaryBlue)
                    .padding(.top, 5)

                if !entry.sentence.isEmpty {
                    Text("Example: \(entry.sentence)")
                        .font(.subheadline)
                        .foregroundStyle(Color.vocSecondaryPurple)
                        .padding(.top, 5)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .cardStyle()
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Color.vocPrimaryBlue)
                .frame(width: 24, height: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(Color.vocTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vocabularyInputView: some View {
        VStack(spacing: 24) {
            inputField(title: "WORD", placeholder: "Enter word", text: $word)
            inputField(title: "TRANSLATION", placeholder: "Enter translation", text: $translation)

            VStack(alignment: .leading, spacing: 8) {
                fieldTitle("EXAMPLE SENTENCE")

                HStack {
                    TextField("Enter an example sentence (optional)", text: $sentence)
                        .padding()
                        .foregroundStyle(Color.vocTextPrimary)

                    Button(action: saveEntry) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(Color.vocPrimaryBlue.opacity(isFormComplete ? 1 : 0.3))
                            .frame(width: 36, height: 36)
                            .background(Color.vocPrimaryBlue.opacity(0.1), in: .circle)
                    }
                    .padding(.trailing, 12)
                    .disabled(!isFormComplete)
                    .accessibilityLabel("Add word")
                }
                .cardStyle(cornerRadius: 10)
            }
        }
    }

    private func inputField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldTitle(title)

            TextField(placeholder, text: text)
                .padding()
                .foregroundStyle(Color.vocTextPrimary)
                .cardStyle(cornerRadius: 10)
        }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(Color.vocTextSecondary)
    }

    private var startQuizButton: some View {
        Button(action: startQuiz) {
            Label("Start Quiz", systemImage: "play.fill")
        }
        .buttonStyle(FilledButtonStyle(color: .vocAccentGreen))
        .disabled(vocabularyManager.vocabulary.isEmpty)
        .hint("Add vocabulary first", isVisible: vocabularyManager.vocabulary.isEmpty)
    }

    private var quizControlButtons: some View {
        HStack(spacing: 20) {
            Button(action: vocabularyManager.revealTranslation) {
                Label("Translation", systemImage: "arrow.left.to.line.alt")
            }
            .buttonStyle(FilledButtonStyle(color: .vocPrimaryBlue))

            Button(action: vocabularyManager.showNextWord) {
                Label("Next Word", systemImage: "arrow.right")
            }
            .buttonStyle(FilledButtonStyle(color: .vocAccentGreen))
        }
    }

    // MARK: - Actions

    private func showFormOnDisplay() {
        guard isFormComplete else { return }
        bleManager.showOnDisplay(line1: trimmedWord, line2: trimmedTranslation, line3: trimmedSentence)
    }

    private func saveEntry() {
        guard isFormComplete else { return }

        vocabularyManager.addEntry(word: trimmedWord, translation: trimmedTranslation, sentence: trimmedSentence)
        resetForm()
    }

    private func resetForm() {
        word = ""
        translation = ""
        sentence = ""
    }

    private func startQuiz() {
        // The first time, explain the quiz. The instructions sheet starts it.
        guard hasSeenQuizInstructions else {
            hasSeenQuizInstructions = true
            showingQuizInstructions = true
            return
        }

        vocabularyManager.startQuiz()

        if !bleManager.isConnected {
            NotificationService.shared.show(
                title: "App-Only Quiz Mode",
                body: "Quiz started without E-ink display. Use the app interface to navigate."
            )
        }
    }
}

// MARK: - Quiz Instructions

struct QuizInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VocabularyManager.self) private var vocabularyManager
    @Environment(BLEManager.self) private var bleManager

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vocPrimaryBackground
                    .ignoresSafeArea()

                VStack(spacing: 25) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 70))
                        .foregroundStyle(Color.vocPrimaryBlue)
                        .padding()

                    Text("Vocabulary Quiz Mode")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.vocTextPrimary)

                    Text("How it works:")
                        .font(.headline)
                        .foregroundStyle(Color.vocTextPrimary)
                        .padding(.top)

                    VStack(alignment: .leading, spacing: 20) {
                        if bleManager.isConnected {
                            instructionRow(number: 1, text: "The word appears on the E-ink display")
                            instructionRow(number: 2, text: "Try to recall the translation")
                            instructionRow(number: 3, text: "Turn the knob left to reveal the translation and example sentence")
                            instructionRow(number: 4, text: "Turn the knob right to move to the next word")
                            instructionRow(number: 5, text: "Press the knob to stop the quiz")
                        } else {
                            instructionRow(number: 1, text: "The word appears in the app interface")
                            instructionRow(number: 2, text: "Try to recall the translation")
                            instructionRow(number: 3, text: "Tap the 'Translation' button to reveal the translation and example")
                            instructionRow(number: 4, text: "Tap the 'Next Word' button to continue to the next word")
                        }
                    }
                    .padding()
                    .cardStyle(cornerRadius: 15)
                    .padding(.horizontal)

                    Spacer()

                    Button("Start Quiz Now") {
                        dismiss()
                        vocabularyManager.startQuiz()
                    }
                    .buttonStyle(FilledButtonStyle(color: .vocPrimaryBlue))
                    .padding(.horizontal, 40)
                    .padding(.bottom, 20)
                }
                .padding()
            }
            .navigationTitle("Quiz Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            Text("\(number)")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.vocPrimaryBlue, in: .circle)

            Text(text)
                .font(.body)
                .foregroundStyle(Color.vocTextPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Dictionary

struct VocabularyDictionaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VocabularyManager.self) private var vocabularyManager
    @Environment(BLEManager.self) private var bleManager
    @State private var searchText = ""
    @State private var editingEntry: VocabularyEntry?

    private var filteredEntries: [VocabularyEntry] {
        let entries = vocabularyManager.entriesNewestFirst
        guard !searchText.isEmpty else { return entries }

        return entries.filter { entry in
            entry.word.localizedCaseInsensitiveContains(searchText) ||
            entry.translation.localizedCaseInsensitiveContains(searchText) ||
            entry.sentence.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vocPrimaryBackground
                    .ignoresSafeArea()

                if vocabularyManager.vocabulary.isEmpty {
                    emptyDictionaryView
                } else {
                    let entries = filteredEntries
                    List {
                        ForEach(entries) { entry in
                            dictionaryEntryRow(entry)
                                .listRowBackground(Color.vocCardBackground)
                        }
                        .onDelete { offsets in
                            // The offsets index into the filtered, sorted list, so map them to IDs first.
                            vocabularyManager.deleteEntries(withIDs: Set(offsets.map { entries[$0].id }))
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .searchable(text: $searchText, prompt: "Search vocabulary")
            .navigationTitle("Vocabulary Dictionary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        vocabularyManager.startQuiz()
                        dismiss()
                    } label: {
                        Label("Quiz", systemImage: "play.fill")
                    }
                    .disabled(vocabularyManager.vocabulary.isEmpty)
                }
            }
            .sheet(item: $editingEntry) { entry in
                EditVocabularyView(entry: entry)
            }
        }
    }

    private var emptyDictionaryView: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 70))
                .foregroundStyle(Color.vocTextSecondary.opacity(0.7))
                .padding()

            Text("Your Dictionary is Empty")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(Color.vocTextSecondary)

            Text("Add vocabulary entries by entering words and translations on the main screen")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.vocTextSecondary)
                .padding(.horizontal, 40)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dictionaryEntryRow(_ entry: VocabularyEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.word)
                    .font(.headline)
                    .foregroundStyle(Color.vocTextPrimary)

                Text(entry.translation)
                    .font(.subheadline)
                    .foregroundStyle(Color.vocTextSecondary)

                if !entry.sentence.isEmpty {
                    Text(entry.sentence)
                        .font(.caption)
                        .foregroundStyle(Color.vocSecondaryPurple)
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                if let lastReview = entry.lastReviewDate, entry.reviewCount > 0 {
                    Label {
                        Text("Reviews: \(entry.reviewCount) | Last: \(lastReview.formatted(date: .numeric, time: .omitted))")
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(Color.vocTextSecondary.opacity(0.7))
                }
            }

            Spacer()

            rowButton(systemImage: "pencil", color: .vocSecondaryPurple, label: "Edit") {
                editingEntry = entry
            }
            .padding(.trailing, 8)

            rowButton(
                systemImage: bleManager.isConnected ? "display" : "display.trianglebadge.exclamationmark",
                color: .vocPrimaryBlue,
                isDimmed: !bleManager.isConnected,
                label: "Show on display"
            ) {
                show(entry)
            }
        }
        .padding(.vertical, 8)
    }

    private func rowButton(systemImage: String, color: Color, isDimmed: Bool = false, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .foregroundStyle(color.opacity(isDimmed ? 0.3 : 1))
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1), in: .circle)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }

    private func show(_ entry: VocabularyEntry) {
        if bleManager.isConnected {
            bleManager.showOnDisplay(line1: entry.word, line2: entry.translation, line3: entry.sentence)
        } else {
            NotificationService.shared.show(
                title: "Device Not Connected",
                body: "Connect an E-ink display to show vocabulary"
            )
        }
        dismiss()
    }
}

// MARK: - Edit Entry

struct EditVocabularyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VocabularyManager.self) private var vocabularyManager
    let entry: VocabularyEntry

    @State private var word: String
    @State private var translation: String
    @State private var sentence: String

    init(entry: VocabularyEntry) {
        self.entry = entry
        _word = State(initialValue: entry.word)
        _translation = State(initialValue: entry.translation)
        _sentence = State(initialValue: entry.sentence)
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Word") {
                    TextField("Word", text: $word)
                }

                Section("Translation") {
                    TextField("Translation", text: $translation)
                }

                Section("Example Sentence") {
                    TextField("Sentence (optional)", text: $sentence)
                }
            }
            .navigationTitle("Edit Vocabulary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        vocabularyManager.updateEntry(
                            id: entry.id,
                            word: trimmed(word),
                            translation: trimmed(translation),
                            sentence: trimmed(sentence)
                        )
                        dismiss()
                    }
                    .disabled(trimmed(word).isEmpty || trimmed(translation).isEmpty)
                }
            }
        }
    }
}
