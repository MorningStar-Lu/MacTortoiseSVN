import Foundation
import StatusService

@main
struct MacSVNStatusServiceCLI {
    static func main() async {
        do {
            let configuration = try parseConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
            let host = try StatusServiceHost(configuration: configuration)
            let processor = StatusServiceCommandProcessor(host: host)

            while let line = readLine() {
                let requestData = Data(line.utf8)
                let response: StatusServiceResponse

                do {
                    let request = try JSONDecoder().decode(StatusServiceRequest.self, from: requestData)
                    response = await processor.handle(request)
                } catch {
                    response = StatusServiceResponse(
                        id: "decode-error",
                        ok: false,
                        error: error.localizedDescription
                    )
                }

                if let encoded = try? JSONEncoder.pretty.encode(response),
                   let text = String(data: encoded, encoding: .utf8) {
                    print(text)
                    fflush(stdout)
                }

                if response.shouldTerminate {
                    break
                }
            }
        } catch {
            fputs("macsvn-statusd error: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }

    private static func parseConfiguration(arguments: [String]) throws -> StatusServiceConfiguration {
        var repositoryRoot: String?
        var databasePath: String?
        var iterator = arguments.makeIterator()

        while let argument = iterator.next() {
            switch argument {
            case "--repository-root":
                repositoryRoot = iterator.next()
            case "--database":
                databasePath = iterator.next()
            default:
                continue
            }
        }

        let resolvedRoot = repositoryRoot ?? FileManager.default.currentDirectoryPath
        let defaultConfiguration = StatusServiceConfiguration.development(repositoryRoot: resolvedRoot)
        return StatusServiceConfiguration(
            repositoryRoot: resolvedRoot,
            databaseURL: databasePath.map { URL(fileURLWithPath: $0) } ?? defaultConfiguration.databaseURL,
            maxIncrementalDirtyPaths: defaultConfiguration.maxIncrementalDirtyPaths,
            bridgeConfiguration: defaultConfiguration.bridgeConfiguration,
            clientConfiguration: defaultConfiguration.clientConfiguration,
            statusCenterConfiguration: defaultConfiguration.statusCenterConfiguration
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }
}
