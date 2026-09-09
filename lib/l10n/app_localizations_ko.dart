// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Korean (`ko`).
class AppLocalizationsKo extends AppLocalizations {
  AppLocalizationsKo([String locale = 'ko']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => '당신의 AI. 귀하의 장치. 귀하의 규칙.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => '취소';

  @override
  String get confirm => '확인';

  @override
  String get delete => '삭제';

  @override
  String get save => '저장';

  @override
  String get retry => '재시도';

  @override
  String get close => '닫기';

  @override
  String get done => '완료';

  @override
  String get continue_action => '계속';

  @override
  String get skip => '건너뛰기';

  @override
  String get install => '설치';

  @override
  String get download => '다운로드';

  @override
  String get resume => '이력서';

  @override
  String get pause => '일시중지';

  @override
  String get stop => '중지';

  @override
  String get edit => '편집';

  @override
  String get preview => '미리보기';

  @override
  String get unload => '언로드';

  @override
  String get load => '로드';

  @override
  String get rename => '이름 바꾸기';

  @override
  String get pin => '핀';

  @override
  String get unpin => '고정 해제';

  @override
  String get share => '공유';

  @override
  String get copy => '복사';

  @override
  String get copied => '복사되었습니다!';

  @override
  String get copied_to_clipboard => '클립보드에 복사됨';

  @override
  String get select => '선택';

  @override
  String get active => '활성';

  @override
  String get all => '모두';

  @override
  String get none => '없음';

  @override
  String get none_selected => '선택한 항목 없음';

  @override
  String get online => '온라인';

  @override
  String get connected => '연결됨';

  @override
  String get checking => '확인 중';

  @override
  String get offline => '오프라인';

  @override
  String get error => '오류';

  @override
  String get unknown_error => '알 수 없는 오류';

  @override
  String get not_now => '지금은 아님';

  @override
  String get enable => '활성화';

  @override
  String get proceed_anyway => '어쨌든 진행';

  @override
  String get test_connection => '연결 테스트';

  @override
  String get testing => '테스트 중...';

  @override
  String get connection_successful => '연결 성공!';

  @override
  String get connection_failed => '연결에 실패했습니다. 설정을 확인하세요.';

  @override
  String get save_continue => '저장하고 계속하기';

  @override
  String get save_changes => '변경 사항 저장';

  @override
  String get finish_setup => '설정 완료';

  @override
  String get start_new_chat => '새 채팅 시작';

  @override
  String get cannot_undo => '이 작업은 취소할 수 없습니다.';

  @override
  String get ram_warning => 'RAM 경고';

  @override
  String get recommended => '추천';

  @override
  String get may_be_large => '이 기기에 비해 너무 클 수 있습니다.';

  @override
  String get calculating => '계산 중...';

  @override
  String get download_failed => '다운로드 실패';

  @override
  String get downloaded => '다운로드됨';

  @override
  String get not_downloaded => '다운로드되지 않음';

  @override
  String get installed => '설치됨';

  @override
  String get not_installed => '설치되지 않음';

  @override
  String get loading => '로드 중...';

  @override
  String get thinking => '생각';

  @override
  String get processing => '처리 중...';

  @override
  String get initializing => '초기화 중...';

  @override
  String get ready => '준비';

  @override
  String get preparing_app => '앱 준비 중...';

  @override
  String get initializing_services => '서비스 초기화 중...';

  @override
  String get configuring_server => '서버 구성 중...';

  @override
  String get startup_failed => '시작 실패';

  @override
  String get something_went_wrong => '문제가 발생했습니다.';

  @override
  String get delete_model_title => '모델 삭제';

  @override
  String delete_model_body(String name) {
    return '$name을 삭제하시겠습니까?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return '$name을 삭제하시겠습니까? 이렇게 하면 약 $size 정도의 공간이 확보됩니다.\n\n필요한 경우 나중에 이 모델을 다시 다운로드할 수 있습니다.';
  }

  @override
  String get delete_voice_title => '음성 삭제';

  @override
  String delete_voice_body(String name, String size) {
    return '$name을 삭제하시겠습니까? 이렇게 하면 약 $size 정도의 공간이 확보됩니다.\n\n필요한 경우 나중에 이 음성을 다시 다운로드할 수 있습니다.';
  }

  @override
  String get delete_server_title => '서버 삭제';

  @override
  String delete_server_body(String name) {
    return '정말로 \"$name\"을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.';
  }

  @override
  String get delete_conversation_title => '대화를 삭제하시겠습니까?';

  @override
  String delete_conversation_body(String title) {
    return '정말로 \"$title\"을 삭제하시겠습니까? 이 작업은 취소할 수 없습니다.';
  }

  @override
  String get delete_message_title => '메시지를 삭제하시겠습니까?';

  @override
  String delete_persona_title(String name) {
    return '\'$name\'를 삭제하시겠습니까?';
  }

  @override
  String get delete_persona_body => '이 작업은 취소할 수 없습니다.';

  @override
  String get delete_builtin_persona_body =>
      '이것은 내장된 페르소나입니다. 나중에 설정에서 복원할 수 있습니다.';

  @override
  String get restore_builtin_personas => '기본 페르소나 복원';

  @override
  String get restore_builtin_personas_desc => '삭제한 내장 페르소나를 다시 추가하세요.';

  @override
  String get restore_builtin_personas_success => '기본 페르소나가 복원되었습니다.';

  @override
  String get clear_personas => '명확한 페르소나';

  @override
  String get enable_image_compression => '보내기 전에 이미지를 압축하세요';

  @override
  String get enable_image_compression_desc =>
      '업로드가 서버 제한 내에서 유지되도록 첨부된 이미지의 크기를 조정하고 압축합니다.';

  @override
  String get image_compression_level => '압축 공격성';

  @override
  String get image_compression_level_desc =>
      '공격성이 높을수록 품질이 낮을수록 업로드 크기가 작아집니다.';

  @override
  String get image_compression_level_low => '낮음';

  @override
  String get image_compression_level_medium => '중간';

  @override
  String get image_compression_level_high => '높음';

  @override
  String get sort_models_tooltip => '모델 정렬';

  @override
  String get sort_by_favorites => '즐겨찾기 먼저';

  @override
  String get sort_by_name => '이름(A~Z)';

  @override
  String get sort_by_size_smallest => '크기(가장 작은 것부터)';

  @override
  String get sort_by_size_largest => '크기(큰 것부터)';

  @override
  String get sort_by_context_length => '컨텍스트 길이';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return '$done/$total 이름 바꾸기...';
  }

  @override
  String selected_count(int count) {
    return '$count 선택됨';
  }

  @override
  String get ai_rename_tooltip => 'AI로 선택한 이름 바꾸기';

  @override
  String get new_chat_in_folder_tooltip => '이 폴더의 새 채팅';

  @override
  String total_tokens_count(int count) {
    return '$count 토큰';
  }

  @override
  String get smart_replies_use_persona => '스마트 답장에 페르소나 사용';

  @override
  String get smart_replies_use_persona_desc =>
      '제안된 답변은 일반적인 어시스턴트가 아닌 활성 페르소나의 어조와 일치합니다.';

  @override
  String get keep_persona_on_new_chat => '새 채팅에서 페르소나 유지';

  @override
  String get keep_persona_on_new_chat_desc => '새 채팅을 시작한 후 선택한 페르소나를 지우지 마세요.';

  @override
  String get role_swap_button_enabled => '역할 전환 버튼 표시';

  @override
  String get role_swap_button_enabled_desc =>
      '응답을 생성하지 않고 사용자 대신 어시스턴트로 메시지를 보내려면 채팅 입력에 버튼을 표시하세요.';

  @override
  String get send_as_user_tooltip => '사용자로 보내기';

  @override
  String get send_as_assistant_tooltip => '어시스턴트로 보내기(응답 없음)';

  @override
  String get insert_without_generating_tooltip => '생성하지 않고 삽입';

  @override
  String get token_usage_title => '토큰 사용';

  @override
  String get total_tokens_label => '사용된 토큰';

  @override
  String get usage_percent_label => '사용된 컨텍스트';

  @override
  String get export_choice_title => '수출';

  @override
  String get export_choice_body => '이것을 어떻게 내보내시겠습니까?';

  @override
  String get copy_to_clipboard => '클립보드에 복사';

  @override
  String bulk_export_conversations_success(int count) {
    return '$count 대화를 내보냈습니다.';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'AI로 이름을 바꾸시겠습니까?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return '이는 AI에게 $count가 선택한 각 대화에 대해 현재 제목을 대체하는 새로운 제목을 생성하도록 요청합니다. 이 작업은 시간이 좀 걸릴 수 있으며 취소할 수 없습니다.';
  }

  @override
  String get sort_by_modified_date => '최종 수정됨';

  @override
  String get sort_by_created_date => '생성된 날짜';

  @override
  String get sort_title => '정렬';

  @override
  String get clear_conversation_title => '명확한 대화?';

