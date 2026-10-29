# SpeedIsland

Licznik transferu (pobieranie/wysyłanie), obciążenia CPU i stanu termicznego na **Dynamicznej Wyspie** i ekranie blokady iPhone'a. Open source (MIT), bez reklam, bez analityki i bez sieci: aplikacja niczego nie wysyła.

## Tryby

W aplikacji albo przyciskiem na rozwiniętej Wyspie wybierasz, co ma być widoczne: **Transfer**, **Termika** albo **Oba**.

| Gdzie | Transfer | Termika | Oba |
|---|---|---|---|
| Wyspa, pełna szerokość | `↓ 84 KB/s` · `↑ 12 KB/s` | `❄️` · `OK` | `↓ 84K` · `↑ 12K ❄️` |
| Jedno pole: widok minimalny obok innej aplikacji, zwężona Wyspa (iOS 27) | `84K` w kolorze kierunku | `❄️` | prędkość, a przy 🔥/💀 ikona |
| Wyspa rozwinięta, ekran blokady | prędkości, CPU, sumy | ikona, opis, CPU | wszystko |
| Apple Watch (Smart Stack), CarPlay | ↓/↑ | ikona + CPU | ikona + ↓/↑ |
| Pasek menu Maca | jak na Wyspie (automatycznie) | | |

Termika: ❄️ OK, 🌴 ciepło, 🔥 gorąco, 💀 krytycznie.

## Współpraca z innymi aplikacjami i systemem

- **Kilka Live Activities naraz:** o tym, gdzie trafi każda aktywność, decyduje iOS. SpeedIsland w każdej pozycji pokazuje żywe dane, a nie logo. Na iOS 27 (tryb poziomy, iPhone 18 Pro z dwiema aktywnościami) widok mieści się w kółku 28 pt, a prawe pole znika zgodnie z wytycznymi Apple.
- **Alarm przegrzania** (można wyłączyć): przy wejściu na 🔥 albo 💀 Wyspa sama się rozwija i ekran się podświetla. Działa to także wtedy, gdy główne miejsce na Wyspie zajmuje inna aplikacja. Alarm pojawia się raz na epizod i nie częściej niż co 10 minut.
- **Przycisk na Wyspie:** zmienia widok bez otwierania aplikacji. To jedyny element interaktywny, zgodnie z wytycznymi HIG.
- **Centrum sterowania:** kontrolka „Licznik na Wyspie” uruchamia licznik.
- **Siri, Spotlight, przycisk czynności:** skróty „Uruchom licznik”, „Zatrzymaj licznik” i „Zmień widok”.
- **Nieaktualne dane:** po 30 s bez aktualizacji widok pokazuje **„Wstrzymane – otwórz aplikację”** zamiast starych liczb.

## Ograniczenia iOS (nie do obejścia)

- **Temperatura w °C jest niedostępna** dla aplikacji. Pokazujemy `ProcessInfo.thermalState` jako ikonę: ❄️ OK, 🌴 ciepło, 🔥 gorąco, 💀 krytycznie.
- **Live Activity żyje maksymalnie 8 h.** Potem iOS ją kończy, a po otwarciu aplikacji licznik startuje sam.
- **Praca w tle wymaga zgody na lokalizację „Podczas używania”.** Bez niej iOS usypia aplikację kilka sekund po wyjściu i Wyspa zamarza. Używany jest najtańszy tryb (dokładność 3 km, bez GPS), a współrzędne są ignorowane. iOS pokazuje wtedy niebieski wskaźnik lokalizacji.
- Wymaga iPhone'a z Dynamiczną Wyspą (14 Pro i nowsze). Na starszych licznik jest tylko na ekranie blokady. Minimalny system: iOS 18. Do zbudowania potrzebny jest Xcode 27 (SDK iOS 27).

## Wydajność i energia

- Próbkowanie raz na sekundę (co 2 s w trybie oszczędzania energii) na osobnej kolejce `utility` z 10% tolerancją timera, dzięki czemu system łączy wybudzenia. W tle, gdy Wyspa pokazuje tylko termikę, próbka jest co 5 s, a zmiana stanu termicznego trafia na Wyspę natychmiast (powiadomienie systemowe).
- Pomiar sieci: `getifaddrs` (liczniki jądra) bez uprawnień i bez ruchu. Liczone są tylko interfejsy fizyczne (`en*`, `pdp_ip*`), a VPN, AirDrop i hotspot są pomijane, żeby nic nie liczyło się podwójnie. Obsłużone są przepełnienie liczników 32-bitowych i ich reset.
- Wyspa dostaje aktualizację **tylko wtedy, gdy zmieni się wyświetlany tekst**, plus sygnał podtrzymania co 15 s. Przy bezczynnej sieci to 4 aktualizacje na minutę zamiast 60.
- Gdy aplikacja jest w tle, interfejs nie jest przerysowywany. Bez włączonej Wyspy w tle nie działa nic.

## Instalacja na Macu (zalecana)

1. `brew install xcodegen`
2. W katalogu repo: `xcodegen generate && open SpeedIsland.xcodeproj`
3. Xcode → target **SpeedIsland** i **SpeedIslandWidget** → *Signing & Capabilities* → *Team*: Twoje Apple ID (*Personal Team*).
   Jeśli Xcode zgłosi zajęty identyfikator, zmień `io.github.kucgiez` w `project.yml` na coś własnego i wygeneruj projekt ponownie.
4. Na iPhonie: *Ustawienia → Prywatność i ochrona → Tryb dewelopera* → włącz (wymaga restartu).
5. Podłącz iPhone'a, wybierz go w Xcode i naciśnij **⌘R**.
6. Przy pierwszym uruchomieniu: *Ustawienia → Ogólne → VPN i urządzenia* → zaufaj swojemu profilowi deweloperskiemu.

Darmowe Apple ID podpisuje aplikację na **7 dni**. Potem podłącz telefon i ponownie naciśnij ⌘R (dane zostają).

## Instalacja bez Maca (Windows + Sideloadly)

Workflow `.github/workflows/build.yml` buduje na GitHub Actions niepodpisany `SpeedIsland-unsigned.ipa` (zakładka *Actions → artefakty*). Plik podpisujesz i instalujesz programem [Sideloadly](https://sideloadly.io) za pomocą swojego Apple ID. Tu też obowiązuje 7 dni, a potem *Reinstall*.

## Użycie

1. Otwórz SpeedIsland i stuknij **Pokaż na Wyspie**.
2. Zgódź się na Live Activities i lokalizację „Podczas używania”.
3. Licznik zostaje na Wyspie do czasu, aż go wyłączysz w aplikacji albo przesuniesz aktywność na ekranie blokady.

## Struktura

```
Shared/                  wspólne dla aplikacji i widgetu (stan, formatowanie)
SpeedIsland/Sampling/    pomiar sieci i CPU, silnik próbkowania
SpeedIsland/Island/      Live Activity, praca w tle
SpeedIsland/             model (SpeedMonitor) i interfejs
SpeedIslandWidget/       wygląd Wyspy i ekranu blokady
project.yml              definicja projektu XcodeGen (.xcodeproj nie jest w repo)
```
