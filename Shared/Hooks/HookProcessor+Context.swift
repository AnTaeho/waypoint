import Foundation
import SwiftData

/// `Waypoint:` 블록 전달과 수신 확인(SPEC 5장 「늦은 주입」·「수신 확인」, TRK-35).
///
/// 훅 스크립트는 응답을 1초까지 기다린다. 앱이 블록을 만들었어도 그 사이 응답이 닿지 않으면 대화에 들어가지 않는다.
/// 확인을 보내는 스크립트에는 블록을 대기로 두고, 스크립트가 stdout에 출력한 뒤 보낸 `POST /hooks/ack`를 서버 큐가
/// 받아 두면(`ContextAckInbox`) 그 세션의 다음 훅에서 `contextProjectKey`를 적는다. 확인이 없으면 다음 `UserPromptSubmit`에서
/// 같은 블록을 다시 준다.
extension HookProcessor {
    /// 같은 프로젝트 블록을 확인 없이 보내는 최대 횟수(`SessionStart` 포함). 확인이 계속 닿지 않는 환경에서 매 프롬프트마다
    /// 블록이 붙지 않게 한다.
    public static let maxContextAttempts = 3

    /// 늦은 주입: 메인 세션이 지금 프로젝트의 블록을 아직 받지 못했으면(등록 전에 시작, 다른 폴더에서 옮겨 옴,
    /// 다른 프로젝트의 블록만 받음, 보낸 블록의 확인이 오지 않음) `SessionStart`와 같은 블록을 준다. 서브에이전트 훅·끝난 세션·
    /// 미등록·보관 폴더는 nil. `heartbeat` 뒤에 부른다(세션이 없으면 거기서 만들어진다).
    func lateContext(_ input: HookInput, at date: Date, acknowledges: Bool = false) -> String? {
        guard input.agentID == nil,
              let session = fetchSession(input.sessionID), session.kind == .main, session.endedAt == nil,
              let project = session.project, project.archivedAt == nil,
              session.contextProjectKey != project.key
        else { return nil }
        // 확인 없이 여러 번 보낸 블록은 더 보내지 않는다(옛 스크립트는 아래에서 바로 확정되므로 여기 닿지 않는다).
        if acknowledges, session.contextPendingKey == project.key,
           session.contextPendingCount >= Self.maxContextAttempts { return nil }
        offerContext(project, to: session, restart: false, acknowledges: acknowledges)
        return SessionContext.text(project: project, session: session, now: date, stallTimeout: stallTimeout)
    }

    /// 블록을 건넨다고 적는다. 확인을 보내는 스크립트면 대기(`contextPending*`)로 두고 새 응답 ID를 `lastContextID`에,
    /// 아니면 바로 확정한다. `restart`(`SessionStart` — 재개·압축으로 대화가 새로 짜일 수 있다)면 이미 확정한 키도 비워
    /// 이번 블록의 확인이 없을 때 다음 프롬프트에 다시 준다.
    func offerContext(_ project: Project, to session: Session, restart: Bool, acknowledges: Bool) {
        guard acknowledges else {
            session.confirmContext(project.key)
            return
        }
        if restart { session.contextProjectKey = nil }
        if !restart, session.contextPendingKey == project.key {
            session.contextPendingCount += 1
        } else {
            session.contextPendingKey = project.key
            session.contextPendingCount = 1
        }
        let id = UUID().uuidString.lowercased()
        session.contextPendingID = id
        lastContextID = id
    }

    /// 이 훅의 메인 세션에 대기 블록이 있고 그 ID의 확인을 받아 두었으면 확정한다. 꺼낸 ID(저장 실패 때 되돌릴 것)를 돌려준다.
    /// 확인 요청 자체는 서버 큐에서 `contextAcks`에 넣기만 한다(메인 큐·저장·화면 갱신을 기다리지 않게).
    func applyAcknowledgement(_ input: HookInput) -> String? {
        guard let session = fetchSession(input.sessionID), let id = session.contextPendingID,
              contextAcks.take(id)
        else { return nil }
        session.confirmContext(session.contextPendingKey)
        return id
    }
}
