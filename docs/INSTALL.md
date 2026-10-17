# Cài Mac Monitor / Install Mac Monitor

Bản 0.3.1-beta.3 dành cho Mac Apple Silicon, yêu cầu macOS 14 trở lên; hiện chỉ thử thực tế trên M4 Pro, macOS 27.0.1. Giao diện tiếng Việt và tiếng Anh.

1. Mở file DMG (hoặc giải nén ZIP) tải từ https://github.com/kidside/mac-monitor/releases.
2. Kéo **Mac Monitor.app** vào **Applications**, rồi mở ứng dụng.
3. Bấm biểu tượng màn hình trên menu bar.
4. Muốn dùng phím có hình mặt trời: bật Mac Monitor ở **System Settings → Privacy & Security → Accessibility**. Không cần giữ Fn. F1/F2 thông thường không được dùng làm phím sáng.
5. Muốn tự mở khi đăng nhập: thêm ứng dụng vào **General → Login Items & Extensions → Open at Login**.

Bản beta này ký ad-hoc, chưa được Apple notarize. macOS có thể chặn khi mở lần đầu. Chỉ mở nếu tin nguồn tải, theo [hướng dẫn Open Anyway của Apple](https://support.apple.com/en-us/102445). Không tắt Gatekeeper. Bản ad-hoc khác có thể cần cấp lại quyền Trợ năng.

Thanh sáng có nhãn DDC là đèn nền thật. Nhãn phần mềm là lớp giảm sáng; 100% chỉ bỏ lớp này. “Giảm sáng thêm bằng phần mềm” kết hợp hai cách cho màn vẫn quá sáng ở mức thấp.

Công tắc tắt giữ màn hình ngắt cho đến khi bật lại. Khi đổi độ phân giải/HiDPI, xác nhận trong 20 giây. Nếu gặp lỗi cấu hình, chọn **Khôi phục tất cả**. Luôn giữ ít nhất một màn hình hoạt động. Màn ảo HiDPI cần ứng dụng tiếp tục chạy.

## English

Requires an Apple Silicon Mac and macOS 14+. Physically tested only on M4 Pro / macOS 27.0.1. Open the DMG (or extract the ZIP), then move the app into Applications and open it; controls are in the menu bar. Allow Accessibility for native brightness keys. Add the app to Open at Login if desired.

This beta is ad-hoc signed, not Apple notarized. Only proceed if you trust the source, using Apple's linked Open Anyway instructions. A different ad-hoc build may need Accessibility approval again.

DDC means physical backlight control. Software-only 100% removes dimming and cannot raise physical backlight. The off switch stays off until you reconnect. Confirm resolution/HiDPI changes within 20 seconds; use “Khôi phục tất cả” to attempt restoration. Private display APIs and untested hardware remain beta limitations.


## Cài thêm HiDPI vào hệ thống / Additional system HiDPI modes

Nút cài/gỡ cấu hình cần bản Developer ID đã được Apple notarize. Bản beta ký ad-hoc không đăng ký dịch vụ hay xin quyền quản trị; nút sẽ giải thích hạn chế này. HiDPI có sẵn và màn ảo vẫn dùng được.

Với bản notarized đã được kiểm tra: đặt app trong Applications; bấm nút cài/gỡ ở màn tương ứng, cho phép dịch vụ Mac Monitor trong Login Items & Extensions nếu macOS yêu cầu, rồi thử lại và cấp quyền quản trị trên hộp thoại macOS. Không gửi mật khẩu cho người khác. Đổi cấu hình này có thể cần kết nối lại màn hoặc khởi động lại Mac.

Gỡ cấu hình HiDPI từng màn trước, rồi chọn **Gỡ dịch vụ quản trị… / Remove administrator service…** trong cài đặt app. Gỡ dịch vụ giữ nguyên cấu hình đã cài và backup. Thoát app rồi mới xóa app. Với cấu hình đã cài từ bản cũ, không xóa backup trước khi hoàn tất khôi phục bằng bản notarized.

The additional system-mode installer requires a Developer ID signed and notarized build, service approval and administrator authorization. The ad-hoc beta refuses this operation before registration or authorization. The new daemon's installation/removal still requires testing on a notarized build; it is not a verified feature of the ad-hoc download. Available HiDPI modes and virtual displays remain usable without it.


## Kết nối iPad / Connect an iPad

Yêu cầu iPad hỗ trợ Sidecar và chạy iPadOS 13 trở lên. Xem [danh sách tương thích của Apple](https://support.apple.com/en-us/102597). Không cần cài thêm app trên iPad. Trên Mac Monitor, mở **mục iPad ở đầu bảng → Hướng dẫn kết nối iPad** để xem các bước bằng ngôn ngữ đã chọn.

1. Mac và iPad phải đăng nhập cùng tài khoản Apple, có xác thực hai yếu tố. Mở khóa iPad và để gần Mac.
2. Không dây: bật Wi-Fi, Bluetooth và Handoff trên cả hai thiết bị, trong phạm vi 10 m. Tắt Điểm truy cập cá nhân trên iPad và Chia sẻ Internet trên Mac. Qua USB: dùng dây truyền dữ liệu và chọn **Tin cậy** trên iPad nếu được hỏi.
3. Bấm tìm lại ở tab iPad rồi **Kết nối** cạnh tên thiết bị. Sau khi kết nối, sang tab **Màn hình ngoài** để ngắt hoặc chọn độ phân giải do macOS cung cấp. Chọn mức → **Áp dụng** → **Giữ thay đổi** trong 20 giây; không xác nhận thì app tự khôi phục.

Hỗ trợ Sidecar: iPad Pro, iPad thế hệ 6+, Air thế hệ 3+, mini thế hệ 5+, chạy iPadOS 13+. [Hướng dẫn Apple](https://support.apple.com/en-us/102597). Tính năng mới vẫn cần thử trên iPad thật trước khi phát hành.

Requires a Sidecar-compatible iPad running iPadOS 13 or later. See [Apple’s compatibility list](https://support.apple.com/en-us/102597). No iPad app is needed. Open **the iPad tab at the top → How to connect your iPad** in Mac Monitor for the setup steps in your selected language.

1. Sign in to the same Apple Account with two-factor authentication on both devices. Unlock the iPad and keep it nearby.
2. Wireless: enable Wi-Fi, Bluetooth and Handoff on both, within 10 m. Disable Personal Hotspot on iPad and Internet Sharing on Mac. USB: use a data-capable cable and choose **Trust** on iPad if asked.
3. Refresh the iPad tab, then click **Connect** beside your iPad. Once connected, use **External displays** to disconnect or select a macOS-provided resolution. Choose a mode → **Apply** → **Keep changes** within 20 seconds, otherwise the app reverts.

Sidecar supports any iPad Pro, iPad (6th generation+), Air (3rd generation+) or mini (5th generation+), with iPadOS 13+. [Apple’s guide](https://support.apple.com/en-us/102597). Physical iPad testing of this new feature is still pending before release.

Độ phân giải iPad chỉ dùng các mức mà macOS báo khả dụng; có thể chỉ có một mức trên một số máy/phiên bản OS. Không tạo thêm màn ảo để ép độ phân giải iPad.

iPad resolutions are limited to the modes advertised by macOS; some setups may expose only one. No extra virtual display is created to force an iPad resolution.


### Không tìm thấy iPad / No iPad found

Nếu đã kiểm tra tài khoản Apple, mở khóa iPad và kết nối mà vẫn không thấy thiết bị, bấm **Khắc phục tìm iPad** ngay trong tab iPad. App tự làm mới dịch vụ tìm thiết bị của tài khoản hiện tại rồi tìm lại tối đa ba lượt; không cần chạy Terminal hay nhập mật khẩu quản trị. AirDrop/Handoff có thể gián đoạn trong chốc lát. Nếu vẫn chưa thấy, thử cắm USB và xem lại điều kiện Sidecar.

If your iPad is still missing after checking the Apple Account, unlocking it and checking connectivity, click **Fix iPad discovery** in the iPad tab. The app restarts the current user's discovery service and retries up to three times. No Terminal or administrator password is needed. AirDrop/Handoff may pause briefly. If it still cannot find your iPad, try USB and review the Sidecar requirements.
