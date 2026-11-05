import Foundation
import Testing
@testable import Orchard

struct XcodeTests {
    @Test func findsContainersWorkspacesFirstThenShallowest() throws {
        let repo = try TemporaryDirectory()
        try repo.makeDirectories(
            "App.xcodeproj/project.xcworkspace",
            "App.xcworkspace",
            "Modules/Feature/Feature.xcodeproj",
            "Pods/Pods.xcodeproj",
            ".build/checkouts/Dep/Dep.xcodeproj",
            "a/b/c/d/TooDeep.xcodeproj"
        )
        try repo.write("Package.swift", "")

        #expect(Xcode.findContainers(in: repo.url) == [
            "App.xcworkspace",
            "App.xcodeproj",
            "Modules/Feature/Feature.xcodeproj",
            "",
        ])
    }

    @Test func productsDirectoryFollowsXcodeLayout() {
        let derivedData = URL(fileURLWithPath: "/DD")
        #expect(Xcode.productsDirectory(derivedData: derivedData, configuration: "Debug", platform: .iOS).path
            == "/DD/Build/Products/Debug-iphoneos")
        #expect(Xcode.productsDirectory(derivedData: derivedData, configuration: "Beta", platform: .iOSSimulator).path
            == "/DD/Build/Products/Beta-iphonesimulator")
        #expect(Xcode.productsDirectory(derivedData: derivedData, configuration: "Debug", platform: .macOS).path
            == "/DD/Build/Products/Debug")
    }

    @Test func findsTheOnlyBuiltApp() throws {
        let products = try TemporaryDirectory()
        #expect(Xcode.builtApp(in: products.url.appendingPathComponent("Missing")) == nil)

        try products.makeDirectories("Phone.app", "Widget.appex", "Phone.app.dSYM")
        #expect(Xcode.builtApp(in: products.url) == nil) // no Info.plist
        try plist(bundleID: "com.example.phone", at: products.url.appendingPathComponent("Phone.app/Info.plist"))
        let phone = try #require(Xcode.builtApp(in: products.url))
        #expect(phone.appURL.lastPathComponent == "Phone.app")
        #expect(phone.bundleIdentifier == "com.example.phone")

        try products.makeDirectories("Other.app")
        #expect(Xcode.builtApp(in: products.url) == nil) // ambiguous

        let mac = try TemporaryDirectory()
        try mac.makeDirectories("Mac.app/Contents")
        try plist(bundleID: "com.example.mac", at: mac.url.appendingPathComponent("Mac.app/Contents/Info.plist"))
        #expect(Xcode.builtApp(in: mac.url)?.bundleIdentifier == "com.example.mac")
    }

    private func plist(bundleID: String, at url: URL) throws {
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0)
        try data.write(to: url)
    }

    @Test func containerDisplayName() {
        #expect(Xcode.displayName(forContainer: nil) == "Package.swift")
        #expect(Xcode.displayName(forContainer: "") == "Package.swift")
        #expect(Xcode.displayName(forContainer: "App.xcodeproj") == "App.xcodeproj")
    }
}
