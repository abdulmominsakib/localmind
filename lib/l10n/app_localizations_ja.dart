// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Japanese (`ja`).
class AppLocalizationsJa extends AppLocalizations {
  AppLocalizationsJa([String locale = 'ja']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'ローカルAI。プライバシーを保護して、あなたのルールで。';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'キャンセル';

  @override
  String get confirm => '確認';

  @override
  String get delete => '削除';

  @override
  String get save => '保存';

  @override
  String get retry => '再試行';

  @override
  String get close => '閉じる';

  @override
  String get done => '完了';

  @override
  String get continue_action => '続行';

  @override
  String get skip => 'スキップ';

  @override
  String get install => 'インストール';

  @override
  String get download => 'ダウンロード';

  @override
  String get resume => '再開';

  @override
  String get pause => '一時停止';

  @override
  String get stop => '停止';

  @override
  String get edit => '編集';

  @override
  String get preview => 'プレビュー';

  @override
  String get unload => 'アンロード';

  @override
  String get load => 'ロード';

  @override
  String get rename => '名前変更';

  @override
  String get pin => 'ピン留め';

  @override
  String get unpin => 'ピン留め解除';

  @override
  String get share => '共有';

  @override
  String get copy => 'コピー';

  @override
  String get copied => 'コピーしました！';

  @override
  String get copied_to_clipboard => 'クリップボードにコピーしました';

  @override
  String get select => '選択';

  @override
  String get active => 'アクティブ';

  @override
  String get all => 'すべて';

  @override
  String get none => 'なし';

  @override
  String get none_selected => '未選択';

  @override
  String get online => 'オンライン';

  @override
  String get offline => 'オフライン';

  @override
  String get error => 'エラー';

  @override
  String get unknown_error => '不明なエラー';

  @override
  String get not_now => '後で';

  @override
  String get enable => '有効にする';

  @override
  String get proceed_anyway => 'このまま続行';

  @override
  String get test_connection => '接続テスト';

  @override
  String get testing => 'テスト中...';

  @override
  String get connection_successful => '接続に成功しました！';

  @override
  String get connection_failed => '接続に失敗しました。設定を確認してください。';

  @override
  String get save_continue => '保存して続行';

  @override
  String get save_changes => '変更を保存';

  @override
  String get finish_setup => 'セットアップを完了';

  @override
  String get start_new_chat => '新しいチャットを開始';

  @override
  String get cannot_undo => 'この操作は取り消せません。';

  @override
  String get ram_warning => 'RAM警告';

  @override
  String get recommended => '推奨';

  @override
  String get may_be_large => 'このデバイスには大きすぎる可能性があります';

  @override
  String get calculating => '計算中...';

  @override
  String get download_failed => 'ダウンロード失敗';

  @override
  String get downloaded => 'ダウンロード済み';

  @override
  String get not_downloaded => '未ダウンロード';

  @override
  String get installed => 'インストール済み';

  @override
  String get not_installed => '未インストール';

  @override
  String get loading => '読み込み中...';

  @override
  String get thinking => '思考中';

  @override
  String get processing => '処理中...';

  @override
  String get initializing => '初期化中...';

  @override
  String get ready => '準備完了';

  @override
  String get preparing_app => 'アプリを準備中...';

  @override
  String get initializing_services => 'サービスを初期化中...';

  @override
  String get configuring_server => 'サーバーを構成中...';

  @override
  String get startup_failed => '起動に失敗しました';

  @override
  String get something_went_wrong => '問題が発生しました';

  @override
  String get delete_model_title => 'モデルを削除';

  @override
  String delete_model_body(String name) {
    return '$name を削除してもよろしいですか？';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return '$name を削除してもよろしいですか？これにより約 $size の空き容量が増えます。\n\n必要に応じて、このモデルは後で再ダウンロードできます。';
  }

  @override
  String get delete_voice_title => '音声の削除';

  @override
  String delete_voice_body(String name, String size) {
    return '$name を削除してもよろしいですか？これにより約 $size の空き容量が増えます。\n\n必要に応じて、この音声は後で再ダウンロードできます。';
  }

  @override
  String get delete_server_title => 'サーバーの削除';

  @override
  String delete_server_body(String name) {
    return '本当に「$name」を削除しますか？この操作は取り消せません。';
  }

  @override
  String get delete_conversation_title => 'チャットを削除しますか？';

  @override
  String delete_conversation_body(String title) {
    return '本当に「$title」を削除しますか？この操作は取り消せません。';
  }

  @override
  String get delete_message_title => 'メッセージを削除しますか？';

  @override
  String delete_persona_title(String name) {
    return '「$name」を削除しますか？';
  }

  @override
  String get delete_persona_body => 'この操作は取り消せません。';

  @override
  String get delete_builtin_persona_body =>
      'This is a built-in persona. You can restore it later from Settings.';

  @override
  String get restore_builtin_personas => 'Restore default personas';

  @override
  String get restore_builtin_personas_desc =>
      'Re-add any built-in personas you\'ve deleted';

  @override
  String get restore_builtin_personas_success => 'Default personas restored';

  @override
  String get clear_personas => 'Clear personas';

  @override
  String get enable_image_compression => 'Compress images before sending';

  @override
  String get enable_image_compression_desc =>
      'Resize and compress attached images so uploads stay within server limits';

  @override
  String get image_compression_level => 'Compression aggressiveness';

  @override
  String get image_compression_level_desc =>
      'Higher aggressiveness produces smaller uploads at lower quality';

  @override
  String get image_compression_level_low => 'Low';

  @override
  String get image_compression_level_medium => 'Medium';

  @override
  String get image_compression_level_high => 'High';

  @override
  String get sort_models_tooltip => 'Sort models';

  @override
  String get sort_by_favorites => 'Favorites first';

  @override
  String get sort_by_name => 'Name (A-Z)';

  @override
  String get sort_by_size_smallest => 'Size (smallest first)';

  @override
  String get sort_by_size_largest => 'Size (largest first)';

  @override
  String get sort_by_context_length => 'Context length';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Renaming $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '$count selected';
  }

  @override
  String get ai_rename_tooltip => 'Rename selected with AI';

  @override
  String get new_chat_in_folder_tooltip => 'New chat in this folder';

  @override
  String total_tokens_count(int count) {
    return '$count tokens';
  }

  @override
  String get smart_replies_use_persona => 'Use persona in smart replies';

  @override
  String get smart_replies_use_persona_desc =>
      'Suggested replies match the tone of the active persona instead of a generic assistant';

