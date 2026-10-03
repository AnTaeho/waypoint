import Foundation
import Observation

/// 로그인할 때 열기(TRK-55). macOS의 `SMAppService.mainApp` 상태를 플랫폼 밖에서 다루려는 값.
public enum LoginItemStatus: Sendable, Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    /// 토글이 켜져 보이는가. 승인 대기도 사용자가 켠 것이다.
    public var isOn: Bool { self == .enabled || self == .requiresApproval }
}

/// 로그인 항목을 실제로 등록·해제하는 쪽. macOS 앱은 `SMAppService.mainApp`, Dev·테스트는 가짜.
@MainActor
public protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
}

/// 기억할 값(UserDefaults). 테스트는 메모리 사전으로 바꾼다.
@MainActor
public protocol LoginItemStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: LoginItemStore {}

/// 언제 저절로 켤까(순수 판정).
/// - Dev는 절대 켜지 않는다.
/// - 사용자가 설정에서 한 번이라도 고른 적이 있으면(켬·끔 모두) 건드리지 않는다.
/// - 저절로 켜기는 (성공한 뒤로) 한 번뿐이다. 그 뒤 시스템 설정에서 끈 것을 되살리지 않는다.
/// - 실행 때: 기존 사용자(프로젝트가 있거나 온보딩을 마침)이거나 설치 스크립트가 옛 로그인 항목을 지웠으면 켠다.
///   처음 쓰는 사람은 온보딩 「끝」에서 켠다.
public enum LoginItemPolicy {
    public enum Trigger: Sendable, Equatable {
        case launch(existingUser: Bool, legacyRemoved: Bool)
        case onboardingFinished
    }

    public enum Action: Sendable, Equatable {
        /// 아무것도 하지 않는다
        case none
        /// 이미 켜져 있다. 한 번 켠 것으로 기억만 한다
        case markApplied
        /// 등록하고 한 번 켠 것으로 기억한다
        case register
    }

    public static func action(
        trigger: Trigger, isDev: Bool, userChoice: Bool?, autoApplied: Bool, status: LoginItemStatus
    ) -> Action {
        if isDev { return .none }
        // 설치 스크립트가 지운 항목은 이 앱이 등록한 것일 수 있다(System Events 목록에 새 방식 항목도 보인다).
        // 사용자가 끈 적이 없으면 되살린다.
        if case .launch(_, true) = trigger, userChoice != false {
            return status.isOn ? .markApplied : .register
        }
        if userChoice != nil || autoApplied { return .none }
        switch trigger {
        case .launch(let existingUser, let legacyRemoved):
            guard existingUser || legacyRemoved else { return .none }
        case .onboardingFinished:
            break
        }
        return status.isOn ? .markApplied : .register
    }
}

/// 로그인 항목 상태와 사용자 선택. 설정 「일반」 탭과 실행·온보딩 「끝」이 함께 쓴다.
@MainActor @Observable
public final class LoginItemController {
    /// 설정에서 고른 값(Bool). 없으면 고른 적 없음
    public static let userChoiceKey = "loginItem.userChoice"
    /// 저절로 켜기를 한 번 했다(Bool)
    public static let autoAppliedKey = "loginItem.autoApplied"
    /// 설치 스크립트(`scripts/install-local.sh`)가 옛 System Events 로그인 항목을 지웠다(Bool). 읽으면 지운다
    public static let legacyRemovedKey = "WaypointLoginItemLegacyRemoved"

    public private(set) var status: LoginItemStatus
    /// 마지막 등록·해제가 실패했다
    public private(set) var failed = false
    public let isDev: Bool

    @ObservationIgnored private let service: LoginItemService
    @ObservationIgnored private let store: LoginItemStore

    public init(service: LoginItemService, store: LoginItemStore, isDev: Bool) {
        self.service = service
        self.store = store
        self.isDev = isDev
        self.status = isDev ? .notRegistered : service.status
    }

    public var userChoice: Bool? { store.object(forKey: Self.userChoiceKey) as? Bool }
    public var autoApplied: Bool { store.object(forKey: Self.autoAppliedKey) as? Bool ?? false }

    public func refresh() {
        guard !isDev else { return }
        status = service.status
    }

    /// 실행 때 한 번. 옛 항목 표시는 읽고 지운다.
    public func launch(existingUser: Bool) {
        let legacy = store.object(forKey: Self.legacyRemovedKey) as? Bool ?? false
        if legacy { store.removeObject(forKey: Self.legacyRemovedKey) }
        apply(.launch(existingUser: existingUser, legacyRemoved: legacy))
    }

    /// 온보딩 「끝」
    public func onboardingFinished() {
        apply(.onboardingFinished)
    }

    /// 설정 토글. 고른 값을 기억하고 등록·해제한다.
    public func setEnabled(_ on: Bool) {
        guard !isDev else { return }
        store.set(on, forKey: Self.userChoiceKey)
        failed = !perform { on ? try service.register() : try service.unregister() }
        refresh()
    }

    private func apply(_ trigger: LoginItemPolicy.Trigger) {
        refresh()
        let action = LoginItemPolicy.action(
            trigger: trigger, isDev: isDev, userChoice: userChoice, autoApplied: autoApplied, status: status)
        switch action {
        case .none:
            return
        case .markApplied:
            store.set(true, forKey: Self.autoAppliedKey)
        case .register:
            // 실패하면(옮기기 전의 앱 등) 다음 실행 때 다시 해 본다
            failed = !perform { try service.register() }
            if !failed { store.set(true, forKey: Self.autoAppliedKey) }
            refresh()
        }
    }

    private func perform(_ body: () throws -> Void) -> Bool {
        do { try body(); return true } catch { return false }
    }
}

/// Dev·샘플 화면용. 상태는 늘 꺼짐이고 등록하지 않는다.
@MainActor
public final class DisabledLoginItemService: LoginItemService {
    public init() {}
    public var status: LoginItemStatus { .notRegistered }
    public func register() throws {}
    public func unregister() throws {}
}
