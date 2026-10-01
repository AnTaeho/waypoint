import Foundation
import SwiftData
import Testing
@testable import WaypointKit

/// 블록 수신 확인(SPEC 5장 「수신 확인」, TRK-35): 확인을 보내는 스크립트에는 블록을 대기로 두고,
/// `POST /hooks/ack`가 와야 받은 것으로 적는다. 확인이 없으면 다음 프롬프트에 다시 준다.
@Suite struct ContextAckTests {
    private enum SaveFailure: Error { case diskUnavailable }

    @discardableResult
    func send(_ h: HookHarness, _ name: String, at date: Date, delivers: Bool = true, acknowledges: Bool = true,
              provider: AgentProvider = .claude) throws -> String? {
        h.processor.handle(event: nil, json: try fixture(name), at: date, delivers: delivers,
                           provider: provider, acknowledges: acknowledges)
    }

    /// 정상: 확인이 오면 확정되고 다음 프롬프트에는 블록이 없다.
    @Test func ackConfirmsAndNextPromptGetsNothing() throws {
        let h = try HookHarness()
        let start = try #require(try send(h, "doc-SessionStart", at: t0))
        #expect(start.hasPrefix("Waypoint: LDG"))
        let id = try #require(h.processor.lastContextID)
        #expect(HookRouter.isContextID(id))
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == nil)
        #expect(s.contextPendingKey == "LDG" && s.contextPendingID == id && s.contextPendingCount == 1)

