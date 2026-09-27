import Foundation
import SwiftData

/// 시안(design/*.dc.html)과 같은 장면을 `now` 기준 상대 시각으로 채운다. 샘플 모드(메모리 저장소) 전용.
public enum SampleData {

    /// 프로젝트가 하나도 없을 때만 넣고 저장한다. 넣었으면 true.
    @discardableResult
    public static func seedIfEmpty(_ context: ModelContext, now: Date = Date()) throws -> Bool {
        var descriptor = FetchDescriptor<Project>()
        descriptor.fetchLimit = 1
        guard try context.fetch(descriptor).isEmpty else { return false }
        var seeder = Seeder(context: context, now: now)
        seeder.run()
        try context.save()
        return true
    }
}

/// 시드 조립. 분 단위 상대 시각(`ago`)으로 적는다.
private struct Seeder {
    let context: ModelContext
    let now: Date

    private static let hour: Double = 60
    private static let day: Double = 24 * 60

    func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    mutating func run() {
        seedLedger()
        seedSite()
        seedWaypoint()
        seedPix()
    }

    // MARK: - 조립 도우미

    func project(_ key: String, _ name: String, summary: String, root: String, stack: [String], created: Double) -> Project {
        let p = Project(key: key, name: name, summary: summary, rootPath: root, stack: stack, createdAt: ago(created))
        context.insert(p)
        return p
    }

    @discardableResult
    func card(
        _ p: Project, _ title: String, _ status: CardStatus, kind: CardKind = .task,
        created: Double, origin: CardOrigin = .manual, by session: Session? = nil,
        parent: Card? = nil, body: String = "", criteria: [Criterion] = [], log: Bool = true
    ) -> Card {
        let at = ago(created)
        let c = p.makeCard(
            in: context, title: title, kind: kind, status: status, body: body,
            origin: origin, originSessionId: session?.id, parent: parent, criteria: criteria, at: at
        )
        if log {
            Event.record(.cardCreated, in: context, card: c, session: session, at: at,
                         payload: ["status": .string(status.rawValue)])
        }
        return c
    }

    func session(
        _ p: Project, _ id: String, started: Double, lastSeen: Double? = nil,
        parent: Session? = nil, agent: String? = nil, branch: String? = nil
    ) -> Session {
        let s = Session(
            id: id, kind: parent == nil ? .main : .subagent, agentName: agent,
            cwd: p.rootPath, gitBranch: branch, startedAt: ago(started), lastSeenAt: ago(lastSeen ?? started)
        )
        context.insert(s)
        s.project = p
        s.parent = parent
        Event.record(.sessionStart, in: context, project: p, session: s, at: s.startedAt,
                     payload: agent.map { ["agentName": .string($0)] } ?? [:])
        return s
    }

    func end(_ s: Session, at minutesAgo: Double) {
        s.lastSeenAt = ago(minutesAgo)
        CardLifecycle.detachAll(s, at: ago(minutesAgo), in: context)
        Event.record(.sessionEnd, in: context, project: s.project, session: s, at: ago(minutesAgo))
    }

    func attach(_ c: Card, _ s: Session, at minutesAgo: Double) {
        CardLifecycle.attach(c, s, at: ago(minutesAgo), in: context)
    }

    func fileChanged(_ c: Card, _ s: Session, _ path: String, added: Int, removed: Int, at minutesAgo: Double) {
        Event.record(.fileChanged, in: context, card: c, session: s, at: ago(minutesAgo),
                     payload: ["path": .string(path), "added": .int(added), "removed": .int(removed)])
    }

    func commit(_ c: Card, _ s: Session, _ hash: String, _ message: String, at minutesAgo: Double) {
        Event.record(.commit, in: context, card: c, session: s, at: ago(minutesAgo),
                     payload: ["hash": .string(hash), "message": .string(message)])
    }

    func done(_ c: Card, at minutesAgo: Double) {
        try? CardLifecycle.move(c, to: .done, at: ago(minutesAgo), in: context)
    }

