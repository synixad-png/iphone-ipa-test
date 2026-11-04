TEST IPA NA IPHONE — projekt przygotowany do GitHub Actions

STATUS: Nie wykonano jeszcze kompilacji macOS. Nie ma gotowego IPA.
Przygotowanie 2026-11-04: poprawiono zgodnosc animacji z iOS 16,
dodano wspoldzielony schemat Xcode, jawne ARM64 i walidacje IPA.

Repozytorium docelowe: synixad-png/iphone-ipa-test (nowe, prywatne).
Pliki nalezy umiescic w katalogu glownym repozytorium z zachowaniem .github.
Workflow startuje po push do main lub recznie przez workflow_dispatch.
Artefakt HelloIPhone_unsigned_IPA zawiera IPA, SHA256SUMS.txt i verification.json.
Nie nalezy traktowac przygotowanych zrodel jako udanej kompilacji.

INSTALACJA PO UZYSKANIU POPRAWNEGO IPA
1. Pobierz Sideloadly z https://sideloadly.io/ oraz wskazane tam wersje iTunes/iCloud dla Windows.
2. Podlacz odblokowany iPhone przewodem i zatwierdz zaufanie do komputera.
3. W Sideloadly wybierz iPhone i plik HelloIPhone_unsigned.ipa.
4. Podaj Apple ID w Sideloadly, kliknij Start i wykonaj wymagane potwierdzenia Apple.
5. W razie potrzeby zaufaj profilowi w Ustawienia > Ogolne > VPN i zarzadzanie urzadzeniem
   oraz wlacz Tryb dewelopera w Ustawienia > Prywatnosc i ochrona.
6. Darmowy podpis jest wazny 7 dni; odnow go przez Sideloadly.
Aplikacja wymaga fizycznego iPhone z iOS 16 lub nowszym.
Weryfikacja IPA potwierdza strukture i format binarny; dzialanie na telefonie wymaga instalacji.
