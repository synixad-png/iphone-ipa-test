import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreGraphics

// Uses the original Doom renderer and gameplay through the native doomgeneric C bridge.
// The IWAD is supplied by the user (the shareware game data is not redistributed).
struct DoomSharewareView: View {
    @State private var importPresented = false
    @State private var loading = false
    @State private var statusText = "Wybierz legalną wersję DOOM1.WAD (shareware), aby uruchomić grę."
    @State private var screenshot: UIImage?
    @State private var hasWad = false
    @State private var running = false
    @State private var started = false

    private let width = 320
    private let height = 200
    private let poll = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let downloadURL = URL(string: "https://www.doomarchive.com/ListFiles.php?ContentsFolderId=216&FolderId=216")!

    private var wadURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DOOM1.WAD")
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 760
            ZStack {
                LabStyle.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "gamecontroller.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.red)
                                .frame(width: 47, height: 47)
                                .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text("DOOM · SHAREWARE")
                                    .font(.system(size: wide ? 27 : 20, weight: .bold, design: .rounded))
                                Text("Oryginalny silnik z 1993 · Episode 1")
                                    .font(.caption)
                                    .foregroundStyle(LabStyle.muted)
                            }
                            Spacer()
                            Text("1993")
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(.orange)
                        }
                        if wide {
                            HStack(alignment: .top, spacing: 16) {
                                gamePanel
                                    .frame(maxWidth: .infinity)
                                controlsPanel
                                    .frame(width: min(340, geometry.size.width * 0.35))
                            }
                        } else {
                            gamePanel
                            controlsPanel
                        }
                        Text("Port bazuje na doomgeneric (GPL-2.0). Pliki shareware są osobnymi danymi gry. Ta wczesna wersja portu uruchamia silnik bez dźwięku.")
                            .font(.caption2)
                            .foregroundStyle(LabStyle.muted)
                    }
                    .padding(.horizontal, wide ? 22 : 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 1250)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .fileImporter(isPresented: $importPresented,
                      allowedContentTypes: [UTType(filenameExtension: "wad") ?? .data, .data]) { result in
            do {
                let source = try result.get()
                let access = source.startAccessingSecurityScopedResource()
                defer { if access { source.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: source)
                guard data.count > 1_000_000, data.prefix(4).elementsEqual(Array("IWAD".utf8)) else {
                    statusText = "Nieprawidłowy plik. Wybierz oryginalny DOOM1.WAD z wydania shareware."
                    return
                }
                // The core engine starts only once per app process; reject unsafe hot-swapping.
                guard !started else {
                    statusText = "Aby zmienić dane WAD, zamknij i uruchom ponownie aplikację."
                    return
                }
                try data.write(to: wadURL, options: .atomic)
                hasWad = true
                start()
            } catch {
                statusText = "Nie udało się otworzyć WAD: \(error.localizedDescription)"
            }
        }
        .onAppear {
            hasWad = FileManager.default.fileExists(atPath: wadURL.path)
            doom_bridge_pause(0)
            if hasWad && !started { start() }
        }
        .onDisappear {
            releaseAllKeys()
            doom_bridge_pause(1)
        }
        .onReceive(poll) { _ in
            guard started else { return }
            if doom_bridge_status() < 0 {
                loading = false
                statusText = "Błąd inicjalizacji DOOM. Sprawdź plik WAD."
                return
            }
            var pixels = [UInt32](repeating: 0, count: width * height)
            let count = pixels.withUnsafeMutableBufferPointer { pointer -> Int32 in
                doom_bridge_copy(pointer.baseAddress, Int32(pointer.count))
            }
            guard count == width * height else { return }
            let bytes = pixels.withUnsafeBytes { Data($0) }
            guard let provider = CGDataProvider(data: bytes as CFData),
                  let image = CGImage(width: width, height: height,
                                      bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.union(
                                          CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue)),
                                      provider: provider, decode: nil,
                                      shouldInterpolate: false, intent: .defaultIntent) else { return }
            screenshot = UIImage(cgImage: image)
            loading = false
            running = true
            statusText = "DOOM SHAREWARE · silnik aktywny"
        }
    }

    private var gamePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabSectionTitle(title: "DOOM · E1M1", symbol: "gamecontroller")
            ZStack {
                Rectangle().fill(.black)
                if let screenshot {
                    Image(uiImage: screenshot)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(4.0 / 3.0, contentMode: .fit)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(.red)
                        Text(loading ? "URUCHAMIANIE SILNIKA..." : "DOOM SHAREWARE")
                            .font(.system(.headline, design: .monospaced).bold())
                        Text(hasWad ? "Inicjalizacja..." : "Wczytaj DOOM1.WAD, aby zagrać")
                            .font(.caption)
                            .foregroundStyle(LabStyle.muted)
                    }
                    .multilineTextAlignment(.center)
                }
            }
            .aspectRatio(4.0 / 3.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(LabStyle.border))
            Text(statusText)
                .font(.caption)
                .foregroundStyle(running ? LabStyle.accent : LabStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .labPanel()
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            LabSectionTitle(title: "STEROWANIE DOTYKOWE", symbol: "hand.draw")
            HStack(spacing: 8) {
                hold("LEWO", "arrow.turn.up.left", key: 0xac)
                hold("PRZÓD", "arrow.up", key: 0xad)
                hold("PRAWO", "arrow.turn.up.right", key: 0xae)
            }
            HStack(spacing: 8) {
                hold("TYŁ", "arrow.down", key: 0xaf)
                hold("STRZAŁ", "scope", key: 0xa3, color: .red)
                hold("UŻYJ", "hand.tap", key: 0xa2, color: .orange)
            }
            HStack(spacing: 8) {
                hold("MENU", "line.3.horizontal", key: 27)
                hold("ENTER", "return", key: 13)
                hold("MAPA", "map", key: 9)
            }
            Divider().overlay(LabStyle.border)
            Button {
                importPresented = true
            } label: {
                Label(hasWad ? "Zmień WAD (po restarcie)" : "IMPORTUJ SHAREWARE WAD",
                      systemImage: "square.and.arrow.down")
                    .font(.subheadline.bold())
            }
            .buttonStyle(LabPrimaryButtonStyle())
            .disabled(loading || started)
            Text("Brak DOOM1.WAD? Pobierz archiwum oryginalnego shareware i wyodrębnij WAD w aplikacji Pliki.")
                .font(.caption).foregroundStyle(LabStyle.muted)
            Link(destination: downloadURL) {
                Label("Oficjalne archiwum wydań shareware", systemImage: "arrow.down.circle")
                    .font(.caption.bold())
                    .foregroundStyle(LabStyle.accent)
            }
        }
        .labPanel()
    }

    private func hold(_ label: String, _ symbol: String, key: Int32,
                      color: Color = LabStyle.accent) -> some View {
        DoomTouchButton(label: label, symbol: symbol, tint: color, enabled: started) { pressed in
            doom_bridge_key(key, pressed ? 1 : 0)
        }
    }

    private func start() {
        guard hasWad, !started else { return }
        started = true
        loading = true
        statusText = "Start oryginalnego silnika DOOM..."
        let outcome = wadURL.path.withCString { doom_bridge_start($0) }
        if outcome < 0 {
            started = false
            loading = false
            statusText = "Uruchomienie silnika nie powiodło się."
        }
    }

    private func releaseAllKeys() {
        for key: Int32 in [0xac, 0xad, 0xae, 0xaf, 0xa3, 0xa2, 27, 13, 9] {
            doom_bridge_key(key, 0)
        }
    }
}

struct DoomTouchButton: View {
    let label: String
    let symbol: String
    let tint: Color
    let enabled: Bool
    let action: (Bool) -> Void
    @State private var pressing = false
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(pressing ? .black : tint)
        .frame(maxWidth: .infinity, minHeight: 63)
        .background(pressing ? tint : LabStyle.background,
                    in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(tint.opacity(0.5)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressing && enabled { pressing = true; action(true) } }
            .onEnded { _ in if pressing { pressing = false; action(false) } })
        .opacity(enabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }
}