    /// 끝난 작업 세션 한 번: 시작 → 연결 → (파일·커밋) → 종료
    func pastSession(
        _ p: Project, _ c: Card, id: String, started: Double, length: Double,
        files: [(String, Int, Int)] = [], commits: [(String, String)] = [], finish: Bool = false
    ) {
        let s = session(p, id, started: started)
        attach(c, s, at: started)
        let endAt = started - length
        for (i, f) in files.enumerated() {
            fileChanged(c, s, f.0, added: f.1, removed: f.2, at: started - length * Double(i + 1) / Double(files.count + 2))
        }
        for (i, m) in commits.enumerated() {
            commit(c, s, m.0, m.1, at: endAt + Double(commits.count - i))
        }
        if finish { done(c, at: endAt + 0.5) }
        end(s, at: endAt)
    }

    // MARK: - LDG 가계부 앱

    mutating func seedLedger() {
        let d = Self.day, h = Self.hour
        let p = project("LDG", "가계부 앱",
                        summary: "SwiftUI 개인 가계부. 영수증 촬영 → 자동 분류가 핵심.",
                        root: "~/dev/ledger", stack: ["Swift", "SwiftUI", "SwiftData", "iOS 17+"], created: 21 * d)

        // 오래된 카드 1–9 (완료·보관, 아이디어 3개)
        let c1 = card(p, "프로젝트 초기 설정", .next, created: 21 * d)
        let c2 = card(p, "거래 모델 정의", .next, created: 21 * d - 10)
        card(p, "반복 지출 알림", .idea, kind: .idea, created: 20 * d)
        let c4 = card(p, "거래 목록 화면", .next, created: 20 * d - 30)
        let c5 = card(p, "거래 추가 폼", .next, created: 19 * d)
        card(p, "카테고리별 예산 설정", .idea, kind: .idea, created: 18 * d)
        let c7 = card(p, "CoreData 저장소 구성", .next, created: 17 * d)
        card(p, "가족과 가계부 공유", .idea, kind: .idea, created: 16 * d)
        let c9 = card(p, "금액 입력 키패드", .archived, created: 15 * d)
        for (c, at) in [(c1, 20 * d), (c2, 19 * d), (c4, 17 * d), (c5, 15 * d), (c7, 13 * d)] { done(c, at: at) }
        c9.updatedAt = ago(14 * d)

        // 10–13: 최근 완료
        let c10 = card(p, "월별 합계 뷰", .next, created: 12 * d)
        let c11 = card(p, "CoreData → SwiftData 이전", .next, created: 11 * d)
        card(p, "다크모드 색상 토큰 정리", .idea, kind: .idea, created: 10 * d)
        let c13 = card(p, "VisionKit 카메라 화면", .next, created: 8 * d)

        pastSession(p, c10, id: "2b9e04d1-6a3f-4c85-b1d7-0e4f9a3c6d52", started: 6 * d + 3 * h, length: 70,
                    files: [("Ledger/Views/MonthlySummaryView.swift", 96, 4)],
                    commits: [("4c1d9e0", "월별 합계 뷰 추가")], finish: true)
        pastSession(p, c11, id: "8d47c2a0-1f95-4e3b-a6c8-7b2e5d0f9134", started: 5 * d + 5 * h, length: 90,
                    files: [("Ledger/Store/LedgerStore.swift", 120, 88)])
        pastSession(p, c11, id: "f0a6b3e8-2c71-4d94-8e5a-3d9c1b7f0e26", started: 4 * d + 7 * h, length: 60,
                    files: [("Ledger/Models/Transaction.swift", 34, 51)])
        pastSession(p, c11, id: "61c8e9f2-4b0d-4a37-9f16-2e8a5c3d7b90", started: 4 * d + 2 * h, length: 45,
                    commits: [("b83f2a6", "SwiftData로 저장소 이전")], finish: true)
        pastSession(p, c13, id: "a3e5d7c9-0b2f-4e61-8d4a-6c1f9b3e5a07", started: 1 * d + 6 * h, length: 80,
                    files: [("Ledger/OCR/ReceiptScannerView.swift", 142, 0)],
                    commits: [("e1d7c40", "VisionKit 스캐너 화면"), ("7a0b3f5", "스캔 권한 안내")])
        pastSession(p, c13, id: "c9b1f3a5-7d2e-4c08-b6f4-1a3e7d9c5b21", started: 1 * d + 2 * h, length: 40,
                    commits: [("29fe6d1", "스캔 결과 미리보기")], finish: true)

        // 작업 계획 대화(9월 26일 밤) — 14–18, 20 생성
        let plan = session(p, "5d1c0e7a-93b4-4f28-a0d6-8e2b4c6f1a39", started: 40 * h, branch: "main")
        let planAt = 40 * h - 20
        let c14 = card(p, "영수증 OCR 결과를 거래 내역으로 매핑", .next, created: planAt, origin: .claude, by: plan,
                       body: """
                       VisionKit으로 읽은 텍스트 블록에서 가맹점명, 날짜, 합계 금액을 뽑아 `Transaction` 모델로 변환한다. \
                       금액이 여러 개 잡히면 “합계/총액” 키워드 근처 값을 우선한다.
                       """,
                       criteria: [
                           Criterion("가맹점명 · 날짜 추출", isDone: true),
                           Criterion("합계 금액 우선순위 규칙", isDone: true),
                           Criterion("인식 실패 필드는 nil로 두고 UI에서 표시"),
                           Criterion("샘플 영수증 10장 통과"),
                       ])
        c14.nextSessionNote = "카드 금액이 “승인금액”으로만 찍히는 영수증 케이스가 남음. 테스트 결과 보고 규칙 추가 여부 결정."
        card(p, "iCloud 동기화 충돌 처리", .next, created: planAt - 1)
        let c16 = card(p, "파서 단위 테스트 작성", .next, created: planAt - 2, origin: .claude, by: plan, parent: c14)
        card(p, "카테고리 자동 분류 규칙", .next, created: planAt - 3, origin: .claude, by: plan)
        card(p, "OCR 실패 시 수동 입력 폴백", .next, created: planAt - 4, origin: .claude, by: plan)
        card(p, "홈 화면 위젯으로 이번 달 지출 보기", .idea, kind: .idea, created: planAt - 5, origin: .claude, by: plan)
        card(p, "첫 실행 온보딩 3장", .next, created: planAt - 6, origin: .claude, by: plan)
        end(plan, at: 40 * h - 35)

        // 지금 작업중: sess 7f2a → LDG-14, 서브에이전트 test-writer → LDG-16
        let main = session(p, "7f2a9c41-3e8b-4d06-b5a2-9c7e1f4d8b60", started: 38, lastSeen: 0, branch: "feat/ocr-mapping")
        attach(c14, main, at: 38)
        card(p, "거래 내역 CSV 내보내기", .idea, kind: .idea, created: 18, origin: .claude, by: main)
        fileChanged(c14, main, "Ledger/OCR/ReceiptParser.swift", added: 84, removed: 12, at: 13)
        fileChanged(c14, main, "Ledger/Models/Transaction.swift", added: 6, removed: 1, at: 13)
        c14.updatedAt = ago(13)

        let sub = session(p, "3b6d8f0a-2c4e-4a79-8e1b-5d7f9a2c4e68", started: 12, lastSeen: 1,
                          parent: main, agent: "test-writer", branch: "feat/ocr-mapping")
        attach(c16, sub, at: 12)
        fileChanged(c16, sub, "LedgerTests/ReceiptParserTests.swift", added: 58, removed: 0, at: 2)

        // 지침 문서
        let doc = GuideDoc(relPath: "CLAUDE.md", content: Self.ledgerGuide, contentHash: "sample", lastSyncedAt: ago(1 * d))
        context.insert(doc)
        doc.project = p
        let v = GuideVersion(content: Self.ledgerGuide, at: ago(1 * d), source: .local)
        context.insert(v)
        v.doc = doc
        Event.record(.guideSynced, in: context, project: p, at: ago(1 * d),
                     payload: ["relPath": "CLAUDE.md", "source": .string(GuideSource.local.rawValue)])
    }

