import SwiftUI
import UIKit
import Photos

// Independent Paint module. Coordinates are normalised, so drawings survive
// iPad multitasking, device rotation and changes between compact/regular screens.
struct PaintPoint: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
}

struct PaintStroke: Codable, Equatable {
    var points: [PaintPoint]
    var paletteIndex: Int
    var thickness: CGFloat
    var eraser: Bool
}

enum PaintPalette {
    static let colors: [UIColor] = [
        .black, .darkGray, .systemRed, .systemOrange,
        .systemYellow, .systemGreen, .systemTeal, .systemBlue,
        .systemIndigo, .systemPurple, .systemPink, .brown
    ]
    static let names = [
        "Czarny", "Szary", "Czerwony", "Pomarańczowy",
        "Żółty", "Zielony", "Turkusowy", "Niebieski",
        "Indygo", "Fioletowy", "Różowy", "Brązowy"
    ]
}

final class PaintDocument: ObservableObject {
    @Published private(set) var strokes: [PaintStroke] = []
    @Published private(set) var redoStrokes: [PaintStroke] = []
    @Published var selectedColor = 0
    @Published var thickness: Double = 6
    @Published var isEraser = false
    @Published private(set) var revision = 0

    private let shouldPersist: Bool

    private static var storage: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("shader-lab-paint.json")
    }

    init(loadExisting: Bool = true) {
        shouldPersist = loadExisting
        if loadExisting, let bytes = try? Data(contentsOf: Self.storage),
           let saved = try? JSONDecoder().decode([PaintStroke].self, from: bytes) {
            strokes = saved.filter { !$0.points.isEmpty }
        }
    }

    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !redoStrokes.isEmpty }

    func append(_ stroke: PaintStroke) {
        guard !stroke.points.isEmpty else { return }
        strokes.append(stroke)
        redoStrokes.removeAll()
        changed()
    }

    func undo() {
        guard let last = strokes.popLast() else { return }
        redoStrokes.append(last)
        changed()
    }

    func redo() {
        guard let last = redoStrokes.popLast() else { return }
        strokes.append(last)
        changed()
    }

    func clear() {
        guard !strokes.isEmpty else { return }
        redoStrokes.append(contentsOf: strokes.reversed())
        strokes.removeAll()
        changed()
    }

    private func changed() {
        revision += 1
        if shouldPersist, let bytes = try? JSONEncoder().encode(strokes) {
            try? bytes.write(to: Self.storage, options: .atomic)
        }
    }

    static func render(_ strokes: [PaintStroke], size: CGSize, scale: CGFloat = 2) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            UIColor.white.setFill()
            renderer.cgContext.fill(CGRect(origin: .zero, size: size))
            let context = renderer.cgContext
            for stroke in strokes {
                draw(stroke, in: context, size: size)
            }
        }
    }

    static func draw(_ stroke: PaintStroke, in context: CGContext, size: CGSize) {
        guard let first = stroke.points.first else { return }
        context.saveGState()
        let color = stroke.eraser ? UIColor.white : PaintPalette.colors[
            min(max(stroke.paletteIndex, 0), PaintPalette.colors.count - 1)
        ]
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(stroke.thickness)
        let start = CGPoint(x: first.x * size.width, y: first.y * size.height)
        if stroke.points.count == 1 {
            let diameter = stroke.thickness
            context.fillEllipse(in: CGRect(x: start.x - diameter / 2,
                                           y: start.y - diameter / 2,
                                           width: diameter, height: diameter))
        } else {
            context.beginPath()
            context.move(to: start)
            for point in stroke.points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
            context.strokePath()
        }
        context.restoreGState()
    }
}

