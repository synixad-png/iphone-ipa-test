import SwiftUI

// A standalone, offline collection of family-friendly jokes. No accounts or network access.
enum SmileHero: String, CaseIterable, Identifiable {
    case all = "Wszyscy"
    case hania = "Hania"
    case martna = "Martna"
    case ania = "Ania"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .all: return "sparkles"
        case .hania: return "bolt.heart.fill"
        case .martna: return "star.fill"
        case .ania: return "crown.fill"
        }
    }
    var tint: Color {
        switch self {
        case .all: return LabStyle.accent
        case .hania: return .pink
        case .martna: return .purple
        case .ania: return .orange
        }
    }
}

struct SmileQuote: Identifiable, Equatable {
    let id: Int
    let hero: SmileHero
    let text: String
    let signature: String

    static let catalog: [SmileQuote] = [
        .init(id:1, hero:.hania, text:"Hania powiedziała: „Posprzątam za pięć minut”. Zegar do dziś próbuje ustalić, w której strefie czasowej.", signature:"Dziennik domowych odkryć"),
        .init(id:2, hero:.hania, text:"Hania potrafi znaleźć zgubionego cukierka z odległości trzech pokoi. Skarpetki? To już tajemnica kosmosu.", signature:"Supermoc dnia"),
        .init(id:3, hero:.hania, text:"Kiedy Hania mówi „mam mały pomysł”, meble profilaktycznie zapinają pasy.", signature:"Alert domowy"),
        .init(id:4, hero:.hania, text:"Hania nie robi bałaganu. Ona tworzy instalację artystyczną pod tytułem „Nie dotykać”.", signature:"Galeria nowoczesna"),
        .init(id:5, hero:.hania, text:"Hania otworzyła lodówkę po raz czwarty. Liczyła, że w międzyczasie zaktualizowała się oferta deserów.", signature:"Technologia przyszłości"),
        .init(id:6, hero:.hania, text:"Hania powiedziała, że idzie spać. Piętnaście minut później prowadziła negocjacje z poduszką.", signature:"Wieczorne wiadomości"),
        .init(id:7, hero:.hania, text:"Hania ma plan A, plan B i tajny plan C, o którym nawet plan B nic nie wie.", signature:"Agencja pomysłów"),
        .init(id:8, hero:.hania, text:"Hania zadała tylko jedno pytanie. Po godzinie encyklopedia poprosiła o przerwę.", signature:"Nauka nie zna granic"),
        .init(id:9, hero:.hania, text:"Kiedy Hania mówi „patrz, co umiem!”, grawitacja zaczyna czytać regulamin.", signature:"Eksperymenty"),
        .init(id:10, hero:.hania, text:"Hania znalazła sposób, żeby sobota trwała dłużej: po prostu nie przyznaje, że jest już niedziela.", signature:"Kalendarz Hani"),
        .init(id:11, hero:.hania, text:"Hania twierdzi, że nie zjadła ostatniego ciastka. Okruszki twierdzą coś zupełnie innego.", signature:"Śledztwo kuchenne"),
        .init(id:12, hero:.hania, text:"Hania wymyśliła nowy sport: bieg do drzwi, kiedy słychać słowo „pizza”. Rekord świata pobity.", signature:"Sportowe emocje"),
        .init(id:13, hero:.martna, text:"Martna ma tak dobrą pamięć, że pamięta nawet rzeczy, których nikt jeszcze nie powiedział.", signature:"Kroniki przyszłości"),
        .init(id:14, hero:.martna, text:"Martna nie przewraca oczami. Ona robi szybki przegląd nieba w poszukiwaniu cierpliwości.", signature:"Prognoza nastroju"),
        .init(id:15, hero:.martna, text:"Martna powiedziała „zaraz będę gotowa”. Dom zaczął obliczać, czy chodzi o czas ziemski.", signature:"Zegary i zagadki"),
        .init(id:16, hero:.martna, text:"Martna nie potrzebuje pilota. Jedno spojrzenie i telewizor sam pyta, co włączyć.", signature:"Technologia domowa"),
        .init(id:17, hero:.martna, text:"Martna zaplanowała idealny dzień. Pogoda poprosiła o zgodę na drobną zmianę scenariusza.", signature:"Planowanie premium"),
        .init(id:18, hero:.martna, text:"Gdy Martna mówi „to proste”, nawet instrukcja obsługi robi notatki.", signature:"Akademia sprytu"),
        .init(id:19, hero:.martna, text:"Martna nie szuka telefonu. Prowadzi z nim zabawę w chowanego, której nie pamięta, że rozpoczęła.", signature:"Tajemnice pokoju"),
        .init(id:20, hero:.martna, text:"Martna umie spojrzeć na bałagan i powiedzieć: „Wszystko mam pod kontrolą”. Bałagan przytakuje.", signature:"Sztuka organizacji"),
        .init(id:21, hero:.martna, text:"Martna ma trzy tryby: genialny pomysł, jeszcze lepszy pomysł i „daj mi minutkę”.", signature:"System operacyjny"),
        .init(id:22, hero:.martna, text:"Martna robi zdjęcie jedzenia tak dokładnie, że makaron zaczyna pozować.", signature:"Studio fotograficzne"),
        .init(id:23, hero:.martna, text:"Martna nie spóźnia się na przygody. Po prostu pozwala im nabrać napięcia.", signature:"Film sensacyjny"),
        .init(id:24, hero:.martna, text:"Kiedy Martna mówi „wiem, co robię”, rzeczywistość otwiera popcorn.", signature:"Seans specjalny"),
        .init(id:25, hero:.ania, text:"Ania powiedziała „niczego nie potrzebuję”. Lista zakupów rozpłakała się ze śmiechu.", signature:"Raport zakupowy"),
        .init(id:26, hero:.ania, text:"Ania ma supermoc: znajduje rzeczy, których reszta domu szukała przez trzy dni. Zwykle leżały „tam, gdzie zawsze”.", signature:"Detektyw domowy"),
        .init(id:27, hero:.ania, text:"Gdy Ania mówi „mam tylko jedną uwagę”, zebranie przedłuża się do następnej epoki geologicznej.", signature:"Protokół zebrania"),
        .init(id:28, hero:.ania, text:"Ania potrafi spojrzeć na pustą lodówkę i przygotować obiad. Naukowcy podejrzewają portal międzywymiarowy.", signature:"Kulinarny fenomen"),
        .init(id:29, hero:.ania, text:"Ania nie gubi cierpliwości. Ona czasem wysyła ją na krótkie wakacje.", signature:"Wypoczynek psychiczny"),
        .init(id:30, hero:.ania, text:"Kiedy Ania pyta „kto zostawił ten kubek?”, kubek udaje, że nie zna domowników.", signature:"Kryminalne zagadki"),
        .init(id:31, hero:.ania, text:"Ania nie potrzebuje budzika. Ma wbudowany radar wykrywający poranne zamieszanie.", signature:"System wczesnego ostrzegania"),
        .init(id:32, hero:.ania, text:"Ania potrafi zrobić pięć rzeczy naraz. Szósta cierpliwie czeka w kolejce z numerkiem.", signature:"Centrum dowodzenia"),
        .init(id:33, hero:.ania, text:"Ania powiedziała: „Tylko szybko posprzątajmy”. Odkurzacz złożył wniosek o nadgodziny.", signature:"Akcja porządkowa"),
        .init(id:34, hero:.ania, text:"Ania ma tajny radar na niedojedzone warzywa. Działa nawet przez zamknięte drzwi.", signature:"Laboratorium obiadowe"),
        .init(id:35, hero:.ania, text:"Ania zapytała, czy wszyscy są gotowi. Cisza była tak głośna, że odpowiedziała za wszystkich.", signature:"Rodzinna wyprawa"),
        .init(id:36, hero:.ania, text:"Kiedy Ania robi herbatę, nawet czajnik stara się nie popełnić błędu.", signature:"Ceremonia herbaciana"),
        .init(id:37, hero:.all, text:"Hania ma pomysł, Martna ma plan, a Ania ma pytanie: „Czy ktoś pomyślał o posprzątaniu po tym?”.", signature:"Rodzinne centrum operacyjne"),
        .init(id:38, hero:.all, text:"Hania znalazła skarb, Martna narysowała mapę, a Ania odkryła, że skarb to ostatnia czekolada.", signature:"Wyprawa stulecia"),
        .init(id:39, hero:.all, text:"W rodzinnym konkursie na ciszę Hania odpadła po sekundzie, Martna po dwóch, a Ania wygrała samym spojrzeniem.", signature:"Olimpiada domowa"),
        .init(id:40, hero:.all, text:"Hania: „A co, jeśli…?”. Martna: „Zróbmy to!”. Ania: „A kto będzie po tym sprzątał?”.", signature:"Trzy akty przygody"),
        .init(id:41, hero:.all, text:"Hania pilnuje przekąsek, Martna muzyki, a Ania tego, żeby cała wyprawa trafiła pod właściwy adres.", signature:"Ekspedycja rodzinna"),
        .init(id:42, hero:.all, text:"Hania: energia 100%. Martna: pomysły 200%. Ania: bateria cierpliwości — ładowanie w toku.", signature:"Raport systemowy"),
        .init(id:43, hero:.all, text:"Hania i Martna ogłosiły dzień bez zasad. Ania ogłosiła, że pierwszą zasadą będzie sprzątanie.", signature:"Nowa konstytucja domu"),
        .init(id:44, hero:.all, text:"W domu powstała nowa gra: Hania coś chowa, Martna daje wskazówki, Ania znajduje to w dziesięć sekund.", signature:"Mistrzostwa w poszukiwaniach"),
        .init(id:45, hero:.all, text:"Hania wybrała film, Martna przekąski, a Ania pilot. Negocjacje w sprawie głośności trwają.", signature:"Wieczór filmowy"),
        .init(id:46, hero:.all, text:"Hania przyniosła konfetti, Martna balony, Ania worek na śmieci. Wszyscy byli przygotowani do imprezy.", signature:"Plan doskonały"),
        .init(id:47, hero:.all, text:"Hania chciała kota, Martna smoka, a Ania zapytała, kto będzie wynosił smocze śmieci.", signature:"Domowe zoo"),
        .init(id:48, hero:.all, text:"Hania odkryła nową planetę, Martna wymyśliła jej nazwę, a Ania przypomniała o kurtkach na drogę.", signature:"Podróże kosmiczne")
    ]

