import SwiftUI
import SceneKit
import Metal
import SpriteKit
import UniformTypeIdentifiers

@main
struct HelloIPhoneApp: App {
    @UIApplicationDelegateAdaptor(GameOrientationDelegate.self) private var orientationDelegate
    var body: some Scene {
        WindowGroup { MainTabsView() }
    }
}

enum Shape3D: String, CaseIterable, Identifiable {
    case sphere = "Kula", cube = "Sześcian", torus = "Torus", cone = "Stożek", cylinder = "Walec", pyramid = "Ostrosłup", capsule = "Kapsuła", knot = "Chromowy węzeł", imported = "Własny GLB"
    var id: String { rawValue }
    var geometry: SCNGeometry {
        switch self {
        case .sphere:
            let g = SCNSphere(radius: 1.0); g.segmentCount = 64; return g
        case .cube: return SCNBox(width: 1.6, height: 1.6, length: 1.6, chamferRadius: 0.12)
        case .torus: return SCNTorus(ringRadius: 0.8, pipeRadius: 0.3)
        case .cone:
            let g = SCNCone(topRadius: 0, bottomRadius: 0.9, height: 1.9); g.radialSegmentCount = 64; return g
        case .cylinder: return SCNCylinder(radius: 0.8, height: 1.8)
        case .pyramid: return SCNPyramid(width: 1.8, height: 1.9, length: 1.8)
        case .capsule: return SCNCapsule(capRadius: 0.7, height: 2)
        case .knot: return SCNSphere(radius: 0.85)
        case .imported: return SCNSphere(radius: 0.85)
        }
    }
}

enum Shading3D: String, CaseIterable, Identifiable {
    case pbr = "PBR / metal", phong = "Phong / połysk", blinn = "Blinn", lambert = "Lambert / mat", constant = "Bez cieniowania"
    var id: String { rawValue }
    var lighting: SCNMaterial.LightingModel {
        switch self {
        case .pbr: return .physicallyBased
        case .phong: return .phong
        case .blinn: return .blinn
        case .lambert: return .lambert
        case .constant: return .constant
        }
    }
}

enum SurfaceFX: String, CaseIterable, Identifiable {
    case normal = "Standard", wire = "Siatka 3D", glow = "Neon", glass = "Szkło", ceramic = "Ceramika"
    var id: String { rawValue }
}

enum LightPreset: String, CaseIterable, Identifiable {
    case studio = "Studio", sunset = "Zachód", ice = "Lodowy", dramatic = "Dramatyczny"
    var id: String { rawValue }
}


enum GLBKnot {
    enum ErrorKind: Error { case invalid }
    static let filename = "ASTEROIDY_CHROMOWY_WEZEL.glb"
    static var saved: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent(filename)
    }
    static func parse(_ url: URL) throws -> SCNGeometry {
        let file = try Data(contentsOf: url)
        func read32(_ i: Int) throws -> UInt32 {
            guard i >= 0 && i+4 <= file.count else { throw ErrorKind.invalid }
            return file.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: i, as: UInt32.self) }
        }
        guard try read32(0) == 0x46546c67, try read32(4) == 2,
              try read32(8) == UInt32(file.count) else { throw ErrorKind.invalid }
        var json = Data(), bin = Data(), offset = 12
        while offset+8 <= file.count {
            let len = try Int(read32(offset)), kind = try read32(offset+4)
            offset += 8
            guard offset+len <= file.count else { throw ErrorKind.invalid }
            if kind == 0x4e4f534a { json = file.subdata(in: offset..<offset+len) }
            if kind == 0x004e4942 { bin = file.subdata(in: offset..<offset+len) }
            offset += len
        }
        guard let root = try JSONSerialization.jsonObject(with: json) as? [String:Any],
              let meshes = root["meshes"] as? [[String:Any]],
              let primitives = meshes.first?["primitives"] as? [[String:Any]],
              let prim = primitives.first,
              let attrs = prim["attributes"] as? [String:Int],
              let pi = attrs["POSITION"], let ni = attrs["NORMAL"],
              let ii = prim["indices"] as? Int,
              let accessors = root["accessors"] as? [[String:Any]],
              let views = root["bufferViews"] as? [[String:Any]] else { throw ErrorKind.invalid }
        func read(_ id: Int, _ ty: String, _ format: Int) throws -> (Data,Int,Int) {
            guard accessors.indices.contains(id) else { throw ErrorKind.invalid }
            let a = accessors[id]
            guard a["type"] as? String == ty, a["componentType"] as? Int == format,
                  let vi = a["bufferView"] as? Int, views.indices.contains(vi),
                  let count = a["count"] as? Int, count > 0 else { throw ErrorKind.invalid }
            let v = views[vi], bpc = format == 5123 ? 2 : 4
            let size = (ty == "VEC3" ? 3 : 1)*bpc
            let stride = v["byteStride"] as? Int ?? size
            let start = (v["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
            let end = start+(count-1)*stride+size
            guard start >= 0, stride >= size, end <= bin.count else { throw ErrorKind.invalid }
            return (bin.subdata(in: start..<end),count,stride)
        }
        let (pos, n, ps) = try read(pi,"VEC3",5126)
        let (normal, nc, ns) = try read(ni,"VEC3",5126)
        guard nc == n, accessors.indices.contains(ii),
              let fmt = accessors[ii]["componentType"] as? Int,
              fmt == 5125 || fmt == 5123 else { throw ErrorKind.invalid }
        let (idx, ic, bytes) = try read(ii,"SCALAR",fmt)
        guard ic % 3 == 0, bytes == (fmt == 5123 ? 2 : 4) else { throw ErrorKind.invalid }
        let p = SCNGeometrySource(data: pos, semantic: .vertex, vectorCount: n,
                                   usesFloatComponents: true, componentsPerVector: 3,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: ps)
        let v = SCNGeometrySource(data: normal, semantic: .normal, vectorCount: n,
                                   usesFloatComponents: true, componentsPerVector: 3,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: ns)
        let faces = SCNGeometryElement(data: idx, primitiveType: .triangles,
                                       primitiveCount: ic/3, bytesPerIndex: bytes)
        return SCNGeometry(sources: [p,v], elements: [faces])
    }
}

