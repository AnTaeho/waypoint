import Foundation
import WaypointKit

extension AppServices {
    /// 이슈·PR 열기 도구는 몇 초 걸린다. 응답을 미뤄 그동안 메인 큐가 훅과 다른 요청을 받게 한다(TRK-68).
    func deferGitHub(on server: LocalServer, mcp: MCPServer) {
        server.deferredHandler = { [weak self] request, send in
            guard let message = MCPRouter.deferredCall(request) else { return false }
            let taken = mcp.handleDeferred(message) { reply in
                send(.json(reply.serialized()))
                guard let self else { return }
                self.markDataChanged()
                self.reliability.checkResumes(in: self.container.mainContext)
            }
            if taken { self?.integration.receiveMCP() }
            return taken
        }
    }
}