    static func filtered(_ hero: SmileHero) -> [SmileQuote] {
        hero == .all ? catalog : catalog.filter { $0.hero == hero || $0.hero == .all }
    }

    static func next(in quotes: [SmileQuote], excluding current: Int?) -> SmileQuote? {
        guard !quotes.isEmpty else { return nil }
        let candidates = quotes.count > 1 ? quotes.filter { $0.id != current } : quotes
        return candidates.randomElement()
    }
}

struct SmileQuotesView: View {
    @State private var selectedHero: SmileHero = .all
    @State private var quoteID: Int = 37
    @State private var favorites: Set<Int> = Set(UserDefaults.standard.array(forKey: "smiles.favorites") as? [Int] ?? [])
    @State private var onlyFavorites = false

    private var selection: [SmileQuote] {
        let all = SmileQuote.filtered(selectedHero)
        return onlyFavorites ? all.filter { favorites.contains($0.id) } : all
    }

    private var quote: SmileQuote? {
        selection.first(where: { $0.id == quoteID }) ?? selection.first
    }

    private var composedText: String {
        guard let quote else { return "" }
        return "\(quote.text)\n\n— \(quote.signature) 😄"
    }

    var body: some View {
        GeometryReader { layout in
            let wide = layout.size.width >= 760
            ZStack {
                LabStyle.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(spacing: 12) {
                            Image(systemName: "face.smiling.inverse")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(.yellow)
                                .frame(width: 52, height: 52)
                                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ŚMIESZNE TEKSTY")
                                    .font(.system(size: wide ? 28 : 21, weight: .bold, design: .rounded))
                                Text("Hania · Martna · Ania — rodzinna dawka humoru")
                                    .font(.subheadline)
                                    .foregroundStyle(LabStyle.muted)
                            }
                            Spacer(minLength: 0)
                        }
                        if wide {
                            HStack(alignment: .top, spacing: 18) {
                                quotePanel
                                    .frame(maxWidth: .infinity)
                                controlPanel
                                    .frame(width: min(320, layout.size.width * 0.34))
                            }
                        } else {
                            quotePanel
                            controlPanel
                        }
                        Text("48 autorskich, lekkich żartów. Działa bez internetu.")
                            .font(.caption)
                            .foregroundStyle(LabStyle.muted)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, wide ? 24 : 14)
                    .padding(.vertical, 18)
                    .frame(maxWidth: 1150)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .foregroundStyle(.white)
        .tint(LabStyle.accent)
        .onChange(of: selectedHero) { _ in refreshSelection() }
        .onChange(of: onlyFavorites) { _ in refreshSelection() }
    }