enum ShaderScene {
    static var knot: SCNGeometry?
    static var imported: GLBSceneLoader.Loaded?
    static let background = UIColor(red: 0.035, green: 0.055, blue: 0.1, alpha: 1)
    static let environment: UIImage = {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 512), format: format).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(white: 0.32, alpha: 1).cgColor, UIColor(white: 0.06, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 512), options: [])
            UIColor(white: 1, alpha: 1).setFill(); c.fill(CGRect(x: 100, y: 80, width: 100, height: 290))
            UIColor(red: 0.35, green: 0.75, blue: 1, alpha: 1).setFill(); c.fill(CGRect(x: 690, y: 140, width: 170, height: 90))
            UIColor(white: 0.7, alpha: 1).setFill(); c.fill(CGRect(x: 350, y: 20, width: 300, height: 35))
        }
    }()

    static func material(_ shading: Shading3D, color: UIColor, metalness: Double, roughness: Double, effect: SurfaceFX = .normal) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = shading.lighting
        m.diffuse.contents = color
        m.specular.contents = UIColor(white: 0.8, alpha: 1)
        m.metalness.contents = NSNumber(value: metalness)
        m.roughness.contents = NSNumber(value: roughness)
        m.shininess = 0.55
        m.isDoubleSided = false
        // SceneKit constant includes ambient by default. Zero it to obtain true unlit.
        m.locksAmbientWithDiffuse = false
        m.ambient.contents = shading == .constant ? UIColor.black : color
        switch effect {
        case .normal: break
        case .wire:
            m.fillMode = .lines
            m.isDoubleSided = true
        case .glow:
            m.emission.contents = color
            m.emission.intensity = 1.25
        case .glass:
            m.transparency = 0.38
            m.isDoubleSided = true
            m.fresnelExponent = 2.5
            m.roughness.contents = NSNumber(value: 0.08)
        case .ceramic:
            m.metalness.contents = NSNumber(value: 0.0)
            m.roughness.contents = NSNumber(value: 0.24)
        }
        return m
    }

    static func makeScene(shape: Shape3D = .sphere, shading: Shading3D = .pbr,
                          color: UIColor = .systemBlue, metalness: Double = 0.85,
                          roughness: Double = 0.18, effect: SurfaceFX = .normal, lightPreset: LightPreset = .studio, lightPower: Double = 1.0) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = background
        scene.lightingEnvironment.contents = environment
        scene.lightingEnvironment.intensity = 1
        let camera = SCNCamera()
        camera.fieldOfView = 48
        camera.zNear = 0.05; camera.zFar = 100
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        let cameraNode = SCNNode(); cameraNode.name = "camera"; cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.5, 4.7)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        let key = SCNNode(); key.name = "key"
        key.light = SCNLight(); key.light?.type = .omni; key.light?.intensity = 1000
        key.light?.color = UIColor.white; key.position = SCNVector3(-3, 4, 5)
        scene.rootNode.addChildNode(key)
        let rim = SCNNode(); rim.name = "rim"
        rim.light = SCNLight(); rim.light?.type = .omni; rim.light?.intensity = 650
        rim.light?.color = UIColor.cyan; rim.position = SCNVector3(3, 2, -3)
        scene.rootNode.addChildNode(rim)
        let fill = SCNNode(); fill.name = "fill"
        fill.light = SCNLight(); fill.light?.type = .ambient; fill.light?.intensity = 100
        scene.rootNode.addChildNode(fill)
        let model = SCNNode(); model.name = "model"
        model.eulerAngles = SCNVector3(-0.15, 0.35, 0)
        scene.rootNode.addChildNode(model)
        update(scene, shape: shape, shading: shading, color: color, metalness: metalness, roughness: roughness, spinning: false, effect: effect, lightPreset: lightPreset, lightPower: lightPower)
        return scene
    }

    static func update(_ scene: SCNScene, shape: Shape3D, shading: Shading3D,
                       color: UIColor, metalness: Double, roughness: Double, spinning: Bool,
                       effect: SurfaceFX = .normal, lightPreset: LightPreset = .studio, lightPower: Double = 1.0) {
        guard let model = scene.rootNode.childNode(withName: "model", recursively: false) else { return }
        if shape == .imported {
            if let imported, model.childNodes.first !== imported.root {
                model.removeAllAnimations()
                model.removeAction(forKey: "spin")
                for child in model.childNodes { child.removeFromParentNode() }
                model.geometry = nil
                model.addChildNode(imported.root)
                
            }
            // Preserve imported glTF material textures. Controls for built-in shapes must not overwrite them.
        } else {
            if !model.childNodes.isEmpty {
                model.removeAllAnimations()
                for child in model.childNodes { child.removeFromParentNode() }
                model.name = "model"
            }
        }
        let shapeID = "shape:" + shape.rawValue
        if shape != .imported && model.geometry?.name != shapeID {
            model.geometry = shape == .knot ? (knot ?? shape.geometry) : shape.geometry
            model.geometry?.name = shapeID
        }
        let chrome = shape == .knot
        if shape != .imported {
            model.geometry?.materials = [material(shading, color: chrome ? UIColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1) : color, metalness: chrome ? 0.93 : metalness, roughness: chrome ? 0.115 : roughness, effect: effect)]
        }
        let palette: (UIColor, UIColor)
        switch lightPreset {
        case .studio: palette = (.white, .cyan)
        case .sunset: palette = (.init(red: 1, green: 0.55, blue: 0.28, alpha: 1), .init(red: 0.45, green: 0.28, blue: 1, alpha: 1))
        case .ice: palette = (.init(red: 0.55, green: 0.85, blue: 1, alpha: 1), .init(red: 0.15, green: 0.4, blue: 1, alpha: 1))
        case .dramatic: palette = (.white, .init(red: 1, green: 0.1, blue: 0.2, alpha: 1))
        }
        let power = CGFloat(max(0, min(lightPower, 2)))
        let key = scene.rootNode.childNode(withName: "key", recursively: false)?.light
        key?.color = palette.0; key?.intensity = 1000 * power
        let rim = scene.rootNode.childNode(withName: "rim", recursively: false)?.light
        rim?.color = palette.1; rim?.intensity = 650 * power
        if shape != .imported && spinning && model.action(forKey: "spin") == nil {
            model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: shape == .knot ? 16 : 9)), forKey: "spin")
        } else if !spinning || shape == .imported {
            model.removeAction(forKey: "spin")
        }
    }

    static func makeView() -> SCNView {
        let view = SCNView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        view.scene = makeScene()
        view.backgroundColor = background
        view.allowsCameraControl = true
        view.defaultCameraController.target = SCNVector3Zero
        view.defaultCameraController.minimumVerticalAngle = -85
        view.defaultCameraController.maximumVerticalAngle = 85
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: false)
        return view
    }
}

struct ModelView: UIViewRepresentable {
    let shape: Shape3D
    let shading: Shading3D
    let metalness: Double
    let roughness: Double
    let spinning: Bool
    let effect: SurfaceFX
    let lightPreset: LightPreset
    let lightPower: Double
    let color: UIColor
    let knotRevision: Int
    let importedRevision: Int
    let clipIndex: Int
    let playGLB: Bool

    final class Coordinator {
        var selectedClip = -1
        var assetRevision = -1
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView { ShaderScene.makeView() }
    func updateUIView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        if shape == .knot, let geometry = ShaderScene.knot {
            let node = scene.rootNode.childNode(withName: "model", recursively: false)
            if node?.geometry !== geometry { node?.geometry = geometry; node?.geometry?.name = "shape:" + shape.rawValue }
        }
        _ = knotRevision
        ShaderScene.update(scene, shape: shape, shading: shading, color: color,
                           metalness: metalness, roughness: roughness, spinning: spinning,
                           effect: effect, lightPreset: lightPreset, lightPower: lightPower)
        if shape == .imported, let imported = ShaderScene.imported {
            let model = scene.rootNode.childNode(withName: "model", recursively: false)
            let key = "gltf-clip"
            if (context.coordinator.selectedClip != clipIndex || context.coordinator.assetRevision != importedRevision) && imported.animations.indices.contains(clipIndex) {
                model?.removeAnimation(forKey: key)
                model?.addAnimationPlayer(imported.animations[clipIndex].animationPlayer, forKey: key)
                context.coordinator.selectedClip = clipIndex
                context.coordinator.assetRevision = importedRevision
            }
            model?.animationPlayer(forKey: key)?.paused = !playGLB
        }
        if shape != .imported { context.coordinator.selectedClip = -1 }
        view.isPlaying = spinning || (shape == .imported && playGLB)
        view.rendersContinuously = spinning || (shape == .imported && playGLB)
    }
}


enum LabStyle {
    static let background = Color(red: 0.035, green: 0.052, blue: 0.09)
    static let panel = Color(red: 0.075, green: 0.10, blue: 0.155)
    static let accent = Color(red: 0.28, green: 0.90, blue: 1.0)
    static let muted = Color(red: 0.63, green: 0.73, blue: 0.82)
    static let border = Color.white.opacity(0.14)
}

