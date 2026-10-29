import os

/// Logi diagnostyczne (os.Logger), domyślnie wyłączone; włącza się je w aplikacji.
/// Podgląd na Macu: Console.app → iPhone → filtr `subsystem:speedisland`.
/// Zawierają tylko liczby i stany (rytm, aktualizacje Wyspy, sygnały systemu), bez danych osobowych.
/// Wyłączone = żadnego wywołania loggera (sprawdzenie flagi przed zbudowaniem komunikatu).
enum Diagnostics {
    static let engine = Logger(subsystem: "speedisland", category: "engine")
    static let island = Logger(subsystem: "speedisland", category: "island")
    static let system = Logger(subsystem: "speedisland", category: "system")

    /// Flaga dla kodu na wątku głównym. Silnik próbkowania ma własną kopię na swojej kolejce.
    @MainActor static var enabled = false
}
