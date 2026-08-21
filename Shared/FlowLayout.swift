import SwiftUI

// MARK: - FlowLayout
//
// Lays subviews left to right, wrapping to a new line when the next one would
// not fit — what a row of tags or chips wants, and what neither HStack (never
// wraps) nor LazyVGrid (forces a column width on items of different widths)
// gives. Each item keeps its natural width, so short labels stay short.

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unspecified width (inside a ScrollView, say) would otherwise let
        // everything sit on one endless line.
        let maxWidth = proposal.width ?? .infinity
        let rows = layout(subviews: subviews, maxWidth: maxWidth)
        let height = rows.reduce(0) { $0 + $1.height } +
                     lineSpacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        let rows = layout(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat = {
                switch alignment {
                case .center:   return bounds.minX + (bounds.width - row.width) / 2
                case .trailing: return bounds.maxX - row.width
                default:        return bounds.minX
                }
            }()
            for item in row.items {
                let size = subviews[item].sizeThatFits(.unspecified)
                subviews[item].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                     proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func layout(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            // Always keep at least one item per row: an item wider than the
            // container still has to go somewhere.
            if needed > maxWidth, !row.items.isEmpty {
                rows.append(row)
                row = Row()
                row.items = [index]
                row.width = size.width
                row.height = size.height
            } else {
                row.items.append(index)
                row.width = needed
                row.height = max(row.height, size.height)
            }
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}
