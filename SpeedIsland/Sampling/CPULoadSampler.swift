import Darwin

/// Obciążenie CPU całego urządzenia z liczników ticków jądra (host_processor_info).
struct CPULoadSampler {
    private let host = mach_host_self()
    private var previous: [UInt32] = []

    /// Średnie obciążenie wszystkich rdzeni od poprzedniego wywołania (0...1).
    /// Pierwsze wywołanie zwraca nil, bo ustawia dopiero punkt odniesienia.
    mutating func sample() -> Double? {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &cpuCount, &infoArray, &infoCount) == KERN_SUCCESS,
              let info = infoArray
        else { return nil }
        defer {
            _ = vm_deallocate(
                mach_task_self_,
                vm_address_t(UInt(bitPattern: info)),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }

        let count = Int(infoCount)
        let states = Int(CPU_STATE_MAX)
        let idle = Int(CPU_STATE_IDLE)
        guard count == Int(cpuCount) * states else { return nil }

        let hasBaseline = previous.count == count
        if !hasBaseline {
            previous = [UInt32](repeating: 0, count: count)
        }

        var busy: UInt64 = 0
        var total: UInt64 = 0
        for i in 0..<count {
            let now = UInt32(bitPattern: info[i])
            let d = UInt64(now &- previous[i])
            previous[i] = now
            total &+= d
            if i % states != idle { busy &+= d }
        }

        guard hasBaseline, total > 0 else { return nil }
        return Double(busy) / Double(total)
    }

    mutating func reset() {
        previous.removeAll(keepingCapacity: true)
    }
}
