import Foundation

/// 나를 기다리며 서 있는 세션 수(TRK-72). 턴이 끝나 다음 요청을 기다리는 세션은 세지 않는다.
public struct SessionWaiting: Equatable, Sendable {
    public enum Kind: Sendable {
        case approval, question
        /// 세션 줄에 쓰는 말
        public var title: String { self == .approval ? "승인 대기" : "질문 대기" }
    }

    /// 권한 승인을 기다리는 세션 수
    public var approval = 0
    /// 질문의 답을 기다리는 세션 수
    public var question = 0

    public init(approval: Int = 0, question: Int = 0) {
        self.approval = approval
        self.question = question
    }

    public var isEmpty: Bool { approval == 0 && question == 0 }
    public var total: Int { approval + question }

    /// 화면에 나란히 놓는 글. 0인 쪽은 뺀다.
    public var labels: [String] {
        (approval > 0 ? ["승인 기다림 \(approval)"] : []) + (question > 0 ? ["질문 기다림 \(question)"] : [])
    }

    /// 줄·타일 하나에 보이는 기다림. 세션 자신의 것이거나, 줄이 없는 서브에이전트의 것.
    public struct Shown {
        public let kind: Kind
        /// 실제로 기다리는 세션
        public let session: Session
        /// 서브에이전트의 기다림을 부모 줄에 올렸으면 그 에이전트 이름
        public let agentName: String?

        /// 「승인 대기 3분」. 서브에이전트 것이면 「승인 대기 3분 · test-writer」.
        public func text(now: Date) -> String {
            let text = SessionWaiting.text(kind, session: session, now: now)
            guard let agentName, !agentName.isEmpty else { return text }
            return "\(text) · \(agentName)"
        }
    }

    /// 승인 대기면 승인, 질문 도구가 떠 있는 입력 대기면 질문. 끝난 세션과 그 밖은 nil.
    public static func kind(of session: Session, now: Date,
                            stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> Kind? {
        // 대부분의 세션은 저장된 단계만 보고 건너뛴다.
        guard session.endedAt == nil, let phase = SessionActivity(rawValue: session.activityRaw),
              phase == .approval || phase == .waiting
        else { return nil }
        func stored() -> Kind? {
            if phase == .approval { return .approval }
            let asks = SessionActivityRules.tools(session).values.contains(where: SessionActivityRules.questionTools.contains)
            return asks ? .question : nil
        }
        switch SessionActivityRules.activity(session, now: now, timeout: stallTimeout) {
        case .approval, .waiting: return stored()
        case .toolRunning:
            // 도는 서브에이전트에 가려진 메인. 기다림 뒤에 시작한 서브에이전트가 있으면 이미 답한 것으로 본다.
            let since = session.activityAt ?? .distantPast
            let moved = (session.children ?? []).contains { $0.endedAt == nil && $0.startedAt > since }
            return moved ? nil : stored()
        default: return nil
        }
    }

    /// 이 세션 줄에 보일 기다림: 자신의 것, 없으면 카드가 없어 줄이 없는 서브에이전트 중 가장 오래 기다린 것.
    public static func shown(for session: Session, now: Date,
                             stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> Shown? {
        if let kind = kind(of: session, now: now, stallTimeout: stallTimeout) {
            return Shown(kind: kind, session: session, agentName: nil)
        }
        var found: Shown?
        for child in session.children ?? [] {
            guard let kind = kind(of: child, now: now, stallTimeout: stallTimeout),
                  !child.openCardSessions.contains(where: { $0.card != nil }) else { continue }
            if let found, since(found.session) <= since(child) { continue }
            found = Shown(kind: kind, session: child, agentName: child.agentName)
        }
        return found
    }

    /// 이 카드에 붙은 세션 중 먼저 붙은 것부터 보아 처음 나오는 기다림.
    public static func shown(for card: Card, now: Date,
                             stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> Shown? {
        for link in card.openCardSessions.sorted(by: { $0.attachedAt < $1.attachedAt }) {
            guard let session = link.session else { continue }
            if let shown = shown(for: session, now: now, stallTimeout: stallTimeout) { return shown }
        }
        return nil
    }

    private static func since(_ session: Session) -> Date { session.activityAt ?? session.lastSeenAt }

    /// 세션 줄의 「승인 대기 3분」. 기다리기 시작한 때부터 잰다.
    public static func text(_ kind: Kind, session: Session, now: Date) -> String {
        "\(kind.title) \(TimeFormat.elapsed(from: since(session), to: now))"
    }

    /// 세션마다 한 번씩 센다. 서브에이전트가 기다리면 그 세션 하나로 센다(부모 자신이 기다리지 않으면 겹치지 않는다).
    public static func count(_ sessions: [Session], now: Date,
                             stallTimeout: TimeInterval = SessionRules.defaultStallTimeout) -> SessionWaiting {
        var result = SessionWaiting()
        for session in sessions {
            switch kind(of: session, now: now, stallTimeout: stallTimeout) {
            case .approval: result.approval += 1
            case .question: result.question += 1
            case nil: break
            }
        }
        return result
    }
}
