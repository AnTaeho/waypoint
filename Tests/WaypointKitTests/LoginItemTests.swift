import Foundation
import Testing
@testable import WaypointKit

/// 로그인할 때 열기(TRK-55): 언제 저절로 켜나 · 사용자 선택 존중 · Dev 금지 · 옛 항목.
@MainActor
@Suite struct LoginItemTests {
    typealias Policy = LoginItemPolicy

    final class FakeService: LoginItemService {
        var status: LoginItemStatus = .notRegistered
        var registers = 0
        var unregisters = 0
        var fails = false
        /// 등록하면 이 상태가 된다
        var afterRegister: LoginItemStatus = .enabled

        struct Failure: Error {}

        func register() throws {
            registers += 1
            if fails { throw Failure() }
            status = afterRegister
        }

        func unregister() throws {
            unregisters += 1
            if fails { throw Failure() }
            status = .notRegistered
        }
    }

    final class MemoryStore: LoginItemStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
    }

    // MARK: 판정

    @Test func devNeverRegisters() {
        for trigger in [Policy.Trigger.onboardingFinished, .launch(existingUser: true, legacyRemoved: true)] {
            #expect(Policy.action(trigger: trigger, isDev: true, userChoice: nil, autoApplied: false,
                                  status: .notRegistered) == .none)
        }
    }

    @Test func userChoiceIsRespected() {
        for choice in [true, false] {
            #expect(Policy.action(trigger: .onboardingFinished, isDev: false, userChoice: choice, autoApplied: false,
                                  status: .notRegistered) == .none)
            // 설치 스크립트가 지운 경우: 켜 둔 사람은 되살리고, 끈 사람은 그대로 둔다
            #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: true), isDev: false,
                                  userChoice: choice, autoApplied: false, status: .notRegistered)
                    == (choice ? .register : .none))
        }
    }

    @Test func autoAppliesOnlyOnce() {
        #expect(Policy.action(trigger: .onboardingFinished, isDev: false, userChoice: nil, autoApplied: true,
                              status: .notRegistered) == .none)
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: false), isDev: false,
                              userChoice: nil, autoApplied: true, status: .notRegistered) == .none)
    }

    @Test func launchWaitsForOnboardingWhenNew() {
        // 처음 쓰는 사람: 실행 때는 켜지 않고 온보딩 「끝」에서 켠다.
        #expect(Policy.action(trigger: .launch(existingUser: false, legacyRemoved: false), isDev: false,
                              userChoice: nil, autoApplied: false, status: .notRegistered) == .none)
        #expect(Policy.action(trigger: .onboardingFinished, isDev: false, userChoice: nil, autoApplied: false,
                              status: .notRegistered) == .register)
    }

    @Test func launchRegistersExistingUserOrLegacyItem() {
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: false), isDev: false,
                              userChoice: nil, autoApplied: false, status: .notRegistered) == .register)
        #expect(Policy.action(trigger: .launch(existingUser: false, legacyRemoved: true), isDev: false,
                              userChoice: nil, autoApplied: false, status: .notRegistered) == .register)
    }

    @Test func alreadyOnOnlyMarksApplied() {
        for status in [LoginItemStatus.enabled, .requiresApproval] {
            #expect(Policy.action(trigger: .onboardingFinished, isDev: false, userChoice: nil, autoApplied: false,
                                  status: status) == .markApplied)
        }
    }

    // MARK: 컨트롤러

    @Test func onboardingFinishRegistersOnce() {
        let service = FakeService(), store = MemoryStore()
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.onboardingFinished()
        #expect(service.registers == 1 && controller.status == .enabled)
        #expect(controller.autoApplied)
        // 시스템 설정에서 끈 뒤 다시 실행해도 되살리지 않는다.
        service.status = .notRegistered
        controller.launch(existingUser: true)
        controller.onboardingFinished()
        #expect(service.registers == 1 && controller.status == .notRegistered)
    }

    @Test func settingsChoiceBlocksAutoRegister() {
        let service = FakeService(), store = MemoryStore()
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.setEnabled(false)
        #expect(controller.userChoice == false && service.unregisters == 1)
        controller.onboardingFinished()
        controller.launch(existingUser: true)
        #expect(service.registers == 0 && controller.status == .notRegistered)
        controller.setEnabled(true)
        #expect(controller.userChoice == true && controller.status == .enabled)
    }

    @Test func legacyFlagIsConsumedAndRegisters() {
        let service = FakeService(), store = MemoryStore()
        store.set(true, forKey: LoginItemController.legacyRemovedKey)
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.launch(existingUser: false)
        #expect(service.registers == 1 && controller.status == .enabled)
        #expect(store.object(forKey: LoginItemController.legacyRemovedKey) == nil)
    }

    @Test func newUserLaunchDoesNothing() {
        let service = FakeService(), store = MemoryStore()
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.launch(existingUser: false)
        #expect(service.registers == 0 && !controller.autoApplied)
    }

    @Test func alreadyEnabledIsNotRegisteredAgain() {
        let service = FakeService(), store = MemoryStore()
        service.status = .enabled
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.launch(existingUser: true)
        #expect(service.registers == 0 && controller.autoApplied)
    }

    @Test func failedRegisterRetriesNextLaunch() {
        let service = FakeService(), store = MemoryStore()
        service.fails = true
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.launch(existingUser: true)
        #expect(controller.failed && !controller.autoApplied && controller.status == .notRegistered)
        service.fails = false
        controller.launch(existingUser: true)
        #expect(!controller.failed && controller.autoApplied && service.registers == 2)
    }

    @Test func requiresApprovalShowsOn() {
        let service = FakeService(), store = MemoryStore()
        service.afterRegister = .requiresApproval
        let controller = LoginItemController(service: service, store: store, isDev: false)
        controller.onboardingFinished()
        #expect(controller.status == .requiresApproval && controller.status.isOn)
    }

    @Test func devControllerNeverTouchesService() {
        let service = FakeService(), store = MemoryStore()
        service.status = .enabled
        store.set(true, forKey: LoginItemController.legacyRemovedKey)
        let controller = LoginItemController(service: service, store: store, isDev: true)
        #expect(controller.status == .notRegistered)
        controller.launch(existingUser: true)
        controller.onboardingFinished()
        controller.setEnabled(true)
        #expect(service.registers == 0 && service.unregisters == 0)
        #expect(controller.userChoice == nil && controller.status == .notRegistered)
    }

    @Test func legacyRemovalRestoresAppRegistration() {
        typealias Policy = LoginItemPolicy
        // 설치 스크립트가 System Events로 지운 항목이 앱이 등록한 것이어도, 사용자가 끈 적이 없으면 되살린다
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: true), isDev: false,
                              userChoice: nil, autoApplied: true, status: .notRegistered) == .register)
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: true), isDev: false,
                              userChoice: true, autoApplied: true, status: .notRegistered) == .register)
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: true), isDev: false,
                              userChoice: false, autoApplied: true, status: .notRegistered) == .none)
        #expect(Policy.action(trigger: .launch(existingUser: true, legacyRemoved: true), isDev: true,
                              userChoice: nil, autoApplied: true, status: .notRegistered) == .none)
    }
}
