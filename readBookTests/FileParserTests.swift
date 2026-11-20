//
//  FileParserTests.swift
//  readBook
//
//  不加入 App target。运行：
//  swiftc -O -o /tmp/fileparser-tests readBook/Models/Book.swift readBook/Services/FileParser.swift readBookTests/FileParserTests.swift
//  /tmp/fileparser-tests
//

import Foundation

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

private func utf16Length(_ text: String) -> Int {
    (text as NSString).length
}

private func assertLayout(_ chapters: [Chapter], fullLength: Int, label: String) {
    check(!chapters.isEmpty, "\(label) 章节为空")
    check(chapters[0].startOffset == 0, "\(label) 首章起点不是 0")
    for index in chapters.indices {
        let chapter = chapters[index]
        check(chapter.index == index, "\(label) index \(chapter.index) != \(index)")
        check(chapter.length >= 0, "\(label) 负长度 \(chapter.title)")
        check(chapter.length < 50_000, "\(label) \(chapter.title) length=\(chapter.length)")
        if index + 1 < chapters.count {
            let next = chapters[index + 1]
            check(
                chapter.startOffset + chapter.length == next.startOffset,
                "\(label) 区间不连续 \(index): \(chapter.startOffset)+\(chapter.length) != \(next.startOffset)"
            )
        }
    }
    let last = chapters[chapters.count - 1]
    check(last.startOffset + last.length == fullLength, "\(label) 未覆盖全文 \(last.startOffset + last.length) != \(fullLength)")
}

private func padded(_ title: String) -> String {
    title + "\n" + String(repeating: "文", count: 24) + "\n"
}

private func testEmptyFile() {
    do {
        _ = try FileParser.parse(data: Data(), fileName: "empty.txt")
        check(false, "空文件应抛错")
    } catch FileParserError.empty {
        return
    } catch {
        check(false, "空文件抛出了 \(error)")
    }
}

private func testMinimalSample() {
    // 原文「这里是番外内容第一段。」与下一标题起点相距 18（< 20），会被既有去重丢掉。补两个字让间隔达到 20。
    let text = """
    第1章都会说了
    坐在熟悉的5路公交车上，看着车窗外熟悉的街景。

    第2章裑心疲惫
    第二天早上醒来的时候，天已经大亮了。

    番外 1
    这里是番外内容第一段。补足

    番外 2
    这里是番外内容第二段。
    """
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 4, "最小样本章数 \(chapters.count) \(chapters.map(\.title))")
    check(chapters.map(\.title) == ["第1章都会说了", "第2章裑心疲惫", "番外 1", "番外 2"], "最小样本标题 \(chapters.map(\.title))")
    assertLayout(chapters, fullLength: utf16Length(text), label: "最小样本")
}

private func testFormattedRegression() {
    let text = padded("第1章 标题") + padded("第2章 下一章") + padded("Chapter 3 Title")
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.map(\.title) == ["第1章 标题", "第2章 下一章", "Chapter 3 Title"], "规范标题被改写 \(chapters.map(\.title))")
    assertLayout(chapters, fullLength: utf16Length(text), label: "规范书")
}

private func testSpecialTitlesAndSeparators() {
    let titles = [
        "第1章　全角空格",
        "第2章：冒号",
        "第3章、顿号",
        "第4章—破折号",
        "序章",
        "楔子一",
        "引子",
        "后记：完结",
        "尾声",
        "终章",
        "番外篇 2",
    ]
    let text = titles.map(padded).joined()
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.map(\.title) == titles, "特殊标题 \(chapters.map(\.title))")
    assertLayout(chapters, fullLength: utf16Length(text), label: "特殊标题")
}

private func testLongTitleIgnored() {
    let tooLong = "第1章" + String(repeating: "题", count: 38)
    check(tooLong.count == 41, "用例本身长度不是 41")
    let chapters = FileParser.detectChapters(in: tooLong + "\n正文")
    check(chapters.count == 1 && chapters[0].title == "正文", "超长标题被识别 \(chapters.map(\.title))")

    let exact = "第1章" + String(repeating: "题", count: 37)
    check(exact.count == 40, "40 字用例长度不对")
    let kept = FileParser.detectChapters(in: exact)
    check(kept.count == 1 && kept[0].title == exact, "40 字标题应保留 \(kept.map(\.title))")
}

