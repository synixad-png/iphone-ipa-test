import SwiftUI

@main
struct HelloIPhoneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @AppStorage("tapCount") private var tapCount = 0
    @State private var showResetConfirmation = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.08, blue: 0.18), Color(red: 0.12, green: 0.2, blue: 0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 66, weight: .light))
                    .foregroundStyle(.cyan)
                Text("Mój pierwszy IPA")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Natywna aplikacja iPhone • SwiftUI")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                VStack(spacing: 12) {
                    Text("LICZNIK KLIKNIĘĆ")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(tapCount)")
                        .font(.system(size: 76, weight: .bold, design: .rounded))
                        .contentTransition(.opacity)
                    Button {
                        withAnimation(.spring()) { tapCount += 1 }
                    } label: {
                        Label("Naciśnij mnie", systemImage: "hand.tap.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)
                    .foregroundStyle(.black)
                    Button("Wyzeruj licznik") { showResetConfirmation = true }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(24)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 24))
                Text("Wynik zapisuje się na iPhonie i pozostaje po zamknięciu aplikacji.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
                Text("TEST IPA • wersja 1.0")
                    .font(.caption.monospaced())
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .padding(26)
        }
        .confirmationDialog("Wyzerować licznik?", isPresented: $showResetConfirmation) {
            Button("Wyzeruj", role: .destructive) { tapCount = 0 }
            Button("Anuluj", role: .cancel) { }
        }
    }
}
