import SwiftUI

struct ControllerHUDView: View {
    let presentation: ControllerHUDPresentation
    let language: ControllerHUDLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.tint)
                Text(ControllerHUDCopy.title(language))
                    .font(.headline)
            }

            ForEach(presentation.actions) { action in
                HStack(spacing: 10) {
                    Text(ControllerHUDCopy.key(action, language: language))
                        .font(.caption.weight(.bold))
                        .frame(width: 26)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

                    Text(ControllerHUDCopy.action(action, language: language))
                        .font(.callout)
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator.opacity(0.55))
        }
        .allowsHitTesting(false)
    }
}
