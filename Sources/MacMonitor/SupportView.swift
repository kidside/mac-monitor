import SwiftUI
import AppKit

struct SupportView: View {
    let language: String
    @ViewState private var bankExpanded = false
    @ViewState private var copied = false
    @ViewState private var message: String?
    private func localized(_ text: String) -> String { L(text, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("Mac Monitor miễn phí và đầy đủ tính năng. Nếu thấy hữu ích, bạn có thể ủng hộ tác giả bằng một trong hai cách dưới đây."))
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let details = SupportDetails.bundled {
                Button {
                    if let url = details.validatedKoFiURL, !NSWorkspace.shared.open(url) {
                        message = "Chưa mở được Ko-fi. Bạn có thể truy cập link trên trang GitHub."
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "cup.and.saucer.fill").font(.system(size: 23))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ko-fi").font(.system(size: 14, weight: .semibold))
                            Text(localized("Ủng hộ qua trang Ko-fi")).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }.padding(14).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(localized("Mở trang Ko-fi để ủng hộ tác giả"))
                DisclosureGroup(isExpanded: $bankExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(details.bankName).font(.system(size: 13, weight: .semibold))
                        Text(details.accountName).font(.system(size: 12))
                        Text(details.accountNumber).font(.system(size: 15, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            copied = NSPasteboard.general.setString(details.accountNumber, forType: .string)
                        } label: {
                            Label(localized(copied ? "Đã sao chép" : "Sao chép số tài khoản"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        }.controlSize(.small)
                        if let url = Bundle.main.url(forResource: "SupportBankQR", withExtension: "png"),
                           let qr = NSImage(contentsOf: url) {
                            Image(nsImage: qr).resizable().interpolation(.none).scaledToFit()
                                .frame(maxWidth: 280).padding(8).background(.white, in: RoundedRectangle(cornerRadius: 10))
                                .frame(maxWidth: .infinity)
                                .accessibilityLabel(localized("Mã QR chuyển khoản MB Bank"))
                        }
                        Text(localized("Quét mã bằng ứng dụng ngân hàng và kiểm tra tên người nhận trước khi chuyển khoản."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 12)
                } label: {
                    Label(localized("Chuyển khoản ngân hàng"), systemImage: "building.columns")
                        .font(.system(size: 13, weight: .semibold))
                }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                Text(localized("Mọi khoản ủng hộ đều tự nguyện. Cảm ơn bạn đã hỗ trợ Mac Monitor!"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(localized("Chưa tải được thông tin ủng hộ. Vui lòng xem trên trang GitHub của Mac Monitor."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let message { Text(localized(message)).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
