//
//  SpeechPreprocessor.swift
//  readBook
//
//  TTS 发音前文本清洗：去 HTML/URL、数字转中文、过滤英文与特殊符号。
//
//  ⚠️ 听书功能已暂停，见 BACKLOG.md。
//

#if false

import Foundation

enum SpeechPreprocessor {

    private static let digitMap: [Character: String] = [
        "0": "零", "1": "一", "2": "二", "3": "三", "4": "四",
        "5": "五", "6": "六", "7": "七", "8": "八", "9": "九"
    ]

    /// 将原始句子转为适合 AVSpeech 朗读的文本。
    static func prepare(_ raw: String) -> String {
        var text = raw
        text = stripHTML(from: text)
        text = stripURLs(from: text)
        text = convertNumbers(in: text)
        text = stripEnglishWords(from: text)
        text = filterSpecialSymbols(from: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHTML(from text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private static func stripURLs(from text: String) -> String {
        text.replacingOccurrences(
            of: #"https?://[^\s]+|www\.[^\s]+"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func convertNumbers(in text: String) -> String {
        var result = ""
        var digitBuffer = ""

        func flushDigits() {
            guard !digitBuffer.isEmpty else { return }
            for ch in digitBuffer {
                result += digitMap[ch] ?? String(ch)
            }
            digitBuffer = ""
        }

        for ch in text {
            if ch.isNumber {
                digitBuffer.append(ch)
            } else {
                flushDigits()
                result.append(ch)
            }
        }
        flushDigits()
        return result
    }

    /// 连续英文字母替换为空格，避免 TTS 逐字母朗读。
    private static func stripEnglishWords(from text: String) -> String {
        text.replacingOccurrences(of: "[A-Za-z]+", with: " ", options: .regularExpression)
    }

    private static func filterSpecialSymbols(from text: String) -> String {
        let removeSet = CharacterSet(charactersIn: "——……【】（）()[]{}<>《》「」『』\"'`*#@&|\\")
        return text.unicodeScalars
            .filter { !removeSet.contains($0) }
            .map { String($0) }
            .joined()
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
    }
}

#endif
