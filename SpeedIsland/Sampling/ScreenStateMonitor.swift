import Darwin
import Foundation

/// Wygaszenie ekranu z NIEOFICJALNEGO powiadomienia Darwin `com.apple.springboard.hasBlankedScreen`.
///
/// API (`notify_register_dispatch`, `notify_get_state`) jest publiczne, ale nazwa sygnału
/// nie jest udokumentowana: Apple może ją zmienić albo zablokować w dowolnej wersji iOS.
/// Dlatego to tylko dodatkowa warstwa: jeśli sygnał nie przychodzi, `onChange` nigdy nie jest
/// wołane i aplikacja działa na oficjalnych sygnałach (blokada urządzenia).
/// Stan czytamy przy każdym zdarzeniu, a przy szybkim wygaś/zapal może być już nieaktualny,
/// więc każde zapalenie ekranu i tak wymusza świeży pomiar.
@MainActor
final class ScreenStateMonitor {
    private static let name = "com.apple.springboard.hasBlankedScreen"

    /// `true` = ekran zgaszony.
    var onChange: ((Bool) -> Void)?
    private(set) var isRunning = false
    private var token: Int32 = NOTIFY_TOKEN_INVALID

    func start() {
        guard !isRunning else { return }
        let status = notify_register_dispatch(Self.name, &token, .main) { [weak self] token in
            var state: UInt64 = 0
            guard notify_get_state(token, &state) == UInt32(NOTIFY_STATUS_OK) else { return }
            MainActor.assumeIsolated {
                self?.onChange?(state != 0)
            }
        }
        isRunning = status == UInt32(NOTIFY_STATUS_OK)
    }

    func stop() {
        guard isRunning else { return }
        notify_cancel(token)
        token = NOTIFY_TOKEN_INVALID
        isRunning = false
    }
}
