import Foundation
import XCTest
@testable import AppHubCore

enum Fixtures {
    static var directory: URL {
        guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
            fatalError("Fixtures directory missing from test bundle")
        }
        return url
    }

    static func url(_ name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

func temporaryPaths() throws -> AppHubPaths {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("AppHubTests-\(UUID().uuidString)", isDirectory: true)
    let paths = AppHubPaths(root: root)
    try paths.prepare()
    return paths
}
