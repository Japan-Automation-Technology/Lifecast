import SwiftUI

struct VideoGridPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(0..<9, id: \.self) { idx in
                    Rectangle()
                        .fill(idx % 2 == 0 ? Color.blue.opacity(0.3) : Color.pink.opacity(0.3))
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .overlay {
                            Text("#\(idx + 1)")
                                .font(.caption2)
                        }
                }
            }
            Spacer()
        }
    }
}

struct ProfileTabIconStrip: View {
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            iconButton(index: 0, systemName: "folder")
            iconButton(index: 1, systemName: "square.grid.3x3")
            iconButton(index: 2, systemName: "heart")
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    private func iconButton(index: Int, systemName: String) -> some View {
        Button {
            selectedIndex = index
        } label: {
            Image(systemName: selectedIndex == index ? "\(systemName).fill" : systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedIndex == index ? Color.white : Color.clear)
                .clipShape(Capsule())
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
    }
}