struct LabSectionTitle: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .tracking(1.0)
            .foregroundStyle(LabStyle.accent)
    }
}

struct LabPanelModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LabStyle.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LabStyle.border, lineWidth: 1))
    }
}

extension View {
    func labPanel() -> some View { modifier(LabPanelModifier()) }
}

struct LabChipStyle: ButtonStyle {
    let active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(active ? LabStyle.background : Color.white)
            .padding(.horizontal, 8)
            .background(active ? LabStyle.accent : Color.white.opacity(configuration.isPressed ? 0.22 : 0.09),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .strokeBorder(active ? LabStyle.accent : LabStyle.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct LabPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(LabStyle.background)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(LabStyle.accent.opacity(configuration.isPressed ? 0.65 : 1),
                        in: RoundedRectangle(cornerRadius: 12))
    }
}

struct LabValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(title).font(.subheadline)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .foregroundStyle(LabStyle.accent)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range)
                .tint(LabStyle.accent)
                .accessibilityLabel(title)
        }
    }
}

struct ShaderLabView: View {
    @State private var shape: Shape3D = .sphere
    @State private var shading: Shading3D = .pbr
    @State private var metalness = 0.85
    @State private var roughness = 0.18
    @State private var spinning = true
    @State private var selectedColor = 0
    @State private var knotRevision = 0
    @State private var knotError: String?
    @State private var showGLBImporter = false
    @State private var importedRevision = 0
    @State private var importedName = ""
    @State private var playGLB = true
    @State private var clipIndex = 0
    @State private var importing = false
    private let savedGLBName = "imported-model.glb"
    private var savedGLBURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(savedGLBName)
    }
    @State private var effect: SurfaceFX = .normal
    @State private var lightPreset: LightPreset = .studio
    @State private var lightPower = 1.0
    private let swatches: [(String, UIColor, Color)] = [
        ("Tytan", UIColor(red: 0.72, green: 0.80, blue: 0.92, alpha: 1), .init(red: 0.72, green: 0.80, blue: 0.92)),
        ("Miedź", UIColor(red: 0.95, green: 0.45, blue: 0.22, alpha: 1), .orange),
        ("Szmaragd", UIColor(red: 0.08, green: 0.85, blue: 0.58, alpha: 1), .green),
        ("Fiolet", UIColor(red: 0.58, green: 0.35, blue: 0.95, alpha: 1), .purple)
    ]
    var body: some View {
        GeometryReader { layout in
            let wide = layout.size.width >= 780
            ZStack {
                LabStyle.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(LabStyle.accent)
                                .frame(width: 48, height: 48)
                                .background(LabStyle.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("SHADER LAB")
                                    .font(.system(size: wide ? 28 : 22, weight: .bold, design: .rounded))
                                Text("Studio materiałów i modeli 3D")
                                    .font(.subheadline)
                                    .foregroundStyle(LabStyle.muted)
                            }
                            Spacer(minLength: 0)
                            Text("3D / METAL")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(LabStyle.accent)
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .background(LabStyle.accent.opacity(0.1), in: Capsule())
                        }
                        if wide {
                            HStack(alignment: .top, spacing: 18) {
                                previewPanel(wide: true)
                                    .frame(maxWidth: .infinity)
                                settingsPanel(wide: true)
                                    .frame(maxWidth: .infinity)
                            }
                        } else {
                            previewPanel(wide: false)
                            settingsPanel(wide: false)
                        }
                        HStack {
                            Image(systemName: "checkmark.shield")
                            Text("Renderowanie natywne · SceneKit / Metal · iOS 16+")
                        }
                        .font(.caption2)
                        .foregroundStyle(LabStyle.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .padding(.horizontal, wide ? 24 : 14)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 1180)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            if ShaderScene.imported == nil && FileManager.default.fileExists(atPath: savedGLBURL.path) {
                loadImported(savedGLBURL, filename: UserDefaults.standard.string(forKey: "shaderlab.importedFilename") ?? savedGLBName)
            }
        }
        .fileImporter(isPresented: $showGLBImporter, allowedContentTypes: [UTType(filenameExtension: "glb") ?? .data, .data]) { result in
            do {
                let url = try result.get()
                guard url.pathExtension.lowercased() == "glb" else {
                    knotError = "Wybierz plik z rozszerzeniem .glb."
                    return
                }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let temp = savedGLBURL.deletingLastPathComponent().appendingPathComponent("model-import-pending.glb")
                if FileManager.default.fileExists(atPath: temp.path) { try FileManager.default.removeItem(at: temp) }
                try FileManager.default.copyItem(at: url, to: temp)
                importing = true
                GLBSceneLoader.load(from: temp) { result in
                    importing = false
                    switch result {
                    case .success(let loaded):
                        do {
                            if FileManager.default.fileExists(atPath: savedGLBURL.path) {
                                try FileManager.default.removeItem(at: savedGLBURL)
                            }
                            try FileManager.default.moveItem(at: temp, to: savedGLBURL)
                            ShaderScene.imported = loaded
                            importedName = url.lastPathComponent
                            UserDefaults.standard.set(importedName, forKey: "shaderlab.importedFilename")
                            clipIndex = 0
                            playGLB = true
                            spinning = false
                            shape = .imported
                            importedRevision += 1
                        } catch {
                            knotError = "Błąd zapisu modelu: \(error.localizedDescription)"
                        }
                    case .failure(let error):
                        try? FileManager.default.removeItem(at: temp)
                        knotError = "Nie można wczytać GLB: \(error.localizedDescription)"
                    }
                }
            } catch {
                knotError = "Nie można otworzyć pliku: \(error.localizedDescription)"
            }
        }
        .alert("Model GLB", isPresented: Binding(get: { knotError != nil }, set: { if !$0 { knotError = nil } })) {
            Button("OK") { knotError = nil }
        } message: { Text(knotError ?? "") }
    }


    @ViewBuilder private func previewPanel(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LabSectionTitle(title: "PODGLĄD", symbol: "viewfinder")
                Spacer()
                Text(shape.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LabStyle.muted)
                    .lineLimit(1)
            }
            ModelView(shape: shape, shading: shading, metalness: metalness, roughness: roughness,
                      spinning: spinning, effect: effect, lightPreset: lightPreset,
                      lightPower: lightPower, color: swatches[selectedColor].1,
                      knotRevision: knotRevision, importedRevision: importedRevision,
                      clipIndex: clipIndex, playGLB: playGLB)
                .frame(height: wide ? 430 : 300)
                .background(LabStyle.background, in: RoundedRectangle(cornerRadius: 16))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(LabStyle.border, lineWidth: 1))
                .accessibilityLabel("Podgląd modelu 3D. Obrót palcem i przybliżanie gestem szczypania.")
            Label("Obracaj palcem · przybliżaj dwoma palcami", systemImage: "hand.draw")
                .font(.caption)
                .foregroundStyle(LabStyle.muted)
                .lineLimit(2)
            if shape == .imported && ShaderScene.imported != nil {
                Label(importedName.isEmpty ? "Model GLB" : importedName, systemImage: "shippingbox")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(LabStyle.accent)
                    .lineLimit(2)
            }
        }
        .labPanel()
    }

    @ViewBuilder private func settingsPanel(wide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                LabSectionTitle(title: "MODELE 3D", symbol: "square.stack.3d.up")
                Text("Wybierz gotową bryłę albo wczytaj własny model GLB z teksturami i animacjami.")
                    .font(.caption).foregroundStyle(LabStyle.muted)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 142 : 132), spacing: 8)], spacing: 8) {
                    ForEach(Shape3D.allCases.filter { $0 != .knot && $0 != .imported }) { item in
                        Button {
                            shape = item
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: item == .imported ? "square.and.arrow.down" : "cube")
                                    .font(.caption)
                                Text(item.rawValue)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.76)
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                        }
                        .buttonStyle(LabChipStyle(active: shape == item))
                        .accessibilityAddTraits(shape == item ? .isSelected : [])
                    }
                }
                Button {
                    showGLBImporter = true
                } label: {
                    Label(importing ? "Wczytywanie modelu..." : "OTWÓRZ JEDEN PLIK GLB",
                          systemImage: "square.and.arrow.down.on.square")
                }
                .buttonStyle(LabPrimaryButtonStyle())
                .disabled(importing)
                if importing {
                    ProgressView("Przetwarzanie geometrii, tekstur i animacji")
                        .font(.caption)
                        .tint(LabStyle.accent)
                }
                if shape == .imported {
                    if let asset = ShaderScene.imported {
                        Text("Import zachowuje materiały PBR i tekstury oryginalnego modelu.")
                            .font(.caption).foregroundStyle(LabStyle.muted)
                        if !asset.animations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ANIMACJA").font(.caption.bold()).foregroundStyle(LabStyle.muted)
                                Picker("Wybierz animację", selection: $clipIndex) {
                                    ForEach(Array(asset.animations.enumerated()), id: \.offset) { item in
                                        Text(item.element.name.isEmpty ? "Animacja \(item.offset + 1)" : item.element.name)
                                            .tag(item.offset)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .pickerStyle(.menu)
                                Toggle("Odtwarzaj animację GLB", isOn: $playGLB)
                                    .font(.subheadline)
                                    .tint(LabStyle.accent)
                            }
                        } else {
                            Label("Model bez klipów animacji", systemImage: "info.circle")
                                .font(.caption).foregroundStyle(LabStyle.muted)
                        }
                    } else {
                        Label("Wybierz plik GLB, aby zobaczyć model", systemImage: "info.circle")
                            .font(.caption).foregroundStyle(LabStyle.muted)
                    }
                }
            }
            .labPanel()

            VStack(alignment: .leading, spacing: 12) {
                LabSectionTitle(title: "WYGLĄD POWIERZCHNI", symbol: "circle.hexagongrid")
                if shape == .imported {
                    Text("Materiały importowanego GLB pozostają oryginalne. Zmieniaj oświetlenie w panelu poniżej.")
                        .font(.caption).foregroundStyle(LabStyle.muted)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 125 : 110), spacing: 8)], spacing: 8) {
                        ForEach(SurfaceFX.allCases) { item in
                            Button(item.rawValue) { effect = item }
                                .font(.system(size: 12, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .buttonStyle(LabChipStyle(active: effect == item))
                        }
                    }
                    HStack {
                        Text("Model cieniowania")
                        Spacer()
                        Picker("Cieniowanie", selection: $shading) {
                            ForEach(Shading3D.allCases) { item in Text(item.rawValue).tag(item) }
                        }
                        .pickerStyle(.menu)
                    }
                    .font(.subheadline)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("KOLOR").font(.caption.bold()).foregroundStyle(LabStyle.muted)
                        HStack(spacing: 14) {
                            ForEach(swatches.indices, id: \.self) { index in
                                Button {
                                    selectedColor = index
                                } label: {
                                    Circle()
                                        .fill(swatches[index].2)
                                        .frame(width: 36, height: 36)
                                        .overlay(Circle().stroke(.white, lineWidth: selectedColor == index ? 3 : 0))
                                        .frame(width: 44, height: 44)
                                }
                                .accessibilityLabel(swatches[index].0)
                                .accessibilityAddTraits(selectedColor == index ? .isSelected : [])
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    Toggle("Automatyczny obrót", isOn: $spinning)
                        .font(.subheadline).tint(LabStyle.accent)
                    VStack(spacing: 10) {
                        LabValueSlider(title: "Metaliczność", value: $metalness, range: 0...1)
                        LabValueSlider(title: "Chropowatość", value: $roughness, range: 0...1)
                    }
                    .disabled(shading != .pbr)
                    .opacity(shading == .pbr ? 1 : 0.45)
                }
            }
            .labPanel()

            VStack(alignment: .leading, spacing: 12) {
                LabSectionTitle(title: "OŚWIETLENIE", symbol: "sun.max")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: wide ? 125 : 110), spacing: 8)], spacing: 8) {
                    ForEach(LightPreset.allCases) { preset in
                        Button(preset.rawValue) { lightPreset = preset }
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .buttonStyle(LabChipStyle(active: lightPreset == preset))
                    }
                }
                LabValueSlider(title: "Moc lamp", value: $lightPower, range: 0...2)
                Text("PBR korzysta z mapy otoczenia. Neon emituje światło bez bloom, a szkło używa przezroczystości bez ray tracingu.")
                    .font(.caption)
                    .foregroundStyle(LabStyle.muted)
            }
            .labPanel()
        }
    }

    private func loadImported(_ url: URL, filename: String) {
        importing = true
        GLBSceneLoader.load(from: url) { result in
            importing = false
            switch result {
            case .success(let loaded):
                ShaderScene.imported = loaded
                importedName = filename
                clipIndex = 0
                playGLB = true
                spinning = false
                shape = .imported
                importedRevision += 1
            case .failure(let error):
                knotError = "Zapisany model GLB: \(error.localizedDescription)"
            }
        }
    }
}


