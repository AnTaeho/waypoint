import Foundation

public struct HandoffFreshness {
    public let writtenAt: Date?
    public let changedFileCount: Int

    public var label: String {
        guard let writtenAt else { return "메모 작성 시각 알 수 없음" }
        let date = writtenAt.formatted(date: .abbreviated, time: .shortened)
        return "메모 작성 · \(date) · " + (changedFileCount > 0
            ? "이후 파일 \(changedFileCount)개 변경" : "이후 기록된 파일 변경 없음")
    }

    public static func evaluate(_ card: Card) -> Self? {
        guard let note = card.nextSessionNote?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else { return nil }
        let events = (card.events ?? []).filter { $0.card?.id == card.id && $0.project?.id == card.project?.id }
        // 카드의 일반 수정 시각은 메모 시각이 아니다. 현재 내용과 일치하는 마지막 메모만 사용한다.
        let latest = events.filter { $0.type == .note && $0.payloadValues["kind"]?.stringValue == "handoff" }
            .max { $0.at < $1.at }
        guard let latest, latest.payloadValues["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) == note else {
            return Self(writtenAt: nil, changedFileCount: 0)
        }
        let paths = events.filter { $0.type == .fileChanged && $0.at > latest.at }
            .compactMap { $0.payloadValues["path"]?.stringValue }.filter { !$0.isEmpty }
        return Self(writtenAt: latest.at, changedFileCount: Set(paths).count)
    }
}
