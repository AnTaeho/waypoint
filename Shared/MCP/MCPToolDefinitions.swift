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
            description: "폴더 경로로 Waypoint 프로젝트를 찾는다. 없으면 null.",
            inputSchema: schema(["cwd": string("폴더 절대 경로")], required: ["cwd"])
        ),
        MCPToolDefinition(
            name: "project_init",
            description: "폴더를 새 프로젝트로 등록하는 초안을 Waypoint 앱에 띄운다. 사용자가 앱에서 확인하고 등록하므로 결과는 pending. 이미 등록된 폴더면 오류.",
            inputSchema: schema([
                "cwd": string("등록할 폴더 절대 경로"),
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
            description: "카드를 만든다(origin=claude). 나중에 할 것은 kind·status를 idea로.",
            inputSchema: schema([
                "project": projectProperty,
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
            description: "카드 수정. status active는 받지 않는다(card_start로). done은 사용자 확인 후에만.",
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
    ]

    static let projectProperty: JSONValue = [
        "type": "string", "description": "프로젝트 키(예: PRB) 또는 작업 폴더 경로",
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