        #expect(h.processor.acknowledge(contextID: id))
        #expect(s.contextProjectKey == "LDG")
        #expect(s.contextPendingKey == nil && s.contextPendingID == nil && s.contextPendingCount == 0)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60) == nil)
        #expect(h.processor.lastContextID == nil)
        // 같은 확인을 다시 받아도 바뀌는 것이 없다
        #expect(!h.processor.acknowledge(contextID: id))
        #expect(s.contextProjectKey == "LDG")
    }

    /// 시간 초과: 확인이 없으면 다음 프롬프트에 블록을 새 ID로 한 번 더, 그 확인이 오면 확정.
    @Test func missingAckRedeliversOnNextPromptThenConfirms() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        let first = try #require(h.processor.lastContextID)
        let again = try #require(try send(h, "doc-UserPromptSubmit", at: t0 + 60))
        #expect(again.hasPrefix("Waypoint: LDG"))
        let second = try #require(h.processor.lastContextID)
        #expect(second != first)
        let s = try #require(try h.session())
        #expect(s.contextPendingCount == 2)
        // 앞 블록의 ID는 더 이상 대기가 아니다
        #expect(!h.processor.acknowledge(contextID: first))
        #expect(s.contextProjectKey == nil)
        #expect(h.processor.acknowledge(contextID: second))
        #expect(s.contextProjectKey == "LDG")
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 120) == nil)
    }

    /// 확인이 계속 오지 않으면 SessionStart 포함 세 번까지만 보낸다. 늦게라도 마지막 확인이 오면 확정.
    @Test func redeliveryStopsAtLimit() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60) != nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 120) != nil)
        let last = try #require(h.processor.lastContextID)
        #expect(HookProcessor.maxContextAttempts == 3)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 180) == nil)
        #expect(h.processor.lastContextID == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 240) == nil)
        #expect(h.processor.acknowledge(contextID: last))
        #expect(try h.session()?.contextProjectKey == "LDG")
    }

    /// 옛 스크립트(확인 머리 없음): 블록을 주는 즉시 확정. 다음 프롬프트에 반복하지 않는다.
    @Test func oldScriptConfirmsImmediately() throws {
        let h = try HookHarness()
        #expect(try send(h, "doc-SessionStart", at: t0, acknowledges: false)?.hasPrefix("Waypoint: LDG") == true)
        #expect(h.processor.lastContextID == nil)
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == "LDG" && s.contextPendingID == nil)
        for minute in 1...3 {
            #expect(try send(h, "doc-UserPromptSubmit", at: t0 + Double(minute) * 60, acknowledges: false) == nil)
        }
    }

    /// 새 스크립트가 남긴 대기 블록이 있어도 옛 스크립트의 프롬프트는 블록을 한 번 주고 바로 확정한다(사본이 섞인 경우).
    @Test func mixedScriptsDoNotLoop() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60, acknowledges: false) != nil)
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == "LDG" && s.contextPendingID == nil && s.contextPendingCount == 0)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 120) == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 180, acknowledges: false) == nil)
    }

    /// 재개·압축의 SessionStart: 이미 확정한 세션도 이번 블록의 확인이 없으면 다음 프롬프트에 다시 준다.
    @Test func restartedSessionWaitsForNewAck() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        #expect(h.processor.acknowledge(contextID: try #require(h.processor.lastContextID)))
        _ = try send(h, "doc-SessionStart", at: t0 + 600)
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == nil && s.contextPendingCount == 1)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 660)?.hasPrefix("Waypoint: LDG") == true)
    }

    /// outbox 흡수(앱이 꺼진 동안): 블록이 출력되지 않았으므로 대기도 ID도 없다. 앱이 켜진 뒤 첫 프롬프트에 블록과 ID.
    @Test func outboxLeavesNothingPendingAndLiveDeliversWithID() throws {
        let h = try HookHarness()
        #expect(try send(h, "doc-SessionStart", at: t0, delivers: false) == nil)
        #expect(h.processor.lastContextID == nil)
        h.processor.handle(Outbox.Entry(provider: .claude, event: "UserPromptSubmit", receivedAt: t0 + 30,
                                        payload: try fixture("doc-UserPromptSubmit"), claudePid: nil, processPid: nil))
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == nil && s.contextPendingID == nil)
        #expect(try send(h, "doc-UserPromptSubmit", at: t0 + 60)?.hasPrefix("Waypoint: LDG") == true)
        #expect(h.processor.acknowledge(contextID: try #require(h.processor.lastContextID)))
        #expect(s.contextProjectKey == "LDG")
    }

    /// Codex도 같은 확인을 쓴다.
    @Test func codexAckConfirms() throws {
        let h = try HookHarness()
        let text = try #require(try send(h, "doc-codex-SessionStart", at: t0, provider: .codex))
        #expect(text.contains("sessionId: codex:same-id"))
        let session = try #require(try h.session("codex:same-id"))
        #expect(session.contextProjectKey == nil)
        let late = try #require(try send(h, "doc-codex-UserPromptSubmit", at: t0 + 60, provider: .codex))
        #expect(late.contains("provider: codex"))
        #expect(h.processor.acknowledge(contextID: try #require(h.processor.lastContextID)))
        #expect(session.contextProjectKey == "LDG")
        #expect(try send(h, "doc-codex-UserPromptSubmit", at: t0 + 120, provider: .codex) == nil)
    }

    /// 프로젝트를 다시 연결하면(`session_bind` 등) 앞 프로젝트 블록의 대기는 지워진다. 늦은 확인이 와도 키를 적지 않는다.
    @Test func bindingClearsPendingBlock() throws {
        let h = try HookHarness()
        _ = try send(h, "doc-SessionStart", at: t0)
        let id = try #require(h.processor.lastContextID)
        let s = try #require(try h.session())
        let other = Project(key: "OCR", name: "영수증 인식", rootPath: "~/dev/ocr", createdAt: t0)
        h.context.insert(other)
        SessionProjectBinding.bind(s, to: other, at: t0 + 30, in: h.context)
        try h.context.save()
        #expect(!h.processor.acknowledge(contextID: id))
        #expect(s.contextProjectKey == nil)
    }

    /// 저장에 실패하면 응답 ID를 주지 않고(확인할 곳이 없다), 확인 저장에 실패하면 대기를 그대로 둔다.
    @Test func saveFailureKeepsStateConsistent() throws {
        let h = try HookHarness(onDisk: true)
        h.processor.saveContext = { _ in throw SaveFailure.diskUnavailable }
        _ = try send(h, "doc-SessionStart", at: t0)
        #expect(h.processor.lastSaveFailed && h.processor.lastContextID == nil)

        h.processor.saveContext = { try $0.save() }
        _ = try send(h, "doc-SessionStart", at: t0 + 10)
        let id = try #require(h.processor.lastContextID)
        h.processor.saveContext = { _ in throw SaveFailure.diskUnavailable }
        #expect(!h.processor.acknowledge(contextID: id))
        #expect(h.processor.lastSaveFailed)
        let s = try #require(try h.session())
        #expect(s.contextProjectKey == nil && s.contextPendingID == id)
        h.processor.saveContext = { try $0.save() }
        #expect(h.processor.acknowledge(contextID: id))
        #expect(s.contextProjectKey == "LDG")
    }
}

