# Mac Monitor 0.2.0-beta.2 — build 17

Bản thử nghiệm cho Mac Apple Silicon, macOS 14+. Giao diện tiếng Việt và tiếng Anh. Phần cứng từng thử: M4 Pro/macOS 27.0.1, Mi Monitor HDMI và VU241Q USB-C; chưa kiểm tra lại với màn ngoài trong đợt sửa bảo mật này.

- Chỉnh sáng DDC/phần mềm, phím mặt trời, ngắt/kết nối bằng phần mềm, chọn màn chính và chọn HiDPI có sẵn hoặc màn ảo.
- HiDPI ảo có lựa chọn kích thước theo tỉ lệ và tần số quét; cần app tiếp tục chạy. Đổi chế độ có xác nhận/khôi phục sau 20 giây.
- Build 17 sửa lỗi icon menu bar chớp rồi tự mở lại bảng; đã thử bấm liên tiếp, nhấn giữ và bấm ra ngoài trên màn tích hợp.
- Sửa lỗi chỉ số màn hình âm/0, tràn số và đầu vào CLI thiếu; dùng OSLog cho trace, bỏ UUID khỏi chẩn đoán mặc định.
- Chuyển nút cài thêm cấu hình HiDPI hệ thống sang dịch vụ SMAppService có xác thực. **Nút này chỉ hoạt động với bản Developer ID đã notarize và được phép chạy dịch vụ. Bản beta ad-hoc hiện chưa hỗ trợ cài/gỡ cấu hình hệ thống.** Dịch vụ mới còn cần kiểm tra cài/gỡ thực tế bằng bản notarized.
- MIT, gồm m1ddc đã chỉnh sửa với giấy phép gốc. Xem SECURITY.md và hướng dẫn cài đặt.

Gói dự kiến: `MacMonitor-0.2.0-beta.2-arm64.zip`, `mac-monitor-0.2.0-beta.2-source.zip` và `SHA256SUMS.txt`. Gói ad-hoc chưa được Apple notarize; chỉ mở nếu tin nguồn tải theo [hướng dẫn của Apple](https://support.apple.com/en-us/102445). Không tắt Gatekeeper.

## English

Experimental Apple Silicon/macOS 14+ beta, with English and Vietnamese UI. Includes brightness, native brightness keys, display disconnect/reconnect, main-display selection, available HiDPI modes and optional mirrored virtual HiDPI with size/refresh selection. Confirm mode changes within 20 seconds; virtual displays need the app running.

Security changes reject invalid DDC selection/numeric inputs, replace shared temporary trace files with OSLog, redact UUIDs from default diagnostics, and replace legacy administrator execution with an authenticated SMAppService/XPC service.

**The additional system HiDPI installer requires a Developer ID signed and notarized release plus service approval. It is unavailable in the ad-hoc beta.** Its notarized installation/removal lifecycle still needs manual validation. Existing native modes and virtual HiDPI remain available.

This download is ad-hoc signed, not notarized. Physical compatibility beyond M4 Pro/macOS 27.0.1, Mi HDMI and VU USB-C remains unverified. External-display regression tests have not been repeated during this security update. Build 17 fixes the captured status-icon/global-click/focus ordering. The user verified repeated and held clicks plus outside dismissal in normal mode on the built-in display.
