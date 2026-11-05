import SwiftUI
import UIKit
import SpriteKit
import GameController

// Apple GameController supports DualShock 4 (DualShock profile) and compatible
// extended controllers. Read on the main game/UI update thread, so touch input
// remains available and a disconnected controller never leaves keys held down.
enum PS4Controller {
    static func discover() {
        GCController.startWirelessControllerDiscovery(completionHandler: nil)
    }

    static var pad: GCExtendedGamepad? {
        GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
    }

    static func stick(_ stick: GCControllerDirectionPad, deadZone: CGFloat = 0.18) -> CGVector {
        let x = CGFloat(stick.xAxis.value)
        let y = CGFloat(stick.yAxis.value)
        let magnitude = hypot(x, y)
        guard magnitude > deadZone else { return .zero }
        let adjusted = min(1, (magnitude - deadZone) / (1 - deadZone))
        return CGVector(dx: x / magnitude * adjusted, dy: y / magnitude * adjusted)
    }
}

// Full-screen presentations use native iOS 16 scene geometry updates.
// iPadOS may deny orientation changes when another multitasking window is active.
final class GameOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        GameLandscapeMode.active ? .landscape : .allButUpsideDown
    }
}
enum GameLandscapeMode {
    static var active = false
    static func set(_ isActive: Bool) {
        active = isActive
        DispatchQueue.main.async {
            guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }) else { return }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: isActive ? .landscape : .portrait)) { error in
                NSLog("Game landscape rotation denied: %@", error.localizedDescription)
            }
        }
    }
}

struct GameJoystick: View {
    let title: String
    let tint: Color
    var diameter: CGFloat = 122
    let onVector: (CGVector) -> Void
    @State private var knob = CGSize.zero
    var body: some View {
        let r = diameter * 0.34
        VStack(spacing: 5) {
            ZStack {
                Circle().fill(.black.opacity(0.65))
                    .overlay(Circle().strokeBorder(tint.opacity(0.8), lineWidth: 2))
                Circle().stroke(tint.opacity(0.25)).padding(18)
                Circle().fill(tint.opacity(0.8))
                    .frame(width: diameter * 0.42, height: diameter * 0.42)
                    .overlay(Circle().strokeBorder(.white.opacity(0.7)))
                    .shadow(color: tint.opacity(0.45), radius: 8)
                    .offset(knob)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .highPriorityGesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let dx = value.location.x - diameter / 2
                    let dy = value.location.y - diameter / 2
                    let scale = min(1, r / max(0.01, hypot(dx, dy)))
                    knob = CGSize(width: dx * scale, height: dy * scale)
                    onVector(CGVector(dx: knob.width / r, dy: -knob.height / r))
                }
                .onEnded { _ in knob = .zero; onVector(.zero) })
            Text(title).font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
        }
        .accessibilityLabel("Analog: \(title)")
    }
}

struct AsteroidsLandscapeView: View {
    let scene: AsteroidsArcadeScene
    let close: () -> Void
    var body: some View {
        GeometryReader { g in
            let d = min(160, max(98, g.size.height * 0.37))
            ZStack {
                Color.black.ignoresSafeArea()
                SpriteView(scene: scene, options: [.ignoresSiblingOrder]).ignoresSafeArea()
                VStack {
                    HStack {
                        Text("ASTEROIDS").font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(LabStyle.accent)
                        Spacer()
                        Button("RESET") { scene.restart() }.buttonStyle(.bordered)
                        Button("WYJDŹ", action: close).buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        GameJoystick(title: "RUCH", tint: .cyan, diameter: d) { scene.moveAnalog = $0 }
                        Spacer()
                        Button { scene.activateBoost() } label: {
                            Label("BOOST", systemImage: "bolt.fill").font(.caption.bold())
                                .padding(10).background(.orange.opacity(0.75), in: Capsule())
                        }
                        .padding(.bottom, 10)
                        GameJoystick(title: "CELOWANIE · OGIEŃ", tint: .orange, diameter: d) {
                            scene.aimAnalog = $0
                        }
                    }
                }
                .padding(.horizontal, max(16, g.safeAreaInsets.leading + 10))
                .padding(.top, 8)
                .padding(.bottom, max(10, g.safeAreaInsets.bottom))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { PS4Controller.discover(); scene.controllerActive = true; GameLandscapeMode.set(true); scene.isPaused = false }
        .onDisappear { scene.moveAnalog = .zero; scene.aimAnalog = .zero; GameLandscapeMode.set(false) }
    }
}

// Input-only surfaces: no analogue graphics or synthetic center location.
struct DoomGestureMovementZone: View {
    let onVector: (CGVector) -> Void
    @State private var firstPoint: CGPoint?

    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        if firstPoint == nil { firstPoint = value.startLocation }
                        let origin = firstPoint ?? value.startLocation
                        let radius = max(36, min(76, geometry.size.height * 0.26))
                        let dx = (value.location.x - origin.x) / radius
                        let dy = (origin.y - value.location.y) / radius
                        func filtered(_ v: CGFloat) -> CGFloat {
                            let magnitude = min(1, abs(v))
                            return abs(v) < 0.12 ? 0 : (v > 0 ? 1 : -1) * (magnitude - 0.12) / 0.88
                        }
                        onVector(CGVector(dx: filtered(dx), dy: filtered(dy)))
                    }
                    .onEnded { _ in firstPoint = nil; onVector(.zero) })
        }
        .accessibilityLabel("Lewy obszar: ruch i krok w bok")
    }
}

