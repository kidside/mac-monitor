# Cài Mac Monitor / Install Mac Monitor

Bản 0.2.0-beta.2 dành cho Mac Apple Silicon, yêu cầu macOS 14 trở lên; hiện chỉ thử thực tế trên M4 Pro, macOS 27.0.1. Giao diện tiếng Việt và tiếng Anh.

1. Giải nén gói tải từ https://github.com/kidside/mac-monitor/releases.
2. Kéo **Mac Monitor.app** vào **Applications**, rồi mở ứng dụng.
3. Bấm biểu tượng màn hình trên menu bar.
4. Muốn dùng phím có hình mặt trời: bật Mac Monitor ở **System Settings → Privacy & Security → Accessibility**. Không cần giữ Fn. F1/F2 thông thường không được dùng làm phím sáng.
5. Muốn tự mở khi đăng nhập: thêm ứng dụng vào **General → Login Items & Extensions → Open at Login**.

Bản beta này ký ad-hoc, chưa được Apple notarize. macOS có thể chặn khi mở lần đầu. Chỉ mở nếu tin nguồn tải, theo [hướng dẫn Open Anyway của Apple](https://support.apple.com/en-us/102445). Không tắt Gatekeeper. Bản ad-hoc khác có thể cần cấp lại quyền Trợ năng.

Thanh sáng có nhãn DDC là đèn nền thật. Nhãn phần mềm là lớp giảm sáng; 100% chỉ bỏ lớp này. “Giảm sáng thêm bằng phần mềm” kết hợp hai cách cho màn vẫn quá sáng ở mức thấp.

Công tắc tắt giữ màn hình ngắt cho đến khi bật lại. Khi đổi độ phân giải/HiDPI, xác nhận trong 20 giây. Nếu gặp lỗi cấu hình, chọn **Khôi phục tất cả**. Luôn giữ ít nhất một màn hình hoạt động. Màn ảo HiDPI cần ứng dụng tiếp tục chạy.

## English

Requires an Apple Silicon Mac and macOS 14+. Physically tested only on M4 Pro / macOS 27.0.1. Move the extracted app into Applications and open it; controls are in the menu bar. Allow Accessibility for native brightness keys. Add the app to Open at Login if desired.

This beta is ad-hoc signed, not Apple notarized. Only proceed if you trust the source, using Apple's linked Open Anyway instructions. A different ad-hoc build may need Accessibility approval again.

DDC means physical backlight control. Software-only 100% removes dimming and cannot raise physical backlight. The off switch stays off until you reconnect. Confirm resolution/HiDPI changes within 20 seconds; use “Khôi phục tất cả” to attempt restoration. Private display APIs and untested hardware remain beta limitations.


## Cài thêm HiDPI vào hệ thống / Additional system HiDPI modes

Nút cài/gỡ cấu hình cần bản Developer ID đã được Apple notarize. Bản beta ký ad-hoc không đăng ký dịch vụ hay xin quyền quản trị; nút sẽ giải thích hạn chế này. HiDPI có sẵn và màn ảo vẫn dùng được.

Với bản notarized đã được kiểm tra: đặt app trong Applications; bấm nút cài/gỡ ở màn tương ứng, cho phép dịch vụ Mac Monitor trong Login Items & Extensions nếu macOS yêu cầu, rồi thử lại và cấp quyền quản trị trên hộp thoại macOS. Không gửi mật khẩu cho người khác. Đổi cấu hình này có thể cần kết nối lại màn hoặc khởi động lại Mac.

Gỡ cấu hình HiDPI từng màn trước, rồi chọn **Gỡ dịch vụ quản trị… / Remove administrator service…** trong cài đặt app. Gỡ dịch vụ giữ nguyên cấu hình đã cài và backup. Thoát app rồi mới xóa app. Với cấu hình đã cài từ bản cũ, không xóa backup trước khi hoàn tất khôi phục bằng bản notarized.

The additional system-mode installer requires a Developer ID signed and notarized build, service approval and administrator authorization. The ad-hoc beta refuses this operation before registration or authorization. The new daemon's installation/removal still requires testing on a notarized build; it is not a verified feature of the ad-hoc download. Available HiDPI modes and virtual displays remain usable without it.
