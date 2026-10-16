import SwiftUI
import AppKit

// The command-line macOS 27 SDK omits the new State macro plugin.
// Name the longstanding property wrapper explicitly so builds also work without Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>

struct MonitorView: View {
    @ObservedObject var model: DisplayController
    var panelHeight: CGFloat = 680
    @ViewState private var settings = false
    private let accent = Color(red: 0.08, green: 0.49, blue: 0.52)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Image(systemName: "display.2").font(.system(size: 25, weight: .medium)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mac Monitor").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text(L("\(model.external.filter(\.connected).count) màn hình ngoài đang hoạt động"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help(L("Phím tắt và cài đặt")).accessibilityLabel(L("Phím tắt và cài đặt"))
            }.padding(20)
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
                    if model.external.isEmpty {
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
                    shortcutStrip
                    if settings { settingsPanel }
                }.padding(16)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
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
            HStack {
                Button { model.refresh() } label: { Label(L("Làm mới"), systemImage: "arrow.clockwise") }
                    .disabled(model.busy).help(L("Đọc lại danh sách màn hình"))
                Spacer()
                Button(L("Khôi phục tất cả")) { model.reconnectAll() }.disabled(model.busy)
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