// MARK: - Independent arcade game. No changes to the SceneKit shader pipeline.
final class AsteroidsArcadeScene: SKScene {
    struct Rock {
        var node: SKShapeNode
        var velocity: CGVector
        var radius: CGFloat
        var tier: Int
        var spin: CGFloat
        var mass: CGFloat
    }
    struct Shot {
        var node: SKShapeNode
        var velocity: CGVector
        var lifetime: TimeInterval
        var previous: CGPoint
    }

    // Physically integrated sparks keep their original inertia and fade smoothly.
    struct Spark {
        let node: SKShapeNode
        var velocity: CGVector
        var remaining: CGFloat
        let total: CGFloat
        let angularVelocity: CGFloat
    }
    private var sparks: [Spark] = []
    private var exhaustAccumulator: CGFloat = 0
    private var screenShake: CGFloat = 0
    private var elapsed: CGFloat = 0
    private var rockCollisionCooldown: CGFloat = 0

    var turnLeft = false
    var turnRight = false
    var accelerating = false
    var shooting = false
    var moveAnalog = CGVector.zero
    var aimAnalog = CGVector.zero
    private(set) var shieldTime: TimeInterval = 0
    private(set) var boostCooldown: TimeInterval = 0
    private(set) var rapidFireTime: TimeInterval = 0
    private(set) var bestScore = UserDefaults.standard.integer(forKey: "asteroids.bestScore")
    private var shieldRing = SKShapeNode()
    private struct Bonus {
        var node: SKShapeNode
        var kind: Int // 0 shield, 1 rapid fire, 2 extra life
        var remaining: TimeInterval
    }
    private var bonuses: [Bonus] = []
    private var debris: [SKNode] = []

