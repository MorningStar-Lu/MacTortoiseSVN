import Foundation
import StatusServiceXPC

@main
struct MacSVNStatusXPCService {
    static func main() {
        let delegate = StatusServiceXPCListenerDelegate()
        let listener = NSXPCListener.service()
        listener.delegate = delegate
        listener.resume()
    }
}
