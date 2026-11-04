import SwiftUI
import UIKit
import SpriteKit

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
        .onAppear { GameLandscapeMode.set(true); scene.isPaused = false }
        .onDisappear { scene.moveAnalog = .zero; scene.aimAnalog = .zero; GameLandscapeMode.set(false) }
    }
}

struct DoomLandscapeView: View {
    let frame: UIImage?
    let move: (CGVector) -> Void
    let aim: (CGVector) -> Void
    let interact: (Bool) -> Void
    let fire: (Bool) -> Void
    let menu: (Bool) -> Void
    let close: () -> Void

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
                VStack {
                    HStack {
                        Text("DOOM SHAREWARE").font(.system(.caption, design: .monospaced).bold())
                            .foregroundStyle(.orange)
                        Spacer()
                        DoomPressControl(title: "MENU", symbol: "line.3.horizontal", action: menu)
                        Button("WYJDŹ", action: close).buttonStyle(.borderedProminent)
                    }
                    Spacer()
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
                .padding(.horizontal, max(16, g.safeAreaInsets.leading + 10))
                .padding(.top, 8)
                .padding(.bottom, max(10, g.safeAreaInsets.bottom))
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { GameLandscapeMode.set(true) }
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
