//
//  Process.swift
//  ControlRoom
//
//  Created by Dave DeLong on 2/14/20.
//  Copyright © 2020 Paul Hudson. All rights reserved.
//

import Foundation

extension Process {

    @available(*, deprecated, message: "Use the async version of execute instead")
    @objc static func execute(_ command: String, arguments: [String]) -> Data? {
        Self.execute(command, arguments: arguments, environmentOverrides: nil)
    }

    @available(*, deprecated, message: "Use the async version of execute instead")
    static func execute(_ command: String, arguments: [String], environmentOverrides: [String: String]? = nil) -> Data? {
        let task = Process()
        task.launchPath = command
        task.arguments = arguments

        if let environmentOverrides {
            var environment = ProcessInfo.processInfo.environment
            environment.merge(environmentOverrides) { (_, new) in new }
            task.environment = environment
        }

        let pipe = Pipe()
        task.standardOutput = pipe

        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return data
        } catch {
            return nil
        }
    }

    static func execute(_ command: String, arguments: [String], environmentOverrides: [String: String]? = nil) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let task = Process()
                task.launchPath = command
                task.arguments = arguments

                if let environmentOverrides {
                    var environment = ProcessInfo.processInfo.environment
                    environment.merge(environmentOverrides) { _, new in new }
                    task.environment = environment
                }

                let pipe = Pipe()
                task.standardOutput = pipe

                do {
                    try task.run()
                    task.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
