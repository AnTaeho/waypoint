import SwiftData
import SwiftUI
import WaypointKit

/// 프로젝트 보드: 머리(이름·키·요약·폴더)와 네 칸(아이디어·나중에 / 다음 할 일 / 작업중 / 완료).
struct ProjectBoardView: View {
    let project: Project
    @Environment(\.modelContext) private var context

    var body: some View {
        LiveDataTimeline { now in
            content(now: now)
        }
        .background(Theme.bg)
        .navigationTitle(project.name)
    }

    private func content(now: Date) -> some View {
        let columns = BoardQuery.columns(for: project, now: now)
        let tiles = BoardQuery.sessionTiles(for: project, now: now)
        // GeometryReader로 감싸 보드의 최소 폭이 분할 뷰로 번지지 않게 한다(사이드바·인스펙터가 눌려 잘리는 문제).
        return GeometryReader { proxy in
            let boardWidth = max(proxy.size.width - Theme.Spacing.pageH * 2, minimumBoardWidth)
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                BoardHeader(project: project)
                    .padding(.horizontal, Theme.Spacing.pageH)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: Theme.Spacing.l) {
                        ForEach(BoardColumn.allCases, id: \.self) { column in
                            BoardColumnView(
                                column: column,
                                items: columns[column] ?? [],
                                now: now,
                                tiles: column == .active ? tiles : [],
                                onDrop: { id in drop(id, on: column) }
                            )
                        }
                    }
                    .frame(width: boardWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, Theme.Spacing.pageH)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                // 창이 좁아 칸이 넘칠 때 넘긴다는 것이 보이게 막대를 늘 보인다.
                .scrollIndicators(.visible, axes: .horizontal)
            }
            .padding(.vertical, Theme.Spacing.pageV)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
    }

    private var minimumBoardWidth: CGFloat {
        let count = CGFloat(BoardColumn.allCases.count)
        return Theme.Size.boardColumnMinWidth * count + Theme.Spacing.l * (count - 1)
    }

    /// 끌어 놓은 카드(UUID 문자열)를 이 프로젝트에서 찾아 옮기고 저장한다.
    private func drop(_ id: String, on column: BoardColumn) -> Bool {
        guard let card = (project.cards ?? []).first(where: { $0.id.uuidString == id }) else { return false }
        return BoardQuery.dropAndSave(card, on: column, at: Date(), in: context)
    }
}

/// 보드 머리: 이름(페이지 제목) + 키, 요약, 폴더 경로.
private struct BoardHeader: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Text(project.name)
                    .font(Theme.pageTitle)
                    .foregroundStyle(Theme.text)
                Text(project.key)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.horizontal, Theme.Spacing.s - 1)
                    .padding(.vertical, Theme.Spacing.xxs)
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.badge)
                            .strokeBorder(Theme.border, lineWidth: Theme.Size.cardBorder)
                    }
                Spacer(minLength: Theme.Spacing.m)
                GitHubBoardButton(project: project)
            }
            if !project.summary.isEmpty {
                Text(project.summary)
                    .font(Theme.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !project.rootPath.isEmpty {
                Text(project.rootPath)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textMuted)
                    .textSelection(.enabled)
            }
        }
    }
}
