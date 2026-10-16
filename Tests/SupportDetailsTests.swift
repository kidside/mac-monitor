import Foundation

@main enum SupportDetailsTests {
    static func main() throws {
        let details = try JSONDecoder().decode(SupportDetails.self, from: Data(contentsOf: URL(fileURLWithPath:"Resources/Support.json")))
        precondition(details.valid)
        precondition(details.accountNumber == "0590190828888" && details.accountName == "LE CHU AN")
        precondition(details.validatedKoFiURL?.absoluteString == "https://ko-fi.com/U8I328WDGQ")
        func changed(url: String? = nil, bin: String? = nil, payload: String? = nil) -> SupportDetails {
            SupportDetails(koFiURL:url ?? details.koFiURL,bankName:details.bankName,bankBIN:bin ?? details.bankBIN,
                           accountName:details.accountName,accountNumber:details.accountNumber,qrPayload:payload ?? details.qrPayload)
        }
        for url in ["http://ko-fi.com/U8I328WDGQ", "https://ko-fi.com.evil.example/U8I328WDGQ", "https://name:secret@ko-fi.com/U8I328WDGQ", "javascript:alert(1)"] {
            precondition(!changed(url:url).valid, "Reject untrusted payment destinations")
        }
        precondition(!changed(bin:"970436").valid)
        precondition(!changed(payload:String(details.qrPayload.dropLast())+"0").valid)
        precondition(SupportDetails.fields("0005ab") == nil)
        precondition(SupportDetails.fields("000201000201") == nil)
        let fixedAmount = String(details.qrPayload.dropLast(8))+"5403100"+"6304"
        let checksum=String(format:"%04X",SupportDetails.crc16(Array(fixedAmount.utf8)))
        precondition(!changed(payload:fixedAmount+checksum).valid,"No preset transfer amount")
        let merchant=SupportDetails.fields(SupportDetails.fields(details.qrPayload)!["38"]!)!
        let bank=SupportDetails.fields(merchant["01"]!)!
        precondition(bank["00"]=="970422" && bank["01"]=="VQRQAARDW3578", "Keep MB's original virtual payee alias")
        print("PASS: intended Ko-fi destination, account leading zero, QR checksum/bank/alias, reject substituted links and fixed amounts")
    }
}
