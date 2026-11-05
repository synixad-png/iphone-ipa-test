import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreGraphics
import AVFoundation

// Uses the original Doom renderer and gameplay through the native doomgeneric C bridge.
// The IWAD is supplied by the user (the shareware game data is not redistributed).
struct DoomSharewareView: View {
    @State private var importPresented = false
    @State private var loading = false
    @State private var downloading = false
    @State private var statusText = "Wybierz legalną wersję DOOM1.WAD (shareware), aby uruchomić grę."
    @State private var screenshot: UIImage?
    @State private var hasWad = false
    @State private var running = false
    @State private var started = false
    @State private var fullScreen = false
    @State private var moveAxis = CGVector.zero
    @State private var aimAxis = CGVector.zero
    @State private var analogPressed = Set<Int32>()
    @AppStorage("doom.touch.mode") private var touchMode = "analog"
    @AppStorage("doom.touch.lookSensitivity") private var lookSensitivity: Double = 1.4
    @AppStorage("doom.touch.fireHorizontal") private var fireHorizontal: Double = 0.78
    @AppStorage("doom.touch.fireVertical") private var fireVertical: Double = 0.68
    @AppStorage("doom.sfx.enabled") private var effectsEnabled = true
    @AppStorage("doom.sfx.volume") private var effectsVolume: Double = 0.85

    private let width = 320
    private let height = 200
    private let poll = Timer.publish(every: 1.0 / 30.0, on: .main, in: .common).autoconnect()
    private let downloadURL = URL(string: "https://www.doomarchive.com/ListFiles.php?ContentsFolderId=216&FolderId=216")!
    private let zipURL = URL(string: "https://www.jbserver.com/downloads/games/doom/misc/shareware/doom1.wad.zip")!

