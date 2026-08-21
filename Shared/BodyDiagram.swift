import SwiftUI

// MARK: - The muscle diagram, as real shapes
//
// BodyDiagram.json holds the anatomy drawing as plain geometry: one path per
// shape, in coordinates from 0 to 1 within its figure, each tagged with the
// muscle group it belongs to (or nothing, for the body itself).
//
// It is generated from the annotated SVG by tools/svg-to-bodydiagram.py, and
// regenerating after relabelling something in Inkscape is one command. Drawing
// the geometry ourselves rather than importing a picture is what makes each
// muscle tappable and highlightable — and it sidesteps the gradients, clip
// paths and <use> elements that made Xcode's SVG import produce half a body.

struct BodyDiagram: Decodable {

    struct Figure: Decodable {
        /// Width ÷ height of this figure's own bounding box.
        let aspect: CGFloat
        let paths: [Shape]
    }

    struct Shape: Decodable {
        /// Raw value of a MuscleGroup, or nil for parts that are just body.
        let group: String?
        /// Compact path: absolute M / L / C / Z in 0…1 coordinates.
        let d: String

        var muscle: MuscleGroup? { group.flatMap(MuscleGroup.init(rawValue:)) }
    }

    let figures: [String: Figure]

    var front: Figure? { figures["front"] }
    var back: Figure? { figures["back"] }

    /// Loaded once. A missing or unreadable file leaves an empty diagram rather
    /// than crashing: the picker then draws nothing, and the label buttons
    /// beside it still select every group.
    static let shared: BodyDiagram = {
        guard let url = Bundle.main.url(forResource: "BodyDiagram", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(BodyDiagram.self, from: data)
        else {
            assertionFailure("BodyDiagram.json missing or malformed")
            return BodyDiagram(figures: [:])
        }
        return decoded
    }()
}

// MARK: - Path building

extension BodyDiagram.Shape {

    /// Build the path scaled into `rect`.
    ///
    /// The scanner understands exactly what the converter emits — absolute M,
    /// L, C and Z — so anything else in the data is a converter bug rather than
    /// something to handle here.
    func path(in rect: CGRect) -> Path {
        var path = Path()
        var numbers: [CGFloat] = []
        var command: Character = "M"

        func point(_ i: Int) -> CGPoint {
            CGPoint(x: rect.minX + numbers[i] * rect.width,
                    y: rect.minY + numbers[i + 1] * rect.height)
        }
        func flush() {
            switch command {
            case "M" where numbers.count >= 2:
                path.move(to: point(0))
                // Extra pairs after a move are line segments.
                var i = 2
                while i + 1 < numbers.count { path.addLine(to: point(i)); i += 2 }
            case "L":
                var i = 0
                while i + 1 < numbers.count { path.addLine(to: point(i)); i += 2 }
            case "C":
                var i = 0
                while i + 5 < numbers.count {
                    path.addCurve(to: point(i + 4), control1: point(i), control2: point(i + 2))
                    i += 6
                }
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var scanner = d[d.startIndex...]
        while let ch = scanner.first {
            if ch == "M" || ch == "L" || ch == "C" {
                flush()
                command = ch
                scanner = scanner.dropFirst()
            } else if ch == "Z" {
                flush()
                path.closeSubpath()
                scanner = scanner.dropFirst()
            } else if ch == "," || ch == " " {
                scanner = scanner.dropFirst()
            } else {
                let end = scanner.firstIndex(where: { $0 == "," || $0 == " " ||
                                                      $0 == "M" || $0 == "L" ||
                                                      $0 == "C" || $0 == "Z" })
                             ?? scanner.endIndex
                if let value = Double(scanner[scanner.startIndex..<end]) {
                    numbers.append(CGFloat(value))
                }
                scanner = scanner[end...]
            }
        }
        flush()
        return path
    }
}

// MARK: - Prepared geometry
//
// Everything below is built ONCE, at load, in a unit square. The first version
// parsed each path string inside `body` and rebuilt every shape on every layout
// pass — a few hundred string scans per frame, which wedged the simulator
// outright. Scaling a ready-made Path is nearly free by comparison.

struct FigureGeometry {
    let aspect: CGFloat

    /// Every shape, prepared once in a unit square, in the drawing's own order.
    /// Order matters: these paths were drawn to be painted one over another,
    /// and rearranging them (or merging them into one path per group, which an
    /// earlier version did) makes fills spill into places the illustrator had
    /// covered up.
    let ordered: [(muscle: MuscleGroup?, path: Path)]

    /// One merged path per muscle group — for the highlight and for hit
    /// testing only, never for the base drawing. Ordered so the SMALLEST comes
    /// last: SwiftUI gives a tap to the topmost view, and a small muscle lying
    /// on a big sheet is the one that is otherwise unhittable, while the sheet
    /// keeps plenty of clear area elsewhere.
    let groups: [(group: MuscleGroup, path: Path)]

    init(figure: BodyDiagram.Figure) {
        aspect = figure.aspect
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)

        var all: [(MuscleGroup?, Path)] = []
        var byGroup: [MuscleGroup: Path] = [:]
        for shape in figure.paths {
            let path = shape.path(in: unit)
            all.append((shape.muscle, path))
            if let muscle = shape.muscle {
                byGroup[muscle, default: Path()].addPath(path)
            }
        }
        ordered = all.map { (muscle: $0.0, path: $0.1) }
        groups = byGroup
            .map { (group: $0.key, path: $0.value) }
            .sorted { a, b in
                let ra = a.path.boundingRect, rb = b.path.boundingRect
                return ra.width * ra.height > rb.width * rb.height
            }
    }

    static let front = FigureGeometry(figure: BodyDiagram.shared.front
                                      ?? BodyDiagram.Figure(aspect: 0.4, paths: []))
    static let back = FigureGeometry(figure: BodyDiagram.shared.back
                                     ?? BodyDiagram.Figure(aspect: 0.4, paths: []))
}

/// A prepared unit-space path, scaled into whatever rectangle it is given.
struct ScaledPath: SwiftUI.Shape {
    let unitPath: Path

    func path(in rect: CGRect) -> Path {
        unitPath
            .applying(CGAffineTransform(scaleX: rect.width, y: rect.height))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