private func testCloseTitlesDeduped() {
    let text = "第1章甲\n第2章乙\n后面是正文。"
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 1, "近距标题应只留 1 个，实际 \(chapters.map(\.title))")
    check(chapters[0].title == "第1章甲", "留下的不是前一个 \(chapters[0].title)")
    assertLayout(chapters, fullLength: utf16Length(text), label: "去重")
}

private func testSingleLine() {
    let plain = "只有一行没有换行"
    let plainChapters = FileParser.detectChapters(in: plain)
    check(plainChapters.count == 1, "无换行正文应是 1 章")
    assertLayout(plainChapters, fullLength: utf16Length(plain), label: "单行正文")

    let titled = "第1章只有一行"
    let titledChapters = FileParser.detectChapters(in: titled)
    check(titledChapters.count == 1 && titledChapters[0].title == titled, "无换行标题应是 1 章")
}

private func testNoChapterMarkersSplit() {
    let text = String(repeating: "字", count: 60_000)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 2, "无章节行应拆成 2 段，实际 \(chapters.count)")
    check(chapters.map(\.title) == ["正文 (1/2)", "正文 (2/2)"], "兜底标题 \(chapters.map(\.title))")
    check(chapters[0].length == 49_999, "硬切长度 \(chapters[0].length)")
    assertLayout(chapters, fullLength: utf16Length(text), label: "无章节硬切")
}

private func testBlankLineSplit() {
    let text = String(repeating: "字", count: 40_000) + "\n\n" + String(repeating: "字", count: 20_000)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 2, "空行切分章数 \(chapters.count)")
    check(chapters[0].length == 40_002, "应切在空行之后 \(chapters[0].length)")
    check(chapters.map(\.title) == ["正文 (1/2)", "正文 (2/2)"], "空行切分标题 \(chapters.map(\.title))")
    assertLayout(chapters, fullLength: utf16Length(text), label: "空行切分")
}

private func testOnlyOversizedChapterIsSplit() {
    let head = "第1章短章\n" + String(repeating: "短", count: 30) + "\n"
    let text = head + "第2章长章\n" + String(repeating: "长", count: 60_000)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters[0].title == "第1章短章", "短章不应加后缀 \(chapters[0].title)")
    check(chapters.count == 3, "只应拆长章 \(chapters.map(\.title))")
    check(chapters[1].title == "第2章长章 (1/2)" && chapters[2].title == "第2章长章 (2/2)", "长章后缀 \(chapters.map(\.title))")
    assertLayout(chapters, fullLength: utf16Length(text), label: "局部拆分")
}

private func testTitleBlankDoesNotCreateEmptyChapter() {
    let text = "第2章长章\n\n" + String(repeating: "长", count: 60_000)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 2, "标题后空行不应多切一章 \(chapters.map { "\($0.title):\($0.length)" })")
    check(chapters[0].length == 49_999, "应忽略标题后的空行并硬切 \(chapters[0].length)")
    check(chapters[0].length > ("第2章长章\n\n" as NSString).length, "第一段不应只剩标题")
    assertLayout(chapters, fullLength: utf16Length(text), label: "标题后空行")
}

private func testHardCutKeepsEmojiIntact() {
    let text = String(repeating: "字", count: 49_998) + "😀" + String(repeating: "字", count: 10_000)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters[0].length == 49_998, "硬切应退到 emoji 之前 \(chapters[0].length)")
    let ns = text as NSString
    let head = ns.substring(with: NSRange(location: 0, length: chapters[0].length))
    let tail = ns.substring(with: NSRange(location: chapters[1].startOffset, length: 2))
    check(!head.unicodeScalars.contains { $0.value == 0xFFFD }, "切口出现替换字符")
    check(tail == "😀", "下一段应以完整 emoji 开头，实际 \(tail)")
    assertLayout(chapters, fullLength: utf16Length(text), label: "emoji 硬切")
}

