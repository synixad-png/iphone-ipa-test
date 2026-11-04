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

struct PaintView: View {
    @StateObject private var document = PaintDocument()
    @State private var showClearConfirmation = false
    @State private var exportImage: UIImage?
    @State private var showShare = false
    @State private var canvasSize = CGSize(width: 600, height: 450)

    // Only the tool palette scrolls; the drawing canvas never sits inside a ScrollView.
    // This prevents a finger stroke from panning the entire screen.
    var body: some View {
        GeometryReader { layout in
            let wide = layout.size.width > 760
            ZStack {
                LabStyle.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .foregroundStyle(LabStyle.accent)
                            .frame(width: 44, height: 44)
                            .background(LabStyle.accent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PAINT")
                                .font(.system(size: wide ? 26 : 21,
                                              weight: .bold, design: .rounded))
                            Text("Rysuj palcem lub Apple Pencil")
                                .font(.caption)
                                .foregroundStyle(LabStyle.muted)
                        }
                        Spacer(minLength: 0)
                        Button {
                            exportImage = PaintDocument.render(
                                document.strokes, size: CGSize(width: 1400, height: 1000))
                            showShare = true
                        } label: {
                            Label("Zapisz", systemImage: "square.and.arrow.up")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(LabPrimaryButtonStyle())
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel("Zapisz lub udostępnij rysunek")
                    }

                    if wide {
                        HStack(alignment: .top, spacing: 14) {
                            drawingPanel
                                .frame(maxWidth: .infinity, alignment: .top)
                            ScrollView {
                                toolsPanel
                                    .padding(.bottom, 12)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: min(300, layout.size.width * 0.32))
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                    } else {
                        drawingPanel
                            .fixedSize(horizontal: false, vertical: true)
                        ScrollView {
                            toolsPanel
                                .padding(.bottom, 15)
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(.horizontal, wide ? 24 : 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .frame(maxWidth: 1260, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .sheet(isPresented: $showShare) {
            if let exportImage {
                PaintShareSheet(image: exportImage)
            }
        }
        .confirmationDialog("Wyczyścić cały rysunek?", isPresented: $showClearConfirmation,
                            titleVisibility: .visible) {
            Button("Wyczyść płótno", role: .destructive) { document.clear() }
            Button("Anuluj", role: .cancel) {}
        }
    }

    private var drawingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                LabSectionTitle(title: "PŁÓTNO", symbol: "rectangle.on.rectangle")
                Spacer()
                Text("\(document.strokes.count) kresek")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(LabStyle.muted)
            }
            GeometryReader { geometry in
                PaintCanvasRepresentable(document: document)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onAppear { canvasSize = geometry.size }
                    .onChange(of: geometry.size) { canvasSize = $0 }
                    .accessibilityLabel("Białe płótno do rysowania palcem lub Apple Pencil")
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .background(.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LabStyle.border, lineWidth: 1))
        }
        .labPanel()
    }

    private var toolsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabSectionTitle(title: "NARZĘDZIA", symbol: "paintbrush")
            HStack(spacing: 8) {
                toolButton("Pędzel", symbol: "pencil.tip", active: !document.isEraser) {
                    document.isEraser = false
                }
                toolButton("Gumka", symbol: "eraser.fill", active: document.isEraser) {
                    document.isEraser = true
                }
            }
            Text("KOLORY").font(.caption.bold()).foregroundStyle(LabStyle.muted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 41), spacing: 8)], spacing: 8) {
                ForEach(PaintPalette.colors.indices, id: \.self) { index in
                    Button {
                        document.selectedColor = index
                        document.isEraser = false
                    } label: {
                        Circle()
                            .fill(Color(uiColor: PaintPalette.colors[index]))
                            .frame(width: 29, height: 29)
                            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1))
                            .padding(5)
                            .overlay(Circle().strokeBorder(
                                document.selectedColor == index && !document.isEraser ?
                                    LabStyle.accent : .clear, lineWidth: 2))
                    }
                    .accessibilityLabel(PaintPalette.names[index])
                }
            }
            HStack {
                Text("Grubość pędzla")
                Spacer()
                Text("\(Int(document.thickness)) pt")
                    .foregroundStyle(LabStyle.accent)
                    .monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: $document.thickness, in: 2...32, step: 1)
                .tint(LabStyle.accent)
            HStack(spacing: 8) {
                toolButton("Cofnij", symbol: "arrow.uturn.backward",
                           active: false, enabled: document.canUndo) {
                    document.undo()
                }
                toolButton("Ponów", symbol: "arrow.uturn.forward",
                           active: false, enabled: document.canRedo) {
                    document.redo()
                }
            }
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label("Wyczyść cały rysunek", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, minHeight: 42)
            }
            .disabled(!document.canUndo)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(.red)
            .accessibilityLabel("Wyczyść płótno")
        }
        .labPanel()
    }

    private func toolButton(_ title: String, symbol: String,
                            active: Bool, enabled: Bool = true,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 43)
        }
        .buttonStyle(LabChipStyle(active: active))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}