  @override
  String get clear_conversation_body => '이 대화의 모든 메시지가 삭제됩니다.';

  @override
  String get clear => '지우기';

  @override
  String label_completed(String label) {
    return '$label 완료';
  }

  @override
  String error_with_message(String error) {
    return '오류: $error';
  }

  @override
  String preview_failed(String error) {
    return '미리보기 실패: $error';
  }

  @override
  String loading_model(String modelId) {
    return '$modelId 로드 중...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return '로드된 모델: $modelId($backend)';
  }

  @override
  String get no_model_loaded =>
      '로드된 모델이 없습니다. 모델을 다운로드하고 로드하려면 \"기기 내 모델 관리\"를 탭하세요.';

  @override
  String loading_model_error(String error) {
    return '오류: $error';
  }

  @override
  String get delete_conversation => '대화를 삭제하시겠습니까?';

  @override
  String get nav_history => '역사';

  @override
  String get nav_servers => '서버';

  @override
  String get nav_local_models => '지역 모델';

  @override
  String get nav_tts => '텍스트 음성 변환';

  @override
  String get nav_personas => '페르소나';

  @override
  String get nav_settings => '설정';

  @override
  String get nav_new_chat => '새 채팅';

  @override
  String get search_hint => '대화 검색...';

  @override
  String get no_server_selected => '서버를 선택하지 않았습니다.';

  @override
  String get switch_server => '서버 전환';

  @override
  String get switch_server_subtitle => '연결할 서버를 선택하세요';

  @override
  String get manage_servers => '서버 관리';

  @override
  String get open_source => '오픈 소스';

  @override
  String get open_source_desc =>
      'LocalMind는 오픈 소스입니다. 진행 상황을 따르거나 GitHub에 기여해 보세요.';

  @override
  String get star_on_github => 'GitHub의 스타';

  @override
  String get add_more => '더 추가';

  @override
  String get on_github => 'GitHub에서';

  @override
  String get could_not_open_github => 'GitHub를 열 수 없습니다.';

  @override
  String get settings_title => '설정';

  @override
  String get settings_appearance => '외관';

  @override
  String get settings_language => '언어';

  @override
  String get language_system_default => '시스템 기본값';

  @override
  String get settings_tts => '텍스트 음성 변환';

  @override
  String get settings_android_assistant => '안드로이드 어시스턴트';

  @override
  String get assistant_default_title => 'LocalMind를 보조자로 사용';

  @override
  String get assistant_default_description =>
      'Android의 보조 제스처 또는 전원 버튼 단축키를 사용하여 음성 모드를 시작하세요.';

  @override
  String get assistant_status_active => '활성';

  @override
  String get assistant_status_available => '비활성';

  @override
  String get assistant_status_manual => '설정 확인';

  @override
  String get assistant_status_unsupported => '이용 불가';

  @override
  String get assistant_status_checking => '확인 중…';

  @override
  String get assistant_set_default => '기본 도우미로 설정';

  @override
  String get assistant_open_settings => 'Android 어시스턴트 설정 열기';

  @override
  String assistant_error(Object error) {
    return 'Android 어시스턴트 설정을 열 수 없습니다.';
  }

  @override
  String get settings_behavior => '행동';

  @override
  String get settings_on_device => '온디바이스 추론';

  @override
  String get settings_default_server => '기본 서버';

  @override
  String get settings_default_persona => '기본 페르소나';

  @override
  String get settings_default_model => '기본 모델';

  @override
  String get settings_default_model_desc => '새 채팅을 시작하면 자동으로 선택됩니다.';

  @override
  String get settings_privacy => '개인 정보 보호';

  @override
  String get settings_data_management => '데이터 관리';

  @override
  String get settings_about => '소개';

  @override
  String get theme => '테마';

  @override
  String get theme_system => '시스템';

  @override
  String get theme_light => '빛';

  @override
  String get theme_dark => '어둠';

  @override
  String get theme_claude => '클로드';

  @override
  String get font_size => '글꼴 크기';

  @override
  String get font_size_desc => '채팅에서 텍스트 크기를 조정합니다.';

  @override
  String get font_preview => '날렵한 갈색여우가 게으른 개를 뛰어넘습니다.';

  @override
  String get code_theme_dark => '코드 테마(어두움)';

  @override
  String get code_theme_light => '코드 테마(빛)';

  @override
  String get code_theme_desc => '코드 블록에 대한 구문 강조 테마를 선택합니다.';

  @override
  String get tts_engine => 'TTS 엔진';

  @override
  String get tts_engine_system => '시스템 TTS';

  @override
  String get tts_engine_kitten => '새끼 고양이 TTS';

  @override
  String get voice => '음성';

  @override
  String get voice_female => '여성';

  @override
  String get voice_male => '남성';

  @override
  String get voice_other => '기타';

  @override
  String get tts_speed => 'TTS 속도';

  @override
  String get tts_speed_desc => '재생 속도를 조정합니다.';

  @override
  String get manage_tts_models => 'TTS 모델 관리';

  @override
  String get manage_on_device_models => '온디바이스 모델 관리';

  @override
  String get enable_smart_reply => '기기 내 스마트 답장';

  @override
  String get ai_user_response_enabled => 'AI 사용자 메시지(보류 보내기)';

  @override
  String get ai_user_response_enabled_desc =>
      'AI가 다음 메시지를 쓰고 보내도록 하려면 보내기 버튼을 3초 동안 누르세요.';

  @override
  String get ai_user_response_tooltip => 'AI로 사용자 메시지 생성';

  @override
  String get streaming_responses => '스트리밍 응답';

  @override
  String get auto_generate_titles => '제목 자동 생성';

  @override
  String get send_on_enter => '입력 시 보내기';

  @override
  String get show_system_messages => '기본 시스템 프롬프트 보내기';

  @override
  String get show_system_messages_desc =>
      '페르소나가 선택되지 않은 경우 각 요청과 함께 기본 보조 시스템 프롬프트를 보냅니다.';

  @override
  String get show_system_messages_in_chat => '채팅에 시스템 메시지 표시';

  @override
  String get show_system_messages_in_chat_desc =>
      '대화에서 눈에 보이는 풍선으로 시스템 메시지(예: 가져온 백업의 메시지)를 표시합니다.';

  @override
  String get auto_collapse_thinking => '자동 붕괴 사고';

  @override
  String get auto_collapse_thinking_desc =>
      '주요 답변이 있는 경우 응답 생성이 완료된 후 추론 프로세스를 자동으로 축소합니다.';

  @override
  String get haptic_feedback => '햅틱 피드백';

  @override
  String get enable_mcp => 'MCP 활성화';

  @override
  String get new_chat_mcp_default => '새 채팅 MCP 기본값';

  @override
  String get show_data_indicator => '데이터 표시기 표시';

  @override
  String get privacy_info => '\"LocalMind는 귀하의 데이터를 결코 볼 수 없습니다\"';

  @override
  String get delete_all_conversations => '모든 대화 삭제';

  @override
  String get reset_settings_defaults => '설정을 기본값으로 재설정';

  @override
  String get chat_title => '로컬마인드';

  @override
  String get chat_parameters_tooltip => '채팅 매개변수';

  @override
  String get change_persona => '페르소나 변경';

  @override
  String get set_persona => '페르소나 설정';

  @override
  String get remove_persona => '페르소나 제거';

  @override
  String get clear_conversation => '명확한 대화';

  @override
  String get connection_error => '연결 오류입니다. 서버를 확인하세요.';

  @override
  String get disconnected => '서버와의 연결이 끊어졌습니다.';

  @override
  String get configure => '구성';

  @override
  String get select_model => '모델 선택';

  @override
  String get select_persona => '페르소나 선택';

  @override
  String get manage_personas => '페르소나 관리';

  @override
  String get personas_combine_hint => '채팅에서 여러 페르소나를 선택하여 시스템 프롬프트를 쌓으세요.';

  @override
  String get start_conversation => '대화 시작';

  @override
  String get recent_chats => '최근 채팅';

  @override
  String get see_all => '모두 보기';

  @override
  String get quick_write => '함수 작성 도와주세요';

  @override
  String get quick_explain => '이 코드를 설명해보세요';

  @override
  String get quick_debug => '나를 위해 디버깅해 주세요';

  @override
  String get quick_async => '비동기/대기를 어떻게 사용하나요?';

  @override
  String get history_missing_title => '기록 누락';

  @override
  String get history_missing_desc => '이 채팅의 메시지가 삭제되었거나 기록 기록이 손상되었습니다.';

  @override
  String get technical_details => '기술적인 세부사항';

  @override
  String get last_error => '마지막 오류:';

  @override
  String get copy_info => '정보 복사';

  @override
  String get conversation_id => '대화 ID';

  @override
  String get created_at => '생성 날짜';

  @override
  String get expected_messages => '예상되는 메시지';

  @override
  String get debug_dialog_desc => '동기화 문제를 식별하는 데 도움이 되는 진단 정보입니다.';