private func testFalsePositiveTitlesRejected() {
    let text = """
    第一节课结束后他回到宿舍
    第三回合他输了
    尾声渐渐消失在远处
    正文还在继续。
    """
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 1 && chapters[0].title == "正文", "正文被误判成标题 \(chapters.map(\.title))")

    let kept = FileParser.detectChapters(in: padded("第1回 旧事") + padded("第3节"))
    check(kept.map(\.title) == ["第1回 旧事", "第3节"], "带回分隔符或独占一行的标题应保留 \(kept.map(\.title))")
}

private func testBelowLimitStaysWhole() {
    let text = String(repeating: "字", count: 49_999)
    let chapters = FileParser.detectChapters(in: text)
    check(chapters.count == 1 && chapters[0].title == "正文", "未达上限不应拆 \(chapters.map(\.title))")
    check(chapters[0].length == 49_999, "长度被改写 \(chapters[0].length)")
}

private func testSyntheticPerformance() {
    var blocks: [String] = []
    blocks.reserveCapacity(250)
    for index in 1...250 {
        blocks.append("第\(index)章标题\n" + String(repeating: "文", count: 2_000) + "\n")
    }
    let text = blocks.joined()
    check(utf16Length(text) > 500_000, "性能样本不足 50 万字")
    let started = Date()
    let parsed = try? FileParser.parse(data: Data(text.utf8), fileName: "perf.txt")
    let elapsed = Date().timeIntervalSince(started)
    check(parsed != nil, "性能样本解析失败")
    check(elapsed < 2, "50 万字解析超时 \(elapsed)s")
    assertLayout(parsed!.chapters, fullLength: utf16Length(parsed!.fullText), label: "性能样本")
}

private func testRealBook() {
    let path = ("~/Downloads/妻如针，刺我心.txt" as NSString).expandingTildeInPath
    let data = FileManager.default.contents(atPath: path)
    check(data != nil, "找不到真实文件 \(path)")
    let started = Date()
    let parsed: ParsedBook
    do {
        parsed = try FileParser.parse(data: data!, fileName: "妻如针，刺我心.txt")
    } catch {
        check(false, "真实文件解析失败 \(error)")
        return
    }
    let elapsed = Date().timeIntervalSince(started)
    check(parsed.chapters.count == 337, "真实文件章数 \(parsed.chapters.count)，末章 \(parsed.chapters.last?.title ?? "")")
    check(parsed.chapters.first?.title == "第1章都会说了", "首章 \(parsed.chapters.first?.title ?? "")")
    let lastTitle = parsed.chapters.last?.title ?? ""
    check(lastTitle.contains("番外") && lastTitle.contains("45"), "末章 \(lastTitle)")
    assertLayout(parsed.chapters, fullLength: utf16Length(parsed.fullText), label: "真实文件")
    check(elapsed < 2, "真实文件解析超时 \(elapsed)s")
    print("真实文件: \(parsed.chapters.count) 章, 全文 \(utf16Length(parsed.fullText)) 字, \(String(format: "%.3f", elapsed))s, 末章 \(lastTitle)")
}

@main
struct FileParserTestRunner {
    static func main() {
        testEmptyFile()
        testMinimalSample()
        testFormattedRegression()
        testSpecialTitlesAndSeparators()
        testLongTitleIgnored()
        testCloseTitlesDeduped()
        testSingleLine()
        testNoChapterMarkersSplit()
        testBlankLineSplit()
        testOnlyOversizedChapterIsSplit()
        testTitleBlankDoesNotCreateEmptyChapter()
        testHardCutKeepsEmojiIntact()
        testFalsePositiveTitlesRejected()
        testBelowLimitStaysWhole()
        testSyntheticPerformance()
        testRealBook()
        print("ALL PASSED")
    }
}