    private var quotePanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label("HUMOR DNIA", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(LabStyle.accent)
                Spacer()
                if let quote {
                    Label(quote.hero.rawValue, systemImage: quote.hero.icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(quote.hero.tint)
                }
            }

            if let quote {
                Text("„")
                    .font(.system(size: 76, weight: .bold, design: .serif))
                    .foregroundStyle(LabStyle.accent.opacity(0.65))
                    .frame(height: 35, alignment: .top)

                Text(quote.text)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineSpacing(8)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 145, alignment: .center)
                    .multilineTextAlignment(.center)

                Text("— \(quote.signature)")
                    .font(.caption)
                    .foregroundStyle(LabStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 10) {
                    Button {
                        randomize()
                    } label: {
                        Label("Jeszcze jeden!", systemImage: "shuffle")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(LabPrimaryButtonStyle())

                    Button {
                        toggleFavorite(quote.id)
                    } label: {
                        Image(systemName: favorites.contains(quote.id) ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundStyle(favorites.contains(quote.id) ? .pink : .white)
                            .frame(width: 46, height: 46)
                            .background(LabStyle.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(favorites.contains(quote.id) ? "Usuń z ulubionych" : "Dodaj do ulubionych")

                    ShareLink(item: composedText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3)
                            .frame(width: 46, height: 46)
                            .background(LabStyle.background, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Udostępnij żart")
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "heart.slash")
                        .font(.largeTitle)
                        .foregroundStyle(LabStyle.muted)
                    Text("Tutaj nie ma jeszcze ulubionych żartów.")
                        .font(.subheadline)
                        .foregroundStyle(LabStyle.muted)
                    Button("Pokaż wszystkie") {
                        onlyFavorites = false
                    }.buttonStyle(LabPrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(LabStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(LabStyle.border))
    }

    private var controlPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabSectionTitle(title: "KTO DZIŚ ROZŚMIESZA?", symbol: "person.3.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 9)], spacing: 9) {
                ForEach(SmileHero.allCases) { hero in
                    Button {
                        selectedHero = hero
                    } label: {
                        Label(hero.rawValue, systemImage: hero.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 45)
                    }
                    .buttonStyle(LabChipStyle(active: selectedHero == hero))
                    .accessibilityAddTraits(selectedHero == hero ? .isSelected : [])
                }
            }
            Toggle(isOn: $onlyFavorites) {
                Label("Tylko ulubione", systemImage: "heart.fill")
                    .font(.subheadline)
            }
            .tint(.pink)
            HStack {
                Text("Dostępne żarty")
                    .foregroundStyle(LabStyle.muted)
                Spacer()
                Text("\(selection.count)")
                    .foregroundStyle(LabStyle.accent)
                    .monospacedDigit()
            }
            .font(.caption)

            Button {
                randomize()
            } label: {
                Label("Losuj tekst", systemImage: "dice.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(LabPrimaryButtonStyle())
            .disabled(selection.isEmpty)
        }
        .labPanel()
    }

    private func refreshSelection() {
        if !selection.contains(where: { $0.id == quoteID }) {
            quoteID = SmileQuote.next(in: selection, excluding: nil)?.id ?? -1
        }
    }

    private func randomize() {
        if let next = SmileQuote.next(in: selection, excluding: quoteID) {
            quoteID = next.id
        }
    }

    private func toggleFavorite(_ id: Int) {
        if !favorites.insert(id).inserted { favorites.remove(id) }
        UserDefaults.standard.set(favorites.sorted(), forKey: "smiles.favorites")
        refreshSelection()
    }
}
