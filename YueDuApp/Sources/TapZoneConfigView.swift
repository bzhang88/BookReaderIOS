import SwiftUI

/// Legado's real `ClickActionConfigDialog` is a 3x3 grid where each cell picks its own tap action
/// from a menu -- this mirrors that shape directly (see `ReaderTapZoneGrid`'s doc comment for why
/// the action set itself is smaller here: no pages to turn in a continuous-scroll reader).
struct TapZoneConfigView: View {
    @AppStorage(ReaderSettingsKey.tapZoneGrid) private var tapZoneGridRaw: String = ReaderTapZoneGrid.standardEncoded

    private var grid: ReaderTapZoneGrid {
        ReaderTapZoneGrid.decode(tapZoneGridRaw)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(0..<3, id: \.self) { col in
                                zoneCell(row: row, col: col)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            } header: {
                Text("点击区域")
            } footer: {
                Text("阅读时点击屏幕的对应区域会触发这里设置的动作，点每个格子可以更改。")
            }

            Section {
                Button("恢复默认") {
                    tapZoneGridRaw = ReaderTapZoneGrid.standardEncoded
                }
            }
        }
        .navigationTitle("点击区域设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func zoneCell(row: Int, col: Int) -> some View {
        let action = grid.action(row: row, col: col)
        Menu {
            ForEach(ReaderTapZoneAction.allCases) { candidate in
                Button {
                    var updated = grid
                    updated.setAction(candidate, row: row, col: col)
                    tapZoneGridRaw = updated.encoded()
                } label: {
                    if candidate == action {
                        Label(candidate.displayName, systemImage: "checkmark")
                    } else {
                        Text(candidate.displayName)
                    }
                }
            }
        } label: {
            Text(action.displayName)
                .font(.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
