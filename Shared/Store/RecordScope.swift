import Foundation

/// 무엇을 어디에 얼마나 남기는가(TRK-47 기록 탭). 설정 창 「기록」의 문장은 이 표에서만 만든다.
///
/// - 저장소(`WaypointStore.schema`)의 저장 속성 전부를 화면 항목(`Item`)으로 나눈다(`attributes`).
/// - 이벤트 payload 키를 이벤트 종류·`kind`별로 화면 항목으로 나눈다(`payloadKeys`).
/// - 저장소 밖에 이 Mac에만 두는 파일(`localItems`).
///
/// `RecordScopeTests`가 스키마의 속성 목록·실제 생성 지점이 만든 payload 키와 이 표를 양쪽으로 맞춘다.
/// 속성이나 payload 키를 더하면 여기에도 더해야 테스트가 통과한다.
public enum RecordScope {

    // MARK: - 화면 항목

    public enum Retention: Hashable, Sendable {
        /// 지울 때까지
        case kept
        /// 이 일수가 지나면 지운다
        case days(Int)
        /// 이 일수가 지나면 지우되 일부는 남긴다(`kept`: 남는 것)
        case daysExcept(Int, kept: String)

        public var label: String {
            switch self {
            case .kept: "계속"
            case .days(let days): "\(days)일"
            case .daysExcept(let days, let kept): "\(days)일 · \(kept) 계속"
            }
        }
    }

    /// 「남기는 것」 한 줄. 순서가 화면 순서다.
    public enum Item: String, CaseIterable, Sendable {
        case projects, cards, sessions, prompts, files, commits, checks, github, notes, guides

        public var title: String {
            switch self {
            case .projects: "프로젝트"
            case .cards: "카드"
            case .sessions: "세션"
            case .prompts: "요청 문장"
            case .files: "바뀐 파일"
            case .commits: "커밋"
            case .checks: "검증 기록"
            case .github: "이슈 · PR"
            case .notes: "메모"
            case .guides: "지침 문서"
            }
        }

        public var detail: String {
            switch self {
            case .projects: "이름 · 키 · 폴더 위치 · 소개 · 쓰는 기술"
            case .cards: "제목 · 본문 · 완료 조건 · 상태가 바뀐 때"
            case .sessions: "시작·끝 시각 · 작업 폴더 · 브랜치"
            case .prompts: "내가 보낸 요청 앞 \(HookParsing.lastPromptLimit)자 · 보낸 시각"
            case .files: "경로 · 저장소 폴더 · 늘고 준 줄 수"
            case .commits: "해시 · 메시지 첫 줄"
            case .checks: "명령 · 결과 · 짧은 설명"
            case .github: "번호 · 제목 · 주소 · 저장소 · 브랜치"
            case .notes: "카드 메모 · 다음 세션 메모 · 프로젝트 지금 상황"
            case .guides: "등록한 문서의 내용과 이전 판"
            }
        }

        public var retention: Retention {
            let days = RecordRetention.days
            return switch self {
            case .projects, .cards, .github, .notes: .kept
            case .prompts, .files: .days(days)
            case .sessions, .commits, .checks: .daysExcept(days, kept: "카드에 이어진 것은")
            case .guides: .daysExcept(days, kept: "최신 판은")
            }
        }
    }

    /// 남기지 않는 것. 훅 처리는 이것들을 읽어도 저장하지 않는다(명령 출력은 끝 코드·커밋 줄만 뽑고 버린다).
    public static let notKept = ["AI 답변", "대화 전체", "명령 출력", "지침 문서가 아닌 파일의 내용"]

    public static var notKeptLine: String {
        "남기지 않음 · " + notKept.joined(separator: " · ")
    }

    // MARK: - 저장 속성

    /// 속성 하나가 어디에 드는가.
    public enum Owner: Hashable, Sendable {
        case item(Item)
        /// 이벤트 행: 이벤트 종류·payload 키마다(`payloadKeys`)
        case event
    }

    public struct Attribute: Hashable, Sendable {
        public let entity: String
        public let name: String
        public let owner: Owner
        /// 내보내기에 넣는가. 넣지 않는 것은 앱이 돌며 쓰는 상태 값(캐시·대기 중인 도구·블록 확인·PID).
        public let exported: Bool
    }

    private static func attributes(_ entity: String, _ owner: Owner, _ names: [String], exported: Bool = true) -> [Attribute] {
        names.map { Attribute(entity: entity, name: $0, owner: owner, exported: exported) }
    }

    /// 저장 속성 전부(관계는 빼고). 위치는 모두 저장소 = iCloud 미러링 대상.
    public static let attributes: [Attribute] =
        attributes("Project", .item(.projects),
                   ["id", "key", "name", "summary", "rootPath", "stack", "nextCardNumber", "createdAt", "archivedAt"])
        + attributes("Project", .item(.projects), ["lastEventAt"], exported: false)
        + attributes("Card", .item(.cards),
                     ["id", "number", "title", "body", "kindRaw", "statusRaw", "criteria", "originRaw", "originSessionId",
                      "createdAt", "updatedAt", "doneAt"])
        + attributes("Card", .item(.cards), ["statusBeforeActive"], exported: false)
        + attributes("Card", .item(.notes), ["nextSessionNote"])
        + attributes("CardSession", .item(.cards), ["attachedAt", "detachedAt"])
        + attributes("Session", .item(.sessions),
                     ["id", "providerRaw", "kindRaw", "agentName", "cwd", "gitBranch", "startedAt", "lastSeenAt",
                      "endedAt", "endReason", "lastPromptAt"])
        + attributes("Session", .item(.sessions),
                     ["claudePid", "processPid", "contextProjectKey", "contextPendingKey", "contextPendingID",
                      "contextPendingCount", "stateRaw", "activityRaw", "activityAt", "pendingToolsData"], exported: false)
        + attributes("Session", .item(.prompts), ["lastPrompt"])
        + attributes("Event", .event, ["id", "at", "typeRaw", "payload"])
        + attributes("GuideDoc", .item(.guides),
                     ["id", "relPath", "content", "lastSyncedAt", "draft", "isMissing", "conflictContent"])
        + attributes("GuideDoc", .item(.guides), ["contentHash"], exported: false)
        + attributes("GuideVersion", .item(.guides), ["content", "at", "sourceRaw"])

