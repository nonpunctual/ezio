// IORegLoader.swift — Spawn ioreg or read stdin
import Foundation

enum LoaderError: Error, CustomStringConvertible {
    case processFailure(exitCode: Int32)
    case noData

    var description: String {
        switch self {
        case .processFailure(let code):
            return "ioreg exited with status \(code)"
        case .noData:
            return "ioreg returned no data"
        }
    }
}

func loadPlaneData(plane: String, stdinData: Data?) throws -> Data {
    if let data = stdinData {
        return data
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-a", "-l", "-p", plane]
    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()
    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw LoaderError.processFailure(exitCode: process.terminationStatus)
    }
    guard !data.isEmpty else {
        throw LoaderError.noData
    }
    return data
}
