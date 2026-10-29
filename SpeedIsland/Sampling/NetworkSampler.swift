import Darwin

/// Liczy bajty przesłane przez fizyczne interfejsy (getifaddrs, AF_LINK).
/// Bez uprawnień, bez ruchu sieciowego, bez alokacji przy krótkich nazwach interfejsów.
struct NetworkSampler {
    private struct Entry {
        var rx: UInt32
        var tx: UInt32
        var generation: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var generation: UInt64 = 0

    /// Bajty pobrane i wysłane od poprzedniego wywołania.
    /// Interfejs widziany pierwszy raz tylko ustawia punkt odniesienia (bez skoku na starcie).
    mutating func sample() -> (rx: UInt64, tx: UInt64) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return (0, 0) }
        defer { freeifaddrs(head) }

        generation &+= 1
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var seen = 0
        var cursor = head
        while let ifa = cursor {
            cursor = ifa.pointee.ifa_next
            guard let addr = ifa.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_LINK),
                  let raw = ifa.pointee.ifa_data,
                  let cName = ifa.pointee.ifa_name,
                  Self.isCounted(cName)
            else { continue }

            let data = raw.assumingMemoryBound(to: if_data.self).pointee
            let name = String(cString: cName)
            if let old = entries[name] {
                rx &+= Self.delta(data.ifi_ibytes, old.rx)
                tx &+= Self.delta(data.ifi_obytes, old.tx)
            }
            entries[name] = Entry(rx: data.ifi_ibytes, tx: data.ifi_obytes, generation: generation)
            seen += 1
        }

        // Interfejs zniknął (np. wyłączone dane komórkowe): zapomnij go, żeby po powrocie nie było skoku.
        if entries.count > seen {
            let current = generation
            entries = entries.filter { $0.value.generation == current }
        }
        return (rx, tx)
    }

    mutating func reset() {
        entries.removeAll(keepingCapacity: true)
    }

    /// Liczniki w `if_data` są 32-bitowe: odejmowanie modulo 2^32 obsługuje przepełnienie.
    /// Przyrost > 2 GB między próbkami oznacza reset licznika (interfejs wstał na nowo), więc liczymy 0.
    private static func delta(_ new: UInt32, _ old: UInt32) -> UInt64 {
        let d = new &- old
        return d > UInt32.max / 2 ? 0 : UInt64(d)
    }

    /// Liczymy tylko Wi-Fi/Ethernet (`en*`) i sieć komórkową (`pdp_ip*`).
    /// Pomijamy lo0, utun/ipsec (VPN, ruch policzony już na fizycznym interfejsie),
    /// awdl/llw (AirDrop) oraz bridge/ap (hotspot, ruch wychodzi przez pdp_ip).
    private static func isCounted(_ name: UnsafePointer<CChar>) -> Bool {
        strncmp(name, "en", 2) == 0 || strncmp(name, "pdp_ip", 6) == 0
    }
}
