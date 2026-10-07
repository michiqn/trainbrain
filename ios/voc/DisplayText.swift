//
//  DisplayText.swift
//  voc
//

import Foundation

/// Formats text so it fits the firmware's characteristic buffers.
///
/// The limits are in UTF-8 bytes, not characters: umlauts like "ä" take two bytes,
/// so counting characters could overflow the buffers on the device.
enum DisplayText {
    /// Maximum bytes for line 1 and line 2.
    static let maxLineBytes = 32
    /// Maximum bytes for line 3 (example sentence).
    static let maxSentenceBytes = 100

    /// Cuts `text` so its UTF-8 encoding fits into `maxBytes`, without splitting a character.
    static func fitting(_ text: String, maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }

        var result = ""
        var byteCount = 0
        for character in text {
            let characterBytes = character.utf8.count
            guard byteCount + characterBytes <= maxBytes else { break }
            result.append(character)
            byteCount += characterBytes
        }
        return result
    }

    /// Like `fitting(_:maxBytes:)`, but cuts at the last word boundary and appends "...".
    static func sentenceFitting(_ text: String, maxBytes: Int = maxSentenceBytes) -> String {
        guard text.utf8.count > maxBytes else { return text }

        let ellipsis = "..."
        let prefix = fitting(text, maxBytes: maxBytes - ellipsis.utf8.count)
        let wordAligned = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? prefix
        return wordAligned + ellipsis
    }
}
