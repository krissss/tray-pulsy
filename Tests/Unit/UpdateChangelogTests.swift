import Testing

@testable import TrayPulsy

@Suite("UpdateChangelog")
struct UpdateChangelogTests {
    private let sample = """
    # Changelog

    ## [Unreleased]

    - Work in progress

    ## [1.3.0] - 2026-06-06

    ### Added

    - Floating metrics panel

    ## [1.2.0] - 2026-06-06

    ### Added

    - Online skin library

    ## [1.1.3] - 2026-05-14

    ### Fixed

    - Settings resource crash

    ## [1.1.2] - 2026-05-14

    ### Fixed

    - Settings sidebar crash
    """

    @Test("entries parses released versions and skips unreleased")
    func parseEntriesSkipsUnreleased() {
        let entries = UpdateChangelog.parseEntries(in: sample)

        #expect(entries.map(\.version) == ["1.3.0", "1.2.0", "1.1.3", "1.1.2"])
        #expect(entries.first?.date == "2026-06-06")
        #expect(entries.first?.body.contains("Floating metrics panel") == true)
    }

    @Test("entries returns every version between current and latest")
    func rangeIncludesIntermediateVersions() {
        let entries = UpdateChangelog.entries(in: sample, from: "1.1.3", through: "1.3.0")

        #expect(entries.map(\.version) == ["1.3.0", "1.2.0"])
    }

    @Test("version comparison handles v prefix and multi-digit components")
    func versionComparisonHandlesPrefixesAndMultiDigitComponents() {
        let markdown = """
        ## [1.10.0] - 2026-06-10

        - Newer

        ## [1.9.1] - 2026-06-09

        - Older
        """

        let entries = UpdateChangelog.entries(in: markdown, from: "v1.9.1", through: "v1.10.0")

        #expect(entries.map(\.version) == ["1.10.0"])
    }
}
