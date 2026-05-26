struct VimKeyState {
    var pendingKey: String?
    var numericPrefix = ""
    var heldKey: String?

    mutating func clearPendingInput() {
        numericPrefix = ""
        pendingKey = nil
    }

    mutating func clearHeldKey() {
        heldKey = nil
    }

    mutating func clearAll() {
        clearPendingInput()
        clearHeldKey()
    }

    mutating func handleNumericPrefixKey(_ key: String) -> Bool {
        switch key {
        case "1"..."9":
            numericPrefix.append(key)
            pendingKey = nil
            return true
        case "0" where !numericPrefix.isEmpty:
            numericPrefix.append(key)
            pendingKey = nil
            return true
        default:
            return false
        }
    }

    mutating func consumeNumericPrefix() -> Int? {
        defer { numericPrefix = "" }
        return Int(numericPrefix)
    }
}
