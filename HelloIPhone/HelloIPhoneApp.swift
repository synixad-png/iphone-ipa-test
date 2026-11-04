import SwiftUI
import SceneKit
import Metal

@main
struct HelloIPhoneApp: App {
    var body: some Scene {
        WindowGroup { ShaderLabView() }
    }
}

enum Shape3D: String, CaseIterable, Identifiable {
    case sphere = "Kula", cube = "Sześcian", torus = "Torus", cone = "Stożek", cylinder = "Walec", pyramid = "Ostrosłup", capsule = "Kapsuła"
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

enum ShaderScene {
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
        let shapeID = "shape:" + shape.rawValue
        if model.geometry?.name != shapeID {
            model.geometry = shape.geometry
            model.geometry?.name = shapeID
        }
        model.geometry?.materials = [material(shading, color: color, metalness: metalness, roughness: roughness, effect: effect)]
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
        if spinning && model.action(forKey: "spin") == nil {
            model.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 9)), forKey: "spin")
        } else if !spinning {
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

    func makeUIView(context: Context) -> SCNView { ShaderScene.makeView() }
    func updateUIView(_ view: SCNView, context: Context) {
        guard let scene = view.scene else { return }
        ShaderScene.update(scene, shape: shape, shading: shading, color: color,
                           metalness: metalness, roughness: roughness, spinning: spinning,
                           effect: effect, lightPreset: lightPreset, lightPower: lightPower)
        view.isPlaying = spinning
        view.rendersContinuously = spinning
    }
}

struct ShaderLabView: View {
    @State private var shape: Shape3D = .sphere
    @State private var shading: Shading3D = .pbr
    @State private var metalness = 0.85
    @State private var roughness = 0.18
    @State private var spinning = true
    @State private var selectedColor = 0
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
        ZStack {
            Color(red: 0.035, green: 0.055, blue: 0.10).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("SHADER LAB 3D").font(.title2.bold()).tracking(1.2)
                            Text("Natywny podgląd 3D · SceneKit").font(.caption).foregroundStyle(.cyan)
                        }
                        Spacer()
                        Image(systemName: "cube.transparent.fill").font(.title).foregroundStyle(.cyan)
                    }
                    ModelView(shape: shape, shading: shading, metalness: metalness, roughness: roughness, spinning: spinning, effect: effect, lightPreset: lightPreset,
                              lightPower: lightPower, color: swatches[selectedColor].1)
                        .frame(height: 315)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.12)))
                    Text("Przeciągnij palcem, aby obracać · uszczypnij, aby przybliżyć lub oddalić").font(.caption2).foregroundStyle(.white.opacity(0.7))
                    Text("BRYŁA").font(.caption.bold()).tracking(1.5).foregroundStyle(.cyan)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Shape3D.allCases) { item in
                                Button(item.rawValue) { shape = item }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(shape == item ? Color.cyan : Color.white.opacity(0.11), in: Capsule())
                                    .foregroundStyle(shape == item ? .black : .white)
                            }
                        }
                    }
                    Text("EFEKT POWIERZCHNI").font(.caption.bold()).tracking(1.5).foregroundStyle(.cyan)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(SurfaceFX.allCases) { item in
                                Button(item.rawValue) { effect = item }
                                    .padding(.horizontal, 12).padding(.vertical, 9)
                                    .background(effect == item ? Color.cyan : Color.white.opacity(0.11), in: Capsule())
                                    .foregroundStyle(effect == item ? .black : .white)
                            }
                        }
                    }
                    Text("MODEL CIENIOWANIA").font(.caption.bold()).tracking(1.5).foregroundStyle(.cyan)
                    Picker("Cieniowanie", selection: $shading) {
                        ForEach(Shading3D.allCases) { item in Text(item.rawValue).tag(item) }
                    }.pickerStyle(.menu).tint(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                    HStack(spacing: 14) {
                        ForEach(swatches.indices, id: \.self) { index in
                            Button { selectedColor = index } label: {
                                Circle().fill(swatches[index].2).frame(width: 33, height: 33)
                                    .overlay(Circle().stroke(.white, lineWidth: selectedColor == index ? 3 : 0))
                            }.accessibilityLabel(swatches[index].0)
                        }
                        Spacer()
                        Toggle("Obrót", isOn: $spinning).tint(.cyan).fixedSize()
                    }
                    VStack(spacing: 12) {
                        HStack { Text("Metaliczność"); Spacer(); Text("\(Int(metalness * 100))%") }
                        Slider(value: $metalness, in: 0...1).tint(.cyan)
                        HStack { Text("Chropowatość"); Spacer(); Text("\(Int(roughness * 100))%") }
                        Slider(value: $roughness, in: 0...1).tint(.cyan)
                    }
                    .font(.subheadline)
                    .disabled(shading != .pbr)
                    Text("OŚWIETLENIE").font(.caption.bold()).tracking(1.5).foregroundStyle(.cyan)
                    Picker("Scena światła", selection: $lightPreset) {
                        ForEach(LightPreset.allCases) { preset in Text(preset.rawValue).tag(preset) }
                    }.pickerStyle(.menu).tint(.white)
                    HStack { Text("Moc lamp"); Spacer(); Text("\\(Int(lightPower * 100))%") }
                        .font(.subheadline)
                    Slider(value: $lightPower, in: 0...2).tint(.cyan)
                    Text("Efekty siatki, neonu, szkła i ceramiki są oddzielne od modelu cieniowania. Neon to materiał emisyjny, bez dodatkowego bloom; szkło wykorzystuje przezroczystość, bez ray tracingu.")
                        .font(.caption).foregroundStyle(.white.opacity(0.68))
                    Text("Metaliczność i chropowatość wpływają na PBR. Modele Phong, Blinn i Lambert wykorzystują własne równania oświetlenia; tryb stały nie reaguje na światło. PBR wykorzystuje Metal i mapę otoczenia do odbić.")
                        .font(.caption).foregroundStyle(.white.opacity(0.68))
                    Text("SHADER LAB 3D · iOS 16+ · v1.1")
                        .font(.caption2.monospaced()).foregroundStyle(.white.opacity(0.45)).frame(maxWidth: .infinity)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
        }
        .preferredColorScheme(.dark)
    }
}