  @override
  String get keep_persona_on_new_chat => 'Keep persona on new chat';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Don\'t clear the selected persona(s) after starting a new chat';

  @override
  String get role_swap_button_enabled => 'Show role-swap button';

  @override
  String get role_swap_button_enabled_desc =>
      'Show a button in the chat input to send your message as the assistant instead of the user, without generating a response';

  @override
  String get send_as_user_tooltip => 'Send as user';

  @override
  String get send_as_assistant_tooltip => 'Send as assistant (no response)';

  @override
  String get insert_without_generating_tooltip => 'Insert without generating';

  @override
  String get token_usage_title => 'Token Usage';

  @override
  String get total_tokens_label => 'Tokens used';

  @override
  String get usage_percent_label => 'Context used';

  @override
  String get export_choice_title => 'Export';

  @override
  String get export_choice_body => 'How would you like to export this?';

  @override
  String get copy_to_clipboard => 'Copy to Clipboard';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Exported $count conversations';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Rename with AI?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'This will ask the AI to generate a new title for each of the $count selected conversations, replacing their current titles. This can take a while and cannot be undone.';
  }

  @override
  String get sort_by_modified_date => 'Last modified';

  @override
  String get sort_by_created_date => 'Date created';

  @override
  String get sort_title => 'Sort';

  @override
  String get clear_conversation_title => 'チャット履歴をクリアしますか？';

  @override
  String get clear_conversation_body => 'このチャット内のすべてのメッセージが削除されます。';

  @override
  String get clear => 'クリア';

  @override
  String label_completed(String label) {
    return '$label が完了しました';
  }

  @override
  String error_with_message(String error) {
    return 'エラー: $error';
  }

  @override
  String preview_failed(String error) {
    return 'プレビューに失敗しました: $error';
  }

  @override
  String loading_model(String modelId) {
    return '$modelId を読み込み中...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'モデルを読み込みました: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'モデルが読み込まれていません。「ローカルモデルの管理」をタップしてモデルをダウンロードし、読み込んでください。';

  @override
  String loading_model_error(String error) {
    return 'エラー: $error';
  }

  @override
  String get delete_conversation => 'チャットを削除しますか？';

  @override
  String get nav_history => '履歴';

  @override
  String get nav_servers => 'サーバー';

  @override
  String get nav_local_models => 'ローカルモデル';

  @override
  String get nav_tts => '音声合成';

  @override
  String get nav_personas => 'ペルソナ';

  @override
  String get nav_settings => '設定';

  @override
  String get nav_new_chat => '新しいチャット';

  @override
  String get search_hint => 'チャットを検索...';

  @override
  String get no_server_selected => 'サーバーが選択されていません';

  @override
  String get switch_server => 'サーバー切り替え';

  @override
  String get switch_server_subtitle => '接続するサーバーを選択してください';

  @override
  String get manage_servers => 'サーバーの管理';

  @override
  String get open_source => 'オープンソース';

  @override
  String get open_source_desc =>
      'LocalMind はオープンソースです。GitHub で開発状況の確認や貢献ができます。';

  @override
  String get star_on_github => 'GitHub でスターを付ける';

  @override
  String get add_more => 'さらに追加';

  @override
  String get on_github => 'GitHub で';

  @override
  String get could_not_open_github => 'GitHub を開けませんでした。';

  @override
  String get settings_title => '設定';

  @override
  String get settings_appearance => '外観';

  @override
  String get settings_language => '言語';

  @override
  String get language_system_default => 'システムデフォルト';

  @override
  String get settings_tts => '音声合成';

  @override
  String get settings_behavior => '動作';

  @override
  String get settings_on_device => 'ローカル推論';

  @override
  String get settings_default_server => 'デフォルトサーバー';

  @override
  String get settings_default_persona => 'デフォルトペルソナ';

  @override
  String get settings_privacy => 'プライバシー';

  @override
  String get settings_data_management => 'データ管理';

  @override
  String get settings_about => 'LocalMind について';

  @override
  String get theme => 'テーマ';

  @override
  String get theme_system => 'システム';

  @override
  String get theme_light => 'ライト';

  @override
  String get theme_dark => 'ダーク';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'フォントサイズ';

  @override
  String get font_size_desc => 'チャットのテキストサイズを調整します。';

  @override
  String get font_preview => 'これはテキストの表示サイズ確認用のプレビューです。';

  @override
  String get code_theme_dark => 'コードテーマ (ダーク)';

  @override
  String get code_theme_light => 'コードテーマ (ライト)';

  @override
  String get code_theme_desc => 'コードブロックのシンタックスハイライトテーマを選択します。';

  @override
  String get tts_engine => '音声合成エンジン';

  @override
  String get tts_engine_system => 'システム音声合成';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => '音声';

  @override
  String get voice_female => '女性';

  @override
  String get voice_male => '男性';

  @override
  String get voice_other => 'その他';

  @override
  String get tts_speed => '読み上げ速度';

  @override
  String get tts_speed_desc => '再生速度を調整します。';

  @override
  String get manage_tts_models => '音声合成モデルの管理';

  @override
  String get manage_on_device_models => 'ローカルモデルの管理';

  @override
  String get enable_smart_reply => 'スマートリプライ';

  @override
  String get ai_user_response_enabled => 'AI user message (hold send)';

  @override
  String get ai_user_response_enabled_desc =>
      'Hold the send button for 3 seconds to have the AI write and send your next message';

  @override
  String get ai_user_response_tooltip => 'Generate user message with AI';

  @override
  String get streaming_responses => 'ストリーミング応答';

  @override
  String get auto_generate_titles => 'タイトルの自動生成';

  @override
  String get send_on_enter => 'Enterキーで送信';

  @override
  String get show_system_messages => 'システムメッセージを表示';

  @override
  String get show_system_messages_desc =>
      'When no persona is selected, send a default assistant system prompt with each request';

  @override
  String get show_system_messages_in_chat => 'Show System Messages in Chat';

  @override
  String get show_system_messages_in_chat_desc =>
      'Display system messages (e.g. from an imported backup) as visible bubbles in the conversation';

  @override
  String get haptic_feedback => '触覚フィードバック';

  @override
  String get enable_mcp => 'MCPを有効化';

  @override
  String get new_chat_mcp_default => '新規チャットでMCPをデフォルトにする';

  @override
  String get show_data_indicator => 'データインジケーターを表示';

  @override
  String get privacy_info => '「LocalMindがあなたのデータを閲覧することはありません」';

  @override
  String get delete_all_conversations => 'すべてのチャット履歴を削除';

  @override
  String get reset_settings_defaults => '設定をデフォルトに戻す';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'チャットパラメータ';

  @override
  String get change_persona => 'ペルソナを変更';

  @override
  String get set_persona => 'ペルソナを設定';

  @override
  String get remove_persona => 'ペルソナを削除';

  @override
  String get clear_conversation => '履歴をクリア';

  @override
  String get connection_error => '接続エラー。サーバーを確認してください。';

  @override
  String get disconnected => 'サーバーから切断されました。';

  @override
  String get configure => '構成';

  @override
  String get select_model => 'モデルを選択';

  @override
  String get select_persona => 'ペルソナを選択';

  @override
  String get manage_personas => 'Manage personas';

  @override
  String get personas_combine_hint =>
      'Select multiple personas in chat to stack their system prompts.';

  @override
  String get start_conversation => 'チャットを開始しましょう';

  @override
  String get recent_chats => '最近のチャット';

  @override
  String get see_all => 'すべて見る';

  @override
  String get quick_write => '関数の作成をサポートして';

  @override
  String get quick_explain => 'このコードを説明して';

  @override
  String get quick_debug => 'デバッグして';

  @override
  String get quick_async => 'async/await はどう使えばいい？';

  @override
  String get history_missing_title => '履歴が見つかりません';

  @override
  String get history_missing_desc => 'このチャットのメッセージが削除されたか、履歴レコードが破損しています。';

  @override
  String get technical_details => '技術的な詳細';

  @override
  String get last_error => '最後のエラー:';

  @override
  String get copy_info => '情報をコピー';

  @override
  String get conversation_id => '会話ID';

  @override
  String get created_at => '作成日時';

  @override
  String get expected_messages => '期待されるメッセージ数';

  @override
  String get debug_dialog_desc => '同期の問題を特定するための診断情報。';

  @override
  String get chat_input_hint => '何でも質問してください';

  @override
  String get send_message_tooltip => 'メッセージを送信';

  @override
  String get stop_generation_tooltip => '生成を停止';

  @override
  String get attach_images_tooltip => '画像を添付';

  @override
  String get start_listening_tooltip => '聞き取りを開始';

  @override
  String get stop_listening_tooltip => '聞き取りを停止';

  @override
  String tool_label(String toolCallId) {
    return 'ツール: $toolCallId';
  }

  @override
  String get tool_unknown => 'ツール: 不明';

  @override
  String get message_options => 'メッセージオプション';

  @override
  String get copy_markdown => 'Markdownとしてコピー';

  @override
  String get copied_markdown => 'Markdownとしてコピーしました';

  @override
  String get read_aloud => '読み上げる';

  @override
  String get stop_reading => '読み上げを停止';

  @override
  String get more => 'その他';

  @override
  String character_count(int length) {
    return '$length 文字';
  }

  @override
  String get edit_message => 'メッセージを編集';

  @override
  String get edit_message_desc => '保存すると、以下の応答が削除され、再生成されます。';

  @override
  String get save_regenerate => '保存して再生成';

  @override
  String get chat_settings_title => 'チャット設定';

  @override
  String get reset_defaults => 'デフォルトに戻す';

  @override
  String get parameters_tab => 'パラメータ';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => '温度';

  @override
  String get temperature_desc => 'ランダム性を制御：高い＝創造的、低い＝集中';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => '核サンプリングしきい値';

  @override
  String get max_tokens => '最大トークン数';

  @override
  String get max_tokens_desc => '応答制限';

  @override
  String get context_length => 'コンテキスト長';

  @override
  String get context_length_desc => '履歴ウィンドウ';

  @override
  String get mcp_disabled_warning => 'MCPはグローバルで無効化されています。設定画面から有効化して使用してください。';

  @override
  String get mcp_enable_chat => 'このチャットでMCPを有効化';

  @override
  String get auto_execute_tools => 'ツールの自動実行';

  @override
  String get beta_label => 'ベータ';

  @override
  String get experimental_label => '実験的';

  @override
  String get add_ephemeral_mcp => '一時的なMCPサーバーを追加';

  @override
  String get mcp_label_placeholder => 'ラベル';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => '有効な統合';

  @override
  String get enable_notifications => '通知を有効にする';

  @override
  String get enable_notifications_desc => 'モデルのダウンロード完了時に通知を受け取ります。';

  @override
  String get chat_history_title => 'チャット履歴';

  @override
  String get conversation_just_now => 'たった今';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes分前';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours時間前';
  }

  @override
  String get conversation_yesterday => '昨日';

  @override
  String conversation_days_ago(int days) {
    return '$days日前';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$year/$month/$day';
  }

  @override
  String get options_tooltip => 'オプション';

  @override
  String get no_results_found => '結果が見つかりません';

  @override
  String get no_conversations_yet => 'チャット履歴がまだありません';

  @override
  String get try_different_search => '別の検索ワードを試してください';

  @override
  String get start_new_conversation => '新しいチャットを開始する';

  @override
  String get rename_conversation => 'チャットの名前を変更';

  @override
  String get enter_new_title => '新しいタイトルを入力';

  @override
  String get pinned_section => 'ピン留め済み';

  @override
  String get today_section => '今日';

  @override
  String get yesterday_section => '昨日';

  @override
  String get previous_7_days => '過去 7 日間';

  @override
  String get previous_30_days => '過去 30 日間';

  @override
  String get older_section => '過去';

  @override
  String get onboarding_choose_language => '言語の選択';

  @override
  String get onboarding_choose_language_desc =>
      '優先する言語を選択してください。この設定はいつでも変更できます。';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'サーバーへの接続';

  @override
  String get onboarding_connect_desc =>
      'LM Studio、Ollama、またはOpenRouterに接続して、プライベートAI体験を開始しましょう。';

  @override
  String get openai_compatible_api => 'OpenAI 互換 API';

  @override
  String get https_requires_ssl => 'HTTPS には SSL が必要です';

  @override
  String get most_local_setups_use_http => 'ほとんどのローカル設定では http:// を使います';

  @override
  String get onboarding_welcome => 'Welcome to LocalMind';

  @override
  String get server_type_on_device => 'ローカル';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => '統合クラウド';

  @override
  String get ready_continue => '続行可能';

  @override
  String get waiting_selection => '選択待ち';

  @override
  String get setup_connection => '接続のセットアップ';

  @override
  String setup_connection_desc(String server) {
    return 'チャットを開始するには、$server サーバーを構成してください。';
  }

  @override
  String get server_name => 'サーバー名';

  @override
  String get name_required => '名前は必須です';

  @override
  String get name_max_50 => '最大50文字';

  @override
  String get host_label => 'ホスト / IPアドレス';

  @override
  String get host_required => 'ホストは必須です';

  @override
  String get port_label => 'ポート';

  @override
  String get port_required => 'ポートは必須です';

  @override
  String get port_invalid => '数値である必要があります';

  @override
  String get port_range => '有効なポート番号（1-65535）を入力してください';

  @override
  String get api_key_required => 'APIキー *';

  @override
  String get api_key_optional => 'APIキー（オプション）';

  @override
  String get api_key_required_openrouter => 'OpenRouterにはAPIキーが必要です';

  @override
  String get api_key_format => 'OpenRouterのAPIキーは sk- で始まります';

  @override
  String get my_server_hint => 'マイサーバー';

  @override
  String get name_length_validation => '名前は50文字以内にする必要があります';

  @override
  String get host_valid => '有効なホスト名またはIPアドレスを入力してください';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => '認証が必要なサーバー用';

  @override
  String get update_server => 'サーバーを更新';

  @override
  String get save_server => 'サーバーを保存';

  @override
  String get server_updated => 'サーバーを更新しました';

  @override
  String get server_added => 'サーバーを追加しました';

  @override
  String get download_model_title => 'モデルのダウンロード';

  @override
  String get download_model_desc =>
      'ダウンロードするモデルを選択してください。\nモデルはデバイス上でローカルに実行されます。';

  @override
  String get on_device_android_only => 'ローカル推論は現在Androidのみで利用可能です。';

  @override
  String get total_ram => '合計 RAM';

  @override
  String get available => '利用可能';

  @override
  String ram_min_required(String fileSize) {
    return '最低 $fileSize GB RAM';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return '残り時間: $eta';
  }

  @override
  String paused_progress(String percent) {
    return '一時停止中 - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'このモデルは少なくとも $ram GB のRAMを必要としますが、お使いのデバイスのRAMは $totalMemory です。正常に動作しないか、アプリがクラッシュする原因になる可能性があります。';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'デバイスの利用可能RAMは $availableRAM ですが、このモデルは少なくとも $ram GB を推奨しています。ロードに失敗するか、不安定になる可能性があります。';
  }

  @override
  String get choose_theme => 'テーマの選択';

  @override
  String get choose_theme_desc => 'アプリの外観をパーソナライズします。この設定は後からいつでも変更できます。';

  @override
  String get theme_card_system => 'システム';

  @override
  String get theme_card_system_sub => 'デバイスの設定に合わせる';

  @override
  String get theme_card_light => 'ライト';

  @override
  String get theme_card_light_sub => 'クリーンで明るい外観';

  @override
  String get theme_card_dark => 'ダーク';

  @override
  String get theme_card_dark_sub => '目に優しい外観';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => '温かみのあるピーチ調のテーマ';

  @override
  String get stay_updated => '最新情報を維持';

  @override
  String get stay_updated_desc => 'AIモデルのダウンロード完了時や、長時間実行タスクの完了時に通知を受け取ります。';

  @override
  String get notification_benefit_downloads => 'モデルのダウンロード進捗';

  @override
  String get notification_benefit_completions => '生成の完了';

  @override
  String get notification_benefit_background => 'バックグラウンドタスクのステータス';

  @override
  String get allow_notifications => '通知を許可する';

  @override
  String get servers_title => 'サーバー';

  @override
  String get no_servers_yet => 'サーバーがありません';

  @override
  String get no_servers_desc => 'AIモデルとチャットを開始するには、最初のサーバーを追加してください。';

  @override
  String get add_server => 'サーバーを追加';

  @override
  String switched_to_server(String name) {
    return '$name に切り替えました';
  }

  @override
  String get edit_server => 'サーバーを編集';

  @override
  String get add_server_title => 'サーバーを追加';

  @override
  String get server_type_label => 'サーバータイプ';

  @override
  String get server_icon_label => 'サーバーアイコン';

  @override
  String get default_icon => 'デフォルトアイコン';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'OpenAI 互換';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'ローカル';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'ローカル推論';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'デフォルト';

  @override
  String get set_as_default => 'デフォルトに設定';

  @override
  String get select_icon => 'アイコンを選択';

  @override
  String get select_icon_desc => 'サーバーのアイコンを選択してください';

  @override
  String get search_icons_hint => 'アイコンを検索...';

  @override
  String get server_icon_stack => 'サーバースタック';

  @override
  String get server_icon_stack2 => 'サーバースタック 02';

  @override
  String get server_icon_stack3 => 'サーバースタック 03';

  @override
  String get server_icon_cloud => 'クラウド';

  @override
  String get server_icon_cloud_server => 'クラウドサーバー';

  @override
  String get server_icon_mcp => 'MCP サーバー';

  @override
  String get server_icon_database => 'データベース';

  @override
  String get server_icon_database1 => 'データベース 01';

  @override
  String get server_icon_database2 => 'データベース 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'チップ';

  @override
  String get server_icon_chip2 => 'チップ 02';

  @override
  String get server_icon_computer => 'コンピューター';

  @override
  String get server_icon_laptop => 'ノートパソコン';

  @override
  String get server_icon_terminal => 'コンピューターターミナル';

  @override
  String get server_icon_code => 'コード';

  @override
  String get server_icon_ai_brain => 'AI ブレイン';

  @override
  String get server_icon_ai_brain2 => 'AI ブレイン 02';

  @override
  String get server_icon_ai_cloud => 'AI クラウド';

  @override
  String get server_icon_ai_network => 'AI ネットワーク';

  @override
  String get server_icon_ai_chat => 'AI チャット';

  @override
  String get server_icon_cellular => 'モバイルネットワーク';

  @override
  String get server_icon_plug1 => 'プラグ 01';

  @override
  String get server_icon_plug2 => 'プラグ 02';

  @override
  String get server_icon_bot => 'ボット';

  @override
  String get server_icon_bot2 => 'ボット 02';

  @override
  String get server_icon_robotic => 'ロボット';

  @override
  String get server_icon_rocket => 'ロケット';

  @override
  String get server_icon_star => 'スター';

  @override
  String get server_icon_settings1 => '設定 01';

  @override
  String get server_icon_settings2 => '設定 02';

  @override
  String get server_icon_home1 => 'ホーム 01';

  @override
  String get server_icon_home2 => 'ホーム 02';

  @override
  String get server_icon_folder1 => 'フォルダ 01';

  @override
  String get server_icon_folder2 => 'フォルダ 02';

  @override
  String get server_icon_file1 => 'ファイル 01';

  @override
  String get server_icon_lock => 'ロック';

  @override
  String get server_icon_key => 'キー 01';

  @override
  String get server_icon_link => 'リンク 01';

  @override
  String get server_icon_globe => '地球儀';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => '右矢印 01';

  @override
  String get server_icon_check => 'チェックマーク';

  @override
  String get server_icon_alert => '警告マーク';

  @override
  String get server_icon_info => '情報マーク';

  @override
  String get server_icon_zap => '稲妻マーク';

  @override
  String get server_icon_cloud_upload => 'クラウドアップロード';

  @override
  String get server_icon_cloud_download => 'クラウドダウンロード';

  @override
  String get server_icon_refresh => '更新';

  @override
  String get server_icon_hard_drive => 'ハードドライブ';

  @override
  String get server_icon_drive => 'ドライブ';

  @override
  String get personas_title => 'ペルソナ';

  @override
  String get persona_category_general => '全般';

  @override
  String get persona_category_coding => 'コーディング';

  @override
  String get persona_category_education => '教育';

  @override
  String get persona_category_creative => 'クリエイティブ';

  @override
  String get persona_builtin_section => 'プリセット';

  @override
  String get persona_my_section => 'マイペルソナ';

  @override
  String get clone_edit => '複製して編集';

  @override
  String get builtin_badge => 'プリセット';

  @override
  String get no_personas_found => 'ペルソナが見つかりません';

  @override
  String get no_personas_desc => '最初のペルソナを作成して、AIの動作をカスタマイズしましょう。';

  @override
  String get edit_persona => 'ペルソナを編集';

  @override
  String get create_persona => 'ペルソナを作成';

  @override
  String get create_persona_button => '作成';

  @override
  String get emoji_label => '絵文字';

  @override
  String get name_label => '名前';

  @override
  String get my_persona_hint => 'マイペルソナ';

  @override
  String get category_label => 'カテゴリ';

  @override
  String get description_optional => '説明（オプション）';

  @override
  String get description_hint => 'このペルソナの役割について...';

  @override
  String get system_prompt => 'システムプロンプト';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'プロンプトがまだありません...';

  @override
  String get prompt_hint => 'あなたは親切なアシスタントです...';

  @override
  String get prompt_required => 'システムプロンプトは必須です';

  @override
  String get prompt_max_chars => '最大4000文字';

  @override
  String get advanced_settings => '詳細設定';

  @override
  String get temperature_label => '温度（0.0-2.0）';

  @override
  String get top_p_label => 'Top P（0.0-1.0）';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0.9';

  @override
  String get range_0_2 => '0.0-2.0';

  @override
  String get range_0_1 => '0.0-1.0';

  @override
  String get persona_updated => 'ペルソナを更新しました';

  @override
  String get persona_created => 'ペルソナを作成しました';

  @override
  String get tts_models_title => '音声合成モデル';

  @override
  String get always_available => 'いつでも利用可能';

  @override
  String get tts_system_desc =>
      'デバイスの内蔵音声合成エンジンを使用します。\nダウンロードは不要です。音声の選択はデバイスのシステム設定を使用します。';

  @override
  String get downloading_status => 'ダウンロード中...';

  @override
  String tts_kitten_desc(String size) {
    return '8つの表現力豊かな音声を備えた超高速ニューラル音声合成。\nダウンロードサイズ: $size。';
  }

  @override
  String tts_piper_desc(String size) {
    return '2つの表現力豊かな音声を備えた高速オフラインPiper音声。\n音声ごとに $size のダウンロードが必要です。';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount 音声';
  }

  @override
  String get on_device_models_title => 'ローカルモデル';

  @override
  String get settings_huggingface_token => 'Hugging Faceトークン（任意）';

  @override
  String get settings_huggingface_token_desc =>
      '制限付きモデル（例: Gemma）でのみ必要です。トークンは huggingface.co/settings/tokens で取得できます。';

  @override
  String get settings_huggingface_token_set => 'トークンを保存しました';

  @override
  String get settings_huggingface_token_cleared => 'トークンを消去しました';

  @override
  String get model_requires_huggingface_token => 'Hugging Faceトークンが必要です';

  @override
  String get model_missing_huggingface_token =>
      'このモデルはHugging Faceで制限されています。ダウンロードするには、設定 → 端末内推論 にトークンを追加してください。';

  @override
  String get set_huggingface_token => 'トークンを設定';

  @override
  String get clear_huggingface_token => 'クリア';

  @override
  String get edit_huggingface_token_dialog_title => 'Hugging Faceアクセストークン';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc => 'ローカルAIエンジン。APIキーは不要です。';

  @override
  String get server_type_on_device_desc =>
      'スマートフォン上で動作します。一部のモデルにはHugging Faceトークンが必要です。';

  @override
  String get server_type_lm_studio_desc => 'ローカルAPIサーバー。APIキーは不要です。';

  @override
  String get available_models => '利用可能なモデル';

  @override
  String get device_memory => 'デバイスのメモリ';

  @override
  String get ram_usage => 'RAM使用量';

  @override
  String get memory_healthy => '正常';

  @override
  String get memory_critical => '致命的';

  @override
  String get memory_low => '警告';

  @override
  String ram_used(String percent) {
    return '$percent% 使用中';
  }

  @override
  String get available_ram => '空き RAM';

  @override
  String get total_capacity => '合計容量';

  @override
  String get loaded_status => 'ロード済み';

  @override
  String get inference_backend => '推論バックエンド';

  @override
  String get backend_ios_notice => 'iOSではCPUバックエンドのみ利用可能です。';

  @override
  String get backend_cpu_desc => 'すべてのデバイスで動作します。互換性が最も高いです。';

  @override
  String get backend_gpu_desc => 'OpenCL アクセラレーション。サポートされているデバイスで高速に動作します。';

  @override
  String get backend_npu_desc => 'ベンダー NPU (Qualcomm/MediaTek)。最も高速な推論。';

  @override
  String get select_model_title => 'モデルを選択';

  @override
  String get refresh_models => 'モデルを更新';

  @override
  String get search_models_hint => 'モデルを検索...';

  @override
  String get no_server_connected => 'サーバーが接続されていません';

  @override
  String get add_server_first => '利用可能なモデルを表示するには、まずサーバーを追加してください。';

  @override
  String get failed_load_models => 'モデルの読み込みに失敗しました';

  @override
  String get no_models_available => '利用可能なモデルはありません';

  @override
  String no_models_match(String searchQuery) {
    return '「$searchQuery」に一致するモデルはありません';
  }

  @override
  String model_load_failed(String error) {
    return 'モデルの読み込みに失敗しました: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'キープアライブ時間を経過すると $name がアンロードされます';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name を正常にアンロードしました';
  }

  @override
  String model_unload_failed(String error) {
    return 'モデルのアンロードに失敗しました: $error';
  }

  @override
  String get unload_from_server => 'サーバーからアンロード';

  @override
  String context_chip(String ctx) {
    return '$ctx コンテキスト';
  }

  @override
  String get unload_all_models => 'Unload all';

  @override
  String loaded_models_count(int count) {
    return '$count loaded';
  }

  @override
  String get all_models_unloaded => 'All models unloaded';

  @override
  String get branch_chat => 'Branch chat';

  @override
  String get branch_chat_desc => 'Start a new conversation from this message';

  @override
  String get edit_assistant_message_desc => 'Edit the assistant response text.';

  @override
  String switch_to_model(String modelName) {
    return 'Switch to $modelName';
  }

  @override
  String download_notification_title(String modelName) {
    return '$modelName をダウンロード中...';
  }

  @override
  String get download_complete_notification => 'ダウンロード完了！';

  @override
  String download_complete_body(String modelName) {
    return '$modelName のダウンロードが正常に完了しました。';
  }

  @override
  String download_failed_notification(String error) {
    return 'ダウンロード失敗: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return '$modelName のダウンロードに失敗しました。';
  }

  @override
  String get engine_name_system => 'システム音声合成';

  @override
  String get engine_tagline_system => 'デバイス内蔵エンジン';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => '高速ニューラル音声合成';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'オフライン Piper 音声';

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
  String get voice_lessac => 'Lessac (米国)';

  @override
  String get voice_ryan => 'Ryan (米国)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc => '最小の汎用チャットモデル。高速な応答と低メモリ使用が特徴です。';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc => '品質とサイズのバランスが取れたモデル。一般的な会話に適しています。';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc => '推論・思考プロセス（CoT）モデル。論理的なタスクに最適です。';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc => 'Googleのフラッグシップモデル。最高品質ですが、より多くのRAMが必要です。';

  @override
  String export_header(String date) {
    return '*LocalMindからエクスポート — $date*';
  }

  @override
  String get export_role_user => '## 👤 ユーザー';

  @override
  String get export_role_assistant => '## 🤖 アシスタント';

  @override
  String get export_role_system => '## ⚙️ システム';

  @override
  String get export_role_tool => '## 🔧 ツール';

  @override
  String get export_text_user => '[ユーザー]';

  @override
  String get export_text_assistant => '[アシスタント]';

  @override
  String get export_text_system => '[システム]';

  @override
  String get export_text_tool => '[ツール]';

  @override
  String get export_label_user => 'ユーザー';

  @override
  String get export_label_assistant => 'アシスタント';

  @override
  String get export_label_system => 'システム';

  @override
  String get export_label_tool => 'ツール';

  @override
  String get select_model_hint => 'モデルを選択してチャットを開始';

  @override
  String get test_notification_title => 'テスト通知';

  @override
  String get test_notification_body => 'これはモデルのダウンロード進捗用のテスト通知です。';

  @override
  String get tts_supports_background => 'ネイティブオーディオとしてバックグラウンド再生をサポート';

  @override
  String get tts_other_services_background_note =>
      '注意: 他のTTSサービスはネイティブオーディオとしてバックグラウンド再生をサポートしています。';

  @override
  String get gguf_imported_models_title => 'Imported GGUF models';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Import a GGUF from your device or add one from Hugging Face. Imported models run locally with llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      'imported models ready for local inference.';

  @override
  String get gguf_curated_models_subtitle =>
      'Curated on-device models you can download and manage inside LocalMind.';

  @override
  String get gguf_only_supported =>
      'Only GGUF models are supported for this import.';

  @override
  String get gguf_imported_from_local_file => 'imported from local file.';

  @override
  String get gguf_import_failed => 'Failed to import GGUF model';

  @override
  String get gguf_imported_from_huggingface => 'imported from Hugging Face.';

  @override
  String get gguf_import_canceled => 'GGUF import canceled.';

  @override
  String get gguf_enter_huggingface_url => 'Enter a Hugging Face GGUF URL.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Only official Hugging Face GGUF URLs are supported.';

  @override
  String get gguf_use_https_url =>
      'Use an HTTPS Hugging Face URL for GGUF import.';

  @override
  String get gguf_url_must_point_to_file =>
      'The Hugging Face URL must point directly to a .gguf file.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Unable to determine the GGUF file name.';

  @override
  String get gguf_download_empty =>
      'The downloaded GGUF file was empty or missing.';

  @override
  String get gguf_selected_file_missing =>
      'Selected model file does not exist.';

  @override
  String get gguf_import_action => 'Import GGUF';

  @override
  String get gguf_overview_title => 'Bring your own GGUF models';

  @override
  String get gguf_overview_subtitle =>
      'Import a .gguf from local storage or download one straight from Hugging Face. Imported models stay on this device and load with llama.cpp.';

  @override
  String get gguf_imported_count_label => 'imported';

  @override
  String get gguf_local_files_label => 'local files';

  @override
  String get gguf_huggingface_label => 'Hugging Face';

  @override
  String get gguf_import_local_title => 'Import local GGUF';

  @override
  String get gguf_import_local_subtitle => 'Copy a .gguf file from this device';

  @override
  String get gguf_import_huggingface_title => 'Import from Hugging Face';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Paste a GGUF URL or repo path';

  @override
  String get gguf_no_imported_title => 'No imported GGUF models yet';

  @override
  String get gguf_no_imported_subtitle =>
      'You can bring your own GGUF file from device storage or paste a Hugging Face URL or repo path that points to a .gguf file.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Import GGUF from Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Paste a direct GGUF URL or a Hugging Face repo path like `owner/repo/blob/main/model.gguf`. Blob links are converted automatically.';

  @override
  String get gguf_url_or_repo_path => 'GGUF URL or repo path';

  @override
  String get paste => 'Paste';

  @override
  String get gguf_browse => 'Browse GGUFs';

  @override
  String get gguf_huggingface_token_ready => 'Hugging Face token ready';

  @override
  String get gguf_huggingface_token_optional =>
      'Token optional but recommended';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Your saved token will be used automatically for gated or private repositories.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Requires a Hugging Face token. Add one in Settings if this GGUF is gated or private.';

  @override
  String get gguf_downloading => 'Downloading GGUF';

  @override
  String get gguf_preparing => 'Preparing';

  @override
  String get gguf_preparing_download => 'Preparing download...';

  @override
  String get gguf_cancel_import => 'Cancel import';

  @override
  String get clipboard_empty => 'Clipboard is empty.';

  @override
  String get could_not_open_huggingface => 'Could not open Hugging Face.';

  @override
  String get gguf_paste_url_error =>
      'Paste a Hugging Face GGUF URL or repo path.';

  @override
  String get gguf_blob_link => 'Blob link';

  @override
  String get gguf_repository_label => 'Repository';

  @override
  String get gguf_detected_path_label => 'Detected path';

  @override
  String get gguf_imported_section_label => 'Imported GGUF';

  @override
  String get gguf_already_available => 'Already available on this device';

  @override
  String get gguf_curated_models_short => 'Curated on-device models';

  @override
  String get execute_tool_title => 'Execute Tool';

  @override
  String get execute_tool_request_desc =>
      'The model is requesting to execute the following tool:';

  @override
  String get reject => 'Reject';

  @override
  String get approve => 'Approve';

  @override
  String get server_type_help =>
      'Pick the provider before filling connection details.';

  @override
  String get server_identity_title => 'Identity';

  @override
  String get server_identity_desc =>
      'Name this server and choose how it appears in the list.';

  @override
  String get server_connection_title => 'Connection';

  @override
  String get server_connection_desc =>
      'Use the address and port exposed by your server.';

  @override
  String get server_authentication_title => 'Authentication';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter requires an API key before testing.';

  @override
  String get server_authentication_optional_desc =>
      'Leave the API key empty if this server does not require one.';

  @override
  String get mcp_tools_title => 'MCP Tools';

  @override
  String get available_tools => 'Available tools';

  @override
  String get unable_load_tools => 'Unable to load tools';

  @override
  String get no_tools_registered => 'No tools registered';

  @override
  String get no_tools_registered_desc =>
      'Enable the example MCP server or add MCP integrations from chat settings.';

  @override
  String get example_mcp_server_title => 'Example MCP server';

  @override
  String get example_mcp_server_desc =>
      'Registers example.echo and example.word_count through the same MCP tool provider used by external servers.';

  @override
  String get disable_example_server => 'Disable example server';

  @override
  String get enable_example_server => 'Enable example server';

  @override
  String get built_in_label => 'Built-in';

  @override
  String get highlights_label => 'Highlights';

  @override
  String get built_with_label => 'Built with';

  @override
  String get local_label => 'Local';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => 'Requested';

  @override
  String get tool_status_approved => 'Approved';

  @override
  String get tool_status_rejected => 'Rejected';

  @override
  String get tool_status_running => 'Running';

  @override
  String get tool_status_done => 'Done';

  @override
  String get tool_status_failed => 'Failed';

  @override
  String get model_favorite_toggle => 'Toggle favorite';

  @override
  String get model_note_label => 'Note';

  @override
  String get model_note_hint => 'Add a note about this model…';

  @override
  String get unload_models_before_load =>
      'Unload all models before loading a new one';

  @override
  String get temp_chat_keyboard_incognito =>
      'Incognito keyboard in temporary chat';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Disables keyboard learning and suggestions in temporary chats (e.g. SwiftKey incognito).';

  @override
  String get resume_last_chat => 'Resume last chat on launch';

  @override
  String get resume_last_chat_desc =>
      'Restore your last open conversation when reopening the app.';

  @override
  String get export_all_data => 'Export all data';

  @override
  String get import_all_data => 'Import all data';

  @override
  String get export_data_success => 'Backup exported successfully';

  @override
  String get import_data_success => 'Backup imported successfully';

  @override
  String import_data_failed(String error) {
    return 'Failed to import backup: $error';
  }

  @override
  String get import_data_confirm =>
      'Import conversations and custom personas from this backup? Existing items with the same IDs will be updated.';

  @override
  String get import_settings_confirm =>
      'Replace current settings with the imported backup?';

  @override
  String get export_conversations => 'Export conversations';

  @override
  String get import_conversations => 'Import conversations';

  @override
  String get export_personas => 'Export personas';

  @override
  String get import_personas => 'Import personas';

  @override
  String get export_settings => 'Export settings';

  @override
  String get import_settings => 'Import settings';

  @override
  String get export_all_zip => 'Export all (ZIP)';

  @override
  String get import_all_zip => 'Import all (ZIP)';

  @override
  String get duplicate_chat => 'Duplicate chat';

  @override
  String get duplicate_chat_success => 'Chat duplicated';

  @override
  String get move_to_folder => 'Move to folder';

  @override
  String get remove_from_folder => 'Remove from folder';

  @override
  String get create_folder => 'Create folder';

  @override
  String get new_folder => 'New folder';

  @override
  String get folder_name_hint => 'Folder name';

  @override
  String get all_chats => 'All';

  @override
  String get unfiled_chats => 'Unfiled';

  @override
  String get create => 'Create';

  @override
  String get server_path_prefix_label => 'API path prefix';

  @override
  String get server_path_prefix_hint => '/your-secret-token';

  @override
  String get search_message_contents => 'Search message contents';

  @override
  String get message_search_results => 'Message matches';

  @override
  String get saved_messages_title => 'Saved Messages';

  @override
  String get nav_saved_messages => 'Saved Messages';

  @override
  String get saved_messages_empty =>
      'No saved messages yet. Bookmark a message from its options menu.';

  @override
  String get save_message => 'Save message';

  @override
  String get message_saved => 'Message saved';

  @override
  String token_count(int count) {
    return '$count tokens';
  }

  @override
  String estimated_token_count(int count) {
    return '~$count tokens (estimated)';
  }

  @override
  String get test_tts_section_title => 'Test voice';

  @override
  String get test_tts_hint => 'Enter text to hear the current TTS engine…';

  @override
  String get test_speak_button => 'Speak';

  @override
  String get scroll_to_bottom => 'Scroll to bottom';

  @override
  String get generate_ai_response => 'Generate AI response';

  @override
  String get no_response => 'No response';

  @override
  String get export => 'Export';

  @override
  String get import => 'Import';

  @override
  String get conversations_label => 'Conversations';

  @override
  String get personas_label => 'Personas';

  @override
  String get settings_label => 'Settings';

  @override
  String get export_conversation => 'Export conversation';

  @override
  String get tts_process_markdown => 'Process markdown for speech';

  @override
  String get tts_process_markdown_desc =>
      'Strip formatting like **bold** before reading aloud';

  @override
  String get tts_skip_seconds => 'Skip interval';

  @override
  String get tts_skip_seconds_desc =>
      'Forward and rewind jump size during playback';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}s';
  }

  @override
  String get preview_system_prompts => 'Preview system prompts';

  @override
  String get welcome_message_1 => 'What can I help you with today?';

  @override
  String get welcome_message_2 => 'Ask me anything — I\'m ready when you are.';

  @override
  String get welcome_message_3 => 'Start a conversation below.';

  @override
  String get welcome_message_4 => 'Need ideas? Try one of the quick prompts.';

  @override
  String get temporary_chat => 'Temporary chat';

  @override
  String get temporary_chat_desc => 'Chats aren\'t saved to history.';

  @override
  String get temporary_chat_banner => 'Temporary chat — not saved to history';

  @override
  String get temporary_chat_save_warning_title =>
      'Save message in temporary chat?';

  @override
  String get temporary_chat_save_warning_body =>
      'This chat is temporary and hidden from history. The saved message will still appear in Saved Messages.';

  @override
  String get save_to_history => 'Save to history';

  @override
  String get share_conversation => 'Share conversation';

  @override
  String get download_tts_audio => 'Download audio';

  @override
  String get tts_download_unavailable =>
      'Download is only available for Piper and Kitten TTS';

  @override
  String get tts_download_no_audio => 'No audio available to download yet';

  @override
  String get tts_download_success => 'Audio saved';

  @override
  String get return_to_chat => 'Return to chat';

  @override
  String get return_to_temp_chat => 'Return to temporary chat';

  @override
  String get insert_saved_message => 'Insert saved message';

  @override
  String get insert_saved_message_desc =>
      'Choose a saved message to add to your input';

  @override
  String get model_info => 'Model info';

  @override
  String get model_name => 'Model name';

  @override
  String get model_identifier => 'Identifier';

  @override
  String get not_available => 'Not available';

  @override
  String get save_message_folders => 'Save message';

  @override
  String get remove_from_saved => 'Remove from saved';

  @override
  String get message_already_saved => 'Saved';

  @override
  String get stream_ttft => 'Time to first token';

  @override
  String get stream_tokens_per_sec => 'Tokens per second';

  @override
  String get stream_stop_reason => 'Stop reason';

  @override
  String get stream_input_tokens => 'Input tokens';

  @override
  String get stream_output_tokens => 'Output tokens';

  @override
  String get stream_generation_time => 'Generation time';

  @override
  String get attach_image => 'Image';

  @override
  String get attach_text_document => 'Text document';

  @override
  String get add_attachment => 'Add attachment';

  @override
  String get photo_permission_denied =>
      'Photo access is required to attach images';

  @override
  String get characters_label => 'Characters';

  @override
  String get exit_temporary_chat_title => 'Exit temporary chat?';

  @override
  String get exit_temporary_chat_body =>
      'This will discard the current temporary chat and return to a new chat.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'This message was saved from a temporary chat and can\'t be opened in its original conversation.';

  @override
  String get filter_title => 'Filter';

  @override
  String get filter_pinned => 'Pinned';

  @override
  String get filter_archived => 'Archived';

  @override
  String get filter_temp_chats => 'Temporary chats';

  @override
  String get filter_user_messages => 'User messages';

  @override
  String get filter_assistant_messages => 'Assistant messages';

  @override
  String get archive_chat => 'Archive';

  @override
  String get unarchive_chat => 'Unarchive';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return '$count chars';
  }

  @override
  String get generate_title_with_ai => 'Generate with AI';

  @override
  String get generating_title => 'Generating...';

  @override
  String get generate_title_failed => 'Could not generate a title';

  @override
  String get lm_studio_model_browser_title => 'Browse models';

  @override
  String get lm_studio_model_search_hint => 'Search models by name or author…';

  @override
  String get lm_studio_staff_picks => 'Staff picks';

  @override
  String get lm_studio_community_models => 'Community models';

  @override
  String get lm_studio_no_models => 'No models found';

  @override
  String lm_studio_models_count(int count) {
    return '$count models';
  }

  @override
  String get lm_studio_browse_models => 'Browse & download';

  @override
  String get lm_studio_model_search => 'LMS Model Search';

  @override
  String get lm_studio_downloads_title => 'Downloads';

  @override
  String get lm_studio_choose_quant => 'Choose a download option';

  @override
  String get lm_studio_use_default_quant => 'Use default';

  @override
  String get lm_studio_recommended => 'Recommended';

  @override
  String get lm_studio_clear_downloads => 'Clear finished';

  @override
  String get lm_studio_no_downloads => 'No downloads yet';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Downloads run on the LM Studio host. Pausing, stopping, and deleting models must be done on that computer — not from this app.';

  @override
  String get lm_studio_staff_pick => 'Staff pick';

  @override
  String get lm_studio_params => 'PARAMS';

  @override
  String get lm_studio_arch => 'ARCH';

  @override
  String get lm_studio_domain => 'DOMAIN';

  @override
  String get lm_studio_format => 'FORMAT';

  @override
  String get lm_studio_vision => 'Vision';

  @override
  String get lm_studio_tool_use => 'Tool use';

  @override
  String get lm_studio_reasoning => 'Reasoning';

  @override
  String get lm_studio_download_options => 'Download options';

  @override
  String get lm_studio_download => 'Download';

  @override
  String lm_studio_download_size(String size) {
    return 'Download $size';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Downloading $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'README not available for this model.';

  @override
  String get lm_studio_full_gpu_offload => 'Full GPU offload possible';

  @override
  String get lm_studio_partial_gpu_offload => 'Partial GPU offload possible';

  @override
  String get lm_studio_likely_too_large => 'Likely too large';

  @override
  String get lm_studio_available_ram_gb => 'Available RAM (GB, optional)';

  @override
  String get lm_studio_available_vram_gb => 'Available VRAM (GB, optional)';

  @override
  String get lm_studio_memory_settings_title => 'Memory for recommendations';

  @override
  String get lm_studio_memory_settings_desc =>
      'Used to estimate whether models fit on your machine in the model browser.';

  @override
  String get think_button_label => 'Think';

  @override
  String get reasoning_effort_low => 'Low';

  @override
  String get reasoning_effort_medium => 'Medium';

  @override
  String get reasoning_effort_high => 'High';
}
