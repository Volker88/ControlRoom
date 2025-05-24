//
//  SimCtl.swift
//  ControlRoom
//
//  Created by Dave DeLong on 2/13/20.
//  Copyright © 2020 Paul Hudson. All rights reserved.
//

import Combine
import Foundation

/// A container for all the functionality for talking to simctl.
enum SimCtl: CommandLineCommandExecuter {
    typealias Error = CommandLineError

    static let launchPath = "/usr/bin/xcrun"

    static func watchDeviceList() -> AnyPublisher<DeviceList, SimCtl.Error> {
        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .setFailureType(to: SimCtl.Error.self)
            .flatMap { _ in return SimCtl.listDevices() }
            .prepend(SimCtl.listDevices())
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    static func listDeviceTypes() -> AnyPublisher<DeviceTypeList, SimCtl.Error> {
        executeJSON(.list(filter: .devicetypes, flags: [.json]))
    }

    static func listDevices() -> AnyPublisher<DeviceList, SimCtl.Error> {
        executeJSON(.list(filter: .devices, search: .available, flags: [.json]))
    }

    static func listRuntimes() -> AnyPublisher<RuntimeList, SimCtl.Error> {
        executeJSON(.list(filter: .runtimes, flags: [.json]))
    }

    static func listApplications(_ simulator: String) -> AnyPublisher<ApplicationsList, SimCtl.Error> {
        executePropertyList(.listApps(deviceId: simulator, flags: [.json]))
    }

    static func boot(_ simulator: Simulator) async {
        await SnapshotCtl.startSimulatorApp()
        _ = await execute(.boot(simulator: simulator))
    }

    static func shutdown(_ simulator: String) async {
        _ = await execute(.shutdown(.devices([simulator])))
    }

    static func setContentSize(_ simulator: String, contentSize: UI.ContentSizes) async {
        _ = await execute(.ui(deviceId: simulator, option: .contentSize(contentSize)))
    }

    static func reboot(_ simulator: Simulator) async {
        _ = await execute(.shutdown(.devices([simulator.udid])))
        _ = await execute(.boot(simulator: simulator))
    }

    static func erase(_ simulator: String) async {
        _ = await execute(.erase(.devices([simulator])))
    }

    static func clone(_ simulator: String, name: String) async {
        _ = await execute(.clone(deviceId: simulator, name: name))
    }

    static func create(name: String, deviceType: DeviceType, runtime: Runtime) async {
        _ = await execute(.create(name: name, deviceTypeId: deviceType.identifier, runtimeId: runtime.identifier))
    }

    static func rename(_ simulator: String, name: String) async {
        _ = await execute(.rename(deviceId: simulator, name: name))
    }

    static func overrideStatusBarBattery(_ simulator: String, level: Int, state: StatusBar.BatteryState) async {
        _ = await execute(.statusBar(deviceId: simulator, operation: .override([.batteryLevel(level), .batteryState(state)])))
    }

    static func overrideStatusBarWiFi(
        _ simulator: String,
        network: StatusBar.DataNetwork,
        wifiMode: StatusBar.WifiMode,
        wifiBars: StatusBar.WifiBars
    ) async {
        _ = await execute(.statusBar(deviceId: simulator, operation: .override([
            .dataNetwork(network),
            .wifiMode(wifiMode),
            .wifiBars(wifiBars)
        ])))
    }

    static func overrideStatusBarCellular(
        _ simulator: String,
        cellMode: StatusBar.CellularMode,
        cellBars: StatusBar.CellularBars,
        carrier: String
    ) async {
        _ = await execute(.statusBar(deviceId: simulator, operation: .override([
            .cellularMode(cellMode),
            .cellularBars(cellBars),
            .operatorName(carrier)
        ])))
    }

    static func clearStatusBarOverrides(_ simulator: String) async {
        _ = await execute(.statusBar(deviceId: simulator, operation: .clear))
    }

    static func overrideStatusBarTime(_ simulator: String, time: Date) async {
        // Use only time for now since ISO8601 parsing is broken since Xcode 15.3
        // https://stackoverflow.com/a/59071895
        // let timeString = ISO8601DateFormatter().string(from: time)
        let timeOnlyFormatter = DateFormatter()
        timeOnlyFormatter.dateFormat = "hh:mm"
        let timeString = timeOnlyFormatter.string(from: time)

        _ = await execute(.statusBar(deviceId: simulator, operation: .override([.time(timeString)])))
    }

    static func setAppearance(_ simulator: String, appearance: UI.Appearance) async {
        _ = await execute(.ui(deviceId: simulator, option: .appearance(appearance)))
    }

    static func setLogging(_ simulator: Simulator, enableLogging: Bool) async {
        UserDefaults.standard.set(enableLogging, forKey: "\(simulator.udid).logging")
        _ = await execute(.setLogging(deviceTypeId: simulator.udid, enableLogging: enableLogging))
        _ = await execute(.shutdown(.devices([simulator.udid])))
        _ = await execute(.boot(simulator: simulator))
    }

    static func getLogs(_ simulator: String) {
        let source = """
                            tell application "Terminal"
                                activate
                                do script "xcrun simctl diagnose && exit"
                            end tell
                      """
        if let script = NSAppleScript(source: source) {
            var error: NSDictionary?
            script.executeAndReturnError(&error)
            if let error {
                print(error)
            }
        }
    }

    static func triggeriCloudSync(_ simulator: String) async {
        _ = await execute(.icloudSync(deviceId: simulator))
    }

    static func copyPasteboardToMac(_ simulator: String) async {
        _ = await execute(.pbsync(source: .deviceId(simulator), destination: .host))
    }

    static func copyPasteboardToSimulator(_ simulator: String) async {
        _ = await execute(.pbsync(source: .host, destination: .deviceId(simulator)))
    }

    static func saveScreenshot(
        _ simulator: String,
        to file: String,
        type: IO.ImageFormat? = nil,
        display: IO.Display? = nil,
        with mask: IO.Mask? = nil,
        completion: @escaping (Result<Data, CommandLineError>) -> Void
    ) {
        execute(.io(deviceId: simulator, operation: .screenshot(type: type, display: display, mask: mask, url: file)), completion: completion)
    }

    static func startVideo(
        _ simulator: String,
        to file: String,
        type: IO.Codec? = nil,
        display: IO.Display? = nil,
        with mask: IO.Mask? = nil
    ) -> Process {
        executeAsync(.io(deviceId: simulator, operation: .recordVideo(codec: type, display: display, mask: mask, force: true, url: file)))
    }

    static func delete(_ simulators: Set<String>) async {
        _ = await execute(.delete(.devices(Array(simulators))))

        if let simulator = simulators.first {
            SnapshotCtl.deleteAllSnapshots(deviceId: simulator)
        }
    }

    static func uninstall(_ simulator: String, appID: String) async {
        _ = await execute(.uninstall(deviceId: simulator, appBundleId: appID))
    }

    static func launch(_ simulator: String, appID: String) async {
        _ = await execute(.launch(deviceId: simulator, appBundleId: appID))
    }

    static func terminate(_ simulator: String, appID: String) async {
        _ = await execute(.terminate(deviceId: simulator, appBundleId: appID))
    }

    static func restart(_ simulator: String, appID: String) async {
        await terminate(simulator, appID: appID)
        await launch(simulator, appID: appID)
    }

    static func sendPushNotification(_ simulator: String, appID: String, jsonPayload: String) async {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileName = "\(UUID().uuidString).json"
        let tempFile = tempDirectory.appendingPathComponent(fileName)
        do {
            try jsonPayload.write(to: tempFile, atomically: true, encoding: .utf8)

            _ = await execute(.push(deviceId: simulator, appBundleId: appID, json: .path(tempFile.path)))
            try? FileManager.default.removeItem(at: tempFile)
        } catch {
            print("Cannot write json payload to \(tempFile.path)")
        }
    }

    static func openURL(_ simulator: String, URL: String) async {
        _ = await execute(.openURL(deviceId: simulator, url: URL))
    }

    static func addRootCertificate(_ simulator: String, filePath: String) async {
        _ = await execute(.keychain(deviceId: simulator, action: .addRootCert(path: filePath)))
    }

    static func grantPermission(_ simulator: String, appID: String, permission: Privacy.Permission) async {
        _ = await execute(.privacy(deviceId: simulator, action: .grant, service: permission, appBundleId: appID))
    }

    static func revokePermission(_ simulator: String, appID: String, permission: Privacy.Permission) async {
        _ = await execute(.privacy(deviceId: simulator, action: .revoke, service: permission, appBundleId: appID))
    }

    static func resetPermission(_ simulator: String, appID: String, permission: Privacy.Permission) async {
        _ = await execute(.privacy(deviceId: simulator, action: .reset, service: permission, appBundleId: appID))
    }

    static func getAppContainer(_ simulator: String, appID: String) async -> URL? {
        let result = await execute(.getAppContainer(deviceId: simulator, appBundleID: appID))

        switch result {
        case .success(let data):
            if let path = String(data: data, encoding: .utf8) {
                let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)

                return URL(fileURLWithPath: trimmed)
            } else {
                return nil
            }
        case .failure:
            return nil
        }
    }
}
