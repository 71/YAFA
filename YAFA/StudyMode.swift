enum StudyMode: String, CaseIterable, Identifiable, Codable {
    case recallBack, recallFront, recallBothSides

    var id: Self { self }

    var hasRecallBack: Bool {
        switch self {
        case .recallBack, .recallBothSides: true
        default: false
        }
    }
    var hasRecallFront: Bool {
        switch self {
        case .recallFront, .recallBothSides: true
        default: false
        }
    }

    func toggleRecallBack() -> Self {
        switch self {
        case .recallBack, .recallBothSides: .recallFront
        case .recallFront: .recallBothSides
        }
    }
    func toggleRecallFront() -> Self {
        switch self {
        case .recallFront, .recallBothSides: .recallBack
        case .recallBack: .recallBothSides
        }
    }
}
