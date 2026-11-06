import AppKit
import Foundation
import Testing
@testable import Orchard

@MainActor
struct UpdaterTests {
    @Test func parsesReleaseTags() throws {
        let version = try #require(AppVersion(tag: "v1.0.6(7)"))
        #expect(version.components == [1, 0, 6])
        #expect(version.build == 7)
        #expect(version.description == "1.0.6 (7)")
        #expect(AppVersion(tag: "1.2")?.components == [1, 2])
        #expect(AppVersion(tag: "1.2")?.build == 0)
        #expect(AppVersion(tag: "v1.x(3)") == nil)
        #expect(AppVersion(tag: "v1.0(abc)") == nil)
        #expect(AppVersion(tag: "") == nil)
    }

    @Test func comparesMarketingVersionThenBuild() throws {
        func v(_ tag: String) throws -> AppVersion { try #require(AppVersion(tag: tag)) }
        #expect(try v("v1.0.10(1)") > v("v1.0.9(50)"))
        #expect(try v("v1.0.6(8)") > v("v1.0.6(7)"))
        #expect(try v("v2.0(1)") > v("v1.9.9(99)"))
        #expect(try v("1.0") == v("1.0.0"))
        #expect(try !(v("v1.0.6(7)") > v("v1.0.6(7)")))
    }

    @Test func offersOnlyNewerReleases() throws {
        let current = try #require(AppVersion(tag: "v1.0.6(7)"))
        let newer = try #require(AppVersion(tag: "v1.0.7(8)"))
        let older = try #require(AppVersion(tag: "v1.0.5(9)"))
        #expect(Updater.isNewer(newer, than: current))
        #expect(!Updater.isNewer(current, than: current))
        #expect(!Updater.isNewer(older, than: current))
        // Not a bundled app (swift run): any release is worth pointing at.
        #expect(Updater.isNewer(current, than: nil))
    }

    @Test func localBuildsAreComparedByMarketingVersionOnly() throws {
        // build-app.sh without BUILD_NUMBER stamps build 1.
        let local = try #require(AppVersion(tag: "v1.0.7(1)"))
        let sameRelease = try #require(AppVersion(tag: "v1.0.7(42)"))
        let nextRelease = try #require(AppVersion(tag: "v1.0.8(43)"))
        #expect(!Updater.isNewer(sameRelease, than: local))
        #expect(Updater.isNewer(nextRelease, than: local))
    }

    @Test func alertButtonsReportWhichWasClicked() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(sampleJSON.utf8))
        var responses: [NSApplication.ModalResponse] = []
        for index in 0..<3 {
            let alert = Updater.makeAlert(for: release, current: nil, canInstall: true, busy: false)
            AlertPresenter.show(alert, display: false) { responses.append($0) }
            alert.buttons[index].performClick(nil)
        }
        #expect(responses == [.alertFirstButtonReturn, .alertSecondButtonReturn, .alertThirdButtonReturn])
    }

    @Test func swapScriptRestoresTheOldAppWhenTheCopyFails() async throws {
        let dir = try TemporaryDirectory()
        let installed = try makeApp(in: dir, version: "1.0.6", build: "7")
        let work = dir.url.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let missing = work.appendingPathComponent("Orchard.app")  // ditto fails: nothing to copy.

        try Updater.relaunch(replacing: installed, with: missing, opener: "/usr/bin/true", waitingFor: 999_999)
        for _ in 0..<50 where FileManager.default.fileExists(atPath: work.path) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!FileManager.default.fileExists(atPath: work.path))
        let plist = try #require(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0.6")
    }

    @Test func failedDownloadsLeaveNoTemporaryFiles() async throws {
        let dir = try TemporaryDirectory()
        try dir.write("not-a.dmg", "nope")
        func leftovers() throws -> Set<String> {
            Set(try FileManager.default.contentsOfDirectory(atPath: FileManager.default.temporaryDirectory.path)
                .filter { $0.hasPrefix("OrchardUpdate-") })
        }
        let before = try leftovers()
        await #expect(throws: (any Error).self) {
            try await Updater.download(dir.url.appendingPathComponent("not-a.dmg"), expecting: nil)
        }
        #expect(try leftovers() == before)
    }

    @Test func readsTheCurrentVersionFromInfoPlist() throws {
        let dir = try TemporaryDirectory()
        let app = try makeApp(in: dir, version: "1.0.6", build: "7")
        let bundle = try #require(Bundle(url: app))
        let version = try #require(AppVersion.current(bundle: bundle))
        #expect(version == AppVersion(tag: "v1.0.6(7)"))
    }

    @Test func decodesGitHubReleases() throws {
        let release = try JSONDecoder().decode(Release.self, from: Data(sampleJSON.utf8))
        #expect(release.version == AppVersion(tag: "v1.0.7(8)"))
        #expect(release.dmg?.name == "Orchard-1.0.7-8.dmg")
        #expect(release.notes == "• Add update checks by @someone (#11)")
    }

    @Test func validatesTheDownloadedApp() throws {
        let dir = try TemporaryDirectory()
        let app = try makeApp(in: dir, version: "1.0.7", build: "8")
        try Updater.validate(app, expecting: AppVersion(tag: "v1.0.7(8)"))
        #expect(throws: UpdateError.self) { try Updater.validate(app, expecting: AppVersion(tag: "v1.0.8(9)")) }
        let other = try makeApp(in: dir, name: "Other", identifier: "com.example.Other", version: "1.0.7", build: "8")
        #expect(throws: UpdateError.self) { try Updater.validate(other, expecting: nil) }
    }

    @Test func swapScriptReplacesTheAppAfterOrchardQuits() async throws {
        let dir = try TemporaryDirectory()
        let installed = try makeApp(in: dir, version: "1.0.6", build: "7")
        let work = dir.url.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let staged = try makeApp(in: dir, subfolder: "work", version: "1.0.7", build: "8")

        // Stand in for Orchard with a process that runs until we stop it: the script must wait.
        let orchard = Process()
        orchard.executableURL = URL(fileURLWithPath: "/bin/sleep")
        orchard.arguments = ["60"]
        try orchard.run()

        try Updater.relaunch(replacing: installed, with: staged, opener: "/usr/bin/true",
                             waitingFor: orchard.processIdentifier)
        try await Task.sleep(for: .milliseconds(300))
        let stillOld = try #require(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")))
        #expect(stillOld["CFBundleShortVersionString"] as? String == "1.0.6")
        orchard.terminate()

        for _ in 0..<50 where FileManager.default.fileExists(atPath: work.path) {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!FileManager.default.fileExists(atPath: work.path))
        let plist = try #require(NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist")))
        #expect(plist["CFBundleShortVersionString"] as? String == "1.0.7")
    }

    /// Downloads the latest real release and stages its app: `ORCHARD_NETWORK_TESTS=1 swift test --filter Updater`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORCHARD_NETWORK_TESTS"] != nil))
    func downloadsAndStagesTheLatestRelease() async throws {
        let release = try await Updater.fetchLatest()
        let dmg = try #require(release.dmg)
        let staged = try await Updater.download(dmg.browserDownloadURL, expecting: release.version)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        #expect(FileManager.default.fileExists(atPath: staged.appendingPathComponent("Contents/MacOS/Orchard").path))
    }

    /// Writes PR description screenshots of the update alert alongside the window's.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ORCHARD_SCREENSHOTS"] != nil))
    func screenshots() throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ORCHARD_SCREENSHOTS"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let release = try JSONDecoder().decode(Release.self, from: Data(sampleJSON.utf8))
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let alert = Updater.makeAlert(for: release, current: AppVersion(tag: "v1.0.6(7)"),
                                          canInstall: true, busy: false)
            // Lay the panel out without ordering it in: AppKit would pull it onto the screen.
            alert.window.appearance = NSAppearance(named: appearance)
            alert.layout()
            let view = try #require(alert.window.contentView)
            view.layoutSubtreeIfNeeded()
            #expect(!alert.window.isVisible)
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!
                .write(to: directory.appendingPathComponent("update-available-\(name).png"))
        }
    }

    private let sampleJSON = """
        {
          "tag_name": "v1.0.7(8)",
          "html_url": "https://github.com/ambiapps/orchard/releases/tag/v1.0.7%288%29",
          "body": "## What's Changed\\r\\n* Add update checks by @someone in https://github.com/ambiapps/orchard/pull/11\\r\\n\\r\\n\\r\\n**Full Changelog**: https://github.com/ambiapps/orchard/compare/v1.0.6(7)...v1.0.7(8)",
          "assets": [
            {"name": "Orchard-1.0.7-8.dmg",
             "browser_download_url": "https://github.com/ambiapps/orchard/releases/download/v1.0.7%288%29/Orchard-1.0.7-8.dmg"}
          ]
        }
        """

    private func makeApp(in dir: TemporaryDirectory, subfolder: String? = nil, name: String = "Orchard",
                         identifier: String = "se.ambi.Orchard", version: String, build: String) throws -> URL {
        var parent = dir.url
        if let subfolder { parent = parent.appendingPathComponent(subfolder) }
        let app = parent.appendingPathComponent("\(name).app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: NSDictionary = [
            "CFBundleIdentifier": identifier,
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
        ]
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }
}