    private(set) var score = 0
    private(set) var lives = 3
    private(set) var wave = 1
    private(set) var isGameOver = false
    private var ship = SKShapeNode()
    private var rocks: [Rock] = []
    private var shots: [Shot] = []
    private var stars: [SKShapeNode] = []
    private var shipVelocity = CGVector.zero
    private var shipAngle: CGFloat = .pi / 2
    private var lastUpdate: TimeInterval = 0
    private var shotCooldown: TimeInterval = 0
    private var invulnerable: TimeInterval = 0
    private var waveCooldown: TimeInterval = 0
    private let hud = SKLabelNode(fontNamed: "Menlo-Bold")
    private let message = SKLabelNode(fontNamed: "Menlo-Bold")
    private let shipRadius: CGFloat = 13
    private let bloomAlpha: CGFloat = 0.17
    private var backdrop = SKNode()
    private var shipFlame = SKShapeNode()
    private var shipInner = SKShapeNode()
    private var backdropGrid = SKNode()
    private var pulse = SKShapeNode()
    private var oldShipPosition = CGPoint.zero

    static func segmentIntersectsCircle(_ a: CGPoint, _ b: CGPoint, center: CGPoint, radius: CGFloat) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        let t = lengthSquared > 0.00001 ?
            max(0, min(1, ((center.x-a.x)*dx + (center.y-a.y)*dy)/lengthSquared)) : 0
        let cx = a.x + t*dx, cy = a.y + t*dy
        return hypot(cx-center.x, cy-center.y) <= radius
    }

    static func elasticImpulse(_ a: CGVector, _ b: CGVector,
                               massA: CGFloat, massB: CGFloat, normal: CGVector) -> (CGVector, CGVector) {
        let relative = (b.dx-a.dx)*normal.dx + (b.dy-a.dy)*normal.dy
        if relative >= 0 { return (a, b) }
        let restitution: CGFloat = 0.86
        let impulse = -(1+restitution)*relative / (1/massA + 1/massB)
        return (CGVector(dx: a.dx - impulse*normal.dx/massA, dy: a.dy - impulse*normal.dy/massA),
                CGVector(dx: b.dx + impulse*normal.dx/massB, dy: b.dy + impulse*normal.dy/massB))
    }

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.012, green: 0.019, blue: 0.045, alpha: 1)
        scaleMode = .resizeFill
        guard ship.parent == nil else { return }
        configureNodes()
        restart()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        hud.position = CGPoint(x: 12, y: max(20, size.height - 34))
        message.position = CGPoint(x: size.width / 2, y: size.height / 2)
        for star in stars { star.removeFromParent() }
        stars.removeAll()
        backdropGrid.removeAllChildren()
        guard size.width > 0 && size.height > 0 else { return }
        // Keep the ship inside the new playfield after iPad split-view or rotation.
        if oldSize.width > 0 && oldSize.height > 0 && ship.parent != nil {
            ship.position = CGPoint(
                x: min(size.width, max(0, ship.position.x * size.width / oldSize.width)),
                y: min(size.height, max(0, ship.position.y * size.height / oldSize.height))
            )
            shieldRing.position = ship.position
        }
        // Faint perspective-free vector grid: CRT arcade feel without distracting from silhouettes.
        if backdropGrid.parent == nil { backdropGrid.zPosition = -9; addChild(backdropGrid) }
        let pitch: CGFloat = size.width > 700 ? 58 : 42
        let vertical = Int(size.width / pitch) + 1
        let horizontal = Int(size.height / pitch) + 1
        if vertical * horizontal < 700 {
            for i in 0...vertical {
                let x = CGFloat(i)*pitch
                let line = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x:x,y:0)); path.addLine(to: CGPoint(x:x,y:size.height))
                line.path = path; line.strokeColor = .cyan.withAlphaComponent(0.04)
                line.lineWidth = 0.6; backdropGrid.addChild(line)
            }
            for i in 0...horizontal {
                let y = CGFloat(i)*pitch
                let line = SKShapeNode()
                let path = CGMutablePath()
                path.move(to: CGPoint(x:0,y:y)); path.addLine(to: CGPoint(x:size.width,y:y))
                line.path = path; line.strokeColor = .cyan.withAlphaComponent(0.04)
                line.lineWidth = 0.6; backdropGrid.addChild(line)
            }
        }
        for _ in 0..<(size.width > 700 ? 150 : 90) {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.45...1.3))
            dot.fillColor = (Bool.random() ? SKColor.cyan : SKColor.white)
                .withAlphaComponent(CGFloat.random(in: 0.16...0.56))
            dot.strokeColor = .clear
            dot.position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                   y: CGFloat.random(in: 0...size.height))
            dot.zPosition = -5
            addChild(dot)
            stars.append(dot)
        }
    }

    private func configureNodes() {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 16, y: 0))
        path.addLine(to: CGPoint(x: -11, y: 10))
        path.addLine(to: CGPoint(x: -7, y: 0))
        path.addLine(to: CGPoint(x: -11, y: -10))
        path.closeSubpath()
        ship = SKShapeNode(path: path)
        ship.strokeColor = .cyan
        ship.lineWidth = 2.1
        ship.glowWidth = 5
        ship.fillColor = SKColor(red: 0.03, green: 0.09, blue: 0.18, alpha: 0.98)
        ship.zPosition = 5
        addChild(ship)
        let interior = CGMutablePath()
        interior.move(to: CGPoint(x: 9, y: 0))
        interior.addLine(to: CGPoint(x: -5, y: 5))
        interior.move(to: CGPoint(x: 9, y: 0))
        interior.addLine(to: CGPoint(x: -5, y: -5))
        shipInner = SKShapeNode(path: interior)
        shipInner.strokeColor = SKColor(red: 0.65, green: 0.95, blue: 1, alpha: 0.9)
        shipInner.lineWidth = 1.1
        ship.addChild(shipInner)
        let flamePath = CGMutablePath()
        flamePath.move(to: CGPoint(x:-7,y:6))
        flamePath.addLine(to: CGPoint(x:-20,y:0))
        flamePath.addLine(to: CGPoint(x:-7,y:-6))
        shipFlame = SKShapeNode(path:flamePath)
        shipFlame.strokeColor = .systemOrange
        shipFlame.fillColor = .yellow.withAlphaComponent(0.3)
        shipFlame.lineWidth = 2
        shipFlame.glowWidth = 6
        shipFlame.isHidden = true
        ship.addChild(shipFlame)
        shieldRing = SKShapeNode(circleOfRadius: 23)
        shieldRing.strokeColor = .systemTeal
        shieldRing.lineWidth = 2.5
        shieldRing.glowWidth = 4
        shieldRing.fillColor = .clear
        shieldRing.zPosition = 6
        addChild(shieldRing)

        hud.fontSize = 14
        hud.fontColor = .white
        hud.horizontalAlignmentMode = .left
        hud.zPosition = 20
        addChild(hud)

        message.fontSize = 22
        message.fontColor = .cyan
        message.horizontalAlignmentMode = .center
        message.zPosition = 20
        addChild(message)
        didChangeSize(.zero)
    }

    func restart() {
        for rock in rocks { rock.node.removeFromParent() }
        for shot in shots { shot.node.removeFromParent() }
        for bonus in bonuses { bonus.node.removeFromParent() }
        for node in debris { node.removeFromParent() }
        rocks.removeAll()
        shots.removeAll()
        for spark in sparks { spark.node.removeFromParent() }
        sparks.removeAll()
        exhaustAccumulator = 0
        screenShake = 0
        elapsed = 0
        bonuses.removeAll()
        debris.removeAll()
        score = 0
        lives = 3
        wave = 1
        isGameOver = false
        shipVelocity = .zero
        shipAngle = .pi / 2
        lastUpdate = 0
        shotCooldown = 0
        invulnerable = 2
        waveCooldown = 0
        shieldTime = 3
        boostCooldown = 0
        rapidFireTime = 0
        shooting = false
        ship.isHidden = false
        ship.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ship.zRotation = shipAngle
        oldShipPosition = ship.position
        shieldRing.position = ship.position
        spawnWave()
        refreshHUD()
    }

    private func refreshHUD() {
        hud.text = "PKT \(score)  REK \(bestScore)  ŻYCIA \(lives)  FALA \(wave)"
        hud.fontSize = 11
        shieldRing.isHidden = shieldTime <= 0 || isGameOver
        shieldRing.alpha = shieldTime > 0 ? 0.85 : 0
        if isGameOver { message.text = "KONIEC GRY" }
        else if waveCooldown > 0 { message.text = "FALA \(wave)" }
        else { message.text = "" }
    }

    private func spawnWave() {
        guard size.width > 0 && size.height > 0 else { return }
        let count = min(3 + wave, 12)
        for _ in 0..<count {
            var position = CGPoint.zero
            for _ in 0..<24 {
                position = CGPoint(x: CGFloat.random(in: 0...size.width),
                                   y: CGFloat.random(in: 0...size.height))
                if hypot(position.x - ship.position.x, position.y - ship.position.y) > 115 { break }
            }
            addRock(at: position, tier: 3,
                    velocity: CGVector(dx: CGFloat.random(in: -62...62),
                                       dy: CGFloat.random(in: -62...62)))
        }
        waveCooldown = 1.3
    }

    private func addRock(at position: CGPoint, tier: Int, velocity: CGVector) {
        let radius = CGFloat(tier) * 11 + 5
        let polygon = CGMutablePath()
        let edges = 11
        var vertices: [CGPoint] = []
        for i in 0..<edges {
            let a = CGFloat(i) * .pi * 2 / CGFloat(edges)
            let r = radius * CGFloat.random(in: 0.77...1.05)
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            vertices.append(p)
            if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
        }
        polygon.closeSubpath()
        let node = SKShapeNode(path: polygon)
        node.lineWidth = tier == 3 ? 2 : 1.5
        node.strokeColor = tier == 3 ? .systemOrange : (tier == 2 ? .systemYellow : .cyan)
        node.glowWidth = tier == 3 ? 4 : 2.5
        node.fillColor = SKColor(red: 0.075, green: 0.11, blue: 0.16, alpha: 0.98)
        // Triangulated facets and fracture seams are real subpaths in local asteroid space.
        let cracks = CGMutablePath()
        let core = CGPoint(x: CGFloat.random(in: -3...3), y: CGFloat.random(in: -3...3))
        for i in stride(from: 0, to: edges, by: 2) {
            cracks.move(to: vertices[i])
            cracks.addLine(to: core)
            let next = vertices[(i+3)%edges]
            cracks.addLine(to: CGPoint(x: next.x*0.55, y:next.y*0.55))
        }
        let seams = SKShapeNode(path:cracks)
        seams.strokeColor = node.strokeColor.withAlphaComponent(0.24)
        seams.lineWidth = 1
        node.addChild(seams)
        let inset = SKShapeNode(path: polygon)
        inset.setScale(0.85)
        inset.strokeColor = .white.withAlphaComponent(0.08)
        inset.lineWidth = 0.7
        node.addChild(inset)
        node.position = position
        node.zPosition = 3
        addChild(node)
        let mass = CGFloat(tier*tier*tier)
        rocks.append(Rock(node: node, velocity: velocity, radius: radius, tier: tier,
                          spin: CGFloat.random(in: -1.45...1.45), mass: mass))
    }

    private func wrap(_ p: CGPoint, margin: CGFloat = 0) -> CGPoint {
        var p = p
        if p.x < -margin { p.x = size.width + margin }
        else if p.x > size.width + margin { p.x = -margin }
        if p.y < -margin { p.y = size.height + margin }
        else if p.y > size.height + margin { p.y = -margin }
        return p
    }

    private func fire() {
        guard shots.count < (rapidFireTime > 0 ? 16 : 8) else { return }
        let direction = CGVector(dx: cos(shipAngle), dy: sin(shipAngle))
        let origin = CGPoint(x: ship.position.x + direction.dx * 18,
                             y: ship.position.y + direction.dy * 18)
        let bullet = SKShapeNode(circleOfRadius: 2.7)
        bullet.fillColor = .cyan
        bullet.strokeColor = .white
        bullet.glowWidth = 3
        bullet.position = origin
        bullet.zPosition = 4
        addChild(bullet)
        shots.append(Shot(node: bullet,
                          velocity: CGVector(dx: direction.dx * 390 + shipVelocity.dx,
                                             dy: direction.dy * 390 + shipVelocity.dy),
                          lifetime: 0.95, previous: origin))
    }

    private func explodeRock(at index: Int) {
        let rock = rocks.remove(at: index)
        let location = rock.node.position
        rock.node.removeFromParent()
        score += (4 - rock.tier) * 25
        if score > bestScore {
            bestScore = score
            UserDefaults.standard.set(bestScore, forKey: "asteroids.bestScore")
        }
        let tint = rock.node.strokeColor
        burst(at: location, tint: tint, count: rock.tier == 3 ? 31 : 19)
        explosionRing(at: location, radius: rock.radius*2.6, tint:tint)
        screenShake = max(screenShake, CGFloat(rock.tier)*2.6)
        if Int.random(in: 0..<100) < 13 { spawnBonus(at: location) }
        if rock.tier > 1 {
            for sign in [-1.0, 1.0] {
                let angle = CGFloat.random(in: 0...(.pi * 2))
                let speed: CGFloat = CGFloat(85 + (4 - rock.tier) * 24)
                let impulse = CGVector(dx: cos(angle)*speed + CGFloat(sign)*28,
                                       dy: sin(angle)*speed + CGFloat(sign)*18)
                addRock(at: location, tier: rock.tier - 1,
                        velocity: CGVector(dx: rock.velocity.dx + impulse.dx,
                                           dy: rock.velocity.dy + impulse.dy))
            }
        }
    }

    private func explosionRing(at position: CGPoint, radius: CGFloat, tint: SKColor) {
        let ring = SKShapeNode(circleOfRadius: 8)
        ring.strokeColor = tint.withAlphaComponent(0.85)
        ring.lineWidth = 2
        ring.glowWidth = 8
        ring.position = position
        ring.zPosition = 7
        addChild(ring)
        ring.run(.sequence([.group([
            .scale(to: max(1, radius/8), duration: 0.33),
            .fadeOut(withDuration: 0.33)
        ]), .removeFromParent()]))
    }

    private func emitSpark(at position: CGPoint, velocity: CGVector,
                           tint: SKColor, lifetime: CGFloat, shard: Bool) {
        // Limit GPU draw calls and never retain removed particles indefinitely.
        if sparks.count >= 240 { return }
        let node: SKShapeNode
        if shard {
            let line = CGMutablePath()
            line.move(to: CGPoint(x:-CGFloat.random(in: 3...7), y:0))
            line.addLine(to:CGPoint(x:CGFloat.random(in: 3...7), y:0))
            node = SKShapeNode(path:line)
            node.strokeColor = tint
            node.lineWidth = CGFloat.random(in: 1...2.1)
        } else {
            node = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.8...2.5))
            node.fillColor = tint
            node.strokeColor = .clear
        }
        node.glowWidth = 2.7
        node.zPosition = shard ? 6 : 8
        node.position = position
        addChild(node)
        sparks.append(Spark(node:node, velocity:velocity, remaining:lifetime,
                            total:lifetime, angularVelocity:CGFloat.random(in:-9...9)))
    }

    private func burst(at position: CGPoint, tint: SKColor, count: Int) {
        for i in 0..<count {
            let angle = CGFloat(i) * 2 * CGFloat.pi/CGFloat(count) + CGFloat.random(in:-0.2...0.2)
            let speed = CGFloat.random(in: 65...285)
            emitSpark(at:position,
                      velocity:CGVector(dx:cos(angle)*speed, dy:sin(angle)*speed),
                      tint: i%4 == 0 ? .white : tint, lifetime:CGFloat.random(in:0.3...1.15),
                      shard:i%3 == 0)
        }
    }

    private func spawnBonus(at position: CGPoint) {
        let kind = Int.random(in: 0...2)
        let icon = SKShapeNode(circleOfRadius: 12)
        icon.strokeColor = kind == 0 ? .cyan : (kind == 1 ? .systemYellow : .systemGreen)
        icon.fillColor = SKColor(red: 0.04, green: 0.1, blue: 0.16, alpha: 0.95)
        icon.lineWidth = 2
        icon.glowWidth = 3
        icon.position = position
        icon.zPosition = 7
        let label = SKLabelNode(text: kind == 0 ? "S" : (kind == 1 ? "R" : "+"))
        label.fontName = "Menlo-Bold"
        label.fontSize = 14
        label.verticalAlignmentMode = .center
        label.fontColor = icon.strokeColor
        icon.addChild(label)
        addChild(icon)
        bonuses.append(Bonus(node: icon, kind: kind, remaining: 10))
    }

    func activateBoost() {
        guard !isGameOver && boostCooldown <= 0 else { return }
        shipVelocity.dx += cos(shipAngle) * 280
        shipVelocity.dy += sin(shipAngle) * 280
        boostCooldown = 6
        shieldTime = max(shieldTime, 0.7)
        burst(at: ship.position, tint: .cyan, count: 18)
        explosionRing(at: ship.position, radius: 38, tint: .cyan)
    }

    private func loseLife() {
        burst(at: ship.position, tint: .systemRed, count: 35)
        explosionRing(at: ship.position, radius: 92, tint: .systemRed)
        screenShake = 11
        lives -= 1
        shieldTime = 1.8
        invulnerable = 2.2
        ship.position = CGPoint(x: size.width / 2, y: size.height / 2)
        shipVelocity = .zero
        if lives <= 0 {
            isGameOver = true
            ship.isHidden = true
        }
    }

    override func update(_ currentTime: TimeInterval) {
        if lastUpdate == 0 { lastUpdate = currentTime; return }
        let dt = min(max(currentTime - lastUpdate, 0), 1.0/30.0)
        lastUpdate = currentTime
        guard size.width > 1 && size.height > 1 else { return }
        guard !isGameOver else { return }
        let t = CGFloat(dt)
        elapsed += t
        screenShake = max(0, screenShake - 30*t)
        backdropGrid.position = CGPoint(
            x: screenShake > 0.5 ? CGFloat.random(in: -screenShake...screenShake) : 0,
            y: screenShake > 0.5 ? CGFloat.random(in: -screenShake...screenShake) : 0)
        shieldTime = max(0, shieldTime - dt)
        rapidFireTime = max(0, rapidFireTime - dt)
        boostCooldown = max(0, boostCooldown - dt)

        let moveMagnitude = min(1, hypot(moveAnalog.dx, moveAnalog.dy))
        let aimMagnitude = min(1, hypot(aimAnalog.dx, aimAnalog.dy))
        if aimMagnitude > 0.20 {
            shipAngle = atan2(aimAnalog.dy, aimAnalog.dx)
        } else if moveMagnitude > 0.20 {
            shipAngle = atan2(moveAnalog.dy, moveAnalog.dx)
        } else {
            if turnLeft { shipAngle += 3.7 * t }
            if turnRight { shipAngle -= 3.7 * t }
        }
        ship.zRotation = shipAngle
        let isThrusting = accelerating || moveMagnitude > 0.20
        let thrustX = moveMagnitude > 0.20 ? moveAnalog.dx : cos(shipAngle)
        let thrustY = moveMagnitude > 0.20 ? moveAnalog.dy : sin(shipAngle)
        let thrustScale = moveMagnitude > 0.20 ? moveMagnitude : 1
        shipFlame.isHidden = !isThrusting
        if isThrusting {
            shipVelocity.dx += thrustX * 225 * t * thrustScale
            shipVelocity.dy += thrustY * 225 * t * thrustScale
            // Engine exhaust inherits ship velocity, with stochastic velocity and finite lifetime.
            exhaustAccumulator += t*44
            while exhaustAccumulator >= 1 {
                exhaustAccumulator -= 1
                let angle = shipAngle + CGFloat.random(in:-0.25...0.25)
                let speed = CGFloat.random(in: 85...155)
                let outlet = CGPoint(x:ship.position.x - cos(shipAngle)*12,
                                     y:ship.position.y - sin(shipAngle)*12)
                emitSpark(at:outlet,
                          velocity:CGVector(dx:shipVelocity.dx-cos(angle)*speed,
                                            dy:shipVelocity.dy-sin(angle)*speed),
                          tint: Bool.random() ? .systemOrange : .cyan,
                          lifetime:CGFloat.random(in:0.13...0.35), shard:false)
            }
        } else { exhaustAccumulator = 0 }
        let drag = CGFloat(pow(0.993, dt * 60))
        shipVelocity.dx *= drag
        shipVelocity.dy *= drag
        let speed = hypot(shipVelocity.dx, shipVelocity.dy)
        if speed > 250 { shipVelocity.dx *= 250 / speed; shipVelocity.dy *= 250 / speed }
        oldShipPosition = ship.position
        ship.position = wrap(CGPoint(x: ship.position.x + shipVelocity.dx * t,
                                     y: ship.position.y + shipVelocity.dy * t), margin: 15)

        shieldRing.position = ship.position
        shotCooldown -= dt
        if (shooting || aimMagnitude > 0.20) && shotCooldown <= 0 {
            fire()
            shotCooldown = rapidFireTime > 0 ? 0.075 : 0.18
        }
        invulnerable = max(0, invulnerable - dt)
        ship.alpha = invulnerable > 0 ? (sin(currentTime * 17) > 0 ? 1 : 0.28) : 1

        for i in rocks.indices {
            rocks[i].node.position = wrap(
                CGPoint(x: rocks[i].node.position.x + rocks[i].velocity.dx * t,
                        y: rocks[i].node.position.y + rocks[i].velocity.dy * t),
                margin: rocks[i].radius)
            rocks[i].node.zRotation += rocks[i].spin * t
        }
        // Mass-weighted rock collisions with normal impulse and positional separation.
        // Skip rocks on opposite wrap edges to prevent false full-screen collision responses.
        rockCollisionCooldown = max(0, rockCollisionCooldown - t)
        if rocks.count > 1 {
            for i in 0..<(rocks.count-1) {
                for j in (i+1)..<rocks.count {
                    let pa = rocks[i].node.position, pb = rocks[j].node.position
                    let dx = pb.x-pa.x, dy = pb.y-pa.y
                    let distance = hypot(dx,dy)
                    let contact = (rocks[i].radius+rocks[j].radius)*0.86
                    if distance > 0.001 && distance < contact {
                        let n = CGVector(dx: dx/distance, dy: dy/distance)
                        let overlap = contact-distance
                        let ma = rocks[i].mass, mb = rocks[j].mass
                        rocks[i].node.position.x -= n.dx*overlap*mb/(ma+mb)
                        rocks[i].node.position.y -= n.dy*overlap*mb/(ma+mb)
                        rocks[j].node.position.x += n.dx*overlap*ma/(ma+mb)
                        rocks[j].node.position.y += n.dy*overlap*ma/(ma+mb)
                        let result = Self.elasticImpulse(rocks[i].velocity, rocks[j].velocity,
                                                         massA:ma, massB:mb, normal:n)
                        rocks[i].velocity = result.0
                        rocks[j].velocity = result.1
                    }
                }
            }
        }
        for i in shots.indices {
            shots[i].previous = shots[i].node.position
            shots[i].node.position = wrap(
                CGPoint(x: shots[i].node.position.x + shots[i].velocity.dx * t,
                        y: shots[i].node.position.y + shots[i].velocity.dy * t))
            shots[i].lifetime -= dt
        }
        for index in shots.indices.reversed() where shots[index].lifetime <= 0 {
            shots[index].node.removeFromParent()
            shots.remove(at: index)
        }

        for shotIndex in shots.indices.reversed() {
            let shot = shots[shotIndex]
            let hit = rocks.firstIndex {
                let a = shot.previous, b = shot.node.position, c = $0.node.position
                let crossedWrap = abs(b.x-a.x) > size.width*0.5 ||
                                  abs(b.y-a.y) > size.height*0.5
                return crossedWrap ?
                    hypot(c.x-b.x, c.y-b.y) < $0.radius :
                    Self.segmentIntersectsCircle(a, b, center:c, radius:$0.radius)
            }
            if let rockIndex = hit {
                shots[shotIndex].node.removeFromParent()
                shots.remove(at: shotIndex)
                explodeRock(at: rockIndex)
            }
        }

        // Velocity-integrated particle physics with air resistance, spin and fading.
        for i in sparks.indices.reversed() {
            sparks[i].remaining -= t
            if sparks[i].remaining <= 0 {
                sparks[i].node.removeFromParent()
                sparks.remove(at:i)
                continue
            }
            sparks[i].velocity.dx *= CGFloat(pow(0.975, dt*60))
            sparks[i].velocity.dy *= CGFloat(pow(0.975, dt*60))
            sparks[i].node.position.x += sparks[i].velocity.dx*t
            sparks[i].node.position.y += sparks[i].velocity.dy*t
            sparks[i].node.zRotation += sparks[i].angularVelocity*t
            sparks[i].node.alpha = max(0, sparks[i].remaining/sparks[i].total)
        }

        for i in bonuses.indices.reversed() {
            bonuses[i].remaining -= dt
            let b = bonuses[i]
            if b.remaining <= 0 {
                b.node.removeFromParent()
                bonuses.remove(at: i)
            } else if hypot(b.node.position.x - ship.position.x,
                             b.node.position.y - ship.position.y) < 27 {
                switch b.kind {
                case 0: shieldTime = max(shieldTime, 8)
                case 1: rapidFireTime = max(rapidFireTime, 9)
                default: lives = min(5, lives + 1)
                }
                burst(at: b.node.position, tint: b.node.strokeColor, count: 12)
                b.node.removeFromParent()
                bonuses.remove(at: i)
            }
        }
        if invulnerable <= 0 && shieldTime <= 0 && rocks.contains(where: {
            hypot($0.node.position.x - ship.position.x,
                  $0.node.position.y - ship.position.y) < $0.radius + shipRadius
        }) { loseLife() }

        if rocks.isEmpty {
            if waveCooldown <= 0 {
                wave += 1
                spawnWave()
            } else { waveCooldown = max(0, waveCooldown - dt) }
        } else if waveCooldown > 0 { waveCooldown = max(0, waveCooldown - dt) }
        refreshHUD()
    }
}