@Suite struct ContextAckRouterTests {
    func request(_ method: String, _ path: String, headers: [String: String] = [:], body: String = "{}") -> HTTPRequest {
        HTTPRequest(method: method, path: path, headers: headers, body: Data(body.utf8))
    }

    let id = "0f1e2d3c-4b5a-6978-8a9b-acbdcedf0123"

    /// 대기 ID가 있으면 본문 있는 200 응답에만 머리로 싣는다.
    @Test func contextIDHeaderOnlyOnBlockResponses() {
        let start = HookRouter.respond(to: request("POST", "/hooks/SessionStart"), handle: { _, _, _, _ in "Waypoint: LDG" },
                                       contextID: { id })
        #expect(start.status == 200 && start.headers["X-Waypoint-Context-ID"] == id)
        #expect(String(data: start.serialized(), encoding: .utf8)?.contains("X-Waypoint-Context-ID: \(id)\r\n") == true)
        let codex = HookRouter.respond(to: request("POST", "/hooks/codex/UserPromptSubmit"), handle: { _, _, _, _ in "Waypoint" },
                                       contextID: { id })
        #expect(codex.headers["X-Waypoint-Context-ID"] == id)
        let empty = HookRouter.respond(to: request("POST", "/hooks/SessionStart"), handle: { _, _, _, _ in "" },
                                       contextID: { id })
        #expect(empty == .text(""))
        let none = HookRouter.respond(to: request("POST", "/hooks/UserPromptSubmit"), handle: { _, _, _, _ in nil },
                                      contextID: { id })
        #expect(none == .noContent)
        let other = HookRouter.respond(to: request("POST", "/hooks/Stop"), handle: { _, _, _, _ in "x" }, contextID: { id })
        #expect(other == .noContent)
        let old = HookRouter.respond(to: request("POST", "/hooks/SessionStart")) { _, _, _, _ in "Waypoint" }
        #expect(old == .text("Waypoint"))
        let bad = HookRouter.respond(to: request("POST", "/hooks/SessionStart"), handle: { _, _, _, _ in "Waypoint" },
                                     contextID: { "bad id\r\nX: y" })
        #expect(bad == .text("Waypoint"))
    }

    @Test func ackCapabilityHeader() {
        #expect(HookRouter.acknowledges(request("POST", "/hooks/SessionStart", headers: ["x-waypoint-context-ack": "1"])))
        #expect(!HookRouter.acknowledges(request("POST", "/hooks/SessionStart")))
        #expect(!HookRouter.acknowledges(request("POST", "/hooks/SessionStart", headers: ["x-waypoint-context-ack": "0"])))
    }

    @Test func ackEndpoint() {
        var seen: [String] = []
        let ok = HookRouter.respondAck(to: request("POST", HookRouter.ackPath, body: #"{"contextId":"\#(id)"}"#)) { seen.append($0) }
        #expect(ok == .noContent && seen == [id])
        #expect(HookRouter.respondAck(to: request("GET", HookRouter.ackPath)) { seen.append($0) } == .methodNotAllowed)
        for body in ["", "{}", #"{"contextId":"nope"}"#, #"{"contextId":"\#(id.uppercased())"}"#, "[1]"] {
            #expect(HookRouter.respondAck(to: request("POST", HookRouter.ackPath, body: body)) { seen.append($0) } == .badRequest)
        }
        #expect(seen == [id])
    }

    @Test func contextIDShape() {
        #expect(HookRouter.isContextID(UUID().uuidString.lowercased()))
        #expect(!HookRouter.isContextID(UUID().uuidString))
        #expect(!HookRouter.isContextID(""))
        #expect(!HookRouter.isContextID("%header{x-waypoint-context-id}"))
    }
}
