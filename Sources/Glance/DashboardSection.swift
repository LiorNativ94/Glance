import Foundation

enum DashboardSection: String, CaseIterable, Identifiable {
    case system, storage, awake, subscriptions
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "CPU & memory"
        case .storage: return "Storage"
        case .awake: return "Keep awake"
        case .subscriptions: return "AI subscriptions"
        }
    }
    static func restored(_ saved: [String]?) -> [Self] {
        var seen = Set<Self>()
        return ((saved ?? []).compactMap(Self.init(rawValue:)) + allCases).filter { seen.insert($0).inserted }
    }
}
