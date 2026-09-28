import Foundation

/// 로컬 파일과 앱 기록을 맞추는 판정. 해시만 보고 결정하는 순수 함수.
public enum GuideSync {

    /// 로컬 파일을 확인했을 때 할 일.
    public enum Decision: Equatable, Sendable {
        /// 저장된 내용과 같다(앱 자신의 쓰기 포함).
        case none
        /// 로컬 내용을 반영한다(버전 local). 저장 안 한 편집이 있었으면 버린다(같은 내용이거나 원문과 같을 때만 이 판정).
        case applyLocal(String)
        /// 저장 안 한 편집과 로컬 변경이 겹쳤다. 병합하지 않고 로컬 내용을 들고 멈춘다.
        case conflict(String)
        /// 파일이 없어졌다(처음 확인한 때만).
        case markMissing
        /// 없던 파일이 저장된 내용 그대로 다시 생겼다.
        case clearMissing
    }

    /// - Parameters:
    ///   - storedContent: 앱이 마지막으로 맞춘 내용(`GuideDoc.content`)
    ///   - storedHash: 그 해시(`GuideDoc.contentHash`)
    ///   - draft: 저장 안 한 편집(`GuideDoc.draft`)
    ///   - wasMissing: 이전 확인에서 파일이 없었나
    ///   - disk: 지금 디스크 상태
    public static func decide(
        storedContent: String,
        storedHash: String,
        draft: String?,
        wasMissing: Bool,
        disk: GuideFile.Disk
    ) -> Decision {
        guard case .present(let content, let hash) = disk else {
            return wasMissing ? .none : .markMissing
        }
        if hash == storedHash {
            return wasMissing ? .clearMissing : .none
        }
        guard let draft, draft != storedContent, draft != content else {
            return .applyLocal(content)
        }
        return .conflict(content)
    }

    /// 앱에서 저장하기 직전 확인.
    public enum SaveCheck: Equatable, Sendable {
        /// 파일이 마지막 동기화 그대로거나 없다(없으면 새로 만든다).
        case write
        /// 편집하는 사이 파일이 바뀌었다. 로컬 내용을 들고 비교 화면으로.
        case conflict(String)
    }

    public static func checkBeforeSave(storedHash: String, disk: GuideFile.Disk) -> SaveCheck {
        switch disk {
        case .missing:
            return .write
        case .present(let content, let hash):
            return hash == storedHash ? .write : .conflict(content)
        }
    }
}
