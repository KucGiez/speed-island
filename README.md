# SpeedIsland

Licznik transferu (pobieranie/wysyłanie), obciążenia CPU i stanu termicznego na **Dynamicznej Wyspie** i ekranie blokady iPhone'a. Open source (MIT), bez reklam, bez analityki i bez sieci: aplikacja niczego nie wysyła.

## Tryby

W aplikacji albo przyciskiem na rozwiniętej Wyspie wybierasz, co ma być widoczne: **Transfer**, **Termika** albo **Oba**.

| Gdzie | Transfer | Termika | Oba |
|---|---|---|---|
| Kompakt: tylko nasza aktywność (52–62 × 37 pt na stronę) | `↓ 84 KB/s` · `↑ 12 KB/s` | `❄️` · `OK` | `↓84K` nad `↑12K` · `❄️` |
| Widok minimalny: obok aktywności innych aplikacji (owal do 45 × 37 pt) | `↓84K` nad `↑12K` | `❄️` | `↓84K` nad `↑12K`, a przy 🔥/💀 ikona |
| Zwężona Wyspa iOS 27: poziomo, iPhone 18 Pro z 2+ aktywnościami (28 × 28 pt) | `84K` w kolorze kierunku | `❄️` | prędkość, a przy 🔥/💀 ikona |
| Wyspa rozwinięta, ekran blokady | prędkości, CPU, sumy | ikona, opis, CPU | wszystko |
| Apple Watch (Smart Stack), CarPlay | ↓/↑ | ikona + CPU | ikona + ↓/↑ |
| Pasek menu Maca | jak na Wyspie (automatycznie) | | |

Termika: ❄️ OK, 🌴 ciepło, 🔥 gorąco, 💀 krytycznie.

## Współpraca z innymi aplikacjami i systemem

- **Kilka Live Activities naraz:** miejsce przydziela iOS, a aplikacja nie wie, ile aktywności działa. Widzi tylko, który widok ma narysować (kompakt albo minimalny), i flagę iOS 27 `isDynamicIslandLimitedInWidth`. Dlatego układ zwęża się automatycznie: im mniej miejsca, tym bardziej zwarty widok. W każdej pozycji SpeedIsland pokazuje żywe dane, a nie logo. Wymiary pochodzą z HIG (Live Activities → Specifications).
- **VoiceOver:** kompakt i widok minimalny mają opis słowny (prędkości i termika).
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

Zgodnie z dokumentacją Apple („Reducing your app's battery use”, „Responding to power notifications”, „Accessing the device's location efficiently”): wybudzaj się tylko wtedy, gdy wynik ktoś zobaczy, aktualizuj Wyspę tylko przy nowej treści i reaguj na zdarzenia zamiast odpytywać.

**Rytm próbkowania w tle** (gdy aplikacja jest na ekranie, zawsze 1 s):

| Sytuacja | Odstęp |
|---|---|
| Transfer / Oba, odblokowany, ruch w sieci | 1 s |
| Transfer / Oba, odblokowany, 5 próbek bez ruchu (< 1 KB/s) | 3 s (ruch przywraca 1 s) |
| Transfer / Oba, telefon zablokowany (ekran zwykle wyłączony) | 10 s; odblokowanie od razu odświeża |
| Tylko Termika | 30 s (zablokowany: 60 s); zmiana termiki przychodzi zdarzeniem natychmiast |
| Tryb oszczędzania energii | ×2 |
| Stan termiczny 🔥/💀 (zalecenie Apple: mniej odświeżania ekranu) | ×2 |

**Aktualizacje Wyspy:**
- Aktualizacja idzie tylko wtedy, gdy zmieni się to, co widać w danym trybie. CPU i sumy nie wchodzą do klucza zmian: odświeżają się z heartbeatem co 30 s (60 s przy blokadzie).
- Wartości są zaokrąglane jak na Wyspie: poniżej 1 KB/s pokazuje się „0”, do 100 KB/s co 1 KB, potem co 10 KB. Przy stałym ruchu jest więc mniej zmian, a szum (push, keep-alive) nie rusza licznika.
- Wątek główny budzi się tylko wtedy, gdy jest coś do pokazania.
- CPU jest mierzone tylko na ekranie i przy heartbeacie: w tle wynik to średnia z całego okna.
- Gdy aktualizacje ustaną (np. system zamknął aplikację), po 2,5 × heartbeat widok pokazuje „Wstrzymane”.

**Pozostałe:**
- Lokalizacja: dokładność 3 km (bez GPS), maksymalny filtr odległości, wyłączana razem z Wyspą. Alternatywa `CLLocationUpdate` wstrzymuje się w bezruchu, a wtedy system uśpiłby aplikację i licznik.
- Pomiar sieci: `getifaddrs` (liczniki jądra) bez uprawnień i bez ruchu. Liczone są tylko interfejsy fizyczne (`en*`, `pdp_ip*`); VPN, AirDrop i hotspot są pomijane. Obsłużone są przepełnienie i reset liczników 32-bitowych.
- Timer na kolejce `utility` z tolerancją 10% na ekranie i 25% w tle, dzięki czemu system łączy wybudzenia.
- Bez włączonej Wyspy w tle nie działa nic.

**Pomiar u siebie:** Xcode → Debug navigator → Energy Impact (aplikacja uruchomiona na iPhonie), Instruments → Power Profiler, Ustawienia → Bateria.

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
