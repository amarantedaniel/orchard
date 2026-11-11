import Foundation
import Testing
@testable import Orchard

struct DeviceDiscoveryTests {
    private func device(_ name: String, _ kind: DeviceKind) -> Device {
        let platform: BuildPlatform = switch kind {
        case .thisMac: .macOS
        case .physical: .iOS
        case .simulator: .iOSSimulator
        }
        return Device(id: name, name: name, model: name, kind: kind, platform: platform, osVersion: "27.0")
    }

    private func row(_ name: String, _ kind: DeviceKind, connected: Bool) -> DiscoveredDevice {
        DiscoveredDevice(device: device(name, kind), isConnected: connected)
    }

    @Test func enabledDevicesComeFirstThenAvailable() {
        let discovered = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("iPhone C", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
            row("Sim B", .simulator, connected: true),
        ]
        let selected = [device("Sim B", .simulator), device("Missing", .physical), device("iPhone C", .physical)]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: selected).map(\.device.name)
        #expect(names == ["Sim B", "iPhone C", "Missing", "Mac", "iPhone A", "Sim A", "iPhone B"])
    }

    @Test func availableDevicesComeFirstWhenNoneEnabled() {
        let discovered = [
            row("Mac", .thisMac, connected: true),
            row("iPhone A", .physical, connected: true),
            row("iPhone B", .physical, connected: false),
            row("iPhone C", .physical, connected: false),
            row("Sim A", .simulator, connected: true),
        ]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: []).map(\.device.name)
        #expect(names == ["Mac", "iPhone A", "Sim A", "iPhone B", "iPhone C"])
    }

    @Test func selectedDiscoveredDeviceIsNotListedTwice() {
        let discovered = [row("Mac", .thisMac, connected: true), row("iPhone A", .physical, connected: true)]
        let selected = [device("iPhone A", .physical)]
        let names = DeviceDiscovery.listRows(discovered: discovered, selected: selected).map(\.device.name)
        #expect(names == ["iPhone A", "Mac"])
    }

    @Test func readsPairedPhysicalDevicesWithTheirHardwareUDID() {
        func entry(_ id: String, udid: String, reality: String, pairing: String, tunnel: String) -> String {
            #"""
            {"identifier":"\#(id)","connectionProperties":{"pairingState":"\#(pairing)","tunnelState":"\#(tunnel)"},
             "deviceProperties":{"name":"\#(id)","osVersionNumber":"27.0"},
             "hardwareProperties":{"platform":"iOS","reality":"\#(reality)","marketingName":"iPhone 17","udid":"\#(udid)"}}
            """#
        }
        let json = #"""
        {"result":{"devices":[\#([
            entry("Offline", udid: "00008110-AAAA", reality: "physical", pairing: "paired", tunnel: "disconnected"),
            entry("Sim", udid: "Sim", reality: "simulated", pairing: "paired", tunnel: "connected"),
            entry("Unpaired", udid: "00008110-BBBB", reality: "physical", pairing: "unpaired", tunnel: "connected"),
            entry("Online", udid: "00008110-CCCC", reality: "physical", pairing: "paired", tunnel: "connected"),
        ].joined(separator: ","))]}}
        """#
        let devices = DeviceDiscovery.physicalDevices(fromDeviceCtl: Data(json.utf8))
        #expect(devices.map(\.id) == ["Online", "Offline"])
        #expect(devices.map(\.device.udid) == ["00008110-CCCC", "00008110-AAAA"])
        #expect(devices.map(\.isConnected) == [true, false])
    }

    @Test func keepsOrderWhenAllAvailable() {
        let discovered = [row("Mac", .thisMac, connected: true), row("Sim B", .simulator, connected: true)]
        #expect(DeviceDiscovery.listRows(discovered: discovered, selected: []).map(\.device.name) == ["Mac", "Sim B"])
    }
}