final class PaintSurfaceView: UIView {
    var document: PaintDocument? { didSet { setNeedsDisplay() } }
    private var currentStroke: PaintStroke?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        isMultipleTouchEnabled = false
        contentMode = .redraw
        isOpaque = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .white
        isMultipleTouchEnabled = false
        contentMode = .redraw
        isOpaque = true
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0, bounds.height > 0 else { return }
        UIColor.white.setFill()
        ctx.fill(bounds)
        for stroke in document?.strokes ?? [] {
            PaintDocument.draw(stroke, in: ctx, size: bounds.size)
        }
        if let currentStroke {
            PaintDocument.draw(currentStroke, in: ctx, size: bounds.size)
        }
    }

    private func point(_ touch: UITouch) -> PaintPoint {
        let location = touch.location(in: self)
        return PaintPoint(x: max(0, min(1, location.x / max(bounds.width, 1))),
                          y: max(0, min(1, location.y / max(bounds.height, 1))))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard currentStroke == nil, let touch = touches.first, let document,
              bounds.width > 0, bounds.height > 0 else { return }
        currentStroke = PaintStroke(points: [point(touch)], paletteIndex: document.selectedColor,
                                    thickness: CGFloat(document.thickness),
                                    eraser: document.isEraser)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var currentStroke, let touch = touches.first else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            let next = point(sample)
            if next != currentStroke.points.last {
                currentStroke.points.append(next)
            }
        }
        self.currentStroke = currentStroke
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var stroke = currentStroke else { return }
        if let touch = touches.first {
            let last = point(touch)
            if last != stroke.points.last { stroke.points.append(last) }
        }
        currentStroke = nil
        document?.append(stroke)
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        currentStroke = nil
        setNeedsDisplay()
    }
}

struct PaintCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var document: PaintDocument

    func makeUIView(context: Context) -> PaintSurfaceView {
        let surface = PaintSurfaceView()
        surface.document = document
        return surface
    }

    func updateUIView(_ surface: PaintSurfaceView, context: Context) {
        if surface.document !== document { surface.document = document }
        _ = document.revision
        surface.setNeedsDisplay()
    }
}

struct PaintShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ viewController: UIActivityViewController, context: Context) {}
}

// Workspace layout: the canvas fills the screen while tools stay on the right.
// No ScrollView or drag gesture is placed above the drawing surface.
struct PaintView: View {
    var onExit: () -> Void = {}
    @StateObject private var document = PaintDocument()
    @State private var showClearConfirmation = false
    @State private var exportImage: UIImage?
    @State private var showShare = false

