import Foundation

/// 원격·컨테이너 훅이 앱에 닿지 못해 쌓았다가 다시 보낸 줄(`POST /hooks/replay`, TRK-53).
/// Mac outbox와 따로 저장 폴더의 `replay/`에 두고(같은 줄 형식), 실시간 경로(`HookProcessor.handle(_:)`, 메인 context)로
/// 시간 예산만큼씩 처리한다. 한 번에 수백 줄이 와도 메인 액터를 오래 잡지 않아 로컬 훅이 1초 안에 답을 받는다.
/// outbox 흡수(`absorbOutbox`)처럼 새 context를 만들고 다시 읽지 않는다 — 줄마다 비용이 큰 다시 읽기를 조각마다 하게 된다.
/// 저장 실패는 실시간 훅과 같게(rollback 뒤 다시 읽기) 다루고, 그 줄부터 남겨 다음 점검에서 다시 한다.
public enum RemoteReplay {
    public static let folderName = "replay"

    /// 한 번(메인 큐 한 차례)에 쓰는 시간(초). 넘으면 남은 줄을 다음 차례로 넘긴다.
    public static let budget: TimeInterval = 0.1

    public static func directory(support: URL) -> URL {
        support.appendingPathComponent(folderName, isDirectory: true)
    }

    /// 처리할 줄이 남았는지(받아 둔 파일 또는 처리하다 멈춘 파일)
    public static func hasBacklog(directory: URL, fileManager: FileManager = .default) -> Bool {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { $0 == Outbox.fileName || $0.hasPrefix(Outbox.processingPrefix) }
    }

    /// 앞에서부터 `deadline`까지(한 줄은 반드시) 처리한다. 결과의 `more`면 남은 줄이 있다.
    @discardableResult
    public static func drain(directory: URL, processor: HookProcessor, deadline: Date?,
                             fileManager: FileManager = .default,
                             received: (Outbox.Entry) -> Void = { _ in }) -> Outbox.DrainResult {
        guard fileManager.fileExists(atPath: directory.path) else { return Outbox.DrainResult() }
        return Outbox.drain(directory: directory, fileManager: fileManager, deadline: deadline) { entry in
            processor.handle(entry)
            guard !processor.lastSaveFailed else { throw Outbox.SaveFailed() }
            received(entry)
        }
    }
}