    // MARK: - WEB 포트폴리오 사이트

    mutating func seedSite() {
        let d = Self.day
        let p = project("WEB", "포트폴리오 사이트", summary: "Astro로 만든 개인 포트폴리오.",
                        root: "~/dev/site", stack: ["Astro", "TypeScript"], created: 30 * d)
        let olds = ["Astro 프로젝트 설정", "소개 페이지", "작업물 목록", "다국어 라우팅", "배포 설정"]
        for (i, t) in olds.enumerated() {
            let c = card(p, t, .next, created: 30 * d - Double(i) * d)
            done(c, at: 28 * d - Double(i) * 2 * d)
        }
        card(p, "블로그 RSS 피드", .idea, kind: .idea, created: 9 * d)
        card(p, "이미지 지연 로딩", .next, created: 8 * d)
        card(p, "모바일 메뉴 포커스 순서", .next, kind: .bug, created: 6 * d)
        let c9 = card(p, "작업물 상세 페이지 레이아웃", .next, created: 5 * d)
        card(p, "다크모드 전환 애니메이션", .idea, kind: .idea, created: 4 * d)
        card(p, "방문자 통계 붙이기", .idea, kind: .idea, created: 2 * d)

        let s = session(p, "c41e7b20-5d9a-4f13-8c6e-a0b2d4f69e15", started: 65, lastSeen: 1, branch: "work-detail")
        attach(c9, s, at: 64)
        fileChanged(c9, s, "src/pages/work/[slug].astro", added: 41, removed: 9, at: 3)
    }

