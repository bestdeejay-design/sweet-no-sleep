import CoreGraphics
import Foundation
let opts = CGWindowListOption([.optionOnScreenOnly])
guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    if owner.contains("SweetNoSleep") || owner.contains("Sweet No Sleep") {
        let num = w["kCGWindowNumber"] as? Int ?? -1
        let name = w["kCGWindowName"] as? String ?? ""
        let bounds = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        let layer = w["kCGWindowLayer"] as? Int ?? -1
        print("WIN \(num) owner=\(owner) name='\(name)' layer=\(layer) bounds=\(bounds)")
    }
}
