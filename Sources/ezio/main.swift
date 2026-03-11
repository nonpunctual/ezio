// main.swift — CLI entry point
import ArgumentParser
import Foundation
import Darwin

struct Ezio: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "ezio",
        abstract: "Navigate and search the macOS IORegistry.",
        discussion: """
            The easiest way to use ezio is in a 2-phase workflow:

            1) Discover
            2) Collect

            DISCOVER: Find the strings you need — 3 ways.

              1) Interactive shell (best for exploration, similar to dscl):

                  ezio -i
                    > ls, cd, read, get, find

              2) Bare search (matches node name, class, and property key):

                  ezio AppleSmartBattery              find node, see its location
                  ezio AppleSmartBattery -p           find node + show all properties
                  ezio AppleSmartBattery -p -C        find node + properties + children
                  ezio AppleRawBatteryVoltage         find any node that has this key

              3) Scoped search (similar to xpath):

                  ezio '/IOService//[AppleSmartBattery]'              by class
                  ezio '/IOService//[contains(@name,"Battery")]'      substring on name
                  ezio '/IOService//[contains(@class,"CPU")]'         substring on class
                  ezio '/IOService//[@id=0x100000300]'                by registry ID

            COLLECT: Extract key / value strings.

            EXAMPLES:

              ezio '/IOService//AppleSmartBattery/@AppleRawBatteryVoltage' -S
              ezio '/IOService//[IOPlatformExpertDevice]/@IOPlatformUUID' -S
              ezio '/IOService//AppleSmartBattery/@CurrentCapacity' -S
              ezio product-name -S

            The -S flag attempts to print the raw value with no formatting.

            OTHER:

              ezio --planes                       list all IORegistry planes
            """
    )

    @Argument(help: "Path expression or bare name to search.")
    var path: String?

    @Flag(name: [.customShort("C"), .customLong("children")], help: "Show children tree.")
    var children: Bool = false

    @Flag(name: [.customShort("i"), .customLong("interactive")], help: "Enter interactive shell mode.")
    var interactive: Bool = false

    @Flag(name: [.customShort("p"), .customLong("properties")], help: "Show properties bag.")
    var properties: Bool = false

    @Flag(name: [.customShort("S"), .customLong("string")], help: "Print raw string value only (for scripting).")
    var stringOnly: Bool = false

    @Flag(name: [.customShort("P"), .customLong("planes")], help: "List all IORegistry planes.")
    var planes: Bool = false

    func run() throws {
        // Detect piped stdin before anything else.
        // Treat empty stdin as no pipe — covers non-tty subprocess environments.
        let stdinData: Data? = {
            guard isatty(STDIN_FILENO) == 0 else { return nil }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            return data.isEmpty ? nil : data
        }()

        // Plane loader: loads on demand, uses stdin data if available
        let loader: (String) throws -> IORegNode = { plane in
            let data = try loadPlaneData(plane: plane, stdinData: stdinData)
            return try parsePlane(data: data)
        }

        // Planes listing
        if planes {
            let planeList = [
                ("IOService",    "main driver/service stack (default)"),
                ("IOPower",      "power management relationships"),
                ("IODeviceTree", "firmware/ACPI device tree"),
                ("IOUSB",        "USB controller/device topology"),
                ("IOAudio",      "audio device graph"),
                ("IOFireWire",   "FireWire topology"),
            ]
            for (name, desc) in planeList {
                print("  \(name.padding(toLength: 16, withPad: " ", startingAt: 0))  \(desc)")
            }
            return
        }

        // Interactive mode
        if interactive {
            runInteractive(planeLoader: loader)
            return
        }

        // No argument: show help
        guard let pathStr = path else {
            throw CleanExit.helpRequest()
        }

        // Parse path expression
        let expr: PathExpr
        do {
            expr = try PathParser.parse(pathStr)
        } catch let e as PathError {
            fputs("error: \(e)\n", stderr)
            Darwin.exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            Darwin.exit(1)
        }

        // Evaluate
        let result: EvalResult
        do {
            result = try evaluate(expr: expr, planeLoader: loader)
        } catch let e as LoaderError {
            fputs("error: \(e)\n", stderr)
            Darwin.exit(1)
        } catch let e as IORegParserError {
            fputs("error: failed to parse ioreg output: \(e)\n", stderr)
            Darwin.exit(1)
        } catch {
            fputs("error: \(error)\n", stderr)
            Darwin.exit(1)
        }

        // Render
        let hadResults = renderResult(result, showProperties: properties, showChildren: children, stringOnly: stringOnly)
        if !hadResults {
            print("No matches found.")
            Darwin.exit(1)
        }
    }
}

Ezio.main()