  @override
  String get chat_input_hint => '무엇이든 물어보세요';

  @override
  String get send_message_tooltip => '메시지 보내기';

  @override
  String get stop_generation_tooltip => '생성 중지';

  @override
  String get attach_images_tooltip => '이미지 또는 텍스트 첨부';

  @override
  String get start_listening_tooltip => '듣기 시작';

  @override
  String get stop_listening_tooltip => '듣기 중지';

  @override
  String tool_label(String toolCallId) {
    return '도구: $toolCallId';
  }

  @override
  String get tool_unknown => '도구: 알 수 없음';

  @override
  String get message_options => '메시지 옵션';

  @override
  String get copy_markdown => '마크다운으로 복사';

  @override
  String get copied_markdown => '마크다운으로 복사됨';

  @override
  String get read_aloud => '소리내어 읽기';

  @override
  String get stop_reading => '읽기 중지';

  @override
  String get more => '더보기';

  @override
  String character_count(int length) {
    return '$length 문자';
  }

  @override
  String get edit_message => '메시지 편집';

  @override
  String get edit_message_desc => '저장하면 아래 어시스턴트 응답이 제거되고 다시 생성됩니다.';

  @override
  String get save_regenerate => '저장 및 재생성';

  @override
  String get chat_settings_title => '채팅 설정';

  @override
  String get reset_defaults => '기본값 재설정';

  @override
  String get parameters_tab => '매개변수';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => '온도';

  @override
  String get temperature_desc => '무작위성 제어: 높음 = 창의적, 낮음 = 집중';

  @override
  String get top_p => '탑 P';

  @override
  String get top_p_desc => '핵 샘플링 임계값';

  @override
  String get max_tokens => '최대 토큰';

  @override
  String get max_tokens_desc => '응답 한도';

  @override
  String get context_length => '컨텍스트 길이';

  @override
  String get context_length_desc => '기록 창';

  @override
  String get mcp_disabled_warning =>
      'MCP는 전역적으로 비활성화됩니다. 이러한 기능을 사용하려면 설정에서 활성화하세요.';

  @override
  String get mcp_enable_chat => '이 채팅에 대해 MCP를 활성화합니다.';

  @override
  String get auto_execute_tools => '자동 실행 도구';

  @override
  String get beta_label => '베타';

  @override
  String get experimental_label => '실험적';

  @override
  String get add_ephemeral_mcp => '임시 MCP 서버 추가';

  @override
  String get mcp_label_placeholder => '라벨';

  @override
  String get mcp_url_placeholder => 'URL(https://...)';

  @override
  String get active_integrations => '활성 통합';

  @override
  String get import_mcp_json => 'JSON 가져오기';

  @override
  String get import_mcp_json_dialog_title => 'MCP 구성 JSON 가져오기';

  @override
  String get import_mcp_json_instructions =>
      'LM Studio(mcp.json)에서 직접 mcpServers JSON을 복사하거나 아래에 플러그인 배열을 붙여넣으세요.';

  @override
  String get import_mcp_json_placeholder =>
      '여기에 mcpServers JSON 또는 플러그인 목록을 붙여넣으세요...';

  @override
  String mcp_import_success(int count) {
    return '$count 통합을 성공적으로 가져왔습니다.';
  }

  @override
  String get mcp_import_failed => 'JSON에 유효한 MCP 통합이 없습니다.';

  @override
  String get enable_notifications => '알림 활성화';

  @override
  String get enable_notifications_desc => '모델 다운로드가 완료되면 알림을 받습니다.';

  @override
  String get chat_history_title => '채팅 기록';