struct ArcadeHoldButton: View {
    let symbol: String
    let title: String
    let action: (Bool) -> Void
    var buttonWidth: CGFloat = 72
    var buttonHeight: CGFloat = 65
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: buttonHeight >= 70 ? 23 : 19, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
        }
        .foregroundStyle(pressed ? LabStyle.background : Color.white)
        .frame(width: buttonWidth, height: buttonHeight)
        .background(pressed ? LabStyle.accent : LabStyle.panel,
                    in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13)
            .strokeBorder(pressed ? LabStyle.accent : LabStyle.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !pressed { pressed = true; action(true) }
            }
            .onEnded { _ in pressed = false; action(false) })
        .accessibilityLabel(title)
    }
}

struct AsteroidsGameView: View {
    @State private var scene = AsteroidsArcadeScene(size: CGSize(width: 390, height: 650))
    @State private var fullScreen = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= 700
            let stickDiameter = min(wide ? 145 : 118, max(92, geo.size.width * 0.23))
            ZStack {
                LabStyle.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .foregroundStyle(LabStyle.accent)
                            .frame(width: 32, height: 32)
                            .background(LabStyle.accent.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 10))
                        Text("ASTEROIDS")
                            .font(.system(size: wide ? 22 : 17, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Spacer(minLength: 1)
                        Button {
                            scene.activateBoost()
                        } label: {
                            Image(systemName: "bolt.fill")
                                .frame(width: 33, height: 36)
                        }
                        .accessibilityLabel("Dopalacz")
                        .foregroundStyle(.orange)
                        .background(.orange.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 9))
                        Button {
                            scene.restart()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .frame(width: 33, height: 36)
                        }
                        .accessibilityLabel("Nowa gra")
                        .foregroundStyle(LabStyle.accent)
                        .background(LabStyle.panel, in: RoundedRectangle(cornerRadius: 9))
                        Button {
                            fullScreen = true
                        } label: {
                            Label("PEŁNY EKRAN", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .padding(.horizontal, 9)
                                .frame(height: 36)
                        }
                        .foregroundStyle(.black)
                        .background(LabStyle.accent, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, wide ? 22 : 10)
                    .padding(.vertical, 8)

                    SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(red: 0.018, green: 0.025, blue: 0.065))
                        .overlay(alignment: .bottom) {
                            HStack(alignment: .bottom) {
                                GameJoystick(title: "RUCH", tint: .cyan,
                                             diameter: stickDiameter) {
                                    scene.moveAnalog = $0
                                }
                                Spacer(minLength: 12)
                                GameJoystick(title: "CEL · OGIEŃ", tint: .orange,
                                             diameter: stickDiameter) {
                                    scene.aimAnalog = $0
                                }
                            }
                            .padding(.horizontal, wide ? 24 : 14)
                            .padding(.bottom, 14)
                        }
                        .accessibilityLabel("Pole gry ASTEROIDS z dwoma analogami")
                }
            }
        }
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $fullScreen) {
            AsteroidsLandscapeView(scene: scene) {
                fullScreen = false
            }
        }
        .onDisappear {
            scene.moveAnalog = .zero
            scene.aimAnalog = .zero
            scene.turnLeft = false
            scene.turnRight = false
            scene.accelerating = false
            scene.shooting = false
            if !fullScreen { scene.isPaused = true }
        }
        .onAppear { scene.isPaused = false }
    }
}

struct MainTabsView: View {
    var body: some View {
        TabView {
            ShaderLabView()
                .tabItem { Label("SHADER LAB", systemImage: "cube.transparent.fill") }
            NavigationStack {
                AsteroidsGameView()
            }
            .tabItem { Label("ASTEROIDS", systemImage: "gamecontroller.fill") }
            PaintView()
                .tabItem { Label("PAINT", systemImage: "paintbrush.pointed.fill") }
            SmileQuotesView()
                .tabItem { Label("HUMOR", systemImage: "face.smiling.fill") }
            DoomSharewareView()
                .tabItem { Label("DOOM", systemImage: "bolt.shield.fill") }
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}