    // MARK: - TRK Waypoint

    mutating func seedWaypoint() {
        let d = Self.day
        let p = project("TRK", "Waypoint", summary: "Claude Code 세션을 프로젝트 카드 보드로 추적하는 앱.",
                        root: "~/dev/waypoint", stack: ["Swift", "SwiftUI", "SwiftData"], created: 6 * d)
        let c1 = card(p, "프로젝트 골격", .next, created: 6 * d)
        let c2 = card(p, "명세와 시안 정리", .next, created: 6 * d - 20)
        done(c1, at: 5 * d)
        done(c2, at: 4 * d)
        let c3 = card(p, "훅 입력 로깅 모드", .next, created: 3 * d)
        card(p, "로컬 서버 헬스 체크", .next, created: 3 * d - 10)
        card(p, "outbox 흡수", .next, created: 3 * d - 20)
        card(p, "MCP 엔드포인트", .next, created: 3 * d - 30)
        let ideas = [
            "메뉴 막대 상주 모드", "iPhone 잠금화면 위젯", "카드 검색", "세션 타임라인 보기", "주간 작업 요약 화면",
            "지침 문서 비교 화면 단축키", "프로젝트 보관함", "카드 끌어서 순서 바꾸기", "알림: 멈춘 세션",
        ]
        for (i, t) in ideas.enumerated() {
            card(p, t, .idea, kind: .idea, created: 2 * d - Double(i) * 60)
        }

        // 멈춘 세션: 마지막 활동 22분 전
        let s = session(p, "09bd4e61-8a2f-4c57-b3d0-e6f1a9c2b784", started: 50, lastSeen: 22, branch: "hook-logging")
        attach(c3, s, at: 49)
        fileChanged(c3, s, "integration/hooks/waypoint-hook.sh", added: 23, removed: 4, at: 22)
        c3.updatedAt = ago(22)
    }

    // MARK: - PIX 사진 정리 스크립트

    mutating func seedPix() {
        let d = Self.day
        let p = project("PIX", "사진 정리 스크립트", summary: "촬영일 기준으로 사진 폴더를 정리하는 파이썬 스크립트.",
                        root: "~/dev/pix", stack: ["Python"], created: 20 * d)
        for (i, t) in ["EXIF 날짜 읽기", "연·월 폴더로 이동", "중복 파일 건너뛰기"].enumerated() {
            let c = card(p, t, .next, created: 20 * d - Double(i) * d)
            done(c, at: 18 * d - Double(i) * d)
        }
        card(p, "HEIC 변환 옵션", .next, created: 10 * d)
        let c5 = card(p, "실행 전 미리보기 출력", .next, created: 6 * d)
        pastSession(p, c5, id: "a91c3e20-7b4d-4e8f-9c16-d2f5a8b0e347", started: 3 * d + 50, length: 50,
                    files: [("pix/cli.py", 37, 6)],
                    commits: [("a91c3e2", "--dry-run 출력 정리")], finish: true)
    }

    // MARK: - 지침 문서 본문

    static let ledgerGuide = """
    # 가계부 앱

    - SwiftUI + SwiftData, iOS 17+.
    - OCR 파서는 `Ledger/OCR/`에 둔다. 금액 파싱은 Decimal만 쓴다.
    - 테스트: `xcodebuild test -scheme Ledger`
    """
}
