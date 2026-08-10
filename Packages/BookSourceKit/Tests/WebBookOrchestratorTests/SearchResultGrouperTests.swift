import XCTest
@testable import WebBookOrchestrator

final class SearchResultGrouperTests: XCTestCase {
    private func result(
        source: String, name: String, author: String? = "Author A", intro: String? = nil,
        lastChapter: String? = nil, coverUrl: String? = nil, wordCount: String? = nil
    ) -> SearchResult {
        SearchResult(
            bookSourceUrl: "https://\(source).example.com", bookSourceName: source, name: name, author: author,
            intro: intro, lastChapter: lastChapter, bookUrl: "https://\(source).example.com/book/1", coverUrl: coverUrl,
            wordCount: wordCount
        )
    }

    func testSameNameAndAuthorFromDifferentSourcesAreGroupedTogether() {
        let a = result(source: "SiteA", name: "凡人修仙传")
        let b = result(source: "SiteB", name: "凡人修仙传")

        let groups = SearchResultGrouper.merge([a], into: [])
        let merged = SearchResultGrouper.merge([b], into: groups)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sourceCount, 2)
        XCTAssertEqual(merged[0].entries.map(\.bookSourceName), ["SiteA", "SiteB"])
    }

    func testDifferentAuthorsWithSameTitleAreNotMerged() {
        let a = result(source: "SiteA", name: "Same Title", author: "Author One")
        let b = result(source: "SiteB", name: "Same Title", author: "Author Two")

        let groups = SearchResultGrouper.merge([a, b], into: [])

        XCTAssertEqual(groups.count, 2, "different authors under the same title must not be merged as if they were the same book")
    }

    func testNewBooksAreAppendedAfterExistingGroupsPreservingOrder() {
        let first = result(source: "SiteA", name: "Book One")
        let second = result(source: "SiteA", name: "Book Two")
        let firstAgain = result(source: "SiteB", name: "Book One")

        var groups = SearchResultGrouper.merge([first, second], into: [])
        groups = SearchResultGrouper.merge([firstAgain], into: groups)

        XCTAssertEqual(groups.map(\.name), ["Book One", "Book Two"], "existing group order must be preserved across merges")
        XCTAssertEqual(groups[0].sourceCount, 2)
        XCTAssertEqual(groups[1].sourceCount, 1)
    }

    func testIntroPrefersTheLongestAvailableAcrossSources() {
        let short = result(source: "SiteA", name: "Book", intro: "Short.")
        let long = result(source: "SiteB", name: "Book", intro: "A much longer and more detailed introduction.")

        let groups = SearchResultGrouper.merge([short, long], into: [])

        XCTAssertEqual(groups[0].intro, long.intro)
    }

    func testLastChapterAndCoverFallBackToFirstEntryThatHasOne() {
        let noExtras = result(source: "SiteA", name: "Book", lastChapter: nil, coverUrl: nil)
        let withExtras = result(source: "SiteB", name: "Book", lastChapter: "Chapter 5", coverUrl: "https://example.com/cover.jpg")

        let groups = SearchResultGrouper.merge([noExtras, withExtras], into: [])

        XCTAssertEqual(groups[0].lastChapter, "Chapter 5")
        XCTAssertEqual(groups[0].coverUrl, "https://example.com/cover.jpg")
    }

    func testNameAndAuthorWhitespaceIsTrimmedBeforeComparing() {
        let a = result(source: "SiteA", name: " 三体 ", author: " 刘慈欣")
        let b = result(source: "SiteB", name: "三体", author: "刘慈欣 ")

        let groups = SearchResultGrouper.merge([a, b], into: [])

        XCTAssertEqual(groups.count, 1, "whitespace differences alone shouldn't split what's really the same book")
    }

    func testWordCountFallsBackToFirstEntryThatHasOne() {
        let noWordCount = result(source: "SiteA", name: "Book", wordCount: nil)
        let withWordCount = result(source: "SiteB", name: "Book", wordCount: "120万字")

        let groups = SearchResultGrouper.merge([noWordCount, withWordCount], into: [])

        XCTAssertEqual(groups[0].wordCount, "120万字")
    }

    func testRankedBySourceCountPutsMultiSourceBooksFirstButKeepsOrderAmongTies() {
        let soloA = result(source: "SiteA", name: "Solo Book A")
        let soloB = result(source: "SiteA", name: "Solo Book B")
        let popularHit1 = result(source: "SiteA", name: "Popular Book")
        let popularHit2 = result(source: "SiteB", name: "Popular Book")

        // Arrival order: Solo A, Solo B, Popular (1 source so far) -- Popular only becomes
        // multi-source on a later merge, matching how results actually stream in live.
        var groups = SearchResultGrouper.merge([soloA, soloB, popularHit1], into: [])
        groups = SearchResultGrouper.merge([popularHit2], into: groups)

        let ranked = groups.rankedBySourceCount()

        XCTAssertEqual(ranked.map(\.name), ["Popular Book", "Solo Book A", "Solo Book B"])
        XCTAssertEqual(ranked[0].sourceCount, 2)
    }

    // MARK: - rankedByRelevance

    func testRankedByRelevancePutsExactTitleMatchFirstEvenWithFewerSources() {
        let exactSingleSource = result(source: "SiteA", name: "斗破")
        let popularButLooseMatch1 = result(source: "SiteA", name: "斗破苍穹后传")
        let popularButLooseMatch2 = result(source: "SiteB", name: "斗破苍穹后传")

        var groups = SearchResultGrouper.merge([exactSingleSource, popularButLooseMatch1], into: [])
        groups = SearchResultGrouper.merge([popularButLooseMatch2], into: groups)

        // Sanity check: by-source-count ranking would bury the exact single-source match.
        XCTAssertEqual(groups.rankedBySourceCount().map(\.name).first, "斗破苍穹后传")

        let ranked = groups.rankedByRelevance(query: "斗破")
        XCTAssertEqual(ranked.map(\.name).first, "斗破", "an exact single-source match should outrank a looser multi-source match")
    }

    func testRankedByRelevanceOrdersExactThenPrefixThenSubstringThenOther() {
        let exact = result(source: "SiteA", name: "斗破")
        let prefix = result(source: "SiteA", name: "斗破苍穹")
        let substring = result(source: "SiteA", name: "大话斗破往事")
        let unrelated = result(source: "SiteA", name: "完美世界")

        let groups = SearchResultGrouper.merge([unrelated, substring, prefix, exact], into: [])
        let ranked = groups.rankedByRelevance(query: "斗破")

        XCTAssertEqual(ranked.map(\.name), ["斗破", "斗破苍穹", "大话斗破往事", "完美世界"])
    }

    func testRankedByRelevanceBreaksTiesWithinATierBySourceCount() {
        let soloPrefix = result(source: "SiteA", name: "斗破前传")
        let popularPrefixHit1 = result(source: "SiteA", name: "斗破外传")
        let popularPrefixHit2 = result(source: "SiteB", name: "斗破外传")

        var groups = SearchResultGrouper.merge([soloPrefix, popularPrefixHit1], into: [])
        groups = SearchResultGrouper.merge([popularPrefixHit2], into: groups)

        let ranked = groups.rankedByRelevance(query: "斗破")
        XCTAssertEqual(ranked.map(\.name), ["斗破外传", "斗破前传"], "same relevance tier -- more sources should still win the tiebreak")
    }

    // MARK: - groupKey(name:author:)

    func testGroupKeyMatchesRegardlessOfWhitespace() {
        XCTAssertEqual(
            GroupedSearchResult.groupKey(name: " 三体 ", author: " 刘慈欣"),
            GroupedSearchResult.groupKey(name: "三体", author: "刘慈欣 ")
        )
    }

    func testGroupKeyTreatsNilAndEmptyAuthorTheSame() {
        XCTAssertEqual(
            GroupedSearchResult.groupKey(name: "Book", author: nil),
            GroupedSearchResult.groupKey(name: "Book", author: "")
        )
    }
}
