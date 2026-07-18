import SwiftUI

struct ControllerHUDView: View {
    let presentation: ControllerHUDPresentation
    let language: ControllerHUDLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.tint)
                Text(ControllerHUDCopy.title(language))
                    .font(.headline)
                Spacer()
                Text(ControllerHUDCopy.readyTitle(language))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 7) {
                ForEach(presentation.layers) { layer in
                    layerBadge(layer)
                }
            }

            Divider()

            Text(ControllerHUDCopy.slotsTitle(language))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 7),
                    count: 3
                ),
                spacing: 7
            ) {
                ForEach(presentation.slots) { slot in
                    slotBadge(slot)
                }
            }
        }
        .padding(14)
        .frame(width: 430, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.55))
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func layerBadge(
        _ layer: ControllerHUDPresentation.Layer
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ControllerHUDCopy.layer(layer.kind, language: language))
                .font(.caption.weight(.semibold))
            Text(ControllerHUDCopy.status(layer.status, language: language))
                .font(.caption2)
                .foregroundStyle(statusColor(layer.status))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(
            layer.isActive ? Color.accentColor.opacity(0.20) : .clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    layer.isActive ? Color.accentColor.opacity(0.7) :
                        Color.secondary.opacity(0.22)
                )
        }
    }

    @ViewBuilder
    private func slotBadge(
        _ slot: ControllerHUDPresentation.Slot
    ) -> some View {
        HStack(spacing: 5) {
            Text("\(slot.position)")
                .font(.caption.weight(.bold))
            Text(ControllerHUDCopy.status(slot.status, language: language))
                .font(.caption2)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(statusColor(slot.status))
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }

    private func statusColor(_ status: ControllerHUDStatus) -> Color {
        switch status {
        case .confirmed: .green
        case .unavailable: .orange
        case .unknown: .secondary
        }
    }
}
