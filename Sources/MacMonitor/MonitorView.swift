import SwiftUI
import AppKit

// The command-line macOS 27 SDK omits the new State macro plugin.
// Name the longstanding property wrapper explicitly so builds also work without Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>

struct MonitorView: View {
    @ObservedObject var model: DisplayController
    var panelHeight: CGFloat = 680
    @ViewState private var settings = false
    private var ipadPage: Bool {
        get { model.showingIPad }
        nonmutating set { model.showingIPad = newValue }
    }
    private var connectedIPads: [SidecarDevice] { model.sidecar.devices.filter(\.connected) }
    private let accent = Color(red: 0.08, green: 0.49, blue: 0.52)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: model.showingSupport ? "heart" : "display.2").font(.system(size: 25, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.showingSupport ? L("Ủng hộ tác giả") : ipadPage ? L("Kết nối iPad") : "Mac Monitor").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(model.showingSupport ? L("Ủng hộ hoàn toàn tự nguyện") : ipadPage ? L("Sử dụng iPad làm màn hình phụ") : L("\(model.external.filter(\.connected).count + connectedIPads.count) màn hình ngoài đang hoạt động"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help(L("Phím tắt và cài đặt")).accessibilityLabel(L("Phím tắt và cài đặt"))
            }.padding(20)
            if !model.showingSupport {
            Picker(L("Chọn mục điều khiển"), selection: Binding(
                get: { ipadPage },
                set: { selected in
                    settings = false
                    ipadPage = selected
                    if selected { model.sidecar.refresh() }
                })) {
                Label(L("Màn hình ngoài"), systemImage: "display.2").tag(false)
                Label("iPad", systemImage: "ipad.landscape").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel(L("Chọn mục điều khiển"))
            .padding(.horizontal, 16).padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                VStack(spacing: 12) {
                    if let title = model.pendingTitle {
                        VStack(alignment: .leading, spacing: 9) {
                            Label(L(title), systemImage: "timer").font(.system(size: 12, weight: .semibold))
                            Text(L("Tự khôi phục sau \(model.secondsRemaining) giây.")).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(L("Khôi phục")) { model.revert() }
                                Spacer()
                                Button(L("Giữ thay đổi")) { model.confirm() }.buttonStyle(.borderedProminent).tint(accent)
                            }
                        }.padding(13).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    if let message = model.message {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").foregroundStyle(accent)
                            Text(L(message)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L("Đóng thông báo"))
                        }.padding(12).background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if model.showingSupport {
                        SupportView(language: model.appLanguage)
                    } else if ipadPage {
                        SidecarSection(sidecar: model.sidecar, language: model.appLanguage, available: model.canChange, accent: accent)
                    } else {
                        if model.external.isEmpty && connectedIPads.isEmpty {
                            VStack(spacing: 13) {
                                Image(systemName: "display.trianglebadge.exclamationmark").font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
                                Text(L("Chưa thấy màn hình ngoài")).font(.headline)
                                Text(L("Kết nối màn hình bằng HDMI hoặc USB-C, rồi bấm Làm mới."))
                                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                                Button(L("Làm mới")) { model.refresh() }
                            }.frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(model.external) { monitor in
                            MonitorCard(model: model, monitor: monitor, accent: accent)
                        }
                        ForEach(connectedIPads) { device in
                            ConnectedIPadCard(model: model, device: device, accent: accent)
                        }
                        if let message = model.sidecar.message {
                            Text(L(message)).font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !model.builtins.isEmpty {
                            BuiltinDisplaySection(model: model, accent: accent)
                        }
                        shortcutStrip
                    }
                    if settings { settingsPanel }
                }.padding(16)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(model.showingSupport ? "support" : ipadPage ? "ipad" : "displays")
            .onAppear { if ipadPage { model.sidecar.refresh() } }
            Divider()
            if !ipadPage && !model.showingSupport {
                Button {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension?arrangementSection"),
                       !NSWorkspace.shared.open(url) {
                        model.message = "Chưa mở được Sắp xếp màn hình trong Cài đặt macOS."
                    }
                } label: {
                    Label(L("Sắp xếp màn hình"), systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity)
                }
                .font(.system(size: 11)).buttonStyle(.borderless)
                .padding(.vertical, 9)
                .help(L("Mở thẳng Arrange Displays trong Cài đặt macOS"))
                Divider()
            }
            HStack {
                if model.showingSupport {
                    Button { model.showingSupport = false; settings = false } label: {
                        Label(L("Quay lại"), systemImage: "chevron.left")
                    }
                    Spacer()
                } else if ipadPage {
                    Button { ipadPage = false; settings = false } label: {
                        Label(L("Màn hình ngoài"), systemImage: "chevron.left")
                    }
                    Spacer()
                } else {
                    Button { model.refresh() } label: { Label(L("Làm mới"), systemImage: "arrow.clockwise") }
                        .disabled(model.busy).help(L("Đọc lại danh sách màn hình"))
                    Spacer()
                    Button(L("Khôi phục tất cả")) { model.reconnectAll() }.disabled(model.busy)
                }
                if !model.showingSupport {
                    Button { settings = false; model.showingSupport = true } label: {
                        Label(L("Ủng hộ"), systemImage: "heart")
                    }.help(L("Ủng hộ tác giả"))
                }
                Menu {
                    Button(L("Cài đặt màn hình macOS")) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
                    }
                    Divider()
                    Button(L("Thoát Mac Monitor")) { NSApp.terminate(nil) }
                } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 20)
            }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 13)
        }
        .frame(width: 420, height: panelHeight)
        .background(.regularMaterial)
        .tint(accent)
    }

    private var shortcutStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: "sun.min").keyboardCap().accessibilityLabel(L("Phím giảm sáng"))
            Image(systemName: "sun.max.fill").keyboardCap().accessibilityLabel(L("Phím tăng sáng"))
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Giảm / tăng sáng")).font(.system(size: 12, weight: .medium))
                Text(L(!model.shortcutsEnabled ? L("Đang tắt phím độ sáng") : model.shortcutReady ? model.shortcutFeedback ?? L("Đang nghe phím độ sáng ☀") : L("Cần quyền Trợ năng")))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.shortcutReady {
                Button(L("Mở cài đặt")) { model.requestShortcutAccess() }.controlSize(.small)
            } else {
                Image(systemName: model.shortcutsEnabled ? "checkmark.circle.fill" : "pause.circle").foregroundStyle(accent)
            }
        }.padding(.horizontal, 3).padding(.top, 3)
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker(L("Ngôn ngữ"), selection: $model.appLanguage) {
                Text(L("Tự động (theo macOS)")).tag("automatic")
                Text("Tiếng Việt").tag("vi")
                Text("English").tag("en")
            }.accessibilityLabel(L("Ngôn ngữ"))
            Text("Mac Monitor \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "")")
                .font(.caption).foregroundStyle(.secondary)
            Button(L("Gỡ dịch vụ quản trị…")) { model.removeOverrideService() }.disabled(!model.canChange)
            Text(L("Gỡ cấu hình HiDPI đã cài ở từng màn trước khi gỡ dịch vụ. Các chế độ HiDPI có sẵn và màn ảo không cần dịch vụ này."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("PHÍM TẮT & KHÔI PHỤC")).font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            Toggle(L("Dùng phím độ sáng ☀"), isOn: $model.shortcutsEnabled).toggleStyle(.switch).controlSize(.small)
            Picker(L("Điều khiển"), selection: $model.shortcutTarget) {
                Text(L("Màn hình có con trỏ chuột")).tag("pointer")
                Text(L("Tất cả màn hình ngoài")).tag("all")
                ForEach(model.external) { Text(L($0.name)).tag($0.id) }
            }.font(.system(size: 12))
            Menu {
                ForEach(model.monitors.filter(\.connected)) { display in
                    Button { model.setMainDisplay(display) } label: {
                        if display.main { Label(L(display.name), systemImage: "checkmark") }
                        else { Text(L(display.name)) }
                    }
                }
            } label: { Label(L("Chọn màn hình chính"), systemImage: "menubar.rectangle") }
                .disabled(!model.canChange)
            Toggle(L("Nhớ HiDPI khi kết nối lại"), isOn: $model.restoreOnReconnect).toggleStyle(.switch).controlSize(.small)
            Text(L("Bấm phím biểu tượng mặt trời để giảm/tăng sáng, không cần giữ Fn. Các tổ hợp có ⌘, ⌥, ⇧ hoặc ⌃ vẫn dùng bình thường."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L("HiDPI trực tiếp đã xác nhận vẫn được giữ. Khi thoát app, màn đang ngắt được kết nối lại; HiDPI ảo trở về màn thật."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MonitorCard: View {
    @ObservedObject var model: DisplayController
    let monitor: Monitor
    let accent: Color
    @ViewState private var expanded = false
    @ViewState private var selectedWidth = 1920
    @ViewState private var selectedRate = 60.0
    @ViewState private var useVirtual = false
    @ViewState private var customWidth = ""


    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "display").font(.system(size: monitor.inches > 25 ? 37 : 32, weight: .light))
                        .foregroundStyle(monitor.connected ? accent : .secondary)
                    if monitor.inches > 1 {
                        Text("\(Int(monitor.inches.rounded()))″").font(.system(size: 9, weight: .semibold, design: .monospaced)).offset(y: -3)
                    }
                }.frame(width: 49, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(monitor.name)).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(monitor.name)
                    HStack(spacing: 4) {
                        Circle().fill(monitor.connected ? accent : Color.secondary).frame(width: 5, height: 5)
                        Text(monitor.connected ? L("Đang kết nối") : L("Đã ngắt / chưa có tín hiệu")).font(.system(size: 10)).foregroundStyle(.secondary)
                        if monitor.hiDPI && monitor.connected {
                            Text("HiDPI").font(.system(size: 9, weight: .bold)).foregroundStyle(accent)
                                .padding(.horizontal, 5).padding(.vertical, 2).background(accent.opacity(0.10), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 0)
                Toggle(L("Kết nối \(monitor.name)"), isOn: Binding(get: { monitor.connected }, set: { _ in model.toggleConnection(monitor) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .disabled(!model.canChange || !MMCanSetEnabled())
                    .help(monitor.connected ? L("Ngắt kết nối màn hình bằng phần mềm") : L("Kết nối lại màn hình"))
            }
            if monitor.connected {
                if monitor.main {
                    Label(L("Màn hình chính"), systemImage: "menubar.rectangle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                } else {
                    Button { model.setMainDisplay(monitor) } label: {
                        Label(L("Đặt làm màn hình chính"), systemImage: "menubar.rectangle")
                    }.font(.system(size: 10)).buttonStyle(.borderless).disabled(!model.canChange)
                }
                VStack(spacing: 5) {
                    HStack {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: Binding(get: { monitor.brightness }, set: { model.setBrightness($0, id: monitor.id) }), in: model.brightness.minimum(monitor.id)...1)
                            .accessibilityLabel(L("Độ sáng \(monitor.name)"))
                        Image(systemName: "sun.max.fill").foregroundStyle(accent)
                        Text("\(Int((monitor.brightness * 100).rounded()))%")
                            .font(.system(size: 11, weight: .medium, design: .monospaced)).frame(width: 37, alignment: .trailing)
                    }
                    HStack {
                        Text(L(monitor.brightnessBackend)).font(.system(size: 9)).foregroundStyle(.secondary)
                        Spacer()
                        Button { model.retryBrightness(monitor.id) } label: { Image(systemName: "arrow.clockwise") }
                            .buttonStyle(.borderless).font(.system(size: 9)).help(L("Kiểm tra lại điều khiển độ sáng DDC"))
                    }
                    if model.brightness.supportsHardware(monitor.id) {
                        Toggle(L("Giảm sáng thêm bằng phần mềm"), isOn: Binding(
                            get: { model.brightness.usesExtraDimming(monitor.id) },
                            set: { model.setExtraDimming($0, id: monitor.id) }))
                            .font(.system(size: 9)).toggleStyle(.checkbox)
                            .help(L("Giảm thêm ánh sáng khi mức đèn nền thấp nhất của màn vẫn quá sáng. Cần bật lại sau mỗi lần mở app để tránh tự đổi độ sáng."))
                    } else {
                        Text(L("100% = bỏ lớp giảm sáng; độ sáng đèn nền chỉnh bằng nút trên màn."))
                            .font(.system(size: 9)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                Button { expanded.toggle() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(L("Độ phân giải & HiDPI")).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary)
                            Text(L(monitor.current)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                if expanded { resolutionControls }
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }

    private var resolutionControls: some View {
        let sizes = model.scalingSizes(monitor)
        let selected = sizes.min { abs($0.width - selectedWidth) < abs($1.width - selectedWidth) } ?? monitor.panel
        let native = HiDPIScaling.bestMode(size: selected, refresh: selectedRate, modes: monitor.modes)
        return VStack(alignment: .leading, spacing: 10) {
            Text(L("Trông như \(selected.label)")).font(.system(size: 12, weight: .medium))
            HStack {
                Text(L("Chữ lớn")).font(.caption)
                Slider(value: Binding(get: {
                    Double(sizes.firstIndex(of: selected) ?? 0)
                }, set: { index in
                    let i = min(sizes.count - 1, max(0, Int(index.rounded())))
                    if i >= 0 { selectedWidth = sizes[i].width }
                }), in: 0...Double(max(1, sizes.count - 1)), step: 1)
                    .accessibilityLabel(L("Kích thước giao diện \(monitor.name)"))
                Text(L("Nhiều chỗ")).font(.caption)
            }
            HStack {
                Picker(L("Kích thước"), selection: Binding(get: { selected.width }, set: { selectedWidth = $0 })) {
                    ForEach(sizes) { size in Text(size.label).tag(size.width) }
                }.labelsHidden().accessibilityLabel(L("Mức HiDPI \(monitor.name)"))
                Picker("Hz", selection: $selectedRate) {
                    ForEach(model.scalingRates(monitor), id: \.self) { rate in Text("\(Int(rate)) Hz").tag(rate) }
                }.labelsHidden().frame(width: 85).accessibilityLabel(L("Tần số quét HiDPI \(monitor.name)"))
            }
            Picker(L("Cách hiển thị"), selection: $useVirtual) {
                Text(L("Trực tiếp")).tag(false)
                Text(L("Màn ảo")).tag(true)
            }.pickerStyle(.segmented)
            Text(useVirtual ? L("Dựng HiDPI 2× trên màn ảo rồi phản chiếu sang màn này.")
                 : native.map { L("Có trực tiếp: \($0.label)") } ?? L("Mức này cần bổ sung vào macOS trước khi dùng trực tiếp."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(L("Áp dụng HiDPI")) { model.applyScaling(selected, refresh: selectedRate, virtual: useVirtual, monitor: monitor) }
                .buttonStyle(.borderedProminent).tint(accent)
                .disabled(!model.canChange || (useVirtual && !model.virtualSupported) || (!useVirtual && native == nil))
            HStack {
                TextField(L("Chiều rộng tùy chỉnh"), text: $customWidth).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L("Chiều rộng HiDPI tùy chỉnh \(monitor.name)"))
                Button(L("Thêm")) {
                    if let width = Int(customWidth) { model.addScalingWidth(width, monitor: monitor); selectedWidth = width }
                    else { model.message = "Nhập chiều rộng bằng số, ví dụ 1808." }
                }.disabled(!model.canChange)
            }
            Text(L("Chiều cao được tính theo tỉ lệ màn \(monitor.panel.label). HiDPI dựng hình ở \(selected.width * 2) × \(selected.height * 2); độ nét vẫn phụ thuộc điểm ảnh thật."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if monitor.virtual {
                Label(L("Đang dùng màn ảo"), systemImage: "sparkle").font(.caption)
                Button(L("Tắt màn ảo, về chế độ ban đầu")) { model.disableHiDPI(monitor) }.disabled(!model.canChange)
            } else {
                Button(model.overrideInstalled(monitor) ? L("Cập nhật các mức HiDPI trong macOS…") : L("Bổ sung các mức HiDPI vào macOS…")) {
                    model.configureNativeScaling(monitor, enabled: true)
                }.disabled(!model.canChange)
                if model.overrideInstalled(monitor) {
                    Button(L("Gỡ cấu hình HiDPI của Mac Monitor…")) { model.configureNativeScaling(monitor, enabled: false) }
                        .disabled(!model.canChange)
                }
                Text(L("Dịch vụ cần bản phát hành đã được Apple xác nhận và quyền quản trị. Áp dụng cho các màn cùng mẫu, giữ bản sao để gỡ lại. macOS có thể cần kết nối lại màn hoặc khởi động lại."))
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Menu {
                    ForEach(monitor.modes) { choice in
                        Button { model.selectMode(choice, for: monitor) } label: {
                            if choice.id == monitor.currentModeID { Label(choice.label, systemImage: "checkmark") }
                            else { Text(choice.label) }
                        }
                    }
                } label: { Label(L("Tất cả chế độ có sẵn"), systemImage: "list.bullet") }.disabled(!model.canChange)
            }
        }.controlSize(.small)
        .onAppear {
            let current = model.scalingModes(monitor).first { $0.id == monitor.currentModeID }
            selectedWidth = current?.width ?? 1920
            selectedRate = current?.refreshRate ?? model.scalingRates(monitor).first ?? 60
            useVirtual = monitor.virtual
        }
    }

}

private extension Image {
    func keyboardCap() -> some View {
        self.font(.system(size: 11, weight: .medium, design: .monospaced))
            .frame(width: 28, height: 24)
            .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.1)))
    }
}


private struct SidecarSection: View {
    @ViewState private var showGuide = false
    @ObservedObject var sidecar: SidecarController
    let language: String
    private func localized(_ text: String) -> String { L(text, language: language) }
    let available: Bool
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(localized("Kết nối iPad"), systemImage: "ipad.landscape")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if sidecar.scanning || sidecar.changing || sidecar.repairing { ProgressView().controlSize(.small) }
                Button { sidecar.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).help(localized("Tìm lại iPad"))
                    .accessibilityLabel(localized("Tìm lại iPad"))
                    .disabled(sidecar.scanning || sidecar.changing || sidecar.repairing)
            }
            if !sidecar.supported {
                Text(localized("Sidecar chưa khả dụng trên phiên bản macOS này."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if sidecar.devices.isEmpty {
                Text(localized(sidecar.scanning ? "Đang tìm iPad…" : "Chưa tìm thấy iPad. Mở khóa iPad, dùng cùng tài khoản Apple và bật Wi-Fi, Bluetooth; hoặc kết nối bằng USB."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if sidecar.supported && sidecar.devices.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Button { sidecar.repairDiscovery() } label: {
                        Label(localized(sidecar.repairing ? "Đang khắc phục và tìm lại…" : "Khắc phục tìm iPad"), systemImage: "wrench.and.screwdriver")
                    }.controlSize(.small)
                        .disabled(!available || sidecar.scanning || sidecar.changing || sidecar.repairing)
                    Text(localized("Làm mới dịch vụ tìm thiết bị rồi tự tìm lại iPad. Không cần mật khẩu quản trị; AirDrop và Handoff có thể gián đoạn trong chốc lát."))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(sidecar.devices) { device in
                HStack(spacing: 8) {
                    Text(device.name).font(.system(size: 12, weight: .medium)).lineLimit(1).help(device.name)
                    Spacer()
                    if device.connected {
                        Label(localized("Đã kết nối"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    } else {
                        Button(localized("Kết nối")) { sidecar.toggle(device) }
                            .controlSize(.small)
                            .disabled(!available || sidecar.scanning || sidecar.changing || sidecar.repairing ||
                                      sidecar.devices.contains(where: \.connected))
                    }
                }
            }
            if let message = sidecar.message {
                Text(localized(message)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(localized("Không cần cài thêm ứng dụng trên iPad."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text(localized("Yêu cầu iPad hỗ trợ Sidecar và chạy iPadOS 13 trở lên."))
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(localized("Danh sách iPad hỗ trợ Sidecar (Apple)"),
                 destination: URL(string: "https://support.apple.com/en-us/102597")!)
                .font(.system(size: 10))
            DisclosureGroup(isExpanded: $showGuide) {
                SidecarGuide(language: language)
                    .padding(.top, 8)
            } label: {
                Label(localized("Hướng dẫn kết nối iPad"), systemImage: "questionmark.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            Button(localized("Mở cài đặt Sidecar")) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            }.font(.system(size: 10)).buttonStyle(.borderless)
        }.padding(14).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}


private struct SidecarGuide: View {
    let language: String
    private func localized(_ text: String) -> String { L(text, language: language) }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(localized("1. Đăng nhập cùng tài khoản Apple trên Mac và iPad, bật xác thực hai yếu tố cho tài khoản."))
            Text(localized("2. Mở khóa iPad và đặt gần máy Mac."))
            Text(localized("Không dây: bật Wi-Fi, Bluetooth và Handoff trên cả hai thiết bị, để cách nhau dưới 10 m. Tắt Điểm truy cập cá nhân trên iPad và Chia sẻ Internet trên Mac."))
            Text(localized("Qua USB: dùng dây có truyền dữ liệu để nối iPad với Mac. Trên iPad, chọn Tin cậy và nhập mật mã iPad nếu được hỏi."))
            Text(localized("3. Bấm nút tìm lại rồi chọn Kết nối cạnh tên iPad. Khi đã kết nối, sang Màn hình ngoài để chỉnh độ phân giải hoặc ngắt kết nối."))
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }
}


private struct ConnectedIPadCard: View {
    @ViewState private var selectedModeID: Int32?
    @ObservedObject var model: DisplayController
    let device: SidecarDevice
    let accent: Color
    private var monitor: Monitor? { model.monitors.first { $0.displayID == device.displayID && $0.connected } }
    private func localized(_ text: String) -> String { L(text, language: model.appLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "ipad.landscape").font(.system(size: 32, weight: .light))
                    .foregroundStyle(accent).frame(width: 49, height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).help(device.name)
                    Label(localized("Đang kết nối qua Sidecar"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10)).foregroundStyle(accent)
                }
                Spacer(minLength: 0)
                if model.sidecar.changing { ProgressView().controlSize(.small) }
                Button(localized("Ngắt kết nối")) { model.sidecar.toggle(device) }
                    .controlSize(.small)
                    .disabled(!model.canChange || model.sidecar.scanning)
            }
            if let monitor {
                if monitor.main {
                    Label(localized("Màn hình chính"), systemImage: "menubar.rectangle")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(accent)
                } else {
                    Button { model.setMainDisplay(monitor) } label: {
                        Label(localized("Đặt làm màn hình chính"), systemImage: "menubar.rectangle")
                    }.font(.system(size: 10)).buttonStyle(.borderless).disabled(!model.canChange)
                }
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Độ phân giải iPad")).font(.system(size: 12, weight: .semibold))
                    Text(localized("Hiện tại: \(monitor.current)"))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    if monitor.modes.count > 1 {
                        Picker(localized("Chọn độ phân giải"), selection: $selectedModeID) {
                            ForEach(monitor.modes) { mode in
                                Text(mode.label).tag(Optional(mode.id))
                            }
                        }.labelsHidden().pickerStyle(.menu)
                            .accessibilityLabel(localized("Độ phân giải iPad"))
                            .disabled(!model.canChange)
                        HStack {
                            Text(localized("Chọn mức do macOS cung cấp, rồi xác nhận trong 20 giây."))
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Button(localized("Áp dụng")) {
                                if let mode = monitor.modes.first(where: { $0.id == selectedModeID }) {
                                    model.selectIPadMode(mode, device: device, monitor: monitor)
                                }
                            }.controlSize(.small)
                                .disabled(!model.canChange || selectedModeID == monitor.currentModeID ||
                                          !monitor.modes.contains(where: { $0.id == selectedModeID }))
                        }
                    } else {
                        Text(localized("macOS chưa cung cấp mức độ phân giải khác cho iPad này."))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .onAppear { selectedModeID = monitor.currentModeID }
                .onChange(of: monitor.currentModeID) { _, id in selectedModeID = id }
            } else {
                Text(localized("Đang đọc độ phân giải iPad…"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct BuiltinDisplaySection: View {
    @ObservedObject var model: DisplayController
    let accent: Color
    @ViewState private var askingPermission = false
    @ViewState private var lidAttempted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L("Màn hình tích hợp"), systemImage: "laptopcomputer").font(.headline)
            Text("Apple Silicon").font(.caption).foregroundStyle(.secondary)
            if model.lidState != 0 {
                Text(L(model.lidState == 1 ? "Đang gập nắp — macOS quản lý màn tích hợp." : "Chưa đọc được trạng thái nắp — tạm khóa điều khiển màn tích hợp."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.builtins) { monitor in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(monitor.name).font(.system(size: 13, weight: .semibold))
                        Text(L(monitor.connected ? "Đang kết nối" : "Đã ngắt / chưa có tín hiệu"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(L("Kết nối màn hình tích hợp"), isOn: Binding(get: { monitor.connected },
                        set: { _ in
                            lidAttempted = MMLidState() != 0
                            model.toggleConnection(monitor)
                        }))
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(!model.canChange || (model.lidState == 0 && !model.canToggleBuiltin(monitor)))
                        .help(L(model.lidState == 1 ? "Mở nắp MacBook để bật màn hình tích hợp." : "Kết nối màn hình tích hợp"))
                }
                if lidAttempted && model.lidState != 0 {
                    Label(L(model.lidState == 1
                        ? "MacBook đang gập nắp. Hãy mở nắp để điều khiển màn hình tích hợp."
                        : "Chưa đọc được trạng thái nắp MacBook. Tạm thời không thể điều khiển màn hình tích hợp."), systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
                if monitor.connected && !monitor.main {
                    Button(L("Đặt làm màn hình chính")) { model.setMainDisplay(monitor) }.disabled(!model.canChange || model.lidState != 0)
                }
            }
            Toggle(L("Cho phép ngắt màn hình tích hợp"), isOn: Binding(
                get: { model.allowBuiltinDisconnect }, set: { value in
                    if value { askingPermission = true } else { model.allowBuiltinDisconnect = false }
                })).disabled(!model.canChange || !model.builtinConnectionAvailable)
            Toggle(L("Tự ngắt khi có màn hình ngoài"), isOn: $model.autoDisconnectBuiltin)
                .disabled(!model.canChange || !model.allowBuiltinDisconnect || !model.builtinConnectionAvailable)
            Text(L("Dành cho MacBook mở nắp hoặc đã tháo màn. Chỉ ngắt khi còn màn ngoài vật lý hoạt động; màn ảo và iPad không được tính. Khi mất màn ngoài, app sẽ thử bật lại màn tích hợp."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text(L("Chỉ có hiệu lực khi app đang chạy, sau đăng nhập. Bật lại thủ công hoặc Khôi phục tất cả sẽ tạm dừng tự ngắt."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .alert(L("Cho phép ngắt màn hình tích hợp?"), isPresented: $askingPermission) {
            Button(L("Hủy"), role: .cancel) {}
            Button(L("Cho phép")) { model.allowBuiltinDisconnect = true }
        } message: {
            Text(L("Hãy kiểm tra màn ngoài đang sử dụng được. Một số model có thể cần khởi động lại nếu không bật lại được màn tích hợp. App không xử lý màn khởi động hoặc FileVault."))
        }
    }
}