    private var wadURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DOOM1.WAD")
    }

    // Stationary page: the game frame never slides. Settings have their own scroll region.
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > 760
            ZStack {
                LabStyle.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "gamecontroller.fill")
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.red)
                            .frame(width: 41, height: 41)
                            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DOOM · SHAREWARE")
                                .font(.system(size: wide ? 24 : 18, weight: .bold, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text("DOOM 1993 · Episode 1")
                                .font(.caption)
                                .foregroundStyle(LabStyle.muted)
                        }
                        Spacer(minLength: 4)
                        Button {
                            fullScreen = true
                        } label: {
                            Label("PEŁNY EKRAN", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .padding(.horizontal, 10)
                                .frame(height: 36)
                        }
                        .foregroundStyle(.black)
                        .background(LabStyle.accent, in: RoundedRectangle(cornerRadius: 8))
                        .disabled(!running)
                        .opacity(running ? 1 : 0.5)
                    }
                    .frame(height: 44)

                    if wide {
                        HStack(alignment: .top, spacing: 14) {
                            gamePanel
                                .frame(maxWidth: .infinity, alignment: .top)
                            ScrollView(.vertical) {
                                controlsPanel
                                    .padding(.bottom, 12)
                            }
                            .scrollIndicators(.hidden)
                            .frame(width: min(340, geometry.size.width * 0.37),
                                   height: max(1, geometry.size.height - 75))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else {
                        gamePanel
                            .frame(maxWidth: .infinity, alignment: .top)
                        ScrollView(.vertical) {
                            controlsPanel
                                .padding(.bottom, 18)
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
                .padding(.horizontal, wide ? 20 : 10)
                .padding(.top, 10)
                .padding(.bottom, 5)
                .frame(maxWidth: 1250, maxHeight: .infinity, alignment: .top)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .fullScreenCover(isPresented: $fullScreen) {
            DoomLandscapeView(frame: screenshot,
                              move: { axis in updateAxis(axis, movement: true) },
                              aim: { axis in updateAxis(axis, movement: false) },
                              interact: { pressed in doom_bridge_key(0xa2, pressed ? 1 : 0) },
                              fire: { pressed in doom_bridge_key(0xa3, pressed ? 1 : 0) },
                              menu: { pressed in doom_bridge_key(27, pressed ? 1 : 0) },
                              close: { fullScreen = false },
                              touchMode: $touchMode,
                              lookSensitivity: $lookSensitivity,
                              fireHorizontal: $fireHorizontal,
                              fireVertical: $fireVertical)
                .onAppear { doom_bridge_pause(0) }
        }
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
            configureSound()
            doom_audio_set_volume(effectsEnabled ? Float(effectsVolume) : 0)
            hasWad = FileManager.default.fileExists(atPath: wadURL.path)
            doom_bridge_pause(0)
            if hasWad && !started { start() }
        }
        .onChange(of: effectsVolume) { _ in
            doom_audio_set_volume(effectsEnabled ? Float(effectsVolume) : 0)
        }
        .onChange(of: effectsEnabled) { _ in
            doom_audio_set_volume(effectsEnabled ? Float(effectsVolume) : 0)
        }
        .onChange(of: touchMode) { _ in releaseAllKeys() }
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
            statusText = doom_audio_is_active() == 1
                ? "DOOM SHAREWARE · obraz i oryginalne efekty dźwiękowe aktywne"
                : "DOOM SHAREWARE · obraz aktywny; urządzenie audio niedostępne"
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
            .overlay(alignment: .bottom) {
                if touchMode == "analog" {
                HStack(alignment: .bottom) {
                    GameJoystick(title: "RUCH", tint: .cyan, diameter: 96) {
                        updateAxis($0, movement: true)
                    }
                    Spacer(minLength: 12)
                    DoomPressControl(title: "OGIEŃ", symbol: "scope") { pressed in
                        doom_bridge_key(0xa3, pressed ? 1 : 0)
                    }
                    .padding(.bottom, 7)
                    GameJoystick(title: "OBRÓT", tint: .red, diameter: 96) {
                        updateAxis($0, movement: false)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
                } else {
                    HStack {
                        Text("GESTY: LEWA — RUCH · PRAWA — OBRÓT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                        Spacer()
                        DoomPressControl(title: "OGIEŃ", symbol: "scope") { pressed in
                            doom_bridge_key(0xa3, pressed ? 1 : 0)
                        }
                    }
                    .padding(8)
                }
            }
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
            Picker("Tryb sterowania", selection: $touchMode) {
                Text("Widoczne analogi").tag("analog")
                Text("Gesty bez analogów").tag("gestures")
            }
            .pickerStyle(.segmented)
            Text(touchMode == "gestures"
                 ? "W pełnym ekranie: przesuń palcem po lewej stronie, aby chodzić i robić kroki w bok. Po prawej stronie przesuwaj palcem, aby się rozglądać. Przycisk OGIEŃ można przesuwać w ustawieniach."
                 : "Lewy analog: poruszanie i kroki w bok. Prawy: obrót. Przycisk OGIEŃ jest bezpośrednio na obrazie gry.")
                .font(.caption).foregroundStyle(LabStyle.muted)
            if touchMode == "gestures" {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CZUŁOŚĆ ROZGLĄDANIA: \(lookSensitivity, specifier: "%.1f")×")
                        .font(.caption.bold())
                    Slider(value: $lookSensitivity, in: 0.5...3.0, step: 0.1)
                    Text("PRZYCISK OGIEŃ · POZIOM")
                        .font(.caption.bold())
                    Slider(value: $fireHorizontal, in: 0...1)
                    Text("PRZYCISK OGIEŃ · WYSOKOŚĆ")
                        .font(.caption.bold())
                    Slider(value: $fireVertical, in: 0...1)
                }
            }
            HStack(spacing: 8) {
                hold("UŻYJ", "hand.tap", key: 0xa2, color: .orange)
                hold("MENU", "line.3.horizontal", key: 27)
                hold("ENTER", "return", key: 13)
                hold("MAPA", "map", key: 9)
            }
            Divider().overlay(LabStyle.border)
            LabSectionTitle(title: "DŹWIĘK DOOM", symbol: "speaker.wave.3.fill")
            Toggle("Efekty dźwiękowe", isOn: $effectsEnabled)
                .font(.subheadline)
                .tint(LabStyle.accent)
            HStack {
                Text("Głośność")
                Spacer()
                Text("\(Int(effectsVolume * 100))%")
                    .monospacedDigit()
                    .foregroundStyle(LabStyle.accent)
            }
            .font(.subheadline)
            Slider(value: $effectsVolume, in: 0...1, step: 0.05)
                .disabled(!effectsEnabled)
            Text("Autentyczne strzały, potwory, drzwi i eksplozje z pliku WAD. Muzyka jeszcze nie jest obsługiwana.")
                .font(.caption)
                .foregroundStyle(LabStyle.muted)
            Divider().overlay(LabStyle.border)
            Button {
                downloadOriginalShareware()
            } label: {
                Label(downloading ? "Pobieranie shareware..." : "POBIERZ DOOM SHAREWARE",
                      systemImage: "arrow.down.to.line")
                    .font(.subheadline.bold())
            }
            .buttonStyle(LabPrimaryButtonStyle())
            .disabled(downloading || started)
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

    private func downloadOriginalShareware() {
        guard !started && !downloading else { return }
        downloading = true
        statusText = "Pobieranie archiwum DOOM shareware 1.9..."
        URLSession.shared.downloadTask(with: zipURL) { downloaded, response, error in
            guard error == nil, let downloaded,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                DispatchQueue.main.async {
                    downloading = false
                    statusText = "Serwer shareware jest niedostępny. Możesz pobrać archiwum ręcznie i wskazać DOOM1.WAD."
                }
                return
            }
            let result = downloaded.path.withCString { source in
                wadURL.path.withCString { destination in
                    doom_bridge_extract_shareware_zip(source, destination)
                }
            }
            DispatchQueue.main.async {
                downloading = false
                if result == 0 {
                    hasWad = true
                    statusText = "Pobrano i zweryfikowano oryginalne dane shareware."
                    start()
                } else {
                    statusText = "Nie udało się rozpakować shareware (kod \(result)). Wczytaj DOOM1.WAD ręcznie."
                }
            }
        }.resume()
    }

    private func configureSound() {
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try audio.setActive(true)
        } catch {
            // The engine can still render even when a device denies audio playback.
            statusText = "Nie można aktywować wyjścia audio: \(error.localizedDescription)"
        }
    }

    private func start() {
        configureSound()
        doom_audio_set_volume(effectsEnabled ? Float(effectsVolume) : 0)
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

    private func updateAxis(_ value: CGVector, movement: Bool) {
        if movement { moveAxis = value } else { aimAxis = value }
        var wanted = Set<Int32>()
        if moveAxis.dy > 0.23 { wanted.insert(0xad) }
        if moveAxis.dy < -0.23 { wanted.insert(0xaf) }
        if moveAxis.dx < -0.23 { wanted.insert(0xa0) }
        if moveAxis.dx > 0.23 { wanted.insert(0xa1) }
        if aimAxis.dx < -0.23 { wanted.insert(0xac) }
        if aimAxis.dx > 0.23 { wanted.insert(0xae) }
        for key in analogPressed.subtracting(wanted) { doom_bridge_key(key, 0) }
        for key in wanted.subtracting(analogPressed) { doom_bridge_key(key, 1) }
        analogPressed = wanted
    }

    private func releaseAllKeys() {
        moveAxis = .zero
        aimAxis = .zero
        analogPressed.removeAll()
        for key in [Int32](arrayLiteral: 0xa0, 0xa1, 0xac, 0xad, 0xae, 0xaf, 0xa3, 0xa2, 27, 13, 9) {
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
