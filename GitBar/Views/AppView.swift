import SwiftUI

struct StatusLegendItemView: View {
    let label: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)

            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

