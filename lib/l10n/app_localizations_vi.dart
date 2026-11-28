// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'AI của bạn. Thiết bị của bạn. Quy tắc của bạn.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Hủy';

  @override
  String get confirm => 'Xác nhận';

  @override
  String get delete => 'Xóa';

  @override
  String get save => 'Lưu';

  @override
  String get retry => 'Thử lại';

  @override
  String get close => 'Đóng';

  @override
  String get done => 'Xong';

  @override
  String get continue_action => 'Tiếp tục';

  @override
  String get skip => 'Bỏ qua';

  @override
  String get install => 'Cài đặt';

  @override
  String get download => 'Tải xuống';

  @override
  String get resume => 'Tiếp tục tải';

  @override
  String get pause => 'Tạm dừng';

  @override
  String get stop => 'Dừng';

  @override
  String get edit => 'Chỉnh sửa';

  @override
  String get preview => 'Xem trước';

  @override
  String get unload => 'Giải phóng khỏi bộ nhớ';

  @override
  String get load => 'Nạp';

  @override
  String get rename => 'Đổi tên';

  @override
  String get pin => 'Ghim';

  @override
  String get unpin => 'Bỏ ghim';

  @override
  String get share => 'Chia sẻ';

  @override
  String get copy => 'Sao chép';

  @override
  String get copied => 'Đã sao chép!';

  @override
  String get copied_to_clipboard => 'Đã sao chép vào bảng nhớ tạm';

  @override
  String get select => 'Chọn';

  @override
  String get active => 'Đang hoạt động';

  @override
  String get all => 'Tất cả';

  @override
  String get none => 'Không có';

  @override
  String get none_selected => 'Chưa chọn';

  @override
  String get online => 'Trực tuyến';

  @override
  String get connected => 'Đã kết nối';

  @override
  String get checking => 'Đang kiểm tra';

  @override
  String get offline => 'Ngoại tuyến';

  @override
  String get error => 'Lỗi';

  @override
  String get unknown_error => 'Lỗi không xác định';

  @override
  String get not_now => 'Để sau';

  @override
  String get enable => 'Bật';

  @override
  String get proceed_anyway => 'Vẫn tiếp tục';

  @override
  String get test_connection => 'Kiểm tra kết nối';

  @override
  String get testing => 'Đang kiểm tra…';

  @override
  String get connection_successful => 'Kết nối thành công!';

  @override
  String get connection_failed => 'Kết nối thất bại. Hãy kiểm tra cài đặt.';

  @override
  String get connection_failed_unreachable =>
      'Không thể kết nối với máy chủ. Hãy kiểm tra địa chỉ và cổng, đảm bảo máy chủ lắng nghe trên mạng của bạn (ngoài localhost) và LocalMind được phép truy cập mạng cục bộ.';

  @override
  String get connection_failed_timeout =>
      'Máy chủ phản hồi quá thời hạn. Hãy kiểm tra xem thiết bị và máy chủ có cùng mạng hoặc VPN hay không.';

  @override
  String get connection_failed_tls =>
      'Không thể thiết lập kết nối bảo mật. Hãy kiểm tra chứng chỉ máy chủ hoặc dùng http:// nếu máy chủ không hỗ trợ HTTPS.';

  @override
  String connection_failed_unauthorized(int status) {
    return 'Máy chủ đã từ chối yêu cầu (HTTP $status). Hãy kiểm tra khóa API.';
  }

  @override
  String get connection_failed_not_found =>
      'Máy chủ đã phản hồi nhưng không qua các đường dẫn API dự kiến. Hãy kiểm tra loại máy chủ, cổng và tiền tố đường dẫn.';

  @override
  String connection_failed_status(int status) {
    return 'Máy chủ phản hồi với mã HTTP $status.';
  }

  @override
  String get connection_failed_missing_key =>
      'Nhà cung cấp này yêu cầu khóa API.';

  @override
  String get connection_warning_lmstudio_native =>
      'Chỉ kết nối được qua các đường dẫn /v1 tương thích với OpenAI. Tính năng trò chuyện dùng đường dẫn /api/v1 gốc của LM Studio. Hãy đảm bảo proxy chuyển tiếp các đường dẫn này.';

  @override
  String get context_length_server_default => 'Mặc định của máy chủ';

  @override
  String get context_length_use_server_default =>
      'Dùng giá trị mặc định của máy chủ';

  @override
  String get save_continue => 'Lưu và tiếp tục';

  @override
  String get save_changes => 'Lưu thay đổi';

  @override
  String get finish_setup => 'Hoàn tất thiết lập';

  @override
  String get start_new_chat => 'Bắt đầu cuộc trò chuyện mới';

  @override
  String get cannot_undo => 'Không thể hoàn tác thao tác này.';

  @override
  String get ram_warning => 'Cảnh báo RAM';

  @override
  String get recommended => 'KHUYẾN NGHỊ';

  @override
  String get may_be_large => 'Có thể quá lớn cho thiết bị này';

  @override
  String get calculating => 'Đang tính…';

  @override
  String get download_failed => 'Tải xuống thất bại';

  @override
  String get downloaded => 'Đã tải xuống';

  @override
  String get not_downloaded => 'Chưa tải xuống';

  @override
  String get installed => 'Đã cài đặt';

  @override
  String get not_installed => 'Chưa cài đặt';

  @override
  String get loading => 'Đang tải…';

  @override
  String get thinking => 'Đang suy luận';

  @override
  String get processing => 'Đang xử lý…';

  @override
  String get initializing => 'Đang khởi tạo…';

  @override
  String get ready => 'Sẵn sàng';

  @override
  String get preparing_app => 'Đang chuẩn bị ứng dụng…';

  @override
  String get initializing_services => 'Đang khởi động dịch vụ…';

  @override
  String get configuring_server => 'Đang cấu hình máy chủ…';

  @override
  String get startup_failed => 'Khởi động thất bại';

  @override
  String get something_went_wrong => 'Đã xảy ra lỗi';

  @override
  String get delete_model_title => 'Xóa mô hình';

  @override
  String delete_model_body(String name) {
    return 'Bạn có chắc muốn xóa $name không?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Bạn có chắc muốn xóa $name không? Thao tác này sẽ giải phóng khoảng $size dung lượng.\n\nBạn có thể tải lại mô hình này khi cần.';
  }

  @override
  String get delete_voice_title => 'Xóa giọng nói';

  @override
  String delete_voice_body(String name, String size) {
    return 'Bạn có chắc muốn xóa $name không? Thao tác này sẽ giải phóng khoảng $size dung lượng.\n\nBạn có thể tải lại giọng nói này khi cần.';
  }

  @override
  String get delete_server_title => 'Xóa máy chủ';

  @override
  String delete_server_body(String name) {
    return 'Bạn có chắc muốn xóa “$name” không? Không thể hoàn tác thao tác này.';
  }

  @override
  String get delete_conversation_title => 'Xóa cuộc trò chuyện?';

  @override
  String delete_conversation_body(String title) {
    return 'Bạn có chắc muốn xóa “$title” không? Không thể hoàn tác thao tác này.';
  }

  @override
  String get delete_message_title => 'Xóa tin nhắn?';

  @override
  String delete_persona_title(String name) {
    return 'Xóa “$name”?';
  }

  @override
  String get delete_persona_body => 'Không thể hoàn tác thao tác này.';

  @override
  String get delete_builtin_persona_body =>
      'Đây là nhân vật có sẵn. Bạn có thể khôi phục trong phần Cài đặt.';

  @override
  String get restore_builtin_personas => 'Khôi phục nhân vật mặc định';

  @override
  String get restore_builtin_personas_desc =>
      'Thêm lại các nhân vật có sẵn mà bạn đã xóa';

  @override
  String get restore_builtin_personas_success =>
      'Đã khôi phục nhân vật mặc định';

  @override
  String get clear_personas => 'Xóa tất cả nhân vật';

  @override
  String get enable_image_compression => 'Nén ảnh trước khi gửi';

  @override
  String get enable_image_compression_desc =>
      'Đổi kích thước và nén ảnh đính kèm để tệp tải lên không vượt quá giới hạn máy chủ';

  @override
  String get image_compression_level => 'Mức nén';

  @override
  String get image_compression_level_desc =>
      'Mức nén cao hơn giúp giảm dung lượng tệp nhưng cũng giảm chất lượng';

  @override
  String get image_compression_level_low => 'Thấp';

  @override
  String get image_compression_level_medium => 'Trung bình';

  @override
  String get image_compression_level_high => 'Cao';

  @override
  String get sort_models_tooltip => 'Sắp xếp mô hình';

  @override
  String get sort_by_favorites => 'Ưu tiên mục yêu thích';

  @override
  String get sort_by_name => 'Tên (A–Z)';

  @override
  String get sort_by_size_smallest => 'Dung lượng (nhỏ nhất trước)';

  @override
  String get sort_by_size_largest => 'Dung lượng (lớn nhất trước)';

  @override
  String get sort_by_context_length => 'Độ dài ngữ cảnh';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Đang đổi tên $done/$total…';
  }

  @override
  String selected_count(int count) {
    return 'Đã chọn $count';
  }

  @override
  String get ai_rename_tooltip => 'Dùng AI đổi tên các mục đã chọn';

  @override
  String get new_chat_in_folder_tooltip =>
      'Cuộc trò chuyện mới trong thư mục này';

  @override
  String total_tokens_count(int count) {
    return '$count token';
  }

  @override
  String get smart_replies_use_persona =>
      'Dùng nhân vật cho câu trả lời thông minh';

  @override
  String get smart_replies_use_persona_desc =>
      'Câu trả lời gợi ý sẽ mang giọng điệu của nhân vật đang dùng thay cho giọng điệu mặc định của trợ lý';

  @override
  String get keep_persona_on_new_chat =>
      'Giữ nhân vật khi tạo cuộc trò chuyện mới';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Giữ nguyên các nhân vật đã chọn khi bắt đầu cuộc trò chuyện mới';

  @override
  String get role_swap_button_enabled => 'Hiện nút đổi vai';

  @override
  String get role_swap_button_enabled_desc =>
      'Hiện nút trong ô soạn tin để gửi tin nhắn với vai trò trợ lý thay vì người dùng mà không tạo phản hồi';

  @override
  String get processing_prompt_label => 'Đang xử lý lời nhắc…';

  @override
  String get generating_label => 'Đang tạo…';

  @override
  String get prompts_processed_label => 'Lời nhắc đã xử lý';

  @override
  String get prompt_processing_indicator_enabled =>
      'Hiện chỉ báo xử lý lời nhắc';

  @override
  String get prompt_processing_indicator_enabled_desc =>
      'Hiện tiến độ xử lý theo thời gian thực và số lời nhắc đã xử lý trong cuộc trò chuyện phía trên ô soạn tin.';

  @override
  String get send_as_user_tooltip => 'Gửi với vai trò người dùng';

  @override
  String get send_as_assistant_tooltip =>
      'Gửi với vai trò trợ lý (không tạo phản hồi)';

  @override
  String get insert_without_generating_tooltip => 'Chèn mà không tạo phản hồi';

  @override
  String get token_usage_title => 'Mức sử dụng token';

  @override
  String get total_tokens_label => 'Token đã dùng';

  @override
  String get usage_percent_label => 'Ngữ cảnh đã dùng';

  @override
  String get export_choice_title => 'Xuất';

  @override
  String get export_choice_body => 'Bạn muốn xuất nội dung này theo cách nào?';

  @override
  String get copy_to_clipboard => 'Sao chép vào bảng nhớ tạm';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Đã xuất $count cuộc trò chuyện';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Đổi tên bằng AI?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'AI sẽ tạo tiêu đề mới cho từng cuộc trong số $count cuộc trò chuyện đã chọn và thay thế tiêu đề hiện tại. Việc này có thể mất chút thời gian và không thể hoàn tác.';
  }

  @override
  String get sort_by_modified_date => 'Sửa đổi lần cuối';

  @override
  String get sort_by_created_date => 'Ngày tạo';

  @override
  String get sort_title => 'Sắp xếp';

  @override
  String get clear_conversation_title => 'Dọn sạch cuộc trò chuyện?';

  @override
  String get clear_conversation_body =>
      'Thao tác này sẽ xóa toàn bộ tin nhắn trong cuộc trò chuyện này.';

  @override
  String get clear => 'Xóa nội dung';

  @override
  String label_completed(String label) {
    return 'Đã hoàn tất: $label';
  }

  @override
  String error_with_message(String error) {
    return 'Lỗi: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Không thể xem trước: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Đang nạp $modelId…';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Đã nạp mô hình: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Chưa nạp mô hình nào. Nhấn “Quản lý mô hình trên thiết bị” để tải xuống và nạp một mô hình.';

  @override
  String loading_model_error(String error) {
    return 'Lỗi: $error';
  }

  @override
  String get delete_conversation => 'Xóa cuộc trò chuyện?';

  @override
  String get nav_history => 'Lịch sử';

  @override
  String get nav_servers => 'Máy chủ';

  @override
  String get nav_local_models => 'Mô hình cục bộ';

  @override
  String get nav_tts => 'Chuyển văn bản thành giọng nói';

  @override
  String get nav_personas => 'Nhân vật';

  @override
  String get nav_settings => 'Cài đặt';

  @override
  String get nav_new_chat => 'Cuộc trò chuyện mới';

  @override
  String get search_hint => 'Tìm cuộc trò chuyện…';

  @override
  String get no_server_selected => 'Chưa chọn máy chủ';

  @override
  String get switch_server => 'Đổi máy chủ';

  @override
  String get switch_server_subtitle => 'Chọn máy chủ để kết nối';

  @override
  String get manage_servers => 'Quản lý máy chủ';

  @override
  String get open_source => 'Mã nguồn mở';

  @override
  String get open_source_desc =>
      'LocalMind là ứng dụng mã nguồn mở. Theo dõi tiến độ hoặc đóng góp trên GitHub.';

  @override
  String get star_on_github => 'Gắn sao trên GitHub';

  @override
  String get add_more => 'Thêm';

  @override
  String get on_github => 'trên GitHub';

  @override
  String get could_not_open_github => 'Không thể mở GitHub.';

  @override
  String get settings_title => 'Cài đặt';

  @override
  String get settings_appearance => 'Giao diện';

  @override
  String get settings_language => 'Ngôn ngữ';

  @override
  String get language_system_default => 'Mặc định hệ thống';

  @override
  String get settings_tts => 'Chuyển văn bản thành giọng nói';

  @override
  String get settings_android_assistant => 'Trợ lý Android';

  @override
  String get assistant_default_title => 'Dùng LocalMind làm trợ lý';

  @override
  String get assistant_default_description =>
      'Mở chế độ giọng nói bằng cử chỉ gọi trợ lý Android hoặc phím tắt nút nguồn.';

  @override
  String get assistant_status_active => 'Đang hoạt động';

  @override
  String get assistant_status_available => 'Chưa hoạt động';

  @override
  String get assistant_status_manual => 'Kiểm tra cài đặt';

  @override
  String get assistant_status_unsupported => 'Không khả dụng';

  @override
  String get assistant_status_checking => 'Đang kiểm tra…';

  @override
  String get assistant_set_default => 'Đặt làm trợ lý mặc định';

  @override
  String get assistant_open_settings => 'Mở cài đặt trợ lý Android';

  @override
  String assistant_error(Object error) {
    return 'Không thể mở cài đặt trợ lý Android.';
  }

  @override
  String get settings_behavior => 'Hành vi';

  @override
  String get settings_on_device => 'Suy luận trên thiết bị';

  @override
  String get settings_default_server => 'Máy chủ mặc định';

  @override
  String get settings_default_persona => 'Nhân vật mặc định';

  @override
  String get settings_default_model => 'Mô hình mặc định';

  @override
  String get settings_default_model_desc =>
      'Tự động chọn khi bắt đầu cuộc trò chuyện mới.';

  @override
  String get settings_privacy => 'Quyền riêng tư';

  @override
  String get settings_data_management => 'Quản lý dữ liệu';

  @override
  String get settings_about => 'Giới thiệu';

  @override
  String get theme => 'Giao diện';

  @override
  String get theme_system => 'Theo hệ thống';

  @override
  String get theme_light => 'Sáng';

  @override
  String get theme_dark => 'Tối';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'Cỡ chữ';

  @override
  String get font_size_desc => 'Điều chỉnh cỡ chữ khi trò chuyện.';

  @override
  String get font_preview => 'Chú cáo nâu nhanh nhẹn nhảy qua con chó lười.';

  @override
  String get code_theme_dark => 'Giao diện mã (tối)';

  @override
  String get code_theme_light => 'Giao diện mã (sáng)';

  @override
  String get code_theme_desc =>
      'Chọn giao diện tô sáng cú pháp cho các khối mã.';

  @override
  String get tts_engine => 'Bộ tổng hợp giọng nói';

  @override
  String get tts_engine_system => 'Chuyển văn bản thành giọng nói của hệ thống';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => 'Giọng nói';

  @override
  String get voice_female => 'Nữ';

  @override
  String get voice_male => 'Nam';

  @override
  String get voice_other => 'Khác';

  @override
  String get tts_speed => 'Tốc độ đọc';

  @override
  String get tts_speed_desc => 'Điều chỉnh tốc độ phát.';

  @override
  String get manage_tts_models => 'Quản lý mô hình giọng nói';

  @override
  String get manage_on_device_models => 'Quản lý mô hình trên thiết bị';

  @override
  String get enable_smart_reply => 'Câu trả lời thông minh';

  @override
  String get ai_user_response_enabled =>
      'Tin nhắn người dùng do AI viết (giữ nút gửi)';

  @override
  String get ai_user_response_enabled_desc =>
      'Giữ nút gửi trong 3 giây để AI viết và gửi tin nhắn tiếp theo của bạn';

  @override
  String get ai_user_response_tooltip => 'Dùng AI tạo tin nhắn người dùng';

  @override
  String get streaming_responses => 'Hiện phản hồi theo thời gian thực';

  @override
  String get auto_generate_titles => 'Tự động tạo tiêu đề';

  @override
  String get send_on_enter => 'Nhấn Enter để gửi';

  @override
  String get show_system_messages => 'Gửi lời nhắc hệ thống mặc định';

  @override
  String get show_system_messages_desc =>
      'Khi chưa chọn nhân vật, gửi lời nhắc hệ thống mặc định của trợ lý cùng mỗi yêu cầu';

  @override
  String get show_system_messages_in_chat =>
      'Hiện tin nhắn hệ thống trong cuộc trò chuyện';

  @override
  String get show_system_messages_in_chat_desc =>
      'Hiện tin nhắn hệ thống (chẳng hạn từ bản sao lưu đã nhập) dưới dạng bong bóng trong cuộc trò chuyện';

  @override
  String get auto_collapse_thinking => 'Tự động thu gọn suy luận';

  @override
  String get auto_collapse_thinking_desc =>
      'Tự động thu gọn quá trình suy luận sau khi tạo xong phản hồi nếu đã có câu trả lời chính';

  @override
  String get haptic_feedback => 'Phản hồi rung';

  @override
  String get enable_mcp => 'Bật MCP';

  @override
  String get new_chat_mcp_default => 'Mặc định MCP cho cuộc trò chuyện mới';

  @override
  String get show_data_indicator => 'Hiện chỉ báo dữ liệu';

  @override
  String get privacy_info => '“LocalMind không bao giờ xem dữ liệu của bạn”';

  @override
  String get delete_all_conversations => 'Xóa tất cả cuộc trò chuyện';

  @override
  String get reset_settings_defaults => 'Khôi phục cài đặt mặc định';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Thông số cuộc trò chuyện';

  @override
  String get change_persona => 'Đổi nhân vật';

  @override
  String get set_persona => 'Đặt nhân vật';

  @override
  String get remove_persona => 'Bỏ nhân vật';

  @override
  String get clear_conversation => 'Dọn sạch cuộc trò chuyện';

  @override
  String get connection_error => 'Lỗi kết nối. Hãy kiểm tra máy chủ.';

  @override
  String get disconnected => 'Đã ngắt kết nối với máy chủ.';

  @override
  String get configure => 'Cấu hình';

  @override
  String get select_model => 'Chọn mô hình';

  @override
  String get select_persona => 'Chọn nhân vật';

  @override
  String get manage_personas => 'Quản lý nhân vật';

  @override
  String get personas_combine_hint =>
      'Chọn nhiều nhân vật trong cuộc trò chuyện để kết hợp lời nhắc hệ thống của họ.';

  @override
  String get start_conversation => 'Bắt đầu trò chuyện';

  @override
  String get recent_chats => 'Cuộc trò chuyện gần đây';

  @override
  String get see_all => 'Xem tất cả';

  @override
  String get quick_write => 'Giúp tôi viết một hàm';

  @override
  String get quick_explain => 'Giải thích đoạn mã này';

  @override
  String get quick_debug => 'Giúp tôi gỡ lỗi';

  @override
  String get quick_async => 'Làm sao dùng async/await?';

  @override
  String get history_missing_title => 'Không có lịch sử';

  @override
  String get history_missing_desc =>
      'Tin nhắn trong cuộc trò chuyện đã bị xóa hoặc dữ liệu lịch sử đã bị hỏng.';

  @override
  String get technical_details => 'Chi tiết kỹ thuật';

  @override
  String get last_error => 'Lỗi gần nhất:';

  @override
  String get copy_info => 'Sao chép thông tin';

  @override
  String get conversation_id => 'ID cuộc trò chuyện';

  @override
  String get created_at => 'Ngày tạo';

  @override
  String get expected_messages => 'Số tin nhắn dự kiến';

  @override
  String get debug_dialog_desc =>
      'Thông tin chẩn đoán giúp xác định vấn đề đồng bộ hóa.';

  @override
  String get chat_input_hint => 'Hỏi bất cứ điều gì';

  @override
  String get send_message_tooltip => 'Gửi tin nhắn';

  @override
  String get stop_generation_tooltip => 'Dừng tạo phản hồi';

  @override
  String get attach_images_tooltip => 'Đính kèm ảnh hoặc văn bản';

  @override
  String get start_listening_tooltip => 'Bắt đầu nghe';

  @override
  String get stop_listening_tooltip => 'Dừng nghe';

  @override
  String tool_label(String toolCallId) {
    return 'Công cụ: $toolCallId';
  }

  @override
  String get tool_unknown => 'Công cụ: Không xác định';

  @override
  String get message_options => 'Tùy chọn tin nhắn';

  @override
  String get copy_markdown => 'Sao chép dưới dạng Markdown';

  @override
  String get copied_markdown => 'Đã sao chép dưới dạng Markdown';

  @override
  String get read_aloud => 'Đọc to';

  @override
  String get stop_reading => 'Dừng đọc';

  @override
  String get more => 'Thêm';

  @override
  String character_count(int length) {
    return '$length ký tự';
  }

  @override
  String get edit_message => 'Chỉnh sửa tin nhắn';

  @override
  String get edit_message_desc =>
      'Khi lưu, phản hồi của trợ lý bên dưới sẽ bị xóa và tạo lại.';

  @override
  String get save_regenerate => 'Lưu và tạo lại';

  @override
  String get chat_settings_title => 'Cài đặt trò chuyện';

  @override
  String get reset_defaults => 'Đặt lại về mặc định';

  @override
  String get parameters_tab => 'Thông số';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'Nhiệt độ';

  @override
  String get temperature_desc =>
      'Điều chỉnh độ ngẫu nhiên: cao hơn thì sáng tạo hơn, thấp hơn thì tập trung hơn';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'Ngưỡng lấy mẫu hạt nhân';

  @override
  String get max_tokens => 'Số token tối đa';

  @override
  String get max_tokens_desc => 'Giới hạn độ dài phản hồi';

  @override
  String get context_length => 'Độ dài ngữ cảnh';

  @override
  String get context_length_desc => 'Phạm vi lịch sử trò chuyện';

  @override
  String get mcp_disabled_warning =>
      'MCP đang bị tắt cho toàn ứng dụng. Hãy bật trong phần Cài đặt để dùng các tính năng này.';

  @override
  String get mcp_enable_chat => 'Bật MCP cho cuộc trò chuyện này';

  @override
  String mcp_connection_failed(String error) {
    return 'Không thể kết nối: $error';
  }

  @override
  String get mcp_tools_unsupported_runtime =>
      'Môi trường chạy của mô hình này chưa thể gọi công cụ. Hãy chuyển sang mô hình Gemma (LiteRT) hoặc mô hình trên máy chủ để dùng công cụ MCP.';

  @override
  String get auto_execute_tools => 'Tự động chạy công cụ';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Thử nghiệm';

  @override
  String get add_ephemeral_mcp => 'Thêm máy chủ MCP tạm thời';

  @override
  String get mcp_label_placeholder => 'Nhãn';

  @override
  String get mcp_url_placeholder => 'URL (https://…)';

  @override
  String get active_integrations => 'Tích hợp đang hoạt động';

  @override
  String get import_mcp_json => 'Nhập JSON';

  @override
  String get import_mcp_json_dialog_title => 'Nhập cấu hình MCP từ JSON';

  @override
  String get import_mcp_json_instructions =>
      'Sao chép JSON mcpServers trực tiếp từ LM Studio (mcp.json) hoặc dán mảng plugin bên dưới:';

  @override
  String get import_mcp_json_placeholder =>
      'Dán JSON mcpServers hoặc danh sách plugin vào đây…';

  @override
  String mcp_import_success(int count) {
    return 'Đã nhập $count tích hợp';
  }

  @override
  String get mcp_import_failed =>
      'Không tìm thấy tích hợp MCP hợp lệ trong JSON';

  @override
  String get enable_notifications => 'Bật thông báo';

  @override
  String get enable_notifications_desc =>
      'Nhận thông báo khi tải xong mô hình.';

  @override
  String get chat_history_title => 'Lịch sử trò chuyện';

  @override
  String get conversation_just_now => 'Vừa xong';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes phút trước';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours giờ trước';
  }

  @override
  String get conversation_yesterday => 'Hôm qua';

  @override
  String conversation_days_ago(int days) {
    return '$days ngày trước';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$day/$month/$year';
  }

  @override
  String get options_tooltip => 'Tùy chọn';

  @override
  String get no_results_found => 'Không tìm thấy kết quả';

  @override
  String get no_conversations_yet => 'Chưa có cuộc trò chuyện';

  @override
  String get try_different_search => 'Hãy thử từ khóa khác';

  @override
  String get start_new_conversation => 'Bắt đầu cuộc trò chuyện mới';

  @override
  String get rename_conversation => 'Đổi tên cuộc trò chuyện';

  @override
  String get enter_new_title => 'Nhập tiêu đề mới';

  @override
  String get pinned_section => 'ĐÃ GHIM';

  @override
  String get today_section => 'HÔM NAY';

  @override
  String get yesterday_section => 'HÔM QUA';

  @override
  String get previous_7_days => '7 NGÀY QUA';

  @override
  String get previous_30_days => '30 NGÀY QUA';

  @override
  String get older_section => 'CŨ HƠN';

  @override
  String get onboarding_choose_language => 'Chọn ngôn ngữ';

  @override
  String get onboarding_choose_language_desc =>
      'Chọn ngôn ngữ bạn muốn dùng. Bạn có thể thay đổi bất cứ lúc nào trong phần Cài đặt.';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'Kết nối với\nmáy chủ của bạn';

  @override
  String get onboarding_connect_desc =>
      'Kết nối với LM Studio, Ollama,\nOllama Cloud hoặc OpenRouter để\nbắt đầu dùng AI riêng tư.';

  @override
  String get openai_compatible_api => 'API tương thích với OpenAI';

  @override
  String get https_requires_ssl => 'HTTPS yêu cầu SSL';

  @override
  String get most_local_setups_use_http =>
      'Hầu hết thiết lập cục bộ dùng http://';

  @override
  String get onboarding_welcome => 'Chào mừng đến với LocalMind';

  @override
  String get server_type_on_device => 'Trên thiết bị';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'ĐÁM MÂY ĐƯỢC QUẢN LÝ';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Khi kết nối với Ollama Cloud, tin nhắn và dữ liệu bạn nhập được gửi đến máy chủ do Ollama quản lý để chạy suy luận. LocalMind không theo dõi hay lưu cuộc trò chuyện của bạn. Bạn có thể thu hồi khóa bất cứ lúc nào tại ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud => 'Ollama Cloud yêu cầu khóa API';

  @override
  String get api_key_hint_ollama_cloud => 'Dán khóa API Ollama Cloud';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Kết nối với Ollama Cloud bằng khóa API từ ollama.com/settings/keys để truy cập các mô hình đám mây được quản lý.';

  @override
  String get add_server_openrouter_subtitle =>
      'Kết nối với OpenRouter bằng khóa API hợp lệ để dùng hồ sơ này khi định tuyến yêu cầu đến mô hình.';

  @override
  String get add_server_requesty_subtitle =>
      'Kết nối với Requesty bằng khóa API hợp lệ để dùng hồ sơ này khi định tuyến yêu cầu đến mô hình.';

  @override
  String get add_server_standard_compute_subtitle =>
      'Kết nối với Standard Compute bằng khóa API hợp lệ để dùng hồ sơ này khi định tuyến yêu cầu đến mô hình.';

  @override
  String get add_server_endpoint_subtitle =>
      'Cấu hình điểm cuối cục bộ hoặc tự lưu trữ, rồi kiểm tra kết nối trước khi lưu.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_requesty => 'Requesty';

  @override
  String get server_type_standard_compute => 'Standard Compute';

  @override
  String get server_type_openrouter_sub => 'ĐÁM MÂY HỢP NHẤT';

  @override
  String get server_type_requesty_sub => 'ĐÁM MÂY HỢP NHẤT';

  @override
  String get server_type_standard_compute_sub => 'ĐÁM MÂY HỢP NHẤT';

  @override
  String get ready_continue => 'SẴN SÀNG TIẾP TỤC';

  @override
  String get waiting_selection => 'ĐANG CHỜ CHỌN';

  @override
  String get setup_connection => 'Thiết lập kết nối';

  @override
  String setup_connection_desc(String server) {
    return 'Cấu hình máy chủ $server để bắt đầu trò chuyện.';
  }

  @override
  String get server_name => 'Tên máy chủ';

  @override
  String get name_required => 'Bắt buộc nhập tên';

  @override
  String get name_max_50 => 'Tối đa 50 ký tự';

  @override
  String get host_label => 'Máy chủ / địa chỉ IP';

  @override
  String get host_required => 'Bắt buộc nhập máy chủ';

  @override
  String get port_label => 'Cổng';

  @override
  String get port_required => 'Bắt buộc nhập cổng';

  @override
  String get port_invalid => 'Phải là số';

  @override
  String get port_range => 'Nhập cổng hợp lệ (1–65535)';

  @override
  String get api_key_required => 'Khóa API *';

  @override
  String get api_key_optional => 'Khóa API (không bắt buộc)';

  @override
  String get api_key_required_openrouter => 'OpenRouter yêu cầu khóa API';

  @override
  String get api_key_required_requesty => 'Requesty yêu cầu khóa API';

  @override
  String get api_key_required_standard_compute =>
      'Standard Compute yêu cầu khóa API';

  @override
  String get api_key_format => 'Khóa API OpenRouter bắt đầu bằng sk-';

  @override
  String get my_server_hint => 'Máy chủ của tôi';

  @override
  String get name_length_validation => 'Tên không được dài quá 50 ký tự';

  @override
  String get host_valid => 'Nhập tên máy chủ hoặc địa chỉ IP hợp lệ';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_requesty => 'rqsty-...';

  @override
  String get api_key_hint_standard_compute => 'sk_live_...';

  @override
  String get api_key_hint_generic => 'Dùng cho máy chủ yêu cầu xác thực';

  @override
  String get update_server => 'Cập nhật máy chủ';

  @override
  String get save_server => 'Lưu máy chủ';

  @override
  String get server_updated => 'Đã cập nhật máy chủ';

  @override
  String get server_added => 'Đã thêm máy chủ';

  @override
  String get download_model_title => 'Tải mô hình';

  @override
  String get download_model_desc =>
      'Chọn mô hình để tải xuống.\nMô hình sẽ chạy cục bộ trên thiết bị của bạn.';

  @override
  String get no_model_downloaded_title => 'Chưa tải mô hình nào';

  @override
  String get no_model_downloaded_desc =>
      'Để dùng AI trên thiết bị, bạn cần tải xuống hoặc chọn ít nhất một mô hình. Bạn có thể chọn ngay hoặc bỏ qua và tải xuống sau trong phần Cài đặt.';

  @override
  String get choose_a_model => 'Chọn mô hình';

  @override
  String get skip_for_now => 'Tạm bỏ qua';

  @override
  String get download_in_progress_title => 'Đang tải xuống';

  @override
  String get download_in_progress_desc =>
      'Một mô hình đang được tải xuống. Bạn có thể chờ tải xong hoặc tiếp tục tải trong nền.';

  @override
  String get wait_for_download => 'Chờ';

  @override
  String get continue_anyway => 'Vẫn tiếp tục';

  @override
  String get download_model_required_hint =>
      'Bạn cần tải xuống ít nhất một mô hình để trò chuyện trên thiết bị.';

  @override
  String get on_device_android_only =>
      'Tính năng suy luận trên thiết bị hiện chỉ có trên Android.';

  @override
  String get total_ram => 'Tổng RAM';

  @override
  String get available => 'Khả dụng';

  @override
  String ram_min_required(String fileSize) {
    return 'Tối thiểu $fileSize GB RAM';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Còn lại: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'Đã tạm dừng – $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Mô hình này cần ít nhất $ram GB RAM, nhưng thiết bị của bạn có $totalMemory. Mô hình có thể chạy không đúng hoặc làm ứng dụng gặp sự cố.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Thiết bị còn $availableRAM RAM khả dụng, nhưng mô hình này khuyến nghị ít nhất $ram GB. Việc nạp mô hình có thể thất bại hoặc gây mất ổn định.';
  }

  @override
  String get choose_theme => 'Chọn giao diện';

  @override
  String get choose_theme_desc =>
      'Cá nhân hóa giao diện ứng dụng. Bạn có thể thay đổi sau trong phần Cài đặt.';

  @override
  String get theme_card_system => 'Theo hệ thống';

  @override
  String get theme_card_system_sub => 'Theo cài đặt của thiết bị';

  @override
  String get theme_card_light => 'Sáng';

  @override
  String get theme_card_light_sub => 'Đơn giản và sáng sủa';

  @override
  String get theme_card_dark => 'Tối';

  @override
  String get theme_card_dark_sub => 'Dịu mắt';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'Giao diện tông đào ấm áp';

  @override
  String get stay_updated => 'Luôn cập nhật';

  @override
  String get stay_updated_desc =>
      'Nhận thông báo khi tải xong mô hình AI hoặc khi tác vụ chạy lâu hoàn tất.';

  @override
  String get notification_benefit_downloads => 'Tiến độ tải mô hình';

  @override
  String get notification_benefit_completions => 'Hoàn tất tạo phản hồi';

  @override
  String get notification_benefit_background => 'Trạng thái tác vụ nền';

  @override
  String get allow_notifications => 'Cho phép thông báo';

  @override
  String get servers_title => 'Máy chủ';

  @override
  String get no_servers_yet => 'Chưa có máy chủ';

  @override
  String get no_servers_desc =>
      'Thêm máy chủ đầu tiên để bắt đầu trò chuyện với các mô hình AI.';

  @override
  String get add_server => 'Thêm máy chủ';

  @override
  String switched_to_server(String name) {
    return 'Đã chuyển sang $name';
  }

  @override
  String get edit_server => 'Chỉnh sửa máy chủ';

  @override
  String get add_server_title => 'Thêm máy chủ';

  @override
  String get server_type_label => 'Loại máy chủ';

  @override
  String get server_icon_label => 'Biểu tượng máy chủ';

  @override
  String get default_icon => 'Biểu tượng mặc định';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'Tương thích với OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_requesty_display => 'Requesty';

  @override
  String get server_type_standard_compute_display => 'Standard Compute';

  @override
  String get server_type_on_device_display => 'Trên thiết bị';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_requesty => 'router.requesty.ai';

  @override
  String get server_address_standard_compute => 'api.stdcmpt.com';

  @override
  String get server_address_on_device => 'Suy luận cục bộ';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Mặc định';

  @override
  String get set_as_default => 'Đặt làm mặc định';

  @override
  String get select_icon => 'Chọn biểu tượng';

  @override
  String get select_icon_desc => 'Chọn biểu tượng cho máy chủ';

  @override
  String get search_icons_hint => 'Tìm biểu tượng…';

  @override
  String get server_icon_stack => 'Cụm máy chủ';

  @override
  String get server_icon_stack2 => 'Cụm máy chủ 02';

  @override
  String get server_icon_stack3 => 'Cụm máy chủ 03';

  @override
  String get server_icon_cloud => 'Đám mây';

  @override
  String get server_icon_cloud_server => 'Máy chủ đám mây';

  @override
  String get server_icon_mcp => 'Máy chủ MCP';

  @override
  String get server_icon_database => 'Cơ sở dữ liệu';

  @override
  String get server_icon_database1 => 'Cơ sở dữ liệu 01';

  @override
  String get server_icon_database2 => 'Cơ sở dữ liệu 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'Vi mạch';

  @override
  String get server_icon_chip2 => 'Vi mạch 02';

  @override
  String get server_icon_computer => 'Máy tính';

  @override
  String get server_icon_laptop => 'Máy tính xách tay';

  @override
  String get server_icon_terminal => 'Thiết bị đầu cuối';

  @override
  String get server_icon_code => 'Mã';

  @override
  String get server_icon_ai_brain => 'Bộ não AI';

  @override
  String get server_icon_ai_brain2 => 'Bộ não AI 02';

  @override
  String get server_icon_ai_cloud => 'Đám mây AI';

  @override
  String get server_icon_ai_network => 'Mạng AI';

  @override
  String get server_icon_ai_chat => 'Trò chuyện AI';

  @override
  String get server_icon_cellular => 'Mạng di động';

  @override
  String get server_icon_plug1 => 'Phích cắm 01';

  @override
  String get server_icon_plug2 => 'Phích cắm 02';

  @override
  String get server_icon_bot => 'Bot';

  @override
  String get server_icon_bot2 => 'Bot 02';

  @override
  String get server_icon_robotic => 'Rô-bốt';

  @override
  String get server_icon_rocket => 'Tên lửa';

  @override
  String get server_icon_star => 'Ngôi sao';

  @override
  String get server_icon_settings1 => 'Cài đặt 01';

  @override
  String get server_icon_settings2 => 'Cài đặt 02';

  @override
  String get server_icon_home1 => 'Nhà 01';

  @override
  String get server_icon_home2 => 'Nhà 02';

  @override
  String get server_icon_folder1 => 'Thư mục 01';

  @override
  String get server_icon_folder2 => 'Thư mục 02';

  @override
  String get server_icon_file1 => 'Tệp 01';

  @override
  String get server_icon_lock => 'Ổ khóa';

  @override
  String get server_icon_key => 'Chìa khóa 01';

  @override
  String get server_icon_link => 'Liên kết 01';

  @override
  String get server_icon_globe => 'Quả địa cầu';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Mũi tên sang phải 01';

  @override
  String get server_icon_check => 'Dấu kiểm trong vòng tròn';

  @override
  String get server_icon_alert => 'Cảnh báo trong vòng tròn';

  @override
  String get server_icon_info => 'Thông tin trong vòng tròn';

  @override
  String get server_icon_zap => 'Tia sét';

  @override
  String get server_icon_cloud_upload => 'Tải lên đám mây';

  @override
  String get server_icon_cloud_download => 'Tải xuống từ đám mây';

  @override
  String get server_icon_refresh => 'Làm mới';

  @override
  String get server_icon_hard_drive => 'Ổ đĩa cứng';

  @override
  String get server_icon_drive => 'Ổ đĩa';

  @override
  String get personas_title => 'Nhân vật';

  @override
  String get persona_category_general => 'Chung';

  @override
  String get persona_category_coding => 'Lập trình';

  @override
  String get persona_category_education => 'Giáo dục';

  @override
  String get persona_category_creative => 'Sáng tạo';

  @override
  String get persona_builtin_section => 'CÓ SẴN';

  @override
  String get persona_my_section => 'NHÂN VẬT CỦA TÔI';

  @override
  String get clone_edit => 'Sao chép và chỉnh sửa';

  @override
  String get builtin_badge => 'Có sẵn';

  @override
  String get no_personas_found => 'Không tìm thấy nhân vật';

  @override
  String get no_personas_desc =>
      'Tạo nhân vật đầu tiên để tùy chỉnh hành vi của AI.';

  @override
  String get edit_persona => 'Chỉnh sửa nhân vật';

  @override
  String get create_persona => 'Tạo nhân vật';

  @override
  String get create_persona_button => 'Tạo';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'Tên';

  @override
  String get my_persona_hint => 'Nhân vật của tôi';

  @override
  String get category_label => 'Danh mục';

  @override
  String get description_optional => 'Mô tả (không bắt buộc)';

  @override
  String get description_hint => 'Vai trò của nhân vật này…';

  @override
  String get system_prompt => 'Lời nhắc hệ thống';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Chưa có lời nhắc…';

  @override
  String get prompt_hint => 'Bạn là một trợ lý hữu ích…';

  @override
  String get prompt_required => 'Bắt buộc nhập lời nhắc hệ thống';

  @override
  String get prompt_max_chars => 'Tối đa 4000 ký tự';

  @override
  String prompt_length_warning(int count) {
    return 'Lời nhắc dài ($count ký tự) chiếm nhiều chỗ hơn trong cửa sổ ngữ cảnh của mô hình và có thể khiến mô hình nhỏ phản hồi chậm hoặc gặp lỗi.';
  }

  @override
  String get advanced_settings => 'Cài đặt nâng cao';

  @override
  String get temperature_label => 'Nhiệt độ (0.0–2.0)';

  @override
  String get top_p_label => 'Top P (0.0–1.0)';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0.9';

  @override
  String get range_0_2 => '0.0-2.0';

  @override
  String get range_0_1 => '0.0-1.0';

  @override
  String get persona_updated => 'Đã cập nhật nhân vật';

  @override
  String get persona_created => 'Đã tạo nhân vật';

  @override
  String get tts_models_title => 'Mô hình chuyển văn bản thành giọng nói';

  @override
  String get always_available => 'Luôn khả dụng';

  @override
  String get tts_system_desc =>
      'Dùng bộ tổng hợp giọng nói tích hợp trên thiết bị.\nKhông cần tải xuống. Giọng nói được chọn theo cài đặt hệ thống của thiết bị.';

  @override
  String get downloading_status => 'Đang tải xuống…';

  @override
  String tts_kitten_desc(String size) {
    return 'Chuyển văn bản thành giọng nói bằng mạng nơ-ron cực nhanh với 8 giọng biểu cảm.\nCần tải xuống $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Giọng Piper chạy ngoại tuyến nhanh, với 2 giọng biểu cảm.\nCần tải xuống $size cho mỗi giọng.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount giọng';
  }

  @override
  String get on_device_models_title => 'Mô hình trên thiết bị';

  @override
  String get settings_huggingface_token =>
      'Mã truy cập Hugging Face (không bắt buộc)';

  @override
  String get settings_huggingface_token_desc =>
      'Chỉ cần cho mô hình có giới hạn truy cập (ví dụ: Gemma). Lấy mã truy cập tại huggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Đã lưu mã truy cập';

  @override
  String get settings_huggingface_token_cleared => 'Đã xóa mã truy cập';

  @override
  String get model_requires_huggingface_token =>
      'Yêu cầu mã truy cập Hugging Face';

  @override
  String get model_missing_huggingface_token =>
      'Mô hình này bị giới hạn truy cập trên Hugging Face. Để tải xuống, hãy thêm mã truy cập trong Cài đặt → Suy luận trên thiết bị.';

  @override
  String get set_huggingface_token => 'Đặt mã truy cập';

  @override
  String get clear_huggingface_token => 'Xóa nội dung';

  @override
  String get edit_huggingface_token_dialog_title => 'Mã truy cập Hugging Face';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc => 'Bộ máy AI cục bộ. Không cần khóa API.';

  @override
  String get server_type_on_device_desc =>
      'Chạy trên điện thoại. Một số mô hình cần mã truy cập Hugging Face.';

  @override
  String get server_type_lm_studio_desc =>
      'Máy chủ API cục bộ. Không cần khóa API.';

  @override
  String get available_models => 'Mô hình khả dụng';

  @override
  String get device_memory => 'Bộ nhớ thiết bị';

  @override
  String get ram_usage => 'Mức sử dụng RAM';

  @override
  String get memory_healthy => 'Bình thường';

  @override
  String get memory_critical => 'Mức nguy kịch';

  @override
  String get memory_low => 'Thấp';

  @override
  String ram_used(String percent) {
    return 'Đã dùng $percent%';
  }

  @override
  String get available_ram => 'RAM khả dụng';

  @override
  String get total_capacity => 'Tổng dung lượng';

  @override
  String get loaded_status => 'Đã nạp';

  @override
  String get inference_backend => 'Bộ xử lý suy luận';

  @override
  String get backend_ios_notice => 'Trên iOS chỉ có thể suy luận bằng CPU.';

  @override
  String get backend_cpu_desc =>
      'Chạy trên mọi thiết bị. Tương thích tốt nhất.';

  @override
  String get backend_gpu_desc =>
      'Tăng tốc OpenCL. Chạy nhanh hơn trên các thiết bị được hỗ trợ.';

  @override
  String get backend_npu_desc =>
      'NPU của nhà sản xuất (Qualcomm/MediaTek). Tốc độ suy luận nhanh nhất.';

  @override
  String get select_model_title => 'Chọn mô hình';

  @override
  String get refresh_models => 'Làm mới danh sách mô hình';

  @override
  String get search_models_hint => 'Tìm mô hình…';

  @override
  String get no_server_connected => 'Chưa kết nối máy chủ';

  @override
  String get add_server_first =>
      'Thêm máy chủ trước để xem các mô hình khả dụng.';

  @override
  String get failed_load_models => 'Không thể tải danh sách mô hình';

  @override
  String get no_models_available => 'Không có mô hình khả dụng';

  @override
  String no_models_match(String searchQuery) {
    return 'Không có mô hình nào khớp với “$searchQuery”';
  }

  @override
  String model_load_failed(String error) {
    return 'Không thể nạp mô hình: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'Đã yêu cầu giải phóng $name khỏi bộ nhớ. Nếu kết nối được với Ollama, mô hình sẽ được giải phóng ngay.';
  }

  @override
  String model_unloaded_success(String name) {
    return 'Đã giải phóng $name khỏi bộ nhớ';
  }

  @override
  String model_unload_failed(String error) {
    return 'Không thể giải phóng mô hình khỏi bộ nhớ: $error';
  }

  @override
  String get unload_from_server => 'Giải phóng khỏi bộ nhớ máy chủ';

  @override
  String context_chip(String ctx) {
    return 'Ngữ cảnh: $ctx';
  }

  @override
  String get unload_all_models => 'Giải phóng tất cả khỏi bộ nhớ';

  @override
  String loaded_models_count(int count) {
    return 'Đã nạp $count';
  }

  @override
  String get all_models_unloaded => 'Đã giải phóng tất cả mô hình khỏi bộ nhớ';

  @override
  String get branch_chat => 'Tách nhánh cuộc trò chuyện';

  @override
  String get branch_chat_desc => 'Bắt đầu cuộc trò chuyện mới từ tin nhắn này';

  @override
  String get edit_assistant_message_desc =>
      'Chỉnh sửa nội dung phản hồi của trợ lý.';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Chuyển sang $modelName';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Đang tải $modelName…';
  }

  @override
  String get download_complete_notification => 'Đã tải xong!';

  @override
  String download_complete_body(String modelName) {
    return 'Đã tải xuống $modelName thành công.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Tải xuống thất bại: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Không thể tải xuống $modelName.';
  }

  @override
  String get engine_name_system =>
      'Chuyển văn bản thành giọng nói của hệ thống';

  @override
  String get engine_tagline_system => 'Bộ tổng hợp tích hợp sẵn trên thiết bị';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten =>
      'Chuyển văn bản thành giọng nói tốc độ cao bằng mạng nơ-ron';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'Giọng Piper dùng ngoại tuyến';

  @override
  String get voice_jasper => 'Jasper';

  @override
  String get voice_bella => 'Bella';

  @override
  String get voice_bruno => 'Bruno';

  @override
  String get voice_luna => 'Luna';

  @override
  String get voice_hugo => 'Hugo';

  @override
  String get voice_rosie => 'Rosie';

  @override
  String get voice_leo => 'Leo';

  @override
  String get voice_kiki => 'Kiki';

  @override
  String get voice_lessac => 'Lessac (Hoa Kỳ)';

  @override
  String get voice_ryan => 'Ryan (Hoa Kỳ)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc =>
      'Mô hình trò chuyện đa dụng nhỏ nhất. Phản hồi nhanh, ít tốn bộ nhớ.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'Cân bằng giữa chất lượng và kích thước. Phù hợp cho trò chuyện thông thường.';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Mô hình suy luận theo chuỗi tư duy. Phù hợp nhất với các bài toán logic.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'Mô hình chủ lực của Google. Chất lượng cao nhất, cần thêm RAM.';

  @override
  String export_header(String date) {
    return '*Đã xuất từ LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Người dùng';

  @override
  String get export_role_assistant => '## 🤖 Trợ lý';

  @override
  String get export_role_system => '## ⚙️ Hệ thống';

  @override
  String get export_role_tool => '## 🔧 Công cụ';

  @override
  String get export_text_user => '[NGƯỜI DÙNG]';

  @override
  String get export_text_assistant => '[TRỢ LÝ]';

  @override
  String get export_text_system => '[HỆ THỐNG]';

  @override
  String get export_text_tool => '[CÔNG CỤ]';

  @override
  String get export_label_user => 'NGƯỜI DÙNG';

  @override
  String get export_label_assistant => 'TRỢ LÝ';

  @override
  String get export_label_system => 'HỆ THỐNG';

  @override
  String get export_label_tool => 'CÔNG CỤ';

  @override
  String get select_model_hint => 'Chọn mô hình để bắt đầu trò chuyện';

  @override
  String get test_notification_title => 'Thông báo thử nghiệm';

  @override
  String get test_notification_body =>
      'Đây là thông báo thử nghiệm về tiến độ tải mô hình.';

  @override
  String get tts_supports_background =>
      'Hỗ trợ phát âm thanh trong nền bằng trình phát hệ thống';

  @override
  String get tts_other_services_background_note =>
      'Lưu ý: Các dịch vụ chuyển văn bản thành giọng nói khác hỗ trợ phát âm thanh trong nền bằng trình phát gốc.';

  @override
  String get gguf_imported_models_title => 'Mô hình GGUF đã nhập';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Nhập tệp GGUF từ thiết bị hoặc thêm tệp từ Hugging Face. Mô hình đã nhập chạy cục bộ bằng llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      'mô hình đã nhập sẵn sàng suy luận cục bộ.';

  @override
  String get gguf_curated_models_subtitle =>
      'Các mô hình trên thiết bị được chọn lọc để bạn tải xuống và quản lý ngay trong LocalMind.';

  @override
  String get gguf_only_supported => 'Cách nhập này chỉ hỗ trợ mô hình GGUF.';

  @override
  String get gguf_imported_from_local_file => 'đã được nhập từ tệp cục bộ.';

  @override
  String get gguf_import_failed => 'Không thể nhập mô hình GGUF';

  @override
  String get gguf_imported_from_huggingface => 'đã được nhập từ Hugging Face.';

  @override
  String get gguf_import_canceled => 'Đã hủy nhập GGUF.';

  @override
  String get gguf_enter_huggingface_url =>
      'Nhập URL của tệp GGUF trên Hugging Face.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Chỉ hỗ trợ URL GGUF chính thức của Hugging Face.';

  @override
  String get gguf_use_https_url =>
      'Dùng URL HTTPS của Hugging Face để nhập GGUF.';

  @override
  String get gguf_url_must_point_to_file =>
      'URL Hugging Face phải trỏ trực tiếp đến tệp .gguf.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Không thể xác định tên tệp GGUF.';

  @override
  String get gguf_download_empty =>
      'Tệp GGUF đã tải xuống bị trống hoặc không tồn tại.';

  @override
  String get gguf_selected_file_missing => 'Tệp mô hình đã chọn không tồn tại.';

  @override
  String get gguf_import_action => 'Nhập GGUF';

  @override
  String get gguf_overview_title => 'Thêm hoặc nhập mô hình của bạn';

  @override
  String get gguf_overview_subtitle =>
      'Nhập mô hình GGUF hoặc LiteRT từ bộ nhớ cục bộ, từ URL hoặc tìm trên Hugging Face. Mô hình đã nhập được lưu trên thiết bị này.';

  @override
  String get gguf_imported_count_label => 'đã nhập';

  @override
  String get gguf_local_files_label => 'tệp cục bộ';

  @override
  String get gguf_huggingface_label => 'Hugging Face';

  @override
  String get gguf_import_local_title => 'Nhập tệp GGUF cục bộ';

  @override
  String get gguf_import_local_subtitle => 'Sao chép tệp .gguf từ thiết bị này';

  @override
  String get gguf_import_huggingface_title => 'Nhập từ Hugging Face';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Dán URL GGUF hoặc đường dẫn kho lưu trữ';

  @override
  String get gguf_no_imported_title => 'Chưa nhập mô hình GGUF nào';

  @override
  String get gguf_no_imported_subtitle =>
      'Bạn có thể dùng tệp GGUF của mình từ bộ nhớ thiết bị hoặc dán URL Hugging Face hay đường dẫn kho lưu trữ trỏ đến tệp .gguf.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Nhập GGUF từ Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Dán URL trực tiếp của tệp GGUF hoặc đường dẫn kho lưu trữ Hugging Face, ví dụ owner/repo/blob/main/model.gguf. Liên kết blob sẽ tự động được chuyển đổi.';

  @override
  String get gguf_url_or_repo_path => 'URL GGUF hoặc đường dẫn kho lưu trữ';

  @override
  String get paste => 'Dán';

  @override
  String get gguf_browse => 'Duyệt mô hình GGUF';

  @override
  String get gguf_huggingface_token_ready => 'Đã có mã truy cập Hugging Face';

  @override
  String get gguf_huggingface_token_optional => 'Khuyến nghị dùng mã truy cập';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Mã truy cập đã lưu sẽ tự động được dùng cho kho lưu trữ riêng tư hoặc bị giới hạn truy cập.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Yêu cầu mã truy cập Hugging Face. Hãy thêm mã trong Cài đặt nếu tệp GGUF này là riêng tư hoặc bị giới hạn truy cập.';

  @override
  String get gguf_downloading => 'Đang tải GGUF';

  @override
  String get gguf_preparing => 'Đang chuẩn bị';

  @override
  String get gguf_preparing_download => 'Đang chuẩn bị tải xuống…';

  @override
  String get gguf_cancel_import => 'Hủy nhập';

  @override
  String get clipboard_empty => 'Bảng nhớ tạm đang trống.';

  @override
  String get could_not_open_huggingface => 'Không thể mở Hugging Face.';

  @override
  String get gguf_paste_url_error =>
      'Dán URL GGUF từ Hugging Face hoặc đường dẫn kho lưu trữ.';

  @override
  String get gguf_blob_link => 'Liên kết blob';

  @override
  String get gguf_repository_label => 'Kho lưu trữ';

  @override
  String get gguf_detected_path_label => 'Đường dẫn đã phát hiện';

  @override
  String get gguf_imported_section_label => 'GGUF đã nhập';

  @override
  String get gguf_already_available => 'Đã có trên thiết bị này';

  @override
  String get gguf_curated_models_short => 'Mô hình trên thiết bị được chọn lọc';

  @override
  String get gguf_vision_projector => 'Bộ chiếu ảnh';

  @override
  String get gguf_attach_projector => 'Gắn bộ chiếu ảnh';

  @override
  String get gguf_change_projector => 'Đổi bộ chiếu ảnh';

  @override
  String get gguf_remove_projector => 'Gỡ bộ chiếu';

  @override
  String get gguf_projector_attached => 'Đã gắn bộ chiếu ảnh';

  @override
  String get gguf_projector_removed => 'Đã gỡ bộ chiếu ảnh';

  @override
  String gguf_projector_auto_detected(String name) {
    return 'Đã tự động phát hiện và liên kết bộ chiếu ảnh: $name';
  }

  @override
  String get gguf_is_projector_file =>
      'Tệp đã chọn là bộ chiếu ảnh (mmproj), không phải mô hình độc lập.';

  @override
  String get gguf_projector_url_label =>
      'URL bộ chiếu ảnh (mmproj, không bắt buộc)';

  @override
  String get gguf_projector_url_hint =>
      'https://huggingface.co/.../mmproj-...gguf';

  @override
  String get gguf_vision_not_supported_error =>
      'Mô hình đang dùng không hỗ trợ ảnh đính kèm. Hãy gắn bộ chiếu ảnh (mmproj) hoặc chọn mô hình hỗ trợ ảnh.';

  @override
  String get execute_tool_title => 'Chạy công cụ';

  @override
  String get execute_tool_request_desc => 'Mô hình yêu cầu chạy công cụ sau:';

  @override
  String get reject => 'Từ chối';

  @override
  String get approve => 'Chấp thuận';

  @override
  String get server_type_help =>
      'Chọn nhà cung cấp trước khi điền thông tin kết nối.';

  @override
  String get server_identity_title => 'Nhận dạng';

  @override
  String get server_identity_desc =>
      'Đặt tên cho máy chủ và chọn cách hiển thị trong danh sách.';

  @override
  String get server_connection_title => 'Kết nối';

  @override
  String get server_connection_desc =>
      'Dùng địa chỉ và cổng do máy chủ cung cấp.';

  @override
  String get server_authentication_title => 'Xác thực';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter yêu cầu khóa API trước khi kiểm tra kết nối.';

  @override
  String get server_authentication_required_desc_requesty =>
      'Requesty yêu cầu khóa API trước khi kiểm tra kết nối.';

  @override
  String get server_authentication_required_desc_standard_compute =>
      'Standard Compute yêu cầu khóa API trước khi kiểm tra kết nối.';

  @override
  String get server_authentication_optional_desc =>
      'Để trống khóa API nếu máy chủ không yêu cầu.';

  @override
  String get mcp_tools_title => 'Công cụ MCP';

  @override
  String get available_tools => 'Công cụ khả dụng';

  @override
  String get unable_load_tools => 'Không thể tải danh sách công cụ';

  @override
  String get no_tools_registered => 'Chưa đăng ký công cụ nào';

  @override
  String get no_tools_registered_desc =>
      'Bật máy chủ MCP mẫu hoặc thêm tích hợp MCP trong cài đặt trò chuyện.';

  @override
  String get example_mcp_server_title => 'Máy chủ MCP mẫu';

  @override
  String get example_mcp_server_desc =>
      'Đăng ký example.echo và example.word_count qua cùng trình cung cấp công cụ MCP mà các máy chủ bên ngoài sử dụng.';

  @override
  String get disable_example_server => 'Tắt máy chủ mẫu';

  @override
  String get enable_example_server => 'Bật máy chủ mẫu';

  @override
  String get built_in_label => 'Có sẵn';

  @override
  String get highlights_label => 'Điểm nổi bật';

  @override
  String get built_with_label => 'Được xây dựng bằng';

  @override
  String get local_label => 'Cục bộ';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => 'Đã yêu cầu';

  @override
  String get tool_status_approved => 'Đã chấp thuận';

  @override
  String get tool_status_rejected => 'Đã từ chối';

  @override
  String get tool_status_running => 'Đang chạy';

  @override
  String get tool_status_done => 'Xong';

  @override
  String get tool_status_failed => 'Thất bại';

  @override
  String get model_favorite_toggle => 'Thêm vào hoặc bỏ khỏi mục yêu thích';

  @override
  String get model_set_default => 'Đặt làm mô hình mặc định';

  @override
  String get model_clear_default => 'Bỏ đặt làm mô hình mặc định';

  @override
  String get model_default_badge => 'Mặc định';

  @override
  String get model_note_label => 'Ghi chú';

  @override
  String get model_note_hint => 'Thêm ghi chú về mô hình này…';

  @override
  String get model_update_available => 'Có bản cập nhật';

  @override
  String get model_update_button => 'Cập nhật';

  @override
  String get unload_models_before_load =>
      'Giải phóng tất cả mô hình trước khi nạp mô hình mới';

  @override
  String get settings_allow_background_downloads =>
      'Cho phép tải xuống trong nền';

  @override
  String get settings_allow_background_downloads_desc =>
      'Tiếp tục tải mô hình khi bạn chuyển ứng dụng hoặc khóa màn hình.';

  @override
  String get settings_download_over_wifi_only => 'Chỉ tải xuống qua Wi‑Fi';

  @override
  String get settings_download_over_wifi_only_desc =>
      'Chỉ tải mô hình khi có kết nối Wi‑Fi phù hợp hoặc kết nối không giới hạn dữ liệu.';

  @override
  String get temp_chat_keyboard_incognito =>
      'Bàn phím ẩn danh trong cuộc trò chuyện tạm thời';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Tắt tính năng học và gợi ý của bàn phím trong cuộc trò chuyện tạm thời (ví dụ: chế độ ẩn danh SwiftKey).';

  @override
  String get resume_last_chat =>
      'Mở lại cuộc trò chuyện gần nhất khi khởi động';

  @override
  String get resume_last_chat_desc =>
      'Khôi phục cuộc trò chuyện mở gần nhất khi bạn mở lại ứng dụng.';

  @override
  String get export_all_data => 'Xuất tất cả dữ liệu';

  @override
  String get import_all_data => 'Nhập tất cả dữ liệu';

  @override
  String get export_data_success => 'Đã xuất bản sao lưu';

  @override
  String get import_data_success => 'Đã nhập bản sao lưu';

  @override
  String import_data_failed(String error) {
    return 'Không thể nhập bản sao lưu: $error';
  }

  @override
  String get import_data_confirm =>
      'Nhập cuộc trò chuyện và nhân vật tùy chỉnh từ bản sao lưu này? Các mục hiện có cùng ID sẽ được cập nhật.';

  @override
  String get import_settings_confirm =>
      'Thay thế cài đặt hiện tại bằng cài đặt từ bản sao lưu?';

  @override
  String get export_conversations => 'Xuất cuộc trò chuyện';

  @override
  String get import_conversations => 'Nhập cuộc trò chuyện';

  @override
  String get export_personas => 'Xuất nhân vật';

  @override
  String get import_personas => 'Nhập nhân vật';

  @override
  String get export_settings => 'Xuất cài đặt';

  @override
  String get import_settings => 'Nhập cài đặt';

  @override
  String get export_all_zip => 'Xuất tất cả (ZIP)';

  @override
  String get import_all_zip => 'Nhập tất cả (ZIP)';

  @override
  String get duplicate_chat => 'Nhân bản cuộc trò chuyện';

  @override
  String get duplicate_chat_success => 'Đã nhân bản cuộc trò chuyện';

  @override
  String get move_to_folder => 'Chuyển vào thư mục';

  @override
  String get remove_from_folder => 'Gỡ khỏi thư mục';

  @override
  String get create_folder => 'Tạo thư mục';

  @override
  String get new_folder => 'Thư mục mới';

  @override
  String get folder_name_hint => 'Tên thư mục';

  @override
  String get all_chats => 'Tất cả';

  @override
  String get unfiled_chats => 'Chưa xếp vào thư mục';

  @override
  String get create => 'Tạo';

  @override
  String get server_path_prefix_label => 'Tiền tố đường dẫn API';

  @override
  String get server_path_prefix_hint => '/your-secret-token';

  @override
  String get search_message_contents => 'Tìm trong nội dung tin nhắn';

  @override
  String get message_search_results => 'Tin nhắn phù hợp';

  @override
  String get saved_messages_title => 'Tin nhắn đã lưu';

  @override
  String get nav_saved_messages => 'Tin nhắn đã lưu';

  @override
  String get saved_messages_empty =>
      'Chưa có tin nhắn đã lưu. Hãy đánh dấu một tin nhắn từ menu tùy chọn của tin đó.';

  @override
  String get save_message => 'Lưu tin nhắn';

  @override
  String get message_saved => 'Đã lưu tin nhắn';

  @override
  String token_count(int count) {
    return '$count token';
  }

  @override
  String estimated_token_count(int count) {
    return 'Khoảng $count token';
  }

  @override
  String get test_tts_section_title => 'Thử giọng nói';

  @override
  String get test_tts_hint =>
      'Nhập văn bản để nghe bộ tổng hợp giọng nói hiện tại…';

  @override
  String get test_speak_button => 'Đọc';

  @override
  String get scroll_to_bottom => 'Cuộn xuống cuối';

  @override
  String get generate_ai_response => 'Tạo phản hồi bằng AI';

  @override
  String get no_response => 'Không có phản hồi';

  @override
  String get export => 'Xuất';

  @override
  String get import => 'Nhập';

  @override
  String get conversations_label => 'Cuộc trò chuyện';

  @override
  String get personas_label => 'Nhân vật';

  @override
  String get settings_label => 'Cài đặt';

  @override
  String get export_conversation => 'Xuất cuộc trò chuyện';

  @override
  String get tts_process_markdown => 'Xử lý Markdown khi đọc';

  @override
  String get tts_process_markdown_desc =>
      'Bỏ định dạng như **chữ đậm** trước khi đọc to';

  @override
  String get tts_skip_seconds => 'Khoảng tua';

  @override
  String get tts_skip_seconds_desc =>
      'Khoảng thời gian tua tới hoặc lui khi phát';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$seconds giây';
  }

  @override
  String get preview_system_prompts => 'Xem trước lời nhắc hệ thống';

  @override
  String get welcome_message_1 => 'Hôm nay tôi có thể giúp gì cho bạn?';

  @override
  String get welcome_message_2 =>
      'Bạn cứ hỏi bất cứ điều gì. Tôi sẵn sàng khi bạn muốn.';

  @override
  String get welcome_message_3 =>
      'Dữ liệu của bạn được xử lý cục bộ và luôn ở trên thiết bị.';

  @override
  String get welcome_message_4 =>
      'Bạn cần ý tưởng? Hãy thử một trong các lời nhắc nhanh.';

  @override
  String get temporary_chat => 'Cuộc trò chuyện tạm thời';

  @override
  String get temporary_chat_desc =>
      'Các cuộc trò chuyện sẽ không được lưu vào lịch sử.';

  @override
  String get temporary_chat_banner =>
      'Cuộc trò chuyện tạm thời · không lưu vào lịch sử';

  @override
  String get temporary_chat_save_warning_title =>
      'Lưu tin nhắn trong cuộc trò chuyện tạm thời?';

  @override
  String get temporary_chat_save_warning_body =>
      'Cuộc trò chuyện này là tạm thời và không hiện trong lịch sử. Tin nhắn đã lưu vẫn sẽ xuất hiện trong mục Tin nhắn đã lưu.';

  @override
  String get save_to_history => 'Lưu vào lịch sử';

  @override
  String get share_conversation => 'Chia sẻ cuộc trò chuyện';

  @override
  String get download_tts_audio => 'Tải âm thanh';

  @override
  String get tts_download_unavailable =>
      'Chỉ có thể tải xuống âm thanh từ Piper và Kitten TTS';

  @override
  String get tts_download_no_audio => 'Chưa có âm thanh để tải xuống';

  @override
  String get tts_download_success => 'Đã lưu âm thanh';

  @override
  String get return_to_chat => 'Quay lại cuộc trò chuyện';

  @override
  String get return_to_temp_chat => 'Quay lại cuộc trò chuyện tạm thời';

  @override
  String get insert_saved_message => 'Chèn tin nhắn đã lưu';

  @override
  String get insert_saved_message_desc =>
      'Chọn tin nhắn đã lưu để thêm vào ô soạn tin';

  @override
  String get model_info => 'Thông tin mô hình';

  @override
  String get model_name => 'Tên mô hình';

  @override
  String get model_identifier => 'Mã định danh';

  @override
  String get model_capabilities => 'Tính năng';

  @override
  String get model_api_pricing => 'Giá API (mỗi 1 triệu token)';

  @override
  String get not_available => 'Không có';

  @override
  String get save_message_folders => 'Lưu tin nhắn';

  @override
  String get remove_from_saved => 'Bỏ lưu';

  @override
  String get message_already_saved => 'Đã lưu';

  @override
  String get stream_ttft => 'Thời gian đến token đầu tiên';

  @override
  String get stream_tokens_per_sec => 'Token mỗi giây';

  @override
  String get stream_stop_reason => 'Lý do dừng';

  @override
  String get stream_input_tokens => 'Token đầu vào';

  @override
  String get stream_output_tokens => 'Token đầu ra';

  @override
  String get stream_generation_time => 'Thời gian tạo phản hồi';

  @override
  String get attach_image => 'Ảnh';

  @override
  String get attach_text_document => 'Tài liệu';

  @override
  String get attach_shortcut_camera => 'Máy ảnh';

  @override
  String get attach_shortcut_images => 'Ảnh';

  @override
  String get attach_shortcut_documents => 'Tệp';

  @override
  String get attach_shortcut_saved => 'Đã lưu';

  @override
  String get add_attachment => 'Thêm tệp đính kèm';

  @override
  String get add_to_chat => 'Thêm vào cuộc trò chuyện';

  @override
  String get choose_what_to_attach => 'Bạn muốn thêm gì?';

  @override
  String get choose_attachment_subtitle =>
      'Chọn nguồn tệp đính kèm cho tin nhắn';

  @override
  String get photo_permission_denied =>
      'Cần quyền truy cập ảnh để đính kèm hình ảnh';

  @override
  String get select_model_prompt => 'Chọn mô hình';

  @override
  String get characters_label => 'Ký tự';

  @override
  String get exit_temporary_chat_title => 'Thoát cuộc trò chuyện tạm thời?';

  @override
  String get exit_temporary_chat_body =>
      'Thao tác này sẽ bỏ cuộc trò chuyện tạm thời hiện tại và mở cuộc trò chuyện mới.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Tin nhắn này được lưu từ một cuộc trò chuyện tạm thời và không thể mở trong cuộc trò chuyện ban đầu.';

  @override
  String get filter_title => 'Lọc';

  @override
  String get filter_pinned => 'Đã ghim';

  @override
  String get filter_archived => 'Đã lưu trữ';

  @override
  String get filter_temp_chats => 'Cuộc trò chuyện tạm thời';

  @override
  String get filter_user_messages => 'Tin nhắn người dùng';

  @override
  String get filter_assistant_messages => 'Tin nhắn của trợ lý';

  @override
  String get archive_chat => 'Lưu trữ';

  @override
  String get unarchive_chat => 'Bỏ lưu trữ';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tin nhắn',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return '$count ký tự';
  }

  @override
  String get generate_title_with_ai => 'Tạo bằng AI';

  @override
  String get generating_title => 'Đang tạo…';

  @override
  String get generate_title_failed => 'Không thể tạo tiêu đề';

  @override
  String get lm_studio_model_browser_title => 'Duyệt mô hình';

  @override
  String get lm_studio_model_search_hint =>
      'Tìm mô hình theo tên hoặc tác giả…';

  @override
  String get lm_studio_staff_picks => 'Đề xuất của đội ngũ';

  @override
  String get lm_studio_community_models => 'Mô hình cộng đồng';

  @override
  String get lm_studio_no_models => 'Không tìm thấy mô hình';

  @override
  String lm_studio_models_count(int count) {
    return '$count mô hình';
  }

  @override
  String get lm_studio_browse_models => 'Duyệt và tải xuống';

  @override
  String get lm_studio_model_search => 'Tìm mô hình LMS';

  @override
  String get lm_studio_downloads_title => 'Tệp tải xuống';

  @override
  String get lm_studio_choose_quant => 'Chọn tùy chọn tải xuống';

  @override
  String get lm_studio_use_default_quant => 'Dùng mặc định';

  @override
  String get lm_studio_recommended => 'Khuyến nghị';

  @override
  String get lm_studio_clear_downloads => 'Xóa mục đã hoàn tất';

  @override
  String get lm_studio_no_downloads => 'Chưa có lượt tải xuống';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Quá trình tải xuống chạy trên máy chủ LM Studio. Bạn phải tạm dừng, dừng hoặc xóa mô hình trực tiếp trên máy tính đó.';

  @override
  String get lm_studio_staff_pick => 'Đề xuất của đội ngũ';

  @override
  String get lm_studio_params => 'THÔNG SỐ';

  @override
  String get lm_studio_arch => 'KIẾN TRÚC';

  @override
  String get lm_studio_domain => 'LĨNH VỰC';

  @override
  String get lm_studio_format => 'ĐỊNH DẠNG';

  @override
  String get lm_studio_vision => 'Thị giác';

  @override
  String get lm_studio_tool_use => 'Sử dụng công cụ';

  @override
  String get lm_studio_reasoning => 'Suy luận';

  @override
  String get openrouter_pricing_free => 'Miễn phí';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Đầu vào $input / đầu ra $output trên mỗi 1 triệu token';
  }

  @override
  String get lm_studio_download_options => 'Tùy chọn tải xuống';

  @override
  String get lm_studio_download => 'Tải xuống';

  @override
  String lm_studio_download_size(String size) {
    return 'Tải xuống ($size)';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Đang tải xuống $percent%';
  }

  @override
  String get lm_studio_readme_unavailable => 'Mô hình này không có tệp README.';

  @override
  String get lm_studio_full_gpu_offload =>
      'Có thể chuyển toàn bộ xử lý sang GPU';

  @override
  String get lm_studio_partial_gpu_offload =>
      'Có thể chuyển một phần xử lý sang GPU';

  @override
  String get lm_studio_likely_too_large => 'Có thể quá lớn';

  @override
  String get lm_studio_available_ram_gb => 'RAM khả dụng (GB, không bắt buộc)';

  @override
  String get lm_studio_available_vram_gb =>
      'VRAM khả dụng (GB, không bắt buộc)';

  @override
  String get lm_studio_memory_settings_title => 'Bộ nhớ dùng để đề xuất';

  @override
  String get lm_studio_memory_settings_desc =>
      'Dùng để ước tính xem máy tính có đủ bộ nhớ cho các mô hình trong trình duyệt mô hình hay không.';

  @override
  String get think_button_label => 'Suy luận';

  @override
  String get thinking_mode_title => 'Chế độ suy luận';

  @override
  String get reasoning_effort_low => 'Thấp';

  @override
  String get reasoning_effort_medium => 'Trung bình';

  @override
  String get reasoning_effort_high => 'Cao';

  @override
  String get reasoning_effort_minimal => 'Tối thiểu';

  @override
  String get reasoning_effort_xhigh => 'Rất cao';

  @override
  String get reasoning_effort_max => 'Tối đa';

  @override
  String get reasoning_effort_off => 'Tắt';

  @override
  String get could_not_read_file => 'Không thể đọc tệp';

  @override
  String get server_offline => 'Máy chủ đang ngoại tuyến';

  @override
  String get could_not_establish_connection =>
      'Không thể kết nối với máy chủ. Hãy kiểm tra xem máy chủ có đang chạy và địa chỉ máy chủ cùng cổng có đúng không.';

  @override
  String get retry_connection => 'Kết nối lại';

  @override
  String get tokens_label => 'Token';

  @override
  String get enter_context_length => 'Nhập độ dài ngữ cảnh…';

  @override
  String get openrouter_disclosure =>
      'Khi kết nối với nhà cung cấp này, tin nhắn và dữ liệu bạn nhập sẽ được gửi đến máy chủ của họ. LocalMind không theo dõi hay lưu các cuộc trò chuyện của bạn.';

  @override
  String get requesty_disclosure =>
      'Khi kết nối với nhà cung cấp này, tin nhắn và dữ liệu bạn nhập sẽ được gửi đến máy chủ của họ. LocalMind không theo dõi hay lưu các cuộc trò chuyện của bạn.';

  @override
  String get standard_compute_disclosure =>
      'Khi kết nối với nhà cung cấp này, tin nhắn và dữ liệu bạn nhập sẽ được gửi đến máy chủ của họ. LocalMind không theo dõi hay lưu các cuộc trò chuyện của bạn.';

  @override
  String get welcome_message_cloud =>
      'Tin nhắn của bạn được gửi tới nhà cung cấp đã kết nối.';

  @override
  String get privacy_policy => 'Chính sách quyền riêng tư';

  @override
  String get cloud_sync => 'Đồng bộ đám mây S3';

  @override
  String get cloud_sync_description =>
      'Đồng bộ hóa mã hóa đầu cuối với máy chủ tương thích S3 của bạn';

  @override
  String get cloud_sync_endpoint => 'URL điểm cuối';

  @override
  String get cloud_sync_bucket => 'Vùng lưu trữ (bucket)';

  @override
  String get cloud_sync_region => 'Khu vực';

  @override
  String get cloud_sync_prefix => 'Tiền tố';

  @override
  String get cloud_sync_access_key => 'ID khóa truy cập';

  @override
  String get cloud_sync_secret_key => 'Khóa truy cập bí mật';

  @override
  String get cloud_sync_session_token => 'Mã phiên (không bắt buộc)';

  @override
  String get cloud_sync_passphrase => 'Cụm mật khẩu mã hóa';

  @override
  String get cloud_sync_confirm_passphrase => 'Xác nhận cụm mật khẩu';

  @override
  String get cloud_sync_path_style => 'Dùng kiểu địa chỉ theo đường dẫn';

  @override
  String get cloud_sync_allow_http => 'Cho phép HTTP không bảo mật';

  @override
  String get cloud_sync_http_warning =>
      'HTTP làm lộ siêu dữ liệu yêu cầu và thông tin xác thực trên mạng. Chỉ dùng cho máy chủ S3 cục bộ đáng tin cậy.';

  @override
  String get cloud_sync_test => 'Kiểm tra kết nối';

  @override
  String get cloud_sync_enable => 'Bật đồng bộ hóa có mã hóa';

  @override
  String get cloud_sync_now => 'Đồng bộ ngay';

  @override
  String get cloud_sync_disconnect => 'Ngắt kết nối thiết bị này';

  @override
  String get cloud_sync_last_synced => 'Đồng bộ lần cuối';

  @override
  String get cloud_sync_never => 'Chưa từng';

  @override
  String get cloud_sync_conflicts => 'Đã giữ lại các phiên bản xung đột';

  @override
  String get cloud_sync_passphrase_mismatch => 'Cụm mật khẩu không khớp';

  @override
  String get crash_report_title => 'Đã xảy ra lỗi';

  @override
  String get crash_report_stack_trace => 'Dấu vết ngăn xếp';

  @override
  String get crash_report_tap_to_expand => 'Nhấn để mở rộng';

  @override
  String get crash_report_button => 'Báo cáo sự cố này';

  @override
  String get crash_try_again => 'Thử lại';

  @override
  String get crash_report_empty_stack => '<trống>';

  @override
  String get crash_report_disclaimer =>
      'Thao tác báo cáo sẽ mở GitHub với thông tin chẩn đoán được điền sẵn. Không có nội dung nào tự động được gửi đi. Hãy kiểm tra và xóa thông tin nhạy cảm trước khi gửi.';

  @override
  String get crash_report_copied => 'Đã sao chép vào bảng nhớ tạm';

  @override
  String get report_a_problem => 'Báo cáo vấn đề';

  @override
  String get rename_folder => 'Đổi tên thư mục';

  @override
  String get delete_folder => 'Xóa thư mục';

  @override
  String get delete_folder_title => 'Xóa thư mục?';

  @override
  String delete_folder_body(String name) {
    return 'Bạn có chắc muốn xóa “$name” không? Các cuộc trò chuyện hoặc tin nhắn đã lưu trong thư mục sẽ được chuyển về mục “Chưa xếp vào thư mục”. Không thể hoàn tác thao tác này.';
  }

  @override
  String get folder_name_required => 'Hãy nhập tên thư mục';

  @override
  String get model_required_toast => 'Trước tiên, bạn cần chọn mô hình';

  @override
  String get settings_concise_voice_responses =>
      'Phản hồi ngắn gọn trong chế độ giọng nói';

  @override
  String get settings_concise_voice_responses_desc =>
      'Giữ phản hồi của mô hình ngắn gọn (một đoạn ngắn) và đặt câu hỏi tiếp nối trong chế độ giọng nói.';

  @override
  String get s3_connection_succeeded => 'Đã kết nối thành công với S3.';

  @override
  String failed_to_open_url(String error) {
    return 'Không thể mở URL: $error';
  }

  @override
  String failed_to_copy(String error) {
    return 'Không thể sao chép: $error';
  }

  @override
  String get file_explorer_not_found =>
      'Không tìm thấy trình quản lý tệp. Hãy đảm bảo thiết bị đã cài đặt và bật ứng dụng quản lý tệp.';

  @override
  String export_data_failed(String error) {
    return 'Không thể xuất bản sao lưu: $error';
  }

  @override
  String file_pick_failed(String error) {
    return 'Không thể chọn tệp: $error';
  }

  @override
  String image_pick_failed(String error) {
    return 'Không thể chọn ảnh: $error';
  }

  @override
  String get calendar_access => 'Truy cập lịch';

  @override
  String get calendar_access_desc => 'Cho phép AI đọc và tạo sự kiện trên lịch';

  @override
  String get calendar_permission_denied =>
      'Quyền truy cập lịch bị từ chối. Hãy cấp quyền truy cập lịch trong cài đặt thiết bị.';

  @override
  String get location_access => 'Truy cập vị trí';

  @override
  String get location_access_desc =>
      'Cho phép AI lấy vị trí hiện tại và tên địa điểm của bạn';

  @override
  String get location_permission_denied =>
      'Quyền truy cập vị trí bị từ chối. Hãy cấp quyền truy cập vị trí trong cài đặt thiết bị.';

  @override
  String get builtin_ai_not_supported =>
      'Thiết bị này không hỗ trợ AI tích hợp.';

  @override
  String get builtin_ai_unsupported_desc =>
      'Phần cứng hoặc hệ điều hành của bạn không hỗ trợ AI hệ thống trên thiết bị (ví dụ: Gemini Nano hoặc Apple Intelligence). Hãy chọn một mô hình có thể tải xuống.';

  @override
  String get builtin_ai_unsupported_chip => 'Không được hỗ trợ';

  @override
  String get builtin_ai_enable => 'Bật';

  @override
  String get model_reasoning_default => 'Mặc định của mô hình';

  @override
  String get model_reasoning_on => 'Bật';

  @override
  String get model_reasoning_help =>
      'Áp dụng cho phản hồi tiếp theo. Tùy chọn “Tắt” sẽ tắt suy luận nếu mẫu trò chuyện của mô hình hỗ trợ.';

  @override
  String get model_reasoning_save_error =>
      'Không thể lưu chế độ suy luận. Hãy thử lại.';

  @override
  String get on_device_engine_failed_error =>
      'Mô hình trên thiết bị ngừng phản hồi, thường là do cuộc trò chuyện vượt quá cửa sổ ngữ cảnh. Mô hình đang được nạp lại. Hãy thử lại, bắt đầu cuộc trò chuyện mới hoặc tăng độ dài ngữ cảnh trong phần Cài đặt.';

  @override
  String get stt_error_no_match =>
      'Không nhận dạng được lời nói. Nhấn để thử lại.';

  @override
  String get stt_error_speech_timeout =>
      'Không phát hiện lời nói. Nhấn để thử lại.';

  @override
  String get stt_error_permission => 'Quyền truy cập micrô bị từ chối.';

  @override
  String get stt_error_busy =>
      'Dịch vụ nhận dạng giọng nói đang bận. Hãy thử lại.';

  @override
  String get stt_error_network => 'Lỗi mạng. Hãy kiểm tra kết nối rồi thử lại.';

  @override
  String get stt_error_audio => 'Lỗi ghi âm. Hãy kiểm tra micrô.';

  @override
  String get stt_error_client =>
      'Không thể khởi động dịch vụ nhận dạng giọng nói. Hãy đảm bảo đã cài đặt và đặt một ứng dụng nhập bằng giọng nói làm trình nhận dạng mặc định, sau đó thử lại.';

  @override
  String get stt_error_language =>
      'Trình nhận dạng giọng nói trên thiết bị này không hỗ trợ ngôn ngữ của bạn.';

  @override
  String get stt_error_unavailable =>
      'Không tìm thấy dịch vụ nhận dạng giọng nói trên thiết bị này. Hãy cài đặt ứng dụng nhập bằng giọng nói (ví dụ: FUTO Voice Input) và đặt làm trình nhận dạng mặc định.';

  @override
  String stt_error_generic(String code) {
    return 'Lỗi nhận dạng giọng nói: $code';
  }

  @override
  String get send_temperature_to_api => 'Gửi giá trị nhiệt độ';

  @override
  String get send_top_p_to_api => 'Gửi giá trị Top P';

  @override
  String get send_sampling_params_desc =>
      'Tắt tùy chọn này với các nhà cung cấp hoặc mô hình từ chối thông số này (ví dụ: một số mô hình suy luận). Áp dụng cho mọi cuộc trò chuyện với máy chủ từ xa.';

  @override
  String get default_system_prompt => 'Lời nhắc hệ thống mặc định';

  @override
  String get default_system_prompt_desc =>
      'Dùng cho các cuộc trò chuyện chưa chọn nhân vật và không có lời nhắc hệ thống riêng.';

  @override
  String get default_system_prompt_hint => 'Bạn là một trợ lý hữu ích…';

  @override
  String background_generation_notice(String title) {
    return '“$title” vẫn đang tạo phản hồi. Bạn có thể gửi tin nhắn ở đây khi phản hồi đó hoàn tất. Nhấn để mở cuộc trò chuyện.';
  }

  @override
  String get background_generation_notice_untitled =>
      'Một cuộc trò chuyện khác vẫn đang tạo phản hồi. Bạn có thể gửi tin nhắn ở đây khi phản hồi đó hoàn tất. Nhấn để mở cuộc trò chuyện.';

  @override
  String background_generation_notice_info(String title) {
    return '“$title” đang tạo phản hồi trong nền. Nhấn để mở cuộc trò chuyện.';
  }

  @override
  String get background_generation_notice_info_untitled =>
      'Một cuộc trò chuyện khác đang tạo phản hồi trong nền. Nhấn để mở cuộc trò chuyện.';

  @override
  String background_generation_notice_multiple(int count) {
    return '$count cuộc trò chuyện đang tạo phản hồi trong nền.';
  }

  @override
  String get background_generation_chat_untitled =>
      'Cuộc trò chuyện chưa có tiêu đề';

  @override
  String get model_loaded_status => 'Đã nạp';

  @override
  String get new_chat_title => 'Hỏi bất cứ điều gì.';

  @override
  String get new_chat_on_device_headline =>
      'Mọi thứ đều ở trên điện thoại này.';

  @override
  String get new_chat_on_device_detail =>
      'Phản hồi được tạo ngay trên thiết bị. Không tải dữ liệu lên, không cần tài khoản và hoạt động ngoại tuyến.';

  @override
  String new_chat_self_hosted_headline(String server) {
    return 'Phản hồi từ $server.';
  }

  @override
  String get new_chat_self_hosted_detail =>
      'Tin nhắn chỉ được gửi đến máy chủ của bạn.';

  @override
  String new_chat_endpoint_detail(String server) {
    return 'Tin nhắn được gửi đến $server, điểm cuối tương thích với OpenAI.';
  }

  @override
  String get new_chat_cloud_headline => 'Phản hồi từ đám mây.';

  @override
  String new_chat_router_detail(String provider) {
    return 'Tin nhắn được gửi đến $provider và nhà cung cấp mô hình mà dịch vụ này định tuyến đến.';
  }

  @override
  String get new_chat_ollama_cloud_detail =>
      'Tin nhắn được gửi đến dịch vụ đám mây của Ollama.';

  @override
  String get new_chat_no_server_headline => 'Chọn một mô hình để bắt đầu.';

  @override
  String get new_chat_no_server_detail =>
      'Chạy mô hình trên điện thoại này hoặc kết nối với máy chủ.';

  @override
  String get new_chat_works_offline => 'Hoạt động ngoại tuyến';

  @override
  String get new_chat_no_model => 'Chưa chọn mô hình';

  @override
  String get new_chat_not_connected => 'Chưa kết nối';

  @override
  String get attach_send_as_assistant => 'Gửi với vai trò trợ lý';

  @override
  String get attach_send_as_assistant_desc =>
      'Thêm tin nhắn của bạn làm phản hồi mà không tạo nội dung mới.';

  @override
  String get chat_input_hint_assistant => 'Viết câu trả lời của trợ lý';

  @override
  String get settings_section_general => 'Chung';

  @override
  String get settings_section_chat => 'Trò chuyện';

  @override
  String get settings_section_voice => 'Giọng nói';

  @override
  String get settings_section_models => 'Mô hình';

  @override
  String get settings_section_data => 'Quyền riêng tư và dữ liệu';

  @override
  String get settings_search_hint => 'Tìm trong cài đặt';

  @override
  String get settings_more_chat_options => 'Thêm tùy chọn trò chuyện';

  @override
  String get settings_group_replies => 'Phản hồi';

  @override
  String get settings_group_prompt => 'Lời nhắc hệ thống và thông số';

  @override
  String get settings_group_composer => 'Ô soạn tin';

  @override
  String get sidebar_section_chats => 'Cuộc trò chuyện';

  @override
  String get sidebar_section_models => 'Mô hình';

  @override
  String get sidebar_section_app => 'Ứng dụng';

  @override
  String get add_models_button => 'Thêm mô hình';

  @override
  String get curated_models_title => 'Mô hình chọn lọc';

  @override
  String curated_models_count(Object count) {
    return '$count mô hình';
  }

  @override
  String get your_models_title => 'Mô hình của bạn';

  @override
  String your_models_count(Object count) {
    return 'Đã thêm $count';
  }

  @override
  String get remove_model_from_list => 'Xóa khỏi danh sách';

  @override
  String get delete_model_file_first => 'Xóa tệp mô hình trước';

  @override
  String get add_model_title => 'Thêm mô hình';

  @override
  String get add_model_gguf_tab => 'GGUF';

  @override
  String get add_model_litert_tab => 'LiteRT';

  @override
  String get add_model_gguf_url_label => 'URL GGUF trên Hugging Face';

  @override
  String get add_model_litert_url_label => 'URL LiteRT trên Hugging Face';

  @override
  String get add_model_add_from_url => 'Thêm từ URL';

  @override
  String get add_model_pick_local_file => 'Chọn tệp cục bộ';

  @override
  String get add_model_search_gguf => 'Tìm mô hình GGUF';

  @override
  String get add_model_search_litert => 'Tìm mô hình LiteRT';

  @override
  String get add_model_searching => 'Đang tìm kiếm…';

  @override
  String get add_model_search => 'Tìm kiếm';

  @override
  String get add_model_loading_files => 'Đang tải danh sách tệp…';

  @override
  String get add_model_cancel => 'Hủy';

  @override
  String add_model_files_in(Object repo) {
    return 'Tệp trong $repo';
  }

  @override
  String get add_model_no_gguf_files => 'Không tìm thấy tệp GGUF.';

  @override
  String get add_model_no_litert_files => 'Không tìm thấy tệp LiteRT.';

  @override
  String get add_model_added => 'Đã thêm';

  @override
  String get add_model_add => 'Thêm';

  @override
  String get add_model_gguf_added => 'Đã thêm mô hình GGUF';

  @override
  String get add_model_litert_added => 'Đã thêm mô hình LiteRT';

  @override
  String add_model_file_added(Object name) {
    return 'Đã thêm $name';
  }

  @override
  String get add_model_already_added => 'Mô hình đã được thêm';

  @override
  String get model_still_stopping =>
      'Mô hình vẫn đang dừng. Hãy đợi rồi thử lại.';

  @override
  String get localApiTitle => 'API cục bộ';

  @override
  String get localApiIntro =>
      'Dùng mô hình đã nạp trong các ứng dụng khác qua API tương thích với OpenAI. Hãy khởi động máy chủ trước khi chuyển ứng dụng.';

  @override
  String get localApiRunning => 'API cục bộ đang chạy';

  @override
  String get localApiStopped => 'Máy chủ đã dừng';

  @override
  String get localApiStarting => 'Đang khởi động máy chủ…';

  @override
  String get localApiStopping => 'Đang dừng máy chủ…';

  @override
  String get localApiRotating => 'Đang thay khóa API…';

  @override
  String get localApiModelRequired =>
      'Trước tiên hãy nạp một mô hình LiteRT đã tải xuống hoặc GGUF đã nhập.';

  @override
  String get localApiInvalidPort => 'Nhập cổng từ 1024 đến 65535.';

  @override
  String get localApiStartFailed =>
      'Android không thể khởi động máy chủ. Hãy thử lại khi LocalMind đang mở.';

  @override
  String get localApiPortUnavailable =>
      'Không thể lắng nghe trên cổng này. Hãy thử cổng khác.';

  @override
  String get localApiKeyFailed => 'Không thể truy cập khóa API.';

  @override
  String get localApiModelId => 'ID mô hình';

  @override
  String get localApiTextAndTools => 'Văn bản và lệnh gọi công cụ';

  @override
  String get localApiTextOnly => 'Chỉ văn bản';

  @override
  String get localApiPort => 'Cổng';

  @override
  String get localApiLan => 'Cho phép thiết bị khác trong mạng cục bộ truy cập';

  @override
  String get localApiLanHint =>
      'Chỉ dùng trong mạng đáng tin cậy. HTTP không mã hóa lời nhắc hoặc khóa API.';

  @override
  String get localApiStart => 'Khởi động máy chủ';

  @override
  String get localApiStop => 'Dừng máy chủ';

  @override
  String get localApiUrl => 'URL cơ sở trên thiết bị này';

  @override
  String get localApiLanUrl => 'URL cơ sở trong mạng cục bộ';

  @override
  String get localApiNoLan => 'Không có địa chỉ mạng cục bộ khả dụng.';

  @override
  String get localApiKey => 'Khóa API';

  @override
  String get localApiShowKey => 'Hiện khóa API';

  @override
  String get localApiHideKey => 'Ẩn khóa API';

  @override
  String get localApiRotateKey => 'Thay khóa API';

  @override
  String get localApiRotateHint =>
      'Khóa hiện tại sẽ ngừng hoạt động. Hãy cập nhật khóa mới trong các ứng dụng đã kết nối.';

  @override
  String localApiCopy(String label) {
    return 'Sao chép $label';
  }

  @override
  String get localApiCopied => 'Đã sao chép vào bảng nhớ tạm';

  @override
  String get image_generation => 'Tạo ảnh';

  @override
  String get image_model_ids => 'ID mô hình tạo ảnh';

  @override
  String get image_model_ids_hint =>
      'Nhập các ID tùy chỉnh, phân tách bằng dấu phẩy hoặc xuống dòng.';

  @override
  String get image_generation_prompt => 'Mô tả ảnh bạn muốn tạo';

  @override
  String get image_generation_temporary =>
      'Tính năng tạo ảnh có trong các cuộc trò chuyện được lưu. Hãy bắt đầu một cuộc trò chuyện được lưu để tạo ảnh.';

  @override
  String get image_generation_remove_attachments =>
      'Xóa tệp đính kèm trước khi tạo ảnh.';

  @override
  String get image_generation_unavailable =>
      'Máy chủ hoặc mô hình này không cung cấp Images API tương thích. Hãy kiểm tra URL máy chủ và ID mô hình.';

  @override
  String get image_generation_auth =>
      'Hãy kiểm tra khóa API và quyền truy cập mô hình tạo ảnh này.';

  @override
  String get image_generation_quota =>
      'Đã chạm giới hạn tần suất hoặc hạn mức của nhà cung cấp. Hãy kiểm tra tài khoản trước khi thử lại.';

  @override
  String get image_generation_rejected =>
      'Nhà cung cấp đã từ chối yêu cầu tạo ảnh. Hãy kiểm tra lời nhắc và thử lại.';

  @override
  String get image_generation_timeout =>
      'Quá thời gian chờ tạo ảnh. Hãy thử lại khi dịch vụ của nhà cung cấp khả dụng.';

  @override
  String get image_generation_invalid =>
      'Nhà cung cấp trả về ảnh không hợp lệ hoặc không được hỗ trợ.';

  @override
  String get image_generation_failed =>
      'Không thể tạo ảnh. Hãy kiểm tra kết nối và thử lại.';

  @override
  String get image_generation_save_failed =>
      'Không thể lưu ảnh đã tạo. Hãy kiểm tra dung lượng trống và thử lại.';

  @override
  String get image_generation_share => 'Chia sẻ ảnh';

  @override
  String get onDeviceSearchModels => 'Tìm mô hình';

  @override
  String get onDeviceSearching => 'Đang tìm kiếm…';

  @override
  String get onDeviceSearch => 'Tìm kiếm';

  @override
  String get onDeviceModelTypeBoth => 'Cả hai';

  @override
  String get onDeviceModelTypeLitert => 'LiteRT';

  @override
  String get onDeviceModelTypeGguf => 'Llama.cpp (GGUF)';

  @override
  String get onDeviceModelTypeNone => 'Không có';

  @override
  String get onDeviceModalityAll => 'Tất cả';

  @override
  String get onDeviceModalityText => 'Văn bản';

  @override
  String get onDeviceModalityVision => 'Thị giác';

  @override
  String get onDeviceModalityAudio => 'Âm thanh';

  @override
  String get onDeviceModalityEmbedding => 'Embedding';

  @override
  String get onDeviceModalityOmni => 'Omni';

  @override
  String get onDeviceModalityUnknown => 'Không xác định';

  @override
  String get downloadBackgroundActive => 'Trong nền';

  @override
  String get downloadBackgroundDescription =>
      'Android quản lý lượt tải này và có thể tiếp tục tải khi đóng LocalMind. Android có thể tạm dừng hoặc trì hoãn tùy theo tình trạng hệ thống.';

  @override
  String get downloadQueued => 'Đang xếp hàng';

  @override
  String get downloadWaitingToRetry => 'Đang chờ thử lại';

  @override
  String get onDeviceEnterSearchTerm => 'Nhập từ khóa tìm kiếm';

  @override
  String get onDeviceFilters => 'Bộ lọc';

  @override
  String get onDeviceFramework => 'Khung phần mềm';

  @override
  String get onDeviceModality => 'Loại dữ liệu';

  @override
  String get onDeviceParameterSize => 'Số lượng tham số';

  @override
  String get onDeviceMinParam => 'Tối thiểu (tỷ)';

  @override
  String get onDeviceMaxParam => 'Tối đa (tỷ)';

  @override
  String get onDeviceIncludeUnknownSizes =>
      'Bao gồm mô hình chưa rõ kích thước';

  @override
  String get onDeviceSplitModels => 'Mô hình nhiều phần';

  @override
  String get onDeviceImportFromUrl => 'Nhập từ URL';

  @override
  String get onDeviceImportFromDevice => 'Nhập từ thiết bị';

  @override
  String get onDeviceAddModelFromUrl => 'Thêm mô hình từ URL';

  @override
  String get onDeviceHuggingFaceUrl => 'URL Hugging Face';

  @override
  String get onDeviceUpdateAvailable => 'Có bản cập nhật';

  @override
  String get onDeviceCheckForUpdates => 'Kiểm tra bản cập nhật';

  @override
  String get onDeviceAdded => 'Đã thêm';

  @override
  String get onDeviceSplitModel => 'Mô hình nhiều phần';

  @override
  String get onDevicePickGguf => 'Chọn GGUF';

  @override
  String get onDevicePickLitert => 'Chọn LiteRT';

  @override
  String onDeviceUnknownSizeHidden(int count) {
    return 'Đã ẩn $count mô hình chưa rõ kích thước';
  }

  @override
  String get conversation_tags => 'Thẻ';

  @override
  String get conversation_tags_desc =>
      'Nhóm cuộc trò chuyện theo chủ đề. Một cuộc trò chuyện có thể có nhiều thẻ và thuộc một thư mục.';

  @override
  String get conversation_tags_add_hint => 'Thêm thẻ rồi nhấn Enter';

  @override
  String get conversation_tags_existing => 'Thẻ của bạn';

  @override
  String get conversation_tags_add => 'Thêm thẻ';

  @override
  String get conversation_tags_edit => 'Chỉnh sửa thẻ';

  @override
  String get turn_instruction_title => 'Chỉ dẫn cho phản hồi tiếp theo';

  @override
  String get turn_instruction_desc =>
      'Bổ sung cho lời nhắc của cuộc trò chuyện và chỉ áp dụng cho tin nhắn tiếp theo.';

  @override
  String get turn_instruction_hint => 'Ví dụ: Trả lời bằng ba gạch đầu dòng';

  @override
  String get turn_instruction_remove => 'Xóa chỉ dẫn';

  @override
  String get turn_instruction_chip_label => 'Phản hồi tiếp theo:';

  @override
  String get read_images_on_device => 'Đọc ảnh cho mô hình chỉ hỗ trợ văn bản';

  @override
  String get read_images_on_device_desc =>
      'Khi mô hình trên thiết bị không thể xem ảnh, thiết bị sẽ đọc chữ và nhận diện vật thể trong ảnh rồi chuyển cho mô hình dưới dạng văn bản. Mọi dữ liệu đều ở trên điện thoại.';

  @override
  String get web_search_title => 'Tìm kiếm trên web';

  @override
  String get web_search_enable_desc =>
      'Cho phép tìm thông tin trên web trong cuộc trò chuyện. Từ khóa được gửi đến nhà cung cấp bạn chọn và các trang được tải từ thiết bị này. Tính năng này tắt theo mặc định.';

  @override
  String get web_search_provider => 'Nhà cung cấp tìm kiếm';

  @override
  String get web_search_searxng_url => 'Địa chỉ SearXNG';

  @override
  String get web_search_searxng_hint => 'https://searx.example.com';

  @override
  String get web_search_searxng_help =>
      'Dùng phiên bản SearXNG của bạn. Bật định dạng JSON trong mục search → formats của tệp settings.yml.';

  @override
  String get web_search_api_key => 'Khóa API';

  @override
  String get web_search_api_key_saved =>
      'Đã lưu một khóa. Nhập khóa mới để thay thế.';

  @override
  String get web_search_remove_key => 'Xóa khóa đã lưu';

  @override
  String get web_search_test => 'Kiểm tra tìm kiếm';

  @override
  String web_search_test_ok(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tìm kiếm hoạt động: $count kết quả.',
      zero: 'Tìm kiếm hoạt động nhưng không trả về kết quả.',
    );
    return '$_temp0';
  }

  @override
  String web_search_test_failed(String error) {
    return 'Tìm kiếm thất bại: $error';
  }

  @override
  String get web_search_tools_note =>
      'Các mô hình hỗ trợ công cụ cũng có thể gọi web.search và web.fetch khi bật công cụ trong cuộc trò chuyện. Bạn phê duyệt từng lần gọi.';

  @override
  String get attach_search_web => 'Tìm trên web';

  @override
  String get attach_search_web_desc =>
      'Tra cứu thông tin về tin nhắn này trên web trước khi trả lời';

  @override
  String get web_search_next_chip =>
      'Đã bật tìm kiếm trên web cho tin nhắn này';

  @override
  String get web_search_next_off => 'Tắt tìm kiếm trên web';
}
