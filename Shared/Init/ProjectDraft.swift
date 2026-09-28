import Foundation
import Observation

/// `project_init`이 앱 메모리에 두는 등록 초안. 사용자가 확인 창에서 고치고 등록한다(저장소에는 넣지 않는다).
public struct ProjectDraft: Identifiable, Equatable, Sendable {
    public struct SeedCard: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var title: String
        public var status: CardStatus
        public var kind: CardKind
        public var body: String

        public init(id: UUID = UUID(), title: String, status: CardStatus, kind: CardKind, body: String = "") {
            self.id = id
            self.title = title
            self.status = status
            self.kind = kind
            self.body = body
        }
    }

    public let id: UUID
    /// 정규화한 절대 경로
    public var rootPath: String
    public var name: String
    public var key: String
    public var summary: String
    public var stack: [String]
    /// 폴더 아래 실제 파일로 확인된 상대 경로
    public var guideFiles: [String]
    public var seedCards: [SeedCard]
    public var createdAt: Date

    public init(
        id: UUID = UUID(), rootPath: String, name: String, key: String, summary: String = "",
        stack: [String] = [], guideFiles: [String] = [], seedCards: [SeedCard] = [], createdAt: Date = Date()
    ) {
        self.id = id
        self.rootPath = rootPath
        self.name = name
        self.key = key
        self.summary = summary
        self.stack = stack
        self.guideFiles = guideFiles
        self.seedCards = seedCards
        self.createdAt = createdAt
    }
}

/// 확인을 기다리는 초안들. 같은 폴더의 새 초안은 옛것을 바꾼다. 확인 창은 맨 앞 것부터 하나씩 보인다.
/// 메인 스레드에서만 쓴다(서버 콜백도 메인 큐). `MCPTools`처럼 Sendable이 아니다.
@Observable
public final class ProjectDraftQueue {
    public private(set) var drafts: [ProjectDraft] = []
    /// 초안이 들어오거나 바뀌었을 때(앱이 창을 앞으로 가져온다).
    @ObservationIgnored public var onSubmit: ((ProjectDraft) -> Void)?

    public init() {}

    public var current: ProjectDraft? { drafts.first }

    /// 넣는다. 같은 `rootPath`가 이미 있으면 그 자리에서 바꾼다(id는 새것).
    /// - Returns: 옛 초안을 바꿨으면 true
    @discardableResult
    public func submit(_ draft: ProjectDraft) -> Bool {
        let replaced: Bool
        if let index = drafts.firstIndex(where: { $0.rootPath == draft.rootPath }) {
            drafts[index] = draft
            replaced = true
        } else {
            drafts.append(draft)
            replaced = false
        }
        onSubmit?(draft)
        return replaced
    }

    /// 등록했거나 취소한 초안을 뺀다.
    public func remove(_ id: UUID) {
        drafts.removeAll { $0.id == id }
    }
}
