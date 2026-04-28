import CommitKit
import CoreTypes
import Foundation
import IntegrationKit
import StatusCenter
import SVNCore

@main
struct MacSVNCLI {
    static func main() async {
        let client = NullSVNClient(configuration: .recommended)
        let statusCenter = StatusCenter(client: client)
        let planner = CommitPlanner()
        let registry = ExternalToolRegistry()

        let profiles = await registry.bootstrapDefaultProfiles()
        let snapshot = try? await statusCenter.warmStatusIndex(for: "/tmp/example-working-copy")
        let plan = await planner.plan(
            from: [
                WorkingCopyItem(path: "/tmp/example-working-copy/README.md", isDirectory: false, status: .modified),
                WorkingCopyItem(
                    path: "/tmp/example-working-copy/docs",
                    isDirectory: true,
                    status: .normal,
                    propertyModified: true
                ),
            ],
            explicitSelection: []
        )
        let profileNames = profiles.map(\.displayName).joined(separator: ", ")

        print("MacTortoiseSVN scaffold")
        print("Standalone app: Apps/MacSVNApp")
        print("Finder integration: Apps/MacSVNFinderSync + Apps/MacSVNQuickActions")
        print("Background cache service: Apps/MacSVNStatusService")
        print("Default diff profiles: \(profileNames)")
        print("Current snapshot entries: \(snapshot?.entries.count ?? 0)")
        print("Sample commit candidates: \(plan.includedPaths.count)")
    }
}