    var body: some View {
        GeometryReader { layout in
            let compact = layout.size.width < 600
            let toolsWidth: CGFloat = compact ? 98 : min(236, layout.size.width * 0.27)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(LabStyle.accent)
                        Text("PAINT")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Spacer(minLength: 2)
                        Text("\(document.strokes.count)")
                            .monospacedDigit()
                            .font(.caption)
                            .foregroundStyle(LabStyle.muted)
                        Image(systemName: "pencil.line")
                            .font(.caption)
                            .foregroundStyle(LabStyle.muted)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 35)
                    .background(LabStyle.panel)

                    GeometryReader { canvas in
                        PaintCanvasRepresentable(document: document)
                            .frame(width: canvas.size.width, height: canvas.size.height)
                            .background(Color.white)
                            .accessibilityLabel("Pełnoekranowe płótno Paint do rysowania palcem lub Apple Pencil")
                    }
                    .background(.white)
                    .overlay(Rectangle().strokeBorder(LabStyle.border, lineWidth: 1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Rectangle()
                    .fill(LabStyle.border)
                    .frame(width: 1)

                ScrollView(.vertical) {
                    toolSidebar(compact: compact)
                        .padding(.horizontal, compact ? 6 : 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.hidden)
                .frame(width: toolsWidth, height: layout.size.height)
                .background(LabStyle.panel)
                .accessibilityLabel("Panel narzędzi Paint po prawej stronie")
            }
            .frame(width: layout.size.width, height: layout.size.height)
            .background(LabStyle.background)
        }
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .sheet(isPresented: $showShare) {
            if let exportImage { PaintShareSheet(image: exportImage) }
        }
        .confirmationDialog("Wyczyścić cały rysunek?", isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Wyczyść płótno", role: .destructive) { document.clear() }
            Button("Anuluj", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func toolSidebar(compact: Bool) -> some View {
        VStack(alignment: .center, spacing: compact ? 12 : 16) {
            Button(action: onExit) {
                Label(compact ? "WYJDŹ" : "Wróć do aplikacji", systemImage: "arrow.left")
                    .font(.system(size: compact ? 10 : 12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Zamknij pełnoekranowy Paint i pokaż zakładki aplikacji")

            Text("NARZĘDZIA")
                .font(.system(size: compact ? 9 : 12, weight: .bold))
                .foregroundStyle(LabStyle.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if compact {
                toolButton("Pędzel", symbol: "pencil.tip", active: !document.isEraser, compact: true) {
                    document.isEraser = false
                }
                toolButton("Gumka", symbol: "eraser.fill", active: document.isEraser, compact: true) {
                    document.isEraser = true
                }
            } else {
                HStack(spacing: 6) {
                    toolButton("Pędzel", symbol: "pencil.tip", active: !document.isEraser, compact: false) {
                        document.isEraser = false
                    }
                    toolButton("Gumka", symbol: "eraser.fill", active: document.isEraser, compact: false) {
                        document.isEraser = true
                    }
                }
            }

            Divider().overlay(LabStyle.border)
            Text("KOLORY")
                .font(.system(size: compact ? 9 : 11, weight: .bold))
                .foregroundStyle(LabStyle.muted)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5),
                                     count: compact ? 2 : 4), spacing: 7) {
                ForEach(PaintPalette.colors.indices, id: \.self) { index in
                    Button {
                        document.selectedColor = index
                        document.isEraser = false
                    } label: {
                        Circle()
                            .fill(Color(uiColor: PaintPalette.colors[index]))
                            .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                            .padding(3)
                            .overlay(Circle().strokeBorder(
                                document.selectedColor == index && !document.isEraser
                                    ? LabStyle.accent : .clear, lineWidth: 2))
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(PaintPalette.names[index])
                }
            }

            Divider().overlay(LabStyle.border)
            VStack(spacing: 5) {
                Text(compact ? "ROZMIAR" : "GRUBOŚĆ PĘDZLA")
                    .font(.system(size: compact ? 9 : 11, weight: .bold))
                    .foregroundStyle(LabStyle.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(Int(document.thickness)) px")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LabStyle.accent)
                Slider(value: $document.thickness, in: 2...32, step: 1)
                    .accessibilityLabel("Grubość pędzla")
            }

            Divider().overlay(LabStyle.border)
            if compact {
                toolButton("Cofnij", symbol: "arrow.uturn.backward", active: false,
                           compact: true, enabled: document.canUndo) {
                    document.undo()
                }
                toolButton("Ponów", symbol: "arrow.uturn.forward", active: false,
                           compact: true, enabled: document.canRedo) {
                    document.redo()
                }
            } else {
                HStack(spacing: 6) {
                    toolButton("Cofnij", symbol: "arrow.uturn.backward", active: false,
                               compact: false, enabled: document.canUndo) {
                        document.undo()
                    }
                    toolButton("Ponów", symbol: "arrow.uturn.forward", active: false,
                               compact: false, enabled: document.canRedo) {
                        document.redo()
                    }
                }
            }

            toolButton("Wyczyść", symbol: "trash", active: false,
                       compact: compact, enabled: document.canUndo) {
                showClearConfirmation = true
            }

            Button {
                // Keep the export's pixel dimensions stable between screen orientations.
                exportImage = PaintDocument.render(
                    document.strokes, size: CGSize(width: 1400, height: 1000))
                showShare = true
            } label: {
                if compact {
                    VStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 19, weight: .semibold))
                        Text("ZAPISZ")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                } else {
                    Label("Zapisz / udostępnij", systemImage: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 42)
                }
            }
            .buttonStyle(LabPrimaryButtonStyle())
            .accessibilityLabel("Zapisz lub udostępnij obraz")
        }
    }

    private func toolButton(_ title: String, symbol: String, active: Bool,
                            compact: Bool, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if compact {
                VStack(spacing: 5) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: .medium))
                    Text(title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                Label(title, systemImage: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
        }
        .buttonStyle(LabChipStyle(active: active))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}
