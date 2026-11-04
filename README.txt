TEST IPA NA IPHONE — ZBUDOWANY I ZWERYFIKOWANY
Data: 2026-11-04
Repozytorium prywatne: synixad-png/iphone-ipa-test
Udana kompilacja: https://github.com/synixad-png/iphone-ipa-test/actions/runs/41800996964
Pliki: https://github.com/synixad-png/iphone-ipa-test/releases/tag/ipa-build-41800996964-1

Xcode 16.4, macOS 15.8.2, SDK iOS 18.5.
HelloIPhone_unsigned.ipa: 25454 bajty, Mach-O ARM64, fizyczny iPhone, minimum iOS 16.
SHA-256: 13cce757b4069b1a3d3299d3b9b8051acee528fe266ea256a4ef617d47d5018f
Potwierdzono Payload/HelloIPhone.app, Info.plist, plik wykonywalny 0755,
platforme iOS device i brak podpisu. Kontrola CRC ZIP: OK.
Nie przeprowadzono instalacji ani testu uruchomienia na fizycznym telefonie.

GitHub Actions zbudowal i zweryfikowal IPA. Wysylka zwyklego artefaktu Actions
jest zablokowana limitem miejsca na koncie. Gotowe pliki zapisano zamiast tego
jako zalaczniki do wydania w tym samym prywatnym repozytorium.
ZIP wydania zawiera IPA, verification.json i SHA256SUMS.txt.
Nie zmieniono innych repozytoriow.

INSTALACJA WINDOWS 11 / DARMOWE APPLE ID
1. Pobierz Sideloadly z https://sideloadly.io/ oraz wskazane na tej stronie
   wersje iTunes i iCloud dla Windows pobierane ze strony Apple.
2. Podlacz odblokowany iPhone przewodem USB i zatwierdz zaufanie do komputera.
3. W Sideloadly wybierz iPhone i przeciagnij HelloIPhone_unsigned.ipa do programu.
4. Wybierz instalacje przez Apple ID, podaj swoje Apple ID, kliknij Start
   i wykonaj wymagane potwierdzenia logowania Apple w Sideloadly.
5. Zaufaj profilowi w Ustawienia > Ogolne > VPN i zarzadzanie urzadzeniem.
   Wlacz Tryb dewelopera w Ustawienia > Prywatnosc i ochrona i wykonaj restart,
   jesli iPhone tego wymaga.
6. Uruchom Moj pierwszy IPA. Kliknij licznik, zamknij aplikacje i otworz ja
   ponownie, aby sprawdzic zapis wyniku.
Darmowy podpis jest wazny 7 dni; odnawiaj go przez Sideloadly, uzywajac tego
samego Apple ID i identyfikatora aplikacji.
Zrodla instrukcji: https://sideloadly.io/ i https://sideloadly.io/faq.html

Projekt: SwiftUI, bez zewnetrznych zaleznosci. Poprawiono animacje licznika dla
iOS 16, dodano wspoldzielony schemat Xcode oraz automatyczna walidacje IPA.
