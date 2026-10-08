import Foundation

/// 도구 하나의 이름·설명·입력 스키마(JSON Schema).
public struct MCPToolDefinition: Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public var json: JSONValue {
        ["name": .string(name), "description": .string(description), "inputSchema": inputSchema]
    }
}

extension MCPTools {
    /// SPEC 7장 도구.
    public static let definitions: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "project_resolve",
            description: "폴더 경로로 Waypoint 프로젝트를 찾는다. 없으면 null. SSH 원격·개발 컨테이너처럼 Mac에 없는 폴더면 remote에 git origin 주소를 함께 보낸다.",
            inputSchema: schema(["cwd": string("폴더 절대 경로"),
                                 "remote": string("git remote.origin.url(원격·컨테이너 폴더일 때). 같은 원격 주소의 등록 프로젝트를 찾는다")],
                                required: ["cwd"])
        ),
        MCPToolDefinition(
            name: "project_init",
            description: "폴더를 새 프로젝트로 등록하는 초안을 Waypoint 앱에 띄운다. 사용자가 앱에서 확인하고 등록하므로 결과는 pending. 이미 등록된 폴더면 오류.",
            inputSchema: schema([
                "cwd": string("등록할 폴더 절대 경로"),
                "provider": providerProperty,
                "name": string("프로젝트 이름"),
                "key": string("카드 키(영문 대문자 2–5자, 다른 프로젝트와 겹치지 않게). 없으면 앱이 추천"),
                "summary": string("한두 문장 개요"),
                "stack": ["type": "array", "items": ["type": "string"], "description": "주요 언어·프레임워크"],
                "guideFiles": ["type": "array", "items": ["type": "string"],
                               "description": "지침 문서 후보(cwd 기준 상대 경로, .md·.txt). 예: CLAUDE.md, docs/ARCHITECTURE.md"],
                "seedCards": [
                    "type": "array",
                    "maxItems": JSONValue(seedCardLimit),
                    "description": "초기 카드 후보(최대 8)",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "status": ["type": "string", "enum": ["next", "idea"], "description": "기본 next"],
                            "kind": ["type": "string", "enum": ["task", "idea", "bug"]],
                            "body": ["type": "string", "description": "짧은 본문(markdown)"],
                        ],
                        "required": ["title"],
                        "additionalProperties": false,
                    ],
                ],
            ], required: ["cwd", "name"])
        ),
        MCPToolDefinition(
            name: "session_bind",
            description: "시작 폴더와 관계없이 실제 작업 대상 프로젝트에 메인 세션을 연결한다. 훅 또는 실행 환경의 실제 ID만 사용한다. 프로젝트 전환 시 이전 카드 연결을 풀지만 과거 기록의 프로젝트는 유지한다.",
            inputSchema: schema([
                "project": projectProperty,
                "sessionId": string("훅 또는 실행 환경의 실제 세션 ID. Codex는 codex: 접두사 포함"),
                "provider": providerProperty,
                "cwd": string("세션 시작 폴더 절대 경로"),
            ], required: ["project", "sessionId", "provider", "cwd"])
        ),
        MCPToolDefinition(
            name: "card_list",
            description: "프로젝트의 카드 목록. status를 안 주면 done·archived를 뺀다.",
            inputSchema: schema([
                "project": projectProperty,
                "status": ["type": "string", "enum": statusEnum(), "description": "이 상태만"],
                "query": string("제목·본문·ID에 들어간 글자"),
            ], required: ["project"])
        ),
        MCPToolDefinition(
            name: "card_get",
            description: "카드 상세와 최근 기록.",
            inputSchema: schema(["id": cardIdProperty], required: ["id"])
        ),
        MCPToolDefinition(
            name: "card_create",
            description: "카드를 만든다. 만든 곳은 연결 세션의 도구(Claude·Codex). 나중에 할 것은 kind·status를 idea로.",
            inputSchema: schema([
                "project": projectProperty,
                "provider": providerProperty,
                "title": string("제목"),
                "kind": ["type": "string", "enum": ["task", "idea", "bug"], "description": "기본 task"],
                "status": ["type": "string", "enum": ["idea", "next", "done", "archived"],
                           "description": "기본 next(kind가 idea면 idea)"],
                "body": string("본문(markdown)"),
                "parentId": ["type": "string", "description": "상위 카드 ID(같은 프로젝트)"],
                "criteria": criteriaProperty,
                "sessionId": string("만든 세션 ID(주입된 sessionId)"),
            ], required: ["project", "title"])
        ),
        MCPToolDefinition(
            name: "card_start",
            description: "세션을 카드에 연결해 작업중으로 표시한다. 그 세션의 다른 카드 연결은 먼저 푼다.",
            inputSchema: schema([
                "id": cardIdProperty,
                "sessionId": string("주입된 sessionId"),
            ], required: ["id", "sessionId"])
        ),
        MCPToolDefinition(
            name: "card_update",
            description: "카드 수정. status active는 받지 않는다(card_start로). active 카드의 status를 바꾸면 붙어 있던 세션 연결이 모두 풀린다. done은 사용자 확인 후에만.",
            inputSchema: schema([
                "id": cardIdProperty,
                "title": string("새 제목"),
                "body": string("새 본문(markdown)"),
                "status": ["type": "string", "enum": ["idea", "next", "done", "archived"]],
                "criteria": criteriaProperty.merging(["description": "완료 조건 전체(통째로 바꾼다)"]),
            ], required: ["id"])
        ),
        MCPToolDefinition(
            name: "card_note",
            description: "카드 기록에 짧은 메모를 남긴다(결정, 막힌 점).",
            inputSchema: schema(["id": cardIdProperty, "text": string("메모")], required: ["id", "text"])
        ),
        MCPToolDefinition(
            name: "card_handoff",
            description: "다음 세션을 위한 메모를 카드에 저장한다(어디까지, 남은 것, 먼저 볼 파일. 3줄 이내).",
            inputSchema: schema([
                "id": cardIdProperty,
                "nextSessionNote": string("다음 세션 메모"),
            ], required: ["id", "nextSessionNote"])
        ),
        MCPToolDefinition(
            name: "card_evidence",
            description: "완료 조건을 확인하려고 실행한 검증 명령과 결과를 카드에 남긴다. 실행하지 않은 조건은 남기지 않는다(skipped는 일부러 건너뛴 경우만). 앱이 명령 실행을 직접 본 기록과 맞으면 확인됨으로 보인다.",
            inputSchema: schema([
                "id": cardIdProperty,
                "criterion": ["type": "integer", "minimum": 1,
                              "description": "완료 조건 번호(1부터, card_get의 criteria 순서). 카드 전체 검증이면 생략"],
                "command": string("실행한 명령 그대로(예: swift test)"),
                "outcome": ["type": "string", "enum": ["pass", "fail", "skipped"], "description": "명령 결과"],
                "detail": string("짧은 사실(200자까지, 예: 42개 통과)"),
                "sessionId": string("주입된 sessionId"),
            ], required: ["id", "command", "outcome"])
        ),
        MCPToolDefinition(
            name: "project_status",
            description: "프로젝트 지금 상황(무엇이 진행 중이고 다음에 무엇을 할지)을 새로 쓴다. 최신 것이 시작 블록 「지금 상황」에 보인다. 600자·8줄 이내, 넘으면 오류. text를 빼면 최신 상황을 읽는다.",
            inputSchema: schema([
                "project": projectProperty,
                "text": string("지금 상황 전체(이전 글을 대신한다). 진행 중인 것, 다음 할 것, 막힌 것을 짧게"),
                "sessionId": string("주입된 sessionId"),
                "provider": providerProperty,
            ], required: ["project"])
        ),
        MCPToolDefinition(
            name: "work_file",
            description: "시작 블록 「정리 안 된 작업」의 세션 하나를 정리한다. cardId를 주면 그 세션의 파일 변경·커밋·검증 기록을 카드에 잇는다(카드 상태는 그대로). 빼면 정리할 것 없음으로 넘긴다.",
            inputSchema: schema([
                "sessionId": string("블록에 보인 세션 ID(앞 8자) 또는 전체 ID"),
                "cardId": cardIdProperty.merging(["description": "이을 카드 ID(같은 프로젝트). 넘기려면 뺀다"]),
            ], required: ["sessionId"])
        ),
        MCPToolDefinition(
            name: "github_issue_create",
            description: "프로젝트의 GitHub 저장소(origin)에 이슈를 연다. 연 이슈는 Waypoint 카드에 보인다. 작업 카드가 있으면 cardId로 잇는다. 배치 요청으로는 부를 수 없다.",
            inputSchema: schema([
                "project": projectProperty,
                "title": string("이슈 제목"),
                "body": string("본문(markdown). 그대로 올라간다"),
                "labels": ["type": "array", "items": ["type": "string"], "description": "저장소에 있는 라벨 이름"],
                "cardId": cardIdProperty.merging(["description": "이을 카드 ID(같은 프로젝트)"]),
                "sessionId": string("주입된 sessionId. cardId가 없으면 이 세션의 작업중 카드가 하나일 때 그 카드에 잇는다"),
            ], required: ["project", "title"])
        ),
        MCPToolDefinition(
            name: "github_pr_create",
            description: "프로젝트의 GitHub 저장소(origin)에 PR을 연다. push하지 않으므로 브랜치를 먼저 push한다. 연 PR은 Waypoint 카드에 보인다. 배치 요청으로는 부를 수 없다.",
            inputSchema: schema([
                "project": projectProperty,
                "title": string("PR 제목"),
                "body": string("본문(markdown). 그대로 올라간다"),
                "base": string("합칠 브랜치. 기본은 저장소 기본 브랜치"),
                "head": string("올릴 브랜치. 기본은 cwd 작업 트리의 현재 브랜치"),
                "draft": ["type": "boolean", "description": "초안으로 열기. 기본 false"],
                "cwd": string("작업 트리 절대 경로(worktree일 때). 기본은 프로젝트 폴더"),
                "cardId": cardIdProperty.merging(["description": "이을 카드 ID(같은 프로젝트)"]),
                "sessionId": string("주입된 sessionId. cardId가 없으면 이 세션의 작업중 카드가 하나일 때 그 카드에 잇는다"),
            ], required: ["project", "title"])
        ),
    ]

    static let projectProperty: JSONValue = [
        "type": "string", "description": "프로젝트 키(예: PRB) 또는 작업 폴더 경로",
    ]
    static let providerProperty: JSONValue = [
        "type": "string", "enum": ["claude", "codex"],
        "description": "호출 도구. 기본 claude. card_create는 연결 세션의 도구를 우선함",
    ]
    static let cardIdProperty: JSONValue = [
        "type": "string", "pattern": "^[A-Za-z]{2,5}-[0-9]+$", "description": "카드 ID(예: PRB-1)",
    ]
    static let criteriaProperty: JSONValue = [
        "type": "array",
        "description": "완료 조건",
        "items": [
            "type": "object",
            "properties": [
                "text": ["type": "string"],
                "done": ["type": "boolean", "description": "기본 false"],
            ],
            "required": ["text"],
            "additionalProperties": false,
        ],
    ]

    static func string(_ description: String) -> JSONValue {
        ["type": "string", "description": .string(description)]
    }

    static func statusEnum() -> JSONValue {
        .array(CardStatus.allCases.map { .string($0.rawValue) })
    }

    static func schema(_ properties: [String: JSONValue], required: [String]) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
            "additionalProperties": false,
        ]
    }
}

extension JSONValue {
    /// 객체끼리 합친다(오른쪽 우선). 객체가 아니면 그대로.
    func merging(_ other: [String: JSONValue]) -> JSONValue {
        guard case .object(var o) = self else { return self }
        for (k, v) in other { o[k] = v }
        return .object(o)
    }
}
