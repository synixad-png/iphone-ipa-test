# SHADER LAB 3D v1

Natywna aplikacja SwiftUI + SceneKit, iPhone / iOS 16+, bez zewnętrznych bibliotek i sieci.

7 brył: kula, sześcian, torus, stożek, walec, ostrosłup, kapsuła.
5 natywnych modeli SceneKit: physicallyBased (PBR), phong, blinn, lambert, constant.
Wymuszony Metal zapobiega zastąpieniu PBR przez Blinn. Tryb unlit ma wyłączony składnik ambient.
PBR: metaliczność i chropowatość oraz proceduralna mapa otoczenia do odbić.
Zmiana kolorów, automatyczny obrót, obrót kamery palcem, pinch zoom.
Suwaki metaliczności i chropowatości są aktywne tylko dla PBR.

## Build i testy

GitHub Actions: macOS, standardowy runner, kompilacja Release dla fizycznego iPhone ARM64 bez podpisu.
XCTest na symulatorze: 35 kombinacji brył i modeli, różnice obrazów między modelami,
zmiany metaliczności/chropowatości/koloru, reakcja Lambert na światło, brak reakcji unlit,
konfiguracja kamery i zachowanie obrotu przy zmianach materiału.
Brak Metal w środowisku testowym oznacza jawne pominięcie testów renderowania.
Nie testowano instalacji ani gestów na fizycznym iPhonie.

Wyniki: SHADER_LAB_3D_v1_unsigned.ipa, SHADER_LAB_3D_v1_ZRODLA.zip, SHADER_LAB_3D_v1_TESTY.zip.
Pliki trafiają do Actions oraz do wydania w tym samym prywatnym repozytorium.
Zapis do wydania działa także przy wyczerpanym limicie magazynu artefaktów Actions.

## Instalacja — Windows 11

1. Pobierz Sideloadly: https://sideloadly.io/ oraz wskazane tam wersje iTunes/iCloud ze strony Apple.
2. Podłącz odblokowany iPhone przez USB i zatwierdź zaufanie do komputera.
3. W Sideloadly wybierz iPhone, przeciągnij IPA i wybierz podpisywanie Apple ID.
4. Podaj Apple ID w Sideloadly, kliknij Start i wykonaj potwierdzenia Apple.
5. Na telefonie zaufaj profilowi: Ustawienia > Ogólne > VPN i zarządzanie urządzeniem.
6. Włącz Tryb dewelopera: Ustawienia > Prywatność i ochrona; wykonaj wymagany restart.
Darmowy podpis jest ważny 7 dni; odnawiaj go przez Sideloadly tym samym Apple ID.

Dokumentacja modeli: https://developer.apple.com/documentation/SceneKit/SCNMaterial/LightingModel-swift.struct
PBR/Metal: https://developer.apple.com/documentation/scenekit/scnmaterial/lightingmodel-swift.struct/physicallybased
Unlit: https://developer.apple.com/documentation/scenekit/scnmaterial/lightingmodel-swift.struct/constant
Instalacja: https://sideloadly.io/faq.html
