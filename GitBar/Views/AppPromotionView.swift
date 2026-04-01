import SwiftUI

struct StatusLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status legend")
                .font(.headline)

            StatusLegendItemView(label: "Successful checks", tint: .green)
            StatusLegendItemView(label: "Failed checks", tint: .red)
            StatusLegendItemView(label: "Pending or action required", tint: .yellow)
            StatusLegendItemView(label: "Unknown status", tint: .gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