struct DoomGestureLookZone: View {
    let sensitivity: Double
    let onMotion: (Double) -> Void
    @State private var previous = CGSize.zero

    var body: some View {
        Color.clear.contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    let delta = value.translation.width - previous.width
                    previous = value.translation
                    if abs(delta) > 0.01 {
                        // Native Doom ev_mouse deltas: no return-to-center or key-repeat lag.
                        onMotion(Double(delta) * sensitivity)
                    }
                }
                .onEnded { _ in previous = .zero })
            .onDisappear { previous = .zero }
            .accessibilityLabel("Prawy obszar: płynne rozglądanie przesunięciem palca")
    }
}

struct DoomLandscapeView: View {
    let frame: UIImage?
    let move: (CGVector) -> Void
    let aim: (CGVector) -> Void
    let lookMotion: (Double) -> Void
    let interact: (Bool) -> Void
    let fire: (Bool) -> Void
    let menu: (Bool) -> Void
    let close: () -> Void
    @Binding var touchMode: String
    @Binding var lookSensitivity: Double
    @Binding var fireHorizontal: Double
    @Binding var fireVertical: Double
    @State private var showControlSettings = false

    var body: some View {
        GeometryReader { g in
            let d = min(155, max(100, g.size.height * 0.37))
            ZStack {
                Color.black.ignoresSafeArea()
                if let frame {
                    Image(uiImage: frame).resizable().interpolation(.none)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                } else {
                    Text("DOOM · ŁADOWANIE").foregroundStyle(.orange)
                }
                if touchMode == "gestures" {
                    HStack(spacing: 0) {
                        DoomGestureMovementZone(onVector: move)
                        DoomGestureLookZone(sensitivity: lookSensitivity, onMotion: lookMotion)
                    }
                    .ignoresSafeArea()
                    DoomPressControl(title: "OGIEŃ", symbol: "scope", action: fire)
                        .frame(width: 96, height: 52)
                        .position(x: g.size.width * (0.56 + fireHorizontal * 0.38),
                                  y: g.size.height * (0.20 + fireVertical * 0.65))
                    DoomPressControl(title: "UŻYJ", symbol: "hand.tap", action: interact)
                        .frame(width: 82, height: 45)
                        .position(x: g.size.width * 0.82, y: g.size.height * 0.83)
                }
                VStack {
                    HStack(spacing: 10) {
                        Text("DOOM SHAREWARE").font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(.orange)
                        Spacer()
                        Button {
                            move(.zero); aim(.zero); fire(false); interact(false)
                            showControlSettings = true
                        } label: {
                            Label("STEROWANIE", systemImage: "slider.horizontal.3")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.bordered)
                        DoomPressControl(title: "MENU", symbol: "line.3.horizontal", action: menu)
                        Button("WYJDŹ", action: close).buttonStyle(.borderedProminent)
                    }
                    Spacer()
                    if touchMode != "gestures" {
                        HStack(alignment: .bottom) {
                            GameJoystick(title: "RUCH", tint: .cyan, diameter: d, onVector: move)
                            Spacer()
                            VStack(spacing: 8) {
                                DoomPressControl(title: "OGIEŃ", symbol: "scope", action: fire)
                                DoomPressControl(title: "UŻYJ", symbol: "hand.tap", action: interact)
                            }
                            .padding(.bottom, 12)
                            GameJoystick(title: "OBRÓT", tint: .red, diameter: d, onVector: aim)
                        }
                    }
                }
                .padding(.horizontal, max(16, g.safeAreaInsets.leading + 10))
                .padding(.top, 8)
                .padding(.bottom, max(10, g.safeAreaInsets.bottom))
                if showControlSettings {
                    Color.black.opacity(0.76).ignoresSafeArea()
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("STEROWANIE DOOM").font(.headline)
                            Spacer()
                            Button("GOTOWE") { showControlSettings = false }
                                .buttonStyle(.borderedProminent)
                        }
                        Picker("Tryb", selection: $touchMode) {
                            Text("Analogi").tag("analog")
                            Text("Gesty bez analogów").tag("gestures")
                        }
                        .pickerStyle(.segmented)
                        if touchMode == "gestures" {
                            Text("Lewa połowa: chodzenie i strafing. Prawa: rozglądanie ruchem palca.")
                                .font(.caption)
                            Text("Czułość rozglądania")
                            Slider(value: $lookSensitivity, in: 0.5...3.0, step: 0.1)
                            Text("Pozycja OGIEŃ — prawo / lewo")
                            Slider(value: $fireHorizontal, in: 0...1)
                            Text("Pozycja OGIEŃ — góra / dół")
                            Slider(value: $fireVertical, in: 0...1)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 440)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .padding(18)
                }
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { GameLandscapeMode.set(true) }
        .onChange(of: touchMode) { _ in move(.zero); aim(.zero); fire(false); interact(false) }
        .onDisappear {
            move(.zero); aim(.zero); fire(false); interact(false); menu(false)
            GameLandscapeMode.set(false)
        }
    }
}

struct DoomPressControl: View {
    let title: String
    let symbol: String
    let action: (Bool) -> Void
    @State private var pressed = false
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(10)
            .background(.red.opacity(pressed ? 0.9 : 0.55), in: Capsule())
            .contentShape(Capsule())
            .highPriorityGesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true; action(true) } }
                .onEnded { _ in pressed = false; action(false) })
    }
}