  @override
  String get conversation_just_now => '지금 막';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes분 전';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours시간 전';
  }

  @override
  String get conversation_yesterday => '어제';

  @override
  String conversation_days_ago(int days) {
    return '$days일 전';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => '옵션';

  @override
  String get no_results_found => '검색결과가 없습니다';

  @override
  String get no_conversations_yet => '아직 대화가 없습니다.';

  @override
  String get try_different_search => '다른 검색어를 사용해 보세요.';

  @override
  String get start_new_conversation => '새로운 대화를 시작하세요';

  @override
  String get rename_conversation => '대화 이름 바꾸기';

  @override
  String get enter_new_title => '새 제목을 입력하세요';

  @override
  String get pinned_section => '고정됨';

  @override
  String get today_section => '오늘';

  @override
  String get yesterday_section => '어제';

  @override
  String get previous_7_days => '이전 7일';

  @override
  String get previous_30_days => '이전 30일';

  @override
  String get older_section => '나이가 많은';

  @override
  String get onboarding_choose_language => '언어 선택';

  @override
  String get onboarding_choose_language_desc =>
      '원하는 언어를 선택하세요. 언제든지 설정에서 변경할 수 있습니다.';

  @override
  String get onboarding_localmind => '지역 마인드';

  @override
  String get onboarding_connect_server => '당신의 연결\n서버';

  @override
  String get onboarding_connect_desc =>
      'LM Studio, Ollama에 연결하세요.\nOllama Cloud 또는 OpenRouter를 사용하여\n개인 AI 경험을 시작하세요.';

  @override
  String get openai_compatible_api => 'OpenAI 호환 API';

  @override
  String get https_requires_ssl => 'HTTPS에는 SSL이 필요합니다';

  @override
  String get most_local_setups_use_http => '대부분의 로컬 설정에서는 http://를 사용합니다.';

  @override
  String get onboarding_welcome => '로컬마인드에 오신 것을 환영합니다';

  @override
  String get server_type_on_device => '기기 내';

  @override
  String get server_type_lm_studio => 'LM스튜디오';

  @override
  String get server_type_ollama => '올라마';

  @override
  String get server_type_ollama_cloud => '올라마 클라우드';

  @override
  String get server_type_ollama_cloud_sub => '클라우드 관리';

  @override
  String get server_type_ollama_cloud_display => '올라마 클라우드';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Ollama Cloud를 연결하면 채팅 메시지와 입력 내용이 추론을 위해 Ollama의 관리 서버로 전송됩니다. LocalMind는 대화를 추적하거나 저장하지 않습니다. ollama.com/settings/keys에서 언제든지 이 키를 취소할 수 있습니다.';

  @override
  String get api_key_required_ollama_cloud => 'Ollama Cloud에 필요한 API 키';

  @override
  String get api_key_hint_ollama_cloud => 'Ollama Cloud API 키를 붙여넣으세요.';

  @override
  String get add_server_ollama_cloud_subtitle =>
      '관리형 클라우드 모델에 액세스하려면 ollama.com/settings/keys의 API 키를 사용하여 Ollama Cloud에 연결하세요.';

  @override
  String get add_server_openrouter_subtitle =>
      '유효한 API 키를 사용하여 OpenRouter를 통해 연결하고 모델 라우팅을 위해 이 프로필을 준비하세요.';

  @override
  String get add_server_endpoint_subtitle =>
      '로컬 또는 자체 호스팅 끝점을 구성한 다음 저장하기 전에 연결을 확인하세요.';

  @override
  String get server_type_openrouter => '오픈라우터';

  @override
  String get server_type_openrouter_sub => '통합 클라우드';

  @override
  String get ready_continue => '계속할 준비가 되었습니다';

  @override
  String get waiting_selection => '선택을 기다리는 중';

  @override
  String get setup_connection => '연결 설정';

  @override
  String setup_connection_desc(String server) {
    return '채팅을 시작하려면 $server 서버를 구성하세요.';
  }

  @override
  String get server_name => '서버 이름';

  @override
  String get name_required => '이름이 필요합니다';

  @override
  String get name_max_50 => '최대 50자';

  @override
  String get host_label => '호스트/IP 주소';

  @override
  String get host_required => '호스트 필수';

  @override
  String get port_label => '항구';

  @override
  String get port_required => '포트 필요';

  @override
  String get port_invalid => '숫자여야 합니다.';

  @override
  String get port_range => '유효한 포트(1-65535)를 입력하세요.';

  @override
  String get api_key_required => 'API 키 *';

  @override
  String get api_key_optional => 'API 키(선택사항)';

  @override
  String get api_key_required_openrouter => 'OpenRouter에 필요한 API 키';

  @override
  String get api_key_format => 'OpenRouter API 키는 sk-로 시작합니다.';

  @override
  String get my_server_hint => '내 서버';

  @override
  String get name_length_validation => '이름은 50자 이하여야 합니다.';

  @override
  String get host_valid => '유효한 호스트 이름 또는 IP 주소를 입력하세요.';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => '인증된 서버의 경우';

  @override
  String get update_server => '업데이트 서버';

  @override
  String get save_server => '서버 저장';

  @override
  String get server_updated => '서버가 업데이트되었습니다.';

  @override
  String get server_added => '서버가 추가되었습니다';

  @override
  String get download_model_title => '모델 다운로드';

  @override
  String get download_model_desc => '다운로드할 모델을 선택하세요.\n장치에서 로컬로 실행됩니다.';

  @override
  String get on_device_android_only => '기기 내 추론은 현재 Android에서만 사용할 수 있습니다.';

  @override
  String get total_ram => '총 RAM';

  @override
  String get available => '가능';

  @override
  String ram_min_required(String fileSize) {
    return '$fileSize GB RAM 최소';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return '도착 예정 시간: $eta';
  }

  @override
  String paused_progress(String percent) {
    return '일시중지됨 - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return '이 모델에는 최소 ${ram}GB RAM이 필요하지만 장치에는 $totalMemory가 있습니다. 제대로 실행되지 않거나 앱이 충돌할 수 있습니다.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return '장치에는 $availableRAM 사용 가능한 RAM이 있지만 이 모델에서는 최소 $ram GB를 권장합니다. 로드가 실패하거나 불안정해질 수 있습니다.';
  }

  @override
  String get choose_theme => '테마 선택';

  @override
  String get choose_theme_desc => '앱 모양을 개인화하세요. 나중에 설정에서 언제든지 변경할 수 있습니다.';

  @override
  String get theme_card_system => '시스템';

  @override
  String get theme_card_system_sub => '기기 설정과 일치';

  @override
  String get theme_card_light => '빛';

  @override
  String get theme_card_light_sub => '깨끗하고 밝다';

  @override
  String get theme_card_dark => '어둠';

  @override
  String get theme_card_dark_sub => '눈이 편하다';

  @override
  String get theme_card_claude => '클로드';

  @override
  String get theme_card_claude_sub => '따뜻한 복숭아빛 테마';

  @override
  String get stay_updated => '최신 정보 유지';

  @override
  String get stay_updated_desc => 'AI 모델 다운로드가 완료되거나 장기 실행 작업이 완료되면 알림을 받으세요.';

  @override
  String get notification_benefit_downloads => '모델 다운로드 진행';

  @override
  String get notification_benefit_completions => '세대 완료';

  @override
  String get notification_benefit_background => '백그라운드 작업 상태';

  @override
  String get allow_notifications => '알림 허용';

  @override
  String get servers_title => '서버';

  @override
  String get no_servers_yet => '아직 서버가 없습니다';

  @override
  String get no_servers_desc => 'AI 모델과 채팅을 시작하려면 첫 번째 서버를 추가하세요.';

  @override
  String get add_server => '서버 추가';

  @override
  String switched_to_server(String name) {
    return '$name로 전환됨';
  }

  @override
  String get edit_server => '서버 편집';

  @override
  String get add_server_title => '서버 추가';

  @override
  String get server_type_label => '서버 유형';

  @override
  String get server_icon_label => '서버 아이콘';

  @override
  String get default_icon => '기본 아이콘';

  @override
  String get server_type_lm_studio_display => 'LM스튜디오';

  @override
  String get server_type_openai_display => 'OpenAI 호환';

  @override
  String get server_type_ollama_display => '올라마';

  @override
  String get server_type_openrouter_display => '오픈라우터';

  @override
  String get server_type_on_device_display => '기기 내';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => '국소 추론';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => '기본값';

  @override
  String get set_as_default => '기본값으로 설정';

  @override
  String get select_icon => '아이콘 선택';

  @override
  String get select_icon_desc => '서버 아이콘을 선택하세요';

  @override
  String get search_icons_hint => '아이콘 검색...';

  @override
  String get server_icon_stack => '서버 스택';

  @override
  String get server_icon_stack2 => '서버 스택 02';

  @override
  String get server_icon_stack3 => '서버 스택 03';

  @override
  String get server_icon_cloud => '클라우드';

  @override
  String get server_icon_cloud_server => '클라우드 서버';

  @override
  String get server_icon_mcp => 'MCP 서버';

  @override
  String get server_icon_database => '데이터베이스';

  @override
  String get server_icon_database1 => '데이터베이스 01';

  @override
  String get server_icon_database2 => '데이터베이스 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => '칩';

  @override
  String get server_icon_chip2 => '칩 02';

  @override
  String get server_icon_computer => '컴퓨터';

  @override
  String get server_icon_laptop => '노트북';

  @override
  String get server_icon_terminal => '컴퓨터 터미널';

  @override
  String get server_icon_code => '코드';

  @override
  String get server_icon_ai_brain => 'AI 브레인';

  @override
  String get server_icon_ai_brain2 => 'AI 브레인 02';

  @override
  String get server_icon_ai_cloud => 'AI 클라우드';

  @override
  String get server_icon_ai_network => 'AI 네트워크';

  @override
  String get server_icon_ai_chat => 'AI채팅';

  @override
  String get server_icon_cellular => '셀룰러 네트워크';

  @override
  String get server_icon_plug1 => '플러그 01';

  @override
  String get server_icon_plug2 => '플러그 02';

  @override
  String get server_icon_bot => '봇';

  @override
  String get server_icon_bot2 => '봇 02';

  @override
  String get server_icon_robotic => '로봇식';

  @override
  String get server_icon_rocket => '로켓';

  @override
  String get server_icon_star => '스타';

  @override
  String get server_icon_settings1 => '설정 01';

  @override
  String get server_icon_settings2 => '설정 02';

  @override
  String get server_icon_home1 => '홈 01';

  @override
  String get server_icon_home2 => '홈 02';

  @override
  String get server_icon_folder1 => '폴더 01';

  @override
  String get server_icon_folder2 => '폴더 02';

  @override
  String get server_icon_file1 => '파일 01';

  @override
  String get server_icon_lock => '잠금';

  @override
  String get server_icon_key => '키 01';

  @override
  String get server_icon_link => '링크 01';

  @override
  String get server_icon_globe => '지구본';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => '화살표 오른쪽 01';

  @override
  String get server_icon_check => '서클 확인';

  @override
  String get server_icon_alert => '경고 서클';

  @override
  String get server_icon_info => '정보 서클';

  @override
  String get server_icon_zap => '잽';

  @override
  String get server_icon_cloud_upload => '클라우드 업로드';

  @override
  String get server_icon_cloud_download => '클라우드 다운로드';

  @override
  String get server_icon_refresh => '새로고침';

  @override
  String get server_icon_hard_drive => '하드 드라이브';

  @override
  String get server_icon_drive => '드라이브';

  @override
  String get personas_title => '페르소나';

  @override
  String get persona_category_general => '일반';

  @override
  String get persona_category_coding => '코딩';

  @override
  String get persona_category_education => '교육';

  @override
  String get persona_category_creative => '크리에이티브';

  @override
  String get persona_builtin_section => '내장';

  @override
  String get persona_my_section => '내 페르소나';

  @override
  String get clone_edit => '복제 및 편집';

  @override
  String get builtin_badge => '내장';

  @override
  String get no_personas_found => '페르소나를 찾을 수 없습니다.';

  @override
  String get no_personas_desc => 'AI 동작을 맞춤화하기 위한 첫 번째 페르소나를 만드세요.';

  @override
  String get edit_persona => '페르소나 편집';

  @override
  String get create_persona => '페르소나 생성';

  @override
  String get create_persona_button => '만들기';

  @override
  String get emoji_label => '이모티콘';

  @override
  String get name_label => '이름';

  @override
  String get my_persona_hint => '내 페르소나';

  @override
  String get category_label => '카테고리';

  @override
  String get description_optional => '설명(선택사항)';

  @override
  String get description_hint => '이 인물이 하는 일은...';

  @override
  String get system_prompt => '시스템 프롬프트';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => '아직 프롬프트가 없습니다...';

  @override
  String get prompt_hint => '당신은 도움이되는 조수입니다 ...';

  @override
  String get prompt_required => '시스템 프롬프트가 필요합니다';

  @override
  String get prompt_max_chars => '최대 4000자';

  @override
  String get advanced_settings => '고급 설정';

  @override
  String get temperature_label => '온도(0.0-2.0)';

  @override
  String get top_p_label => '상위 P(0.0-1.0)';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0.9';

  @override
  String get range_0_2 => '0.0-2.0';

  @override
  String get range_0_1 => '0.0-1.0';

  @override
  String get persona_updated => '페르소나가 업데이트되었습니다.';

  @override
  String get persona_created => '페르소나가 생성되었습니다.';

  @override
  String get tts_models_title => '텍스트 음성 변환 모델';

  @override
  String get always_available => '항상 사용 가능';

  @override
  String get tts_system_desc =>
      '기기에 내장된 텍스트 음성 변환 엔진을 사용합니다.\n다운로드가 필요하지 않습니다. 음성 선택에는 장치의 시스템 설정이 사용됩니다.';

  @override
  String get downloading_status => '다운로드 중...';

  @override
  String tts_kitten_desc(String size) {
    return '8가지 표정이 풍부한 음성을 갖춘 번개처럼 빠른 신경 TTS입니다.\n$size 다운로드가 필요합니다.';
  }

  @override
  String tts_piper_desc(String size) {
    return '표현력이 풍부한 2개의 음성을 갖춘 빠른 오프라인 파이퍼 음성입니다.\n음성당 $size 다운로드가 필요합니다.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount 음성';
  }

  @override
  String get on_device_models_title => '온디바이스 모델';

  @override
  String get settings_huggingface_token => '포옹 얼굴 토큰(선택 사항)';

  @override
  String get settings_huggingface_token_desc =>
      '게이트 모델(예: Gemma)에만 필요합니다. Huggingface.co/settings/tokens에서 토큰을 받으세요.';

  @override
  String get settings_huggingface_token_set => '토큰이 저장되었습니다';

  @override
  String get settings_huggingface_token_cleared => '토큰이 삭제되었습니다';

  @override
  String get model_requires_huggingface_token => '포옹하는 얼굴 토큰이 필요합니다.';

  @override
  String get model_missing_huggingface_token =>
      '이 모델은 Hugging Face에 적용되었습니다. 설정 → 온디바이스 추론에서 토큰을 추가하여 다운로드하세요.';

  @override
  String get set_huggingface_token => '토큰 설정';

  @override
  String get clear_huggingface_token => '지우기';

  @override
  String get edit_huggingface_token_dialog_title => '포옹 얼굴 액세스 토큰';

  @override
  String get huggingface_token_dialog_hint => 'HF_…';

  @override
  String get server_type_ollama_desc => '로컬 AI 엔진. API 키가 필요하지 않습니다.';

  @override
  String get server_type_on_device_desc =>
      '휴대전화에서 실행됩니다. 일부 모델에는 Hugging Face 토큰이 필요합니다.';

  @override
  String get server_type_lm_studio_desc => '로컬 API 서버. API 키가 필요하지 않습니다.';

  @override
  String get available_models => '사용 가능한 모델';

  @override
  String get device_memory => '장치 메모리';

  @override
  String get ram_usage => 'RAM 사용량';

  @override
  String get memory_healthy => '건강하다';

  @override
  String get memory_critical => '심각';

  @override
  String get memory_low => '낮음';

  @override
  String ram_used(String percent) {
    return '$percent% 사용됨';
  }

  @override
  String get available_ram => '사용 가능한 RAM';

  @override
  String get total_capacity => '총 용량';

  @override
  String get loaded_status => '로드됨';

  @override
  String get inference_backend => '추론 백엔드';

  @override
  String get backend_ios_notice => 'iOS에서는 CPU 백엔드만 사용할 수 있습니다.';

  @override
  String get backend_cpu_desc => '모든 장치에서 작동합니다. 가장 호환됩니다.';

  @override
  String get backend_gpu_desc => 'OpenCL 가속. 지원되는 장치에서는 더 빠릅니다.';

  @override
  String get backend_npu_desc => '공급업체 NPU(Qualcomm/MediaTek). 가장 빠른 추론.';

  @override
  String get select_model_title => '모델 선택';

  @override
  String get refresh_models => '모델 새로 고침';

  @override
  String get search_models_hint => '모델 검색...';

  @override
  String get no_server_connected => '연결된 서버가 없습니다';

  @override
  String get add_server_first => '사용 가능한 모델을 보려면 먼저 서버를 추가하세요.';

  @override
  String get failed_load_models => '모델을 로드하지 못했습니다.';

  @override
  String get no_models_available => '사용 가능한 모델이 없습니다.';

  @override
  String no_models_match(String searchQuery) {
    return '\"$searchQuery\"와 일치하는 모델이 없습니다.';
  }

  @override
  String model_load_failed(String error) {
    return '모델을 로드하지 못했습니다: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return '$name에 대한 언로드가 요청되었습니다. Ollama에 접근할 수 있으면 모델이 즉시 출시됩니다.';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name가 성공적으로 언로드되었습니다.';
  }

  @override
  String model_unload_failed(String error) {
    return '모델 언로드 실패: $error';
  }

  @override
  String get unload_from_server => '서버에서 언로드';

  @override
  String context_chip(String ctx) {
    return '$ctx ctx';
  }

  @override
  String get unload_all_models => '모두 언로드';

  @override
  String loaded_models_count(int count) {
    return '$count 로드됨';
  }

  @override
  String get all_models_unloaded => '모든 모델이 언로드됨';

  @override
  String get branch_chat => '지점채팅';

  @override
  String get branch_chat_desc => '이 메시지로 새 대화를 시작하세요';

  @override
  String get edit_assistant_message_desc => '어시스턴트 응답 텍스트를 편집합니다.';

  @override
  String switch_to_model(String modelName, Object model) {
    return '$modelName로 전환';
  }

  @override
  String download_notification_title(String modelName) {
    return '$modelName 다운로드 중...';
  }

  @override
  String get download_complete_notification => '다운로드가 완료되었습니다!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName가 성공적으로 다운로드되었습니다.';
  }

  @override
  String download_failed_notification(String error) {
    return '다운로드 실패: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return '$modelName를 다운로드하지 못했습니다.';
  }

  @override
  String get engine_name_system => '시스템 TTS';

  @override
  String get engine_tagline_system => '내장 장치 엔진';

  @override
  String get engine_name_kitten => '새끼 고양이 TTS';

  @override
  String get engine_tagline_kitten => '고속 신경 TTS';

  @override
  String get engine_name_sherpa => '셰르파 ONNX VITS';

  @override
  String get engine_tagline_sherpa => '오프라인 파이퍼 목소리';

  @override
  String get voice_jasper => '재스퍼';

  @override
  String get voice_bella => '벨라';

  @override
  String get voice_bruno => '브루노';

  @override
  String get voice_luna => '루나';

  @override
  String get voice_hugo => '휴고';

  @override
  String get voice_rosie => '로지';

  @override
  String get voice_leo => '레오';

  @override
  String get voice_kiki => '키키';

  @override
  String get voice_lessac => '레삭(미국)';

  @override
  String get voice_ryan => '라이언(미국)';

  @override
  String get model_qwen_3 => '퀀 3 0.6B';

  @override
  String get model_qwen_3_desc => '가장 작은 범용 채팅 모델. 빠른 응답, 낮은 메모리 사용량.';

  @override
  String get model_license_apache => '아파치-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B 지시';

  @override
  String get model_qwen_25_desc => '균형 잡힌 품질과 크기. 일반적인 대화에 좋습니다.';

  @override
  String get model_deepseek => 'DeepSeek R1 증류 Qwen 1.5B';

  @override
  String get model_deepseek_desc => '추론 및 사고 사슬 모델. 논리적 작업에 가장 적합합니다.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => '젬마 4 E2B 교육';

  @override
  String get model_gemma_desc => '구글 플래그십 모델. 최고 품질, 더 많은 RAM이 필요합니다.';

  @override
  String export_header(String date) {
    return '*LocalMind에서 내보내기 — $date*';
  }

  @override
  String get export_role_user => '## 👤 사용자';

  @override
  String get export_role_assistant => '## 🤖 어시스턴트';

  @override
  String get export_role_system => '## ⚙️ 시스템';

  @override
  String get export_role_tool => '## 🔧 도구';

  @override
  String get export_text_user => '[사용자]';

  @override
  String get export_text_assistant => '[어시스턴트]';

  @override
  String get export_text_system => '[시스템]';

  @override
  String get export_text_tool => '[도구]';

  @override
  String get export_label_user => '사용자';

  @override
  String get export_label_assistant => '어시스턴트';

  @override
  String get export_label_system => '시스템';

  @override
  String get export_label_tool => '도구';

  @override
  String get select_model_hint => '채팅을 시작하려면 모델을 선택하세요';

  @override
  String get test_notification_title => '테스트 알림';

  @override
  String get test_notification_body => '모델 다운로드 진행에 대한 테스트 알림입니다.';

  @override
  String get tts_supports_background => '네이티브 오디오로 백그라운드 재생 지원';

  @override
  String get tts_other_services_background_note =>
      '참고: 다른 TTS 서비스는 기본 오디오로 백그라운드 재생을 지원합니다.';

  @override
  String get gguf_imported_models_title => '가져온 GGUF 모델';

  @override
  String get gguf_imported_models_empty_subtitle =>
      '장치에서 GGUF를 가져오거나 Hugging Face에서 추가하세요. 가져온 모델은 llama.cpp를 사용하여 로컬로 실행됩니다.';

  @override
  String get gguf_imported_models_ready => '로컬 추론을 위해 준비된 가져온 모델.';

  @override
  String get gguf_curated_models_subtitle =>
      'LocalMind 내에서 다운로드하고 관리할 수 있는 엄선된 온디바이스 모델.';

  @override
  String get gguf_only_supported => '이 가져오기에는 GGUF 모델만 지원됩니다.';

  @override
  String get gguf_imported_from_local_file => '로컬 파일에서 가져왔습니다.';

  @override
  String get gguf_import_failed => 'GGUF 모델을 가져오지 못했습니다.';

  @override
  String get gguf_imported_from_huggingface => 'Hugging Face에서 가져왔습니다.';

  @override
  String get gguf_import_canceled => 'GGUF 가져오기가 취소되었습니다.';

  @override
  String get gguf_enter_huggingface_url => '포옹 얼굴 GGUF URL을 입력하세요.';

  @override
  String get gguf_only_official_huggingface_urls =>
      '공식 Hugging Face GGUF URL만 지원됩니다.';

  @override
  String get gguf_use_https_url => 'GGUF 가져오기에는 HTTPS 허깅 페이스 URL을 사용하세요.';

  @override
  String get gguf_url_must_point_to_file =>
      'Hugging Face URL은 .gguf 파일을 직접 가리켜야 합니다.';

  @override
  String get gguf_unable_to_detect_file_name => 'GGUF 파일 이름을 확인할 수 없습니다.';

  @override
  String get gguf_download_empty => '다운로드한 GGUF 파일이 비어 있거나 누락되었습니다.';

  @override
  String get gguf_selected_file_missing => '선택한 모델 파일이 존재하지 않습니다.';

  @override
  String get gguf_import_action => 'GGUF 가져오기';

  @override
  String get gguf_overview_title => '나만의 GGUF 모델 가져오기';

  @override
  String get gguf_overview_subtitle =>
      '로컬 저장소에서 .gguf를 가져오거나 Hugging Face에서 바로 다운로드하세요. 가져온 모델은 이 장치에 유지되며 llama.cpp로 로드됩니다.';

  @override
  String get gguf_imported_count_label => '수입됨';

  @override
  String get gguf_local_files_label => '로컬 파일';

  @override
  String get gguf_huggingface_label => '포옹하는 얼굴';

  @override
  String get gguf_import_local_title => '로컬 GGUF 가져오기';

  @override
  String get gguf_import_local_subtitle => '이 장치에서 .gguf 파일을 복사하세요.';

  @override
  String get gguf_import_huggingface_title => '포옹 얼굴에서 가져오기';

  @override
  String get gguf_import_huggingface_subtitle => 'GGUF URL 또는 저장소 경로 붙여넣기';

  @override
  String get gguf_no_imported_title => '아직 가져온 GGUF 모델이 없습니다.';

  @override
  String get gguf_no_imported_subtitle =>
      '장치 저장소에서 자체 GGUF 파일을 가져오거나 Hugging Face URL 또는 .gguf 파일을 가리키는 저장소 경로를 붙여넣을 수 있습니다.';

  @override
  String get gguf_import_huggingface_dialog_title => 'Hugging Face에서 GGUF 가져오기';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      '직접 GGUF URL이나 \'owner/repo/blob/main/model.gguf\'와 같은 Hugging Face 저장소 경로를 붙여넣으세요. Blob 링크는 자동으로 변환됩니다.';

  @override
  String get gguf_url_or_repo_path => 'GGUF URL 또는 저장소 경로';

  @override
  String get paste => '붙여넣기';

  @override
  String get gguf_browse => 'GGUF 찾아보기';

  @override
  String get gguf_huggingface_token_ready => '허깅 페이스 토큰 준비 완료';

  @override
  String get gguf_huggingface_token_optional => '토큰은 선택사항이지만 권장됨';

  @override
  String get gguf_huggingface_token_ready_desc =>
      '저장된 토큰은 게이트 저장소 또는 개인 저장소에 자동으로 사용됩니다.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      '포옹하는 얼굴 토큰이 필요합니다. 이 GGUF가 제한되거나 비공개인 경우 설정에서 하나를 추가하세요.';

  @override
  String get gguf_downloading => 'GGUF 다운로드 중';

  @override
  String get gguf_preparing => '준비 중';

  @override
  String get gguf_preparing_download => '다운로드 준비 중...';

  @override
  String get gguf_cancel_import => '가져오기 취소';

  @override
  String get clipboard_empty => '클립보드가 비어 있습니다.';

  @override
  String get could_not_open_huggingface => '포옹 얼굴을 열 수 없습니다.';

  @override
  String get gguf_paste_url_error => 'Hugging Face GGUF URL 또는 저장소 경로를 붙여넣으세요.';

  @override
  String get gguf_blob_link => '블롭 링크';

  @override
  String get gguf_repository_label => '저장소';

  @override
  String get gguf_detected_path_label => '감지된 경로';

  @override
  String get gguf_imported_section_label => '가져온 GGUF';

  @override
  String get gguf_already_available => '이 기기에서는 이미 사용 가능합니다.';

  @override
  String get gguf_curated_models_short => '선별된 온디바이스 모델';

  @override
  String get execute_tool_title => '도구 실행';

  @override
  String get execute_tool_request_desc => '모델은 다음 도구 실행을 요청합니다.';

  @override
  String get reject => '거부';

  @override
  String get approve => '승인하다';

  @override
  String get server_type_help => '연결 세부정보를 입력하기 전에 공급자를 선택하세요.';

  @override
  String get server_identity_title => '아이덴티티';

  @override
  String get server_identity_desc => '이 서버의 이름을 지정하고 목록에 표시되는 방식을 선택합니다.';

  @override
  String get server_connection_title => '연결';

  @override
  String get server_connection_desc => '서버에서 노출된 주소와 포트를 사용하세요.';

  @override
  String get server_authentication_title => '인증';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter는 테스트하기 전에 API 키가 필요합니다.';

  @override
  String get server_authentication_optional_desc =>
      '이 서버에 API 키가 필요하지 않은 경우 API 키를 비워 두세요.';

  @override
  String get mcp_tools_title => 'MCP 도구';

  @override
  String get available_tools => '사용 가능한 도구';

  @override
  String get unable_load_tools => '도구를 로드할 수 없습니다.';

  @override
  String get no_tools_registered => '등록된 도구가 없습니다.';

  @override
  String get no_tools_registered_desc =>
      '예제 MCP 서버를 활성화하거나 채팅 설정에서 MCP 통합을 추가하세요.';

  @override
  String get example_mcp_server_title => 'MCP 서버 예';

  @override
  String get example_mcp_server_desc =>
      '외부 서버에서 사용하는 것과 동일한 MCP 도구 공급자를 통해 example.echo 및 example.word_count를 등록합니다.';

  @override
  String get disable_example_server => '예제 서버 비활성화';

  @override
  String get enable_example_server => '예제 서버 활성화';

  @override
  String get built_in_label => '내장';

  @override
  String get highlights_label => '하이라이트';

  @override
  String get built_with_label => '다음으로 제작됨';

  @override
  String get local_label => '지역';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => '요청됨';

  @override
  String get tool_status_approved => '승인됨';

  @override
  String get tool_status_rejected => '거부됨';

  @override
  String get tool_status_running => '달리기';

  @override
  String get tool_status_done => '완료';

  @override
  String get tool_status_failed => '실패';

  @override
  String get model_favorite_toggle => '즐겨찾기 전환';

  @override
  String get model_set_default => '기본 모델로 설정';

  @override
  String get model_clear_default => '기본 모델로 제거';

  @override
  String get model_default_badge => '기본값';

  @override
  String get model_note_label => '참고';

  @override
  String get model_note_hint => '이 모델에 대한 메모를 추가하세요…';

  @override
  String get unload_models_before_load => '새 모델을 로드하기 전에 모든 모델을 언로드하세요.';

  @override
  String get temp_chat_keyboard_incognito => '임시 채팅의 시크릿 키보드';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      '임시 채팅(예: SwiftKey 시크릿 모드)에서 키보드 학습 및 제안을 비활성화합니다.';

  @override
  String get resume_last_chat => '실행 시 마지막 채팅 재개';

  @override
  String get resume_last_chat_desc => '앱을 다시 열 때 마지막으로 열린 대화를 복원하세요.';

  @override
  String get export_all_data => '모든 데이터 내보내기';

  @override
  String get import_all_data => '모든 데이터 가져오기';

  @override
  String get export_data_success => '백업을 성공적으로 내보냈습니다.';

  @override
  String get import_data_success => '백업을 성공적으로 가져왔습니다.';

  @override
  String import_data_failed(String error) {
    return '백업을 가져오지 못했습니다: $error';
  }

  @override
  String get import_data_confirm =>
      '이 백업에서 대화와 맞춤 캐릭터를 가져오시겠습니까? 동일한 ID를 가진 기존 항목이 업데이트됩니다.';

  @override
  String get import_settings_confirm => '현재 설정을 가져온 백업으로 바꾸시겠습니까?';

  @override
  String get export_conversations => '대화 내보내기';

  @override
  String get import_conversations => '대화 가져오기';

  @override
  String get export_personas => '페르소나 내보내기';

  @override
  String get import_personas => '페르소나 가져오기';

  @override
  String get export_settings => '설정 내보내기';

  @override
  String get import_settings => '가져오기 설정';

  @override
  String get export_all_zip => '모두 내보내기(ZIP)';

  @override
  String get import_all_zip => '모두 가져오기(ZIP)';

  @override
  String get duplicate_chat => '중복된 채팅';

  @override
  String get duplicate_chat_success => '채팅이 중복되었습니다.';

  @override
  String get move_to_folder => '폴더로 이동';

  @override
  String get remove_from_folder => '폴더에서 제거';

  @override
  String get create_folder => '폴더 생성';

  @override
  String get new_folder => '새 폴더';

  @override
  String get folder_name_hint => '폴더 이름';

  @override
  String get all_chats => '모두';

  @override
  String get unfiled_chats => '미제출';

  @override
  String get create => '만들기';

  @override
  String get server_path_prefix_label => 'API 경로 접두사';

  @override
  String get server_path_prefix_hint => '/당신의 비밀 토큰';

  @override
  String get search_message_contents => '메시지 내용 검색';

  @override
  String get message_search_results => '메시지 일치';

  @override
  String get saved_messages_title => '저장된 메시지';

  @override
  String get nav_saved_messages => '저장된 메시지';

  @override
  String get saved_messages_empty =>
      '아직 저장된 메시지가 없습니다. 옵션 메뉴에서 메시지를 북마크에 추가하세요.';

  @override
  String get save_message => '메시지 저장';

  @override
  String get message_saved => '메시지가 저장되었습니다';

  @override
  String token_count(int count) {
    return '$count 토큰';
  }

  @override
  String estimated_token_count(int count) {
    return '~$count 토큰(추정)';
  }

  @override
  String get test_tts_section_title => '테스트 음성';

  @override
  String get test_tts_hint => '현재 TTS 엔진을 들으려면 텍스트를 입력하세요…';

  @override
  String get test_speak_button => '말하기';

  @override
  String get scroll_to_bottom => '맨 아래로 스크롤';

  @override
  String get generate_ai_response => 'AI 응답 생성';

  @override
  String get no_response => '응답 없음';

  @override
  String get export => '수출';

  @override
  String get import => '가져오기';

  @override
  String get conversations_label => '대화';

  @override
  String get personas_label => '페르소나';

  @override
  String get settings_label => '설정';

  @override
  String get export_conversation => '대화 내보내기';

  @override
  String get tts_process_markdown => '음성에 대한 마크다운 처리';

  @override
  String get tts_process_markdown_desc => '소리내어 읽기 전에 **굵게** 같은 서식을 제거하세요.';

  @override
  String get tts_skip_seconds => '건너뛰기 간격';

  @override
  String get tts_skip_seconds_desc => '재생 중 앞으로 및 되감기 점프 크기';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$seconds';
  }

  @override
  String get preview_system_prompts => '미리보기 시스템 프롬프트';

  @override
  String get welcome_message_1 => '오늘은 무엇을 도와드릴까요?';

  @override
  String get welcome_message_2 => '무엇이든 물어보세요. 귀하가 준비되면 저는 준비되어 있습니다.';

  @override
  String get welcome_message_3 => '귀하의 데이터는 로컬에서 처리되며 절대로 귀하의 장치를 떠나지 않습니다.';

  @override
  String get welcome_message_4 => '아이디어가 필요하신가요? 빠른 프롬프트 중 하나를 시도해 보세요.';

  @override
  String get temporary_chat => '임시 채팅';

  @override
  String get temporary_chat_desc => '채팅은 기록에 저장되지 않습니다.';

  @override
  String get temporary_chat_banner => '임시 채팅 - 기록에 저장되지 않음';

  @override
  String get temporary_chat_save_warning_title => '임시 채팅에 메시지를 저장하시겠습니까?';

  @override
  String get temporary_chat_save_warning_body =>
      '이 채팅은 일시적이며 기록에서 숨겨집니다. 저장된 메시지는 저장된 메시지에 계속 표시됩니다.';

  @override
  String get save_to_history => '기록에 저장';

  @override
  String get share_conversation => '대화 공유';

  @override
  String get download_tts_audio => '오디오 다운로드';

  @override
  String get tts_download_unavailable => '다운로드는 Piper 및 Kitten TTS에서만 가능합니다.';

  @override
  String get tts_download_no_audio => '아직 다운로드할 수 있는 오디오가 없습니다.';

  @override
  String get tts_download_success => '오디오가 저장되었습니다';

  @override
  String get return_to_chat => '채팅으로 돌아가기';

  @override
  String get return_to_temp_chat => '임시 채팅으로 돌아가기';

  @override
  String get insert_saved_message => '저장된 메시지 삽입';

  @override
  String get insert_saved_message_desc => '입력에 추가할 저장된 메시지를 선택하세요.';

  @override
  String get model_info => '모델 정보';

  @override
  String get model_name => '모델명';

  @override
  String get model_identifier => '식별자';

  @override
  String get model_capabilities => '기능';

  @override
  String get model_api_pricing => 'API 가격(100만 개 토큰당)';

  @override
  String get not_available => '사용할 수 없음';

  @override
  String get save_message_folders => '메시지 저장';

  @override
  String get remove_from_saved => '저장된 항목에서 삭제';

  @override
  String get message_already_saved => '저장됨';

  @override
  String get stream_ttft => '첫 번째 토큰까지의 시간';

  @override
  String get stream_tokens_per_sec => '초당 토큰';

  @override
  String get stream_stop_reason => '중지 이유';

  @override
  String get stream_input_tokens => '입력 토큰';

  @override
  String get stream_output_tokens => '출력 토큰';

  @override
  String get stream_generation_time => '생성 시간';

  @override
  String get attach_image => '사진';

  @override
  String get attach_text_document => '문서';

  @override
  String get attach_shortcut_images => '사진';

  @override
  String get attach_shortcut_documents => '파일';

  @override
  String get attach_shortcut_saved => '저장됨';

  @override
  String get add_attachment => '첨부파일 추가';

  @override
  String get add_to_chat => '채팅에 추가';

  @override
  String get choose_what_to_attach => '무엇을 추가하고 싶으신가요?';

  @override
  String get choose_attachment_subtitle => '메시지에 첨부할 소스를 선택하세요.';

  @override
  String get photo_permission_denied => '이미지를 첨부하려면 사진 접근권한이 필요합니다';

  @override
  String get select_model_prompt => '모델 선택';

  @override
  String get characters_label => '캐릭터';

  @override
  String get exit_temporary_chat_title => '임시 채팅을 종료하시겠습니까?';

  @override
  String get exit_temporary_chat_body => '현재 임시 채팅이 삭제되고 새 채팅으로 돌아갑니다.';

  @override
  String get saved_message_temp_snap_unavailable =>
      '이 메시지는 임시 채팅에서 저장되었으므로 원래 대화에서는 열 수 없습니다.';

  @override
  String get filter_title => '필터';

  @override
  String get filter_pinned => '고정됨';

  @override
  String get filter_archived => '보관됨';

  @override
  String get filter_temp_chats => '임시 채팅';

  @override
  String get filter_user_messages => '사용자 메시지';

  @override
  String get filter_assistant_messages => '어시스턴트 메시지';

  @override
  String get archive_chat => '아카이브';

  @override
  String get unarchive_chat => '보관 취소';

  @override
  String conversation_message_count(int count) {
    return '$count개의 메시지';
  }

  @override
  String conversation_character_count(int count) {
    return '$count 문자';
  }

  @override
  String get generate_title_with_ai => 'AI로 생성';

  @override
  String get generating_title => '생성 중...';

  @override
  String get generate_title_failed => '제목을 생성할 수 없습니다.';

  @override
  String get lm_studio_model_browser_title => '모델 찾아보기';

  @override
  String get lm_studio_model_search_hint => '이름이나 작성자로 모델 검색…';

  @override
  String get lm_studio_staff_picks => '직원 추천';

  @override
  String get lm_studio_community_models => '커뮤니티 모델';

  @override
  String get lm_studio_no_models => '모델을 찾을 수 없습니다.';

  @override
  String lm_studio_models_count(int count) {
    return '$count 모델';
  }

  @override
  String get lm_studio_browse_models => '탐색 및 다운로드';

  @override
  String get lm_studio_model_search => 'LMS 모델 검색';

  @override
  String get lm_studio_downloads_title => '다운로드';

  @override
  String get lm_studio_choose_quant => '다운로드 옵션을 선택하세요';

  @override
  String get lm_studio_use_default_quant => '기본값 사용';

  @override
  String get lm_studio_recommended => '추천';

  @override
  String get lm_studio_clear_downloads => '클리어 완료';

  @override
  String get lm_studio_no_downloads => '아직 다운로드가 없습니다.';

  @override
  String get lm_studio_downloads_disclaimer =>
      '다운로드는 LM Studio 호스트에서 실행됩니다. 모델 일시 중지, 중지 및 삭제는 이 앱이 아닌 해당 컴퓨터에서 수행되어야 합니다.';

  @override
  String get lm_studio_staff_pick => '스탭픽';

  @override
  String get lm_studio_params => '매개변수';

  @override
  String get lm_studio_arch => '아치';

  @override
  String get lm_studio_domain => '도메인';

  @override
  String get lm_studio_format => '형식';

  @override
  String get lm_studio_vision => '비전';

  @override
  String get lm_studio_tool_use => '도구 사용';

  @override
  String get lm_studio_reasoning => '추론';

  @override
  String get openrouter_pricing_free => '무료';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return '입력 $input / 1M 토큰당 $output 출력';
  }

  @override
  String get lm_studio_download_options => '다운로드 옵션';

  @override
  String get lm_studio_download => '다운로드';

  @override
  String lm_studio_download_size(String size) {
    return '$size 다운로드';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return '$percent% 다운로드 중';
  }

  @override
  String get lm_studio_readme_unavailable => '이 모델에는 README가 제공되지 않습니다.';

  @override
  String get lm_studio_full_gpu_offload => '전체 GPU 오프로드 가능';

  @override
  String get lm_studio_partial_gpu_offload => '부분 GPU 오프로드 가능';

  @override
  String get lm_studio_likely_too_large => '너무 클 것 같음';

  @override
  String get lm_studio_available_ram_gb => '사용 가능한 RAM(GB, 옵션)';

  @override
  String get lm_studio_available_vram_gb => '사용 가능한 VRAM(GB, 옵션)';

  @override
  String get lm_studio_memory_settings_title => '추천을 위한 메모리';

  @override
  String get lm_studio_memory_settings_desc =>
      '모델 브라우저에서 모델이 귀하의 컴퓨터에 적합한지 여부를 추정하는 데 사용됩니다.';

  @override
  String get think_button_label => '생각하다';

  @override
  String get thinking_mode_title => '사고 모드';

  @override
  String get reasoning_effort_low => '낮음';

  @override
  String get reasoning_effort_medium => '중간';

  @override
  String get reasoning_effort_high => '높음';

  @override
  String get reasoning_effort_minimal => '최소';

  @override
  String get reasoning_effort_xhigh => '엑스하이';

  @override
  String get reasoning_effort_max => '맥스';

  @override
  String get reasoning_effort_off => '끄기';

  @override
  String get could_not_read_file => '파일을 읽을 수 없습니다.';

  @override
  String get server_offline => '서버 오프라인';

  @override
  String get could_not_establish_connection =>
      '서버에 연결을 설정할 수 없습니다. 서버가 실행 중인지, 호스트/포트 설정이 올바른지 확인하세요.';

  @override
  String get retry_connection => '연결 재시도';

  @override
  String get tokens_label => '토큰';

  @override
  String get enter_context_length => '컨텍스트 길이를 입력하세요...';

  @override
  String get openrouter_disclosure =>
      '이 공급자를 연결하면 귀하의 채팅 메시지와 입력 내용이 해당 공급자의 서버로 전송됩니다. LocalMind는 대화를 추적하거나 저장하지 않습니다.';

  @override
  String get welcome_message_cloud => '귀하의 메시지는 연결된 공급자에게 전송됩니다.';

  @override
  String get privacy_policy => '개인 정보 보호 정책';

  @override
  String get cloud_sync => 'S3 클라우드 동기화';

  @override
  String get cloud_sync_description => '자체 S3 호환 서버에 대한 엔드투엔드 암호화 동기화';

  @override
  String get cloud_sync_endpoint => '엔드포인트 URL';

  @override
  String get cloud_sync_bucket => '버킷';

  @override
  String get cloud_sync_region => '지역';

  @override
  String get cloud_sync_prefix => '접두사';

  @override
  String get cloud_sync_access_key => '액세스 키 ID';

  @override
  String get cloud_sync_secret_key => '비밀 액세스 키';

  @override
  String get cloud_sync_session_token => '세션 토큰(선택사항)';

  @override
  String get cloud_sync_passphrase => '암호화 암호';

  @override
  String get cloud_sync_confirm_passphrase => '암호 확인';

  @override
  String get cloud_sync_path_style => '경로 스타일 주소 지정 사용';

  @override
  String get cloud_sync_allow_http => '안전하지 않은 HTTP 허용';

  @override
  String get cloud_sync_http_warning =>
      'HTTP는 요청 메타데이터와 자격 증명을 네트워크에 노출합니다. 신뢰할 수 있는 로컬 S3 서버에만 사용하세요.';

  @override
  String get cloud_sync_test => '테스트 연결';

  @override
  String get cloud_sync_enable => '암호화된 동기화 활성화';

  @override
  String get cloud_sync_now => '지금 동기화';

  @override
  String get cloud_sync_disconnect => '이 장치를 연결 해제하세요';

  @override
  String get cloud_sync_last_synced => '마지막 동기화';

  @override
  String get cloud_sync_never => '절대로';

  @override
  String get cloud_sync_conflicts => '충돌이 보존됨';

  @override
  String get cloud_sync_passphrase_mismatch => '암호가 일치하지 않습니다.';

  @override
  String get crash_report_title => '문제가 발생했습니다.';

  @override
  String get crash_report_stack_trace => '스택 추적';

  @override
  String get crash_report_tap_to_expand => '펼치려면 탭하세요.';

  @override
  String get crash_report_button => '충돌 신고';

  @override
  String get crash_try_again => '다시 시도하세요';

  @override
  String get crash_report_empty_stack => '<비어있음>';

  @override
  String get crash_report_disclaimer =>
      '보고를 수행하면 진단이 미리 입력된 GitHub가 열립니다. 귀하가 직접 제어할 수 있습니다. 아무것도 자동으로 제출되지 않습니다. 제출하기 전에 민감한 콘텐츠를 검토하고 삭제하시기 바랍니다.';

  @override
  String get crash_report_copied => '클립보드에 복사됨';

  @override
  String get report_a_problem => '문제 신고';

  @override
  String get rename_folder => '폴더 이름 바꾸기';

  @override
  String get delete_folder => '폴더 삭제';

  @override
  String get delete_folder_title => '폴더를 삭제하시겠습니까?';

  @override
  String delete_folder_body(String name) {
    return '정말로 \"$name\"을 삭제하시겠습니까? 대화 또는 내부에 저장된 메시지는 \'파일 없음\'으로 다시 이동됩니다. 이 작업은 취소할 수 없습니다.';
  }

  @override
  String get folder_name_required => '폴더 이름을 입력하세요.';

  @override
  String get model_required_toast => '먼저 모델을 선택해야 합니다.';

  @override
  String get settings_concise_voice_responses => '간결한 음성 모드 응답';

  @override
  String get settings_concise_voice_responses_desc =>
      'LLM 응답을 간략하게(짧은 문단 1개) 유지하고 음성 모드에서 후속 질문을 하세요.';

  @override
  String get s3_connection_succeeded => 'S3 연결에 성공했습니다.';

  @override
  String failed_to_open_url(String error) {
    return 'URL을 열지 못했습니다: $error';
  }

  @override
  String failed_to_copy(String error) {
    return '복사 실패: $error';
  }

  @override
  String get file_explorer_not_found =>
      '파일 탐색기를 찾을 수 없습니다. 파일 관리자 앱이 장치에 설치되어 활성화되어 있는지 확인하세요.';

  @override
  String export_data_failed(String error) {
    return '백업 내보내기 실패: $error';
  }

  @override
  String file_pick_failed(String error) {
    return '파일 선택 실패: $error';
  }

  @override
  String image_pick_failed(String error) {
    return '이미지 선택 실패: $error';
  }

  @override
  String get calendar_access => '캘린더 액세스';

  @override
  String get calendar_access_desc => 'AI가 캘린더 이벤트를 읽고 생성하도록 허용';

  @override
  String get calendar_permission_denied =>
      '캘린더 권한이 거부되었습니다. 기기 설정에서 캘린더 액세스 권한을 부여하세요.';

  @override
  String get location_access => '위치 접근';

  @override
  String get location_access_desc => 'AI가 장소 이름으로 현재 위치를 가져오도록 허용';

  @override
  String get location_permission_denied =>
      '위치 권한이 거부되었습니다. 기기 설정에서 위치 액세스 권한을 부여하세요.';

  @override
  String get builtin_ai_not_supported => '내장 AI는 이 장치에서 지원되지 않습니다.';

  @override
  String get builtin_ai_unsupported_desc =>
      '귀하의 장치 하드웨어 또는 OS는 온디바이스 시스템 AI(예: Gemini Nano / Apple Intelligence)를 지원하지 않습니다. 대신 다운로드 가능한 모델을 선택하세요.';

  @override
  String get builtin_ai_unsupported_chip => '지원되지 않음';

  @override
  String get builtin_ai_enable => '활성화';

  @override
  String get model_reasoning_default => '모델 기본값';

  @override
  String get model_reasoning_on => '켜짐';

  @override
  String get model_reasoning_help =>
      '다음 응답에 적용됩니다. 모델의 채팅 템플릿이 지원하는 경우 끄면 사고가 비활성화됩니다.';

  @override
  String get model_reasoning_save_error => '사고 모드를 저장하지 못했습니다. 다시 시도해 주세요.';
}
