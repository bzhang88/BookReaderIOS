import SwiftUI
import BookSourceModel

/// Browse/delete the covers `CoverPickerView` has saved over time -- a plain management screen,
/// not a picker (picking happens inline within `CoverPickerView` itself).
struct CoverGalleryManagementView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var covers: [SavedCover] = []

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        ScrollView {
            if covers.isEmpty {
                ContentUnavailableView(
                    "相册是空的", systemImage: "photo.on.rectangle",
                    description: Text("在书籍详情页更换封面时选用的图片会自动出现在这里")
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(covers) { cover in
                        VStack(spacing: 4) {
                            AsyncImage(url: URL(string: cover.url)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(.quaternary)
                                }
                            }
                            .frame(width: 90, height: 126)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(cover.bookName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await delete(cover) }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("封面相册")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
    }

    private func reload() async {
        covers = (try? await env.coverGalleryStore.all()) ?? []
    }

    private func delete(_ cover: SavedCover) async {
        try? await env.coverGalleryStore.remove(id: cover.id)
        await reload()
    }
}
