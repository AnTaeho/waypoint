import Foundation

/// 확인 창에서 고치는 값. 초안에서 시작해 사용자가 고른 것만 등록 초안으로 만든다.
public struct InitForm: Equatable, Sendable {
    public let draft: ProjectDraft
    public var name: String
    /// 입력 그대로. 규칙 검사와 등록은 `normalizedKey`로.
    public var key: String
    public var summary: String
    public var stack: [String]
    public var checkedGuides: Set<String>
    public var checkedCards: Set<UUID>

    /// 지침 파일·카드는 기본으로 모두 체크.
    public init(draft: ProjectDraft) {
        self.draft = draft
        name = draft.name
        key = draft.key
        summary = draft.summary
        stack = draft.stack
        checkedGuides = Set(draft.guideFiles)
        checkedCards = Set(draft.seedCards.map(\.id))
    }

    public var normalizedKey: String { ProjectKey.normalize(key) }

    public func keyProblem(taken: Set<String>) -> ProjectKey.Problem? {
        ProjectKey.problem(normalizedKey, taken: taken)
    }

    public func canRegister(taken: Set<String>) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && keyProblem(taken: taken) == nil
    }

    /// 스택 칩 추가(빈 것·중복은 무시).
    public mutating func addStack(_ item: String) {
        stack = ProjectRegistry.cleanStack(stack + [item])
    }

    /// 등록에 넘길 초안: 고친 값 + 체크한 지침 파일·카드(초안 순서 유지).
    public var registration: ProjectDraft {
        var result = draft
        result.name = name
        result.key = normalizedKey
        result.summary = summary
        result.stack = ProjectRegistry.cleanStack(stack)
        result.guideFiles = draft.guideFiles.filter { checkedGuides.contains($0) }
        result.seedCards = draft.seedCards.filter { checkedCards.contains($0.id) }
        return result
    }
}
