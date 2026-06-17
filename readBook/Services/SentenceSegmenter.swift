//
//  SentenceSegmenter.swift
//  readBook
//
//  将章节文本按中文标点切分为朗读句子，并记录章节内字符偏移。
//
//  ⚠️ 听书功能已暂停，见 BACKLOG.md。
//

#if false

import Foundation

struct AudioSentence: Identifiable, Hashable {
    let id: Int
    let text: String
    let spokenText: String
    /// 句子在章节内的起始字符偏移。
    let startOffset: Int
    /// 句子在章节内的结束字符偏移（不含）。
    let endOffset: Int
}

enum SentenceSegmenter {

    private static let primaryBreaks = CharacterSet(charactersIn: "。！？；：\n")
    private static let secondaryBreaks = CharacterSet(charactersIn: "，,")
    private static let maxSentenceLength = 200

    /// 从章节全文切分句子；`fromOffset` 起之后的句子也会被包含。
    static func sentences(in chapterText: String, fromOffset: Int = 0) -> [AudioSentence] {
        let all = segmentAll(chapterText)
        guard fromOffset > 0, !all.isEmpty else { return reindex(all) }
        let startIdx = sentenceIndex(for: fromOffset, in: all)
        return reindex(Array(all.dropFirst(startIdx)))
    }

    /// 根据章节内字符偏移定位应开始朗读的句子索引。
    static func sentenceIndex(for offset: Int, in sentences: [AudioSentence]) -> Int {
        guard !sentences.isEmpty else { return 0 }
        for (i, s) in sentences.enumerated() where offset < s.endOffset {
            return i
        }
        return max(0, sentences.count - 1)
    }

    private static func reindex(_ list: [AudioSentence]) -> [AudioSentence] {
        list.enumerated().map { i, s in
            AudioSentence(id: i, text: s.text, spokenText: s.spokenText, startOffset: s.startOffset, endOffset: s.endOffset)
        }
    }

    private static func segmentAll(_ chapterText: String) -> [AudioSentence] {
        let ns = chapterText as NSString
        guard ns.length > 0 else { return [] }

        var result: [AudioSentence] = []
        var nextId = 0
        var location = 0

        while location < ns.length {
            var end = location
            while end < ns.length {
                let scalar = UnicodeScalar(ns.character(at: end))!
                end += 1
                if primaryBreaks.contains(scalar) { break }
            }
            let chunk = ns.substring(with: NSRange(location: location, length: end - location))
            appendSentences(from: chunk, chapterStart: location, into: &result, nextId: &nextId)
            location = end
        }
        return result
    }

    private static func appendSentences(
        from chunk: String,
        chapterStart: Int,
        into result: inout [AudioSentence],
        nextId: inout Int
    ) {
        let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let nsChunk = chunk as NSString
        let trimRange = nsChunk.range(of: trimmed)
        let absBase = chapterStart + (trimRange.location != NSNotFound ? trimRange.location : 0)

        if trimmed.count <= maxSentenceLength {
            addSentence(trimmed, start: absBase, into: &result, nextId: &nextId)
            return
        }

        let nsTrim = trimmed as NSString
        var local = 0
        while local < nsTrim.length {
            var end = min(local + 1, nsTrim.length)
            while end < nsTrim.length {
                let scalar = UnicodeScalar(nsTrim.character(at: end))!
                end += 1
                let len = end - local
                if secondaryBreaks.contains(scalar) || len >= maxSentenceLength { break }
            }
            let sub = nsTrim.substring(with: NSRange(location: local, length: end - local))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !sub.isEmpty {
                let subRange = nsTrim.range(of: sub, options: [], range: NSRange(location: local, length: end - local))
                let offset = absBase + (subRange.location != NSNotFound ? subRange.location : local)
                addSentence(sub, start: offset, into: &result, nextId: &nextId)
            }
            local = end
        }
    }

    private static func addSentence(
        _ text: String,
        start: Int,
        into result: inout [AudioSentence],
        nextId: inout Int
    ) {
        let spoken = SpeechPreprocessor.prepare(text)
        guard !spoken.isEmpty else { return }
        let len = (text as NSString).length
        result.append(AudioSentence(
            id: nextId,
            text: text,
            spokenText: spoken,
            startOffset: start,
            endOffset: start + len
        ))
        nextId += 1
    }
}

#endif
