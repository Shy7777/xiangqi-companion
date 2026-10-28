import SwiftUI

struct HistoryRuleBanner: View {
    let status: HistoryRuleStatus?
    var body: some View {
        if let status {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 6) {
                    Text(status.detail)
                    ForEach(status.evidence, id: \.self) { Text(verbatim: $0) }
                }.font(.system(size: 11)).foregroundColor(Studio.muted).padding(.top, 7)
            } label: {
                Label(status.title, systemImage: status.kind == .rulingNeeded ? "exclamationmark.circle" : "info.circle")
                    .font(.system(size: 12)).foregroundColor(Studio.accent)
            }.padding(11).background(Studio.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityIdentifier("history-rule-notice")
        }
    }
}
