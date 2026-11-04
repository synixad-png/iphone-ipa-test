import SwiftUI
import SceneKit
import Metal
import SpriteKit

@main
struct HelloIPhoneApp: App {
    var body: some Scene {
        WindowGroup { MainTabsView() }
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
                    HStack { Text("Moc lamp"); Spacer(); Text("\(Int(lightPower * 100))%") }
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


 
// MARK: - Independent arcade game. No changes to the SceneKit shader pipeline.
final class AsteroidsArcadeScene: SKScene {
    struct Rock {
        var node: SKShapeNode
        var velocity: CGVector
        var radius: CGFloat
        var tier: Int
        var spin: CGFloat
    }
    struct Shot {
        var node: SKShapeNode
        var velocity: CGVector
        var lifetime: TimeInterval
    }

    var turnLeft = false
    var turnRight = false
    var accelerating = false
    var shooting = false
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

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.018, green: 0.025, blue: 0.065, alpha: 1)
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
        guard size.width > 0 && size.height > 0 else { return }
        for _ in 0..<80 {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.45...1.3))
            dot.fillColor = .white.withAlphaComponent(CGFloat.random(in: 0.18...0.68))
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
        ship.lineWidth = 2.6
        ship.glowWidth = 2.0
        ship.fillColor = SKColor(red: 0.04, green: 0.28, blue: 0.45, alpha: 0.8)
        ship.zPosition = 5
        addChild(ship)
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
        for i in 0..<10 {
            let a = CGFloat(i) * .pi * 2 / 10
            let r = radius * CGFloat.random(in: 0.72...1.12)
            let p = CGPoint(x: cos(a) * r, y: sin(a) * r)
            if i == 0 { polygon.move(to: p) } else { polygon.addLine(to: p) }
        }
        polygon.closeSubpath()
        let node = SKShapeNode(path: polygon)
        node.lineWidth = 1.8
        node.strokeColor = tier == 3 ? .systemOrange : (tier == 2 ? .systemYellow : .cyan)
        node.fillColor = SKColor(red: 0.13, green: 0.20, blue: 0.29, alpha: 0.92)
        node.position = position
        node.zPosition = 3
        addChild(node)
        rocks.append(Rock(node: node, velocity: velocity, radius: radius, tier: tier,
                          spin: CGFloat.random(in: -1.7...1.7)))
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
                          lifetime: 0.95))
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
        burst(at: location, tint: rock.node.strokeColor, count: rock.tier == 3 ? 13 : 7)
        if Int.random(in: 0..<100) < 13 { spawnBonus(at: location) }
        if rock.tier > 1 {
            for sign in [-1.0, 1.0] {
                let angle = CGFloat.random(in: 0...(.pi * 2))
                let speed: CGFloat = CGFloat(72 + (4 - rock.tier) * 28)
                addRock(at: location, tier: rock.tier - 1,
                        velocity: CGVector(dx: cos(angle) * speed + rock.velocity.dx * CGFloat(sign) * 0.35,
                                           dy: sin(angle) * speed + rock.velocity.dy * CGFloat(sign) * 0.35))
            }
        }
    }

    private func burst(at position: CGPoint, tint: SKColor, count: Int) {
        for _ in 0..<count {
            let dot = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.4...3.0))
            dot.fillColor = tint
            dot.strokeColor = .clear
            dot.glowWidth = 2
            dot.position = position
            dot.zPosition = 8
            addChild(dot)
            debris.append(dot)
            let angle = CGFloat.random(in: 0...(.pi * 2))
            let distance = CGFloat.random(in: 16...55)
            let duration = Double.random(in: 0.25...0.55)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: duration)
            let fade = SKAction.fadeOut(withDuration: duration)
            dot.run(.sequence([.group([move, fade]), .removeFromParent()]))
        }
        // Keep only live particles. The actions remove their scene nodes.
        if debris.count > 250 { debris.removeAll { $0.parent == nil } }
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
    }

    private func loseLife() {
        burst(at: ship.position, tint: .systemRed, count: 24)
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
        let dt = min(max(currentTime - lastUpdate, 0), 0.04)
        lastUpdate = currentTime
        guard size.width > 1 && size.height > 1 else { return }
        guard !isGameOver else { return }
        let t = CGFloat(dt)
        shieldTime = max(0, shieldTime - dt)
        rapidFireTime = max(0, rapidFireTime - dt)
        boostCooldown = max(0, boostCooldown - dt)

        if turnLeft { shipAngle += 3.7 * t }
        if turnRight { shipAngle -= 3.7 * t }
        ship.zRotation = shipAngle
        if accelerating {
            shipVelocity.dx += cos(shipAngle) * 215 * t
            shipVelocity.dy += sin(shipAngle) * 215 * t
        }
        let drag = CGFloat(pow(0.992, dt * 60))
        shipVelocity.dx *= drag
        shipVelocity.dy *= drag
        let speed = hypot(shipVelocity.dx, shipVelocity.dy)
        if speed > 250 { shipVelocity.dx *= 250 / speed; shipVelocity.dy *= 250 / speed }
        ship.position = wrap(CGPoint(x: ship.position.x + shipVelocity.dx * t,
                                     y: ship.position.y + shipVelocity.dy * t), margin: 15)

        shieldRing.position = ship.position
        shotCooldown -= dt
        if shooting && shotCooldown <= 0 { fire(); shotCooldown = rapidFireTime > 0 ? 0.075 : 0.18 }
        invulnerable = max(0, invulnerable - dt)
        ship.alpha = invulnerable > 0 ? (sin(currentTime * 17) > 0 ? 1 : 0.28) : 1

        for i in rocks.indices {
            rocks[i].node.position = wrap(
                CGPoint(x: rocks[i].node.position.x + rocks[i].velocity.dx * t,
                        y: rocks[i].node.position.y + rocks[i].velocity.dy * t),
                margin: rocks[i].radius)
            rocks[i].node.zRotation += rocks[i].spin * t
        }
        for i in shots.indices {
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
            let hit = rocks.firstIndex {
                hypot($0.node.position.x - shots[shotIndex].node.position.x,
                      $0.node.position.y - shots[shotIndex].node.position.y) < $0.radius
            }
            if let rockIndex = hit {
                shots[shotIndex].node.removeFromParent()
                shots.remove(at: shotIndex)
                explodeRock(at: rockIndex)
            }
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
    @State private var pressed = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title2.bold())
            Text(title).font(.caption2.bold())
        }
        .foregroundStyle(pressed ? .black : .white)
        .frame(width: 72, height: 65)
        .background(pressed ? Color.cyan : Color.white.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 15))
        .contentShape(RoundedRectangle(cornerRadius: 15))
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Color(red: 0.02, green: 0.03, blue: 0.08).ignoresSafeArea()
                SpriteView(scene: scene, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 10) {
                    Spacer()
                    HStack(spacing: 7) {
                        ArcadeHoldButton(symbol: "arrow.counterclockwise", title: "LEWO") { scene.turnLeft = $0 }
                        ArcadeHoldButton(symbol: "arrow.clockwise", title: "PRAWO") { scene.turnRight = $0 }
                        ArcadeHoldButton(symbol: "flame.fill", title: "CIĄG") { scene.accelerating = $0 }
                        ArcadeHoldButton(symbol: "scope", title: "OGIEŃ") { scene.shooting = $0 }
                    }
                    .padding(.horizontal, 8)
                    HStack {
                        Button {
                            scene.activateBoost()
                        } label: {
                            Label("DOPALACZ (6 s)", systemImage: "bolt.fill")
                                .font(.caption.bold())
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                .background(Color.orange.opacity(0.25), in: Capsule())
                        }
                        .foregroundStyle(.orange)
                        Spacer()
                        Text("S: OSŁONA  R: SZYBKI OGIEŃ  +: ŻYCIE")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }.padding(.horizontal, 12)
                    .padding(.bottom, 8)
                    Button("NOWA GRA") { scene.restart() }
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                        .padding(.bottom, 4)
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 4))
            }
        }
        .navigationTitle("ASTEROIDS")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            scene.turnLeft = false
            scene.turnRight = false
            scene.accelerating = false
            scene.shooting = false
            scene.isPaused = true
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
        }
        .tint(.cyan)
        .preferredColorScheme(.dark)
    }
}