    // MARK: - 이벤트 payload

    public struct PayloadKey: Hashable, Sendable {
        public let type: EventType
        /// `note` 이벤트의 `kind` 값. 없으면 nil(그냥 메모·다른 종류).
        public let kind: String?
        public let key: String
        public let item: Item
    }

    private static func keys(_ type: EventType, kind: String? = nil, _ item: Item, _ names: [String]) -> [PayloadKey] {
        names.map { PayloadKey(type: type, kind: kind, key: $0, item: item) }
    }

    /// 이벤트 종류별 payload 키. 생성 지점은 `HookProcessor`·`MCPTools`(`+Status` 포함)·`CardLifecycle`·`CardEditing`·
    /// `CardEvidence`·`SessionProjectBinding`·`GuideLibrary`·`ProjectRegistry`·`GitHubLog`.
    public static let payloadKeys: [PayloadKey] =
        keys(.sessionStart, .sessions, ["source", "agentName"])
        + keys(.sessionEnd, .sessions, ["reason"])
        + keys(.cardCreated, .cards, ["origin", "status"])
        + keys(.cardStatus, .cards, ["from", "to"])
        + keys(.cardAttached, .cards, ["sessionId"])
        + keys(.cardDetached, .cards, ["sessionId", "reason"])
        + keys(.fileChanged, .files, ["path", "added", "removed", "toolUseId", "checkout"])
        + keys(.commit, .commits, ["hash", "message", "toolUseId"])
        + keys(.check, .checks, ["command", "outcome", "source", "criterion", "criterionText", "detail", "exitCode",
                                 "provider", "toolUseId"])
        + keys(.guideSynced, .guides, ["relPath", "source"])
        + keys(.projectStatus, .notes, ["summary", "provider", "sessionId"])
        + keys(.sessionFiled, .cards, ["sessionId", "outcome", "cardId", "files", "moved"])
        + keys(.githubIssue, .github, ["number", "url", "title", "state", "repo", "provider"])
        + keys(.githubPR, .github, ["number", "url", "title", "state", "repo", "branch", "provider"])
        + keys(.note, .notes, ["text"])
        + keys(.note, kind: MCPTools.handoffNoteKind, .notes, ["kind", "text"])
        + keys(.note, kind: CardEditing.criterionNoteKind, .cards, ["kind", "text", "isDone"])
        + keys(.note, kind: PromptRetention.promptKind, .prompts, ["kind", "promptId", "text"])
        + keys(.note, kind: SessionProjectBinding.boundNoteKind, .sessions, ["kind", "from", "to"])

    /// payload 키 하나의 항목. 표에 없으면 nil.
    public static func item(type: EventType, kind: String?, key: String) -> Item? {
        payloadKeys.first { $0.type == type && $0.kind == kind && $0.key == key }?.item
    }

    // MARK: - 어디에

    /// 저장소 밖, 이 Mac에만 두는 것. `paths`는 저장 폴더 안 이름.
    public struct LocalItem: Hashable, Sendable {
        public let title: String
        public let detail: String
        public let paths: [String]
    }

    public static let localItems: [LocalItem] = [
        LocalItem(title: "기록 백업", detail: "최근 \(StoreBackup.keep)개", paths: [StoreBackup.folderName]),
        LocalItem(title: "지침 파일 백업", detail: "고치거나 지우기 전 사본",
                  paths: [GuidanceBackupStore.folderName]),
        LocalItem(title: "연결 설정 백업", detail: "연결 설정을 바꾸기 전 사본",
                  paths: [IntegrationInstallContext.backupFolderName]),
        LocalItem(title: "앱이 꺼진 동안 온 기록", detail: "앱이 켜지면 옮기고 비움", paths: [Outbox.fileName]),
        LocalItem(title: "연결 상태와 지표", detail: "시각과 숫자", paths: ["integration-health.json", "metrics.json"]),
        LocalItem(title: "사용량", detail: "마지막으로 읽은 한도", paths: [UsageSnapshot.fileName]),
        LocalItem(title: "이슈 · PR 상태", detail: "마지막으로 확인한 상태", paths: [GitHubStatusCache.fileName]),
    ]

    /// 「어디에」의 저장소 줄. iCloud를 끈 실행(확인용 저장 폴더 등)은 이 Mac에만 있다.
    public static func storePlace(iCloud: Bool) -> (title: String, detail: String) {
        iCloud ? ("iCloud · 이 Mac과 iPhone", "위의 기록 모두") : ("이 Mac", "위의 기록 모두 · iCloud 꺼짐")
    }

    /// 「어디에」의 둘째 줄 이름
    public static let localPlaceTitle = "이 Mac에만"
}
