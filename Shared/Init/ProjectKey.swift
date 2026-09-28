import Foundation

/// 프로젝트 카드 키 규칙: 영문 대문자 2–5자, 보관된 것까지 포함해 다른 프로젝트 키와 겹치지 않는다.
/// CloudKit 호환 때문에 unique 속성을 쓰지 않으므로 중복은 여기서 막는다.
public enum ProjectKey {

    public static let lengthRange = 2...5

    public enum Problem: Equatable, Sendable {
        /// `^[A-Z]{2,5}$`가 아님
        case format
        /// 다른 프로젝트가 쓰는 키
        case taken
    }

    /// 입력을 키 모양으로: 앞뒤 공백을 떼고 대문자로. 글자를 버리거나 자르지 않는다(규칙 검사는 `problem`).
    public static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    public static func isValidFormat(_ key: String) -> Bool {
        lengthRange.contains(key.count) && key.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
    }

    /// 규칙 위반. 없으면 nil. `taken`은 대문자 키 집합(보관 포함).
    public static func problem(_ key: String, taken: Set<String>) -> Problem? {
        guard isValidFormat(key) else { return .format }
        return taken.contains(key) ? .taken : nil
    }

    /// 이름·폴더 이름에서 키를 추천한다. 겹치지 않는 첫 후보.
    /// 1) 이름의 영문 단어 머리글자 2–4자(「Waypoint Init Probe」 → WIP)
    /// 2) 첫 영문 단어의 앞 3자(자음 우선: 「ledger」 → LDG)
    /// 3) 위 후보 뒤에 글자를 하나 붙인 변형(WIPA, WIPB …)
    /// 영문이 없으면 폴더 이름으로 같은 순서, 그래도 없으면 `PRJ` 기준 변형.
    public static func suggest(name: String, folder: String, taken: Set<String>) -> String {
        var bases: [String] = []
        for source in [name, folder] {
            let words = words(in: source)
            guard !words.isEmpty else { continue }
            if words.count >= 2 {
                bases.append(String(words.prefix(4).compactMap(\.first)))
            }
            bases.append(consonantKey(words[0]))
            bases.append(String(words[0].prefix(3)))
        }
        bases.append("PRJ")
        bases = bases.filter { isValidFormat($0) }

        for base in bases where !taken.contains(base) { return base }
        let letters = (UnicodeScalar("A").value...UnicodeScalar("Z").value).compactMap { UnicodeScalar($0).map(Character.init) }
        for base in bases {
            let stem = String(base.prefix(lengthRange.upperBound - 1))
            for letter in letters {
                let candidate = stem + String(letter)
                if !taken.contains(candidate) { return candidate }
            }
        }
        // 26 × 후보 수가 모두 찼을 때(현실적으로 없음): 두 글자 조합을 차례로
        for a in letters { for b in letters { for c in letters {
            let candidate = String([a, b, c])
            if !taken.contains(candidate) { return candidate }
        } } }
        return "PRJ"
    }

    /// 영문 단어(대문자). 카멜 표기와 숫자·기호 경계에서 나눈다.
    static func words(in text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previousLower = false
        for scalar in text.unicodeScalars {
            let isUpper = ("A"..."Z").contains(scalar)
            let isLower = ("a"..."z").contains(scalar)
            guard isUpper || isLower else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previousLower = false
                continue
            }
            if isUpper && previousLower && !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(Character(scalar))
            previousLower = isLower
        }
        if !current.isEmpty { words.append(current) }
        return words.map { $0.uppercased() }
    }

    /// 첫 글자 + 이어지는 자음 두 개(「LEDGER」 → LDG). 자음이 모자라면 남은 글자로 채운다.
    static func consonantKey(_ word: String) -> String {
        guard let first = word.first else { return "" }
        let rest = word.dropFirst()
        let vowels: Set<Character> = ["A", "E", "I", "O", "U"]
        var picked = rest.filter { !vowels.contains($0) }.prefix(2)
        if picked.count < 2 { picked = rest.prefix(2) }
        return String(first) + String(picked)
    }
}
