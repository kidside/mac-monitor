import Foundation

struct SupportDetails: Decodable {
    let koFiURL: String
    let bankName, bankBIN, accountName, accountNumber, qrPayload: String

    var validatedKoFiURL: URL? {
        guard let parts = URLComponents(string: koFiURL), parts.scheme == "https", parts.host?.lowercased() == "ko-fi.com",
              parts.user == nil, parts.password == nil, parts.port == nil, !parts.path.isEmpty else { return nil }
        return parts.url
    }
    var valid: Bool {
        guard validatedKoFiURL != nil, !bankName.isEmpty, !accountName.isEmpty,
              (6...34).contains(accountNumber.utf8.count), accountNumber.utf8.allSatisfy({ (48...57).contains($0) }),
              let bytes = qrPayload.data(using: .utf8), bytes.count <= 1024,
              qrPayload.dropLast(4).hasSuffix("6304"),
              String(format: "%04X", Self.crc16(Array(bytes.dropLast(4)))) == qrPayload.suffix(4).uppercased(),
              let root = Self.fields(qrPayload), root["54"] == nil,
              let merchant = root["38"].flatMap(Self.fields),
              let recipient = merchant["01"].flatMap(Self.fields), recipient["00"] == bankBIN else { return false }
        // The provided MB QR uses a bank-issued virtual recipient alias. Keep
        // its exact payload; do not replace it with the visible account number.
        return !(recipient["01"] ?? "").isEmpty
    }
    static func fields(_ value: String) -> [String: String]? {
        let bytes = Array(value.utf8)
        var offset = 0, fields: [String: String] = [:]
        while offset < bytes.count {
            guard offset + 4 <= bytes.count,
                  let id = String(bytes: bytes[offset..<offset+2], encoding: .ascii),
                  let lengthText = String(bytes: bytes[offset+2..<offset+4], encoding: .ascii),
                  let length = Int(lengthText), length >= 0, offset + 4 + length <= bytes.count,
                  fields[id] == nil,
                  let content = String(bytes: bytes[offset+4..<offset+4+length], encoding: .utf8) else { return nil }
            fields[id] = content; offset += 4 + length
        }
        return fields
    }
    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xffff
        for byte in bytes {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }
    static let bundled: SupportDetails? = {
        guard let url = Bundle.main.url(forResource: "Support", withExtension: "json"),
              let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return nil }
        return value
    }()
}
