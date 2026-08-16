import SwiftUI

struct PhotoGalleryView: View {
    @ObservedObject var viewModel: PhotoGalleryViewModel

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 72), spacing: 6)]

    var body: some View {
        ScrollView(.vertical) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(viewModel.slots.enumerated()), id: \.offset) { _, slot in
                    GallerySlotView(slot: slot)
                }
            }
            .padding(8)
        }
        .frame(height: 100)
        .background(Color.gray.opacity(0.05))
    }
}

private struct GallerySlotView: View {
    let slot: GallerySlot

    @State private var isPulsing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.clear)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                switch slot {
                case .skeleton:
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(isPulsing ? 0.15 : 0.3))
                        .onAppear {
                            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                                isPulsing = true
                            }
                        }
                case .loaded(let cgImage):
                    Image(decorative: cgImage, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
