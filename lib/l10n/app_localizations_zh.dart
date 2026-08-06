// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => '您的 AI。您的设备。您的规则。';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get delete => '删除';

  @override
  String get save => '保存';

  @override
  String get retry => '重试';

  @override
  String get close => '关闭';

  @override
  String get done => '完成';

  @override
  String get continue_action => '继续';

  @override
  String get skip => '跳过';

  @override
  String get install => '安装';

  @override
  String get download => '下载';

  @override
  String get resume => '继续';

  @override
  String get pause => '暂停';

  @override
  String get stop => '停止';

  @override
  String get edit => '编辑';

  @override
  String get preview => '预览';

  @override
  String get unload => '卸载';

  @override
  String get load => '加载';

  @override
  String get rename => '重命名';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => '取消 Pin';

  @override
  String get share => '分享';

  @override
  String get copy => '复制';

  @override
  String get copied => '已复制！';

  @override
  String get copied_to_clipboard => '已复制到剪贴板';

  @override
  String get select => '选择';

  @override
  String get active => '已启用';

  @override
  String get all => '全部';

  @override
  String get none => '无';

  @override
  String get none_selected => '未选择';

  @override
  String get online => '在线';

  @override
  String get connected => '已连接';

  @override
  String get checking => '正在检查';

  @override
  String get offline => '离线';

  @override
  String get error => '错误';

  @override
  String get unknown_error => '未知错误';

  @override
  String get not_now => '暂不';

  @override
  String get enable => '启用';

  @override
  String get proceed_anyway => '仍然继续';

  @override
  String get test_connection => '测试连接';

  @override
  String get testing => '正在测试...';

  @override
  String get connection_successful => '连接成功！';

  @override
  String get connection_failed => '连接失败。请检查您的设置。';

  @override
  String get save_continue => '保存并继续';

  @override
  String get save_changes => '保存更改';

  @override
  String get finish_setup => '完成设置';

  @override
  String get start_new_chat => '开始新聊天';

  @override
  String get cannot_undo => '此操作无法撤销。';

  @override
  String get ram_warning => '内存警告';

  @override
  String get recommended => '推荐';

  @override
  String get may_be_large => '可能对于此设备来说过大';

  @override
  String get calculating => '正在计算...';

  @override
  String get download_failed => '下载失败';

  @override
  String get downloaded => '已下载';

  @override
  String get not_downloaded => '未下载';

  @override
  String get installed => '已安装';

  @override
  String get not_installed => '未安装';

  @override
  String get loading => '正在加载...';

  @override
  String get thinking => '正在思考';

  @override
  String get processing => '正在处理...';

  @override
  String get initializing => '正在初始化...';

  @override
  String get ready => '就绪';

  @override
  String get preparing_app => '正在准备应用...';

  @override
  String get initializing_services => '正在初始化服务...';

  @override
  String get configuring_server => '正在配置服务器...';

  @override
  String get startup_failed => '启动失败';

  @override
  String get something_went_wrong => '出了点问题';

  @override
  String get delete_model_title => '删除模型';

  @override
  String delete_model_body(String name) {
    return '您确定要删除 $name 吗？';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return '您确定要删除 $name 吗？这释放大约 $size 的空间。\n\n如有需要，您稍后可以重新下载此模型。';
  }

  @override
  String get delete_voice_title => '删除语音';

  @override
  String delete_voice_body(String name, String size) {
    return '您确定要删除 $name 吗？这释放大约 $size 的空间。\n\n如有需要，您稍后可以重新下载此语音。';
  }

  @override
  String get delete_server_title => '删除服务器';

  @override
  String delete_server_body(String name) {
    return '您确定要删除 \"$name\" 吗？此操作无法撤销。';
  }

  @override
  String get delete_conversation_title => '删除对话吗？';

  @override
  String delete_conversation_body(String title) {
    return '您确定要删除 \"$title\" 吗？此操作无法撤销。';
  }

  @override
  String get delete_message_title => '删除消息吗？';

  @override
  String delete_persona_title(String name) {
    return '删除 \"$name\" 吗？';
  }

  @override
  String get delete_persona_body => '此操作无法撤销。';

  @override
  String get delete_builtin_persona_body => '这是一个内置角色。您稍后可以在“设置”中将其恢复。';

  @override
  String get restore_builtin_personas => '恢复默认角色';

  @override
  String get restore_builtin_personas_desc => '重新添加您已删除的任何内置角色';

  @override
  String get restore_builtin_personas_success => '已恢复默认角色';

  @override
  String get clear_personas => '清除角色';

  @override
  String get enable_image_compression => '发送前压缩图片';

  @override
  String get enable_image_compression_desc => '调整并压缩附加图片的大小，以使上传大小保持在服务器限制内';

  @override
  String get image_compression_level => '压缩强度';

  @override
  String get image_compression_level_desc => '较高的压缩强度会生成质量较低但上传更小的图片';

  @override
  String get image_compression_level_low => '低';

  @override
  String get image_compression_level_medium => '中';

  @override
  String get image_compression_level_high => '高';

  @override
  String get sort_models_tooltip => '排序模型';

  @override
  String get sort_by_favorites => '收藏优先';

  @override
  String get sort_by_name => '名称 (A-Z)';

  @override
  String get sort_by_size_smallest => '大小 (从小到大)';

  @override
  String get sort_by_size_largest => '大小 (从大到小)';

  @override
  String get sort_by_context_length => '上下文长度';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return '正在重命名 $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '已选择 $count 个';
  }

  @override
  String get ai_rename_tooltip => '使用 AI 重命名所选内容';

  @override
  String get new_chat_in_folder_tooltip => '在此文件夹中新建聊天';

  @override
  String total_tokens_count(int count) {
    return '$count 个 Token';
  }

  @override
  String get smart_replies_use_persona => '在智能回复中应用角色';

  @override
  String get smart_replies_use_persona_desc => '建议的回复将符合当前启用角色的语气，而不是通用的助手语气';

  @override
  String get keep_persona_on_new_chat => '新聊天保留角色';

  @override
  String get keep_persona_on_new_chat_desc => '开始新聊天时不要清除选定的角色';

  @override
  String get role_swap_button_enabled => '显示角色切换按钮';

  @override
  String get role_swap_button_enabled_desc =>
      '在聊天输入框中显示一个按钮，允许您以助手而非用户的身份发送消息，而不生成任何回复';

  @override
  String get send_as_user_tooltip => '以用户身份发送';

  @override
  String get send_as_assistant_tooltip => '以助手身份发送 (无回复)';

  @override
  String get insert_without_generating_tooltip => '仅插入不生成回复';

  @override
  String get token_usage_title => 'Token 使用情况';

  @override
  String get total_tokens_label => '已用 Token';

  @override
  String get usage_percent_label => '已用上下文';

  @override
  String get export_choice_title => '导出';

  @override
  String get export_choice_body => '您希望如何导出此内容？';

  @override
  String get copy_to_clipboard => '复制到剪贴板';

  @override
  String bulk_export_conversations_success(int count) {
    return '已成功导出 $count 个对话';
  }

  @override
  String get bulk_ai_rename_confirm_title => '使用 AI 重命名？';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return '这将请求 AI 为每个选定的 $count 个对话生成新标题，替换其当前的标题。此操作可能需要一些时间，且无法撤销。';
  }

  @override
  String get sort_by_modified_date => '最近修改';

  @override
  String get sort_by_created_date => '创建日期';

  @override
  String get sort_title => '排序';

  @override
  String get clear_conversation_title => '清除对话吗？';

  @override
  String get clear_conversation_body => '这会删除此对话中的所有消息。';

  @override
  String get clear => '清除';

  @override
  String label_completed(String label) {
    return '$label 已完成';
  }

  @override
  String error_with_message(String error) {
    return '错误: $error';
  }

  @override
  String preview_failed(String error) {
    return '预览失败: $error';
  }

  @override
  String loading_model(String modelId) {
    return '正在加载 $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return '模型已加载: $modelId ($backend)';
  }

  @override
  String get no_model_loaded => '未加载任何模型。点击 “管理设备端模型” 以下载并加载模型。';

  @override
  String loading_model_error(String error) {
    return '错误: $error';
  }

  @override
  String get delete_conversation => '删除对话吗？';

  @override
  String get nav_history => '历史';

  @override
  String get nav_servers => '服务器';

  @override
  String get nav_local_models => '本地模型';

  @override
  String get nav_tts => '语音合成';

  @override
  String get nav_personas => '角色';

  @override
  String get nav_settings => '设置';

  @override
  String get nav_new_chat => '新聊天';

  @override
  String get search_hint => '搜索对话...';

  @override
  String get no_server_selected => '未选择服务器';

  @override
  String get switch_server => '切换服务器';

  @override
  String get switch_server_subtitle => '选择要连接的服务器';

  @override
  String get manage_servers => '管理服务器';

  @override
  String get open_source => '开源';

  @override
  String get open_source_desc => 'LocalMind 是开源项目。可在 GitHub 上关注我们的进展或参与贡献。';

  @override
  String get star_on_github => '在 GitHub 上点亮 Star';

  @override
  String get add_more => '添加更多';

  @override
  String get on_github => '在 GitHub 上';

  @override
  String get could_not_open_github => '无法打开 GitHub。';

  @override
  String get settings_title => '设置';

  @override
  String get settings_appearance => '外观';

  @override
  String get settings_language => '语言';

  @override
  String get language_system_default => '系统默认';

  @override
  String get settings_tts => '语音合成 (TTS)';

  @override
  String get settings_behavior => '行为';

  @override
  String get settings_on_device => '设备端推理';

  @override
  String get settings_default_server => '默认服务器';

  @override
  String get settings_default_persona => '默认角色';

  @override
  String get settings_default_model => 'Default Model';

  @override
  String get settings_default_model_desc =>
      'Automatically selected when you start a new chat.';

  @override
  String get settings_privacy => '隐私';

  @override
  String get settings_data_management => '数据管理';

  @override
  String get settings_about => '关于';

  @override
  String get theme => '主题';

  @override
  String get theme_system => '系统';

  @override
  String get theme_light => '亮色';

  @override
  String get theme_dark => '暗色';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => '字体大小';

  @override
  String get font_size_desc => '调整聊天中的文本大小。';

  @override
  String get font_preview => '敏捷的棕色狐狸跳过那只懒狗。';

  @override
  String get code_theme_dark => '代码主题 (暗色)';

  @override
  String get code_theme_light => '代码主题 (亮色)';

  @override
  String get code_theme_desc => '选择代码块的语法高亮主题。';

  @override
  String get tts_engine => 'TTS 引擎';

  @override
  String get tts_engine_system => '系统 TTS';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => '语音';

  @override
  String get voice_female => '女声';

  @override
  String get voice_male => '男声';

  @override
  String get voice_other => '其他';

  @override
  String get tts_speed => 'TTS 速度';

  @override
  String get tts_speed_desc => '调整播放速率。';

  @override
  String get manage_tts_models => '管理 TTS 模型';

  @override
  String get manage_on_device_models => '管理设备端模型';

  @override
  String get enable_smart_reply => '设备端智能回复';

  @override
  String get ai_user_response_enabled => 'AI 用户消息 (长按发送)';

  @override
  String get ai_user_response_enabled_desc => '长按发送按钮 3 秒钟以让 AI 撰写并发送您的下一条消息';

  @override
  String get ai_user_response_tooltip => '使用 AI 生成用户消息';

  @override
  String get streaming_responses => '流式响应';

  @override
  String get auto_generate_titles => '自动生成标题';

  @override
  String get send_on_enter => '按 Enter 键发送';

  @override
  String get show_system_messages => '显示系统消息';

  @override
  String get show_system_messages_desc => '当没有选定角色时，每次请求都发送默认的助手系统提示词';

  @override
  String get show_system_messages_in_chat => '在聊天中显示系统消息';

  @override
  String get show_system_messages_in_chat_desc =>
      '将系统消息 (例如来自导入的备份) 作为对话中的可见气泡显示';

  @override
  String get haptic_feedback => '触觉反馈';

  @override
  String get enable_mcp => '启用 MCP';

  @override
  String get new_chat_mcp_default => '新聊天默认启用 MCP';

  @override
  String get show_data_indicator => '显示数据指示器';

  @override
  String get privacy_info => '\"LocalMind 绝不查看您的数据\"';

  @override
  String get delete_all_conversations => '删除所有对话';

  @override
  String get reset_settings_defaults => '重置设置至默认值';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => '聊天参数';

  @override
  String get change_persona => '更换角色';

  @override
  String get set_persona => '设置角色';

  @override
  String get remove_persona => '删除角色';

  @override
  String get clear_conversation => '清除对话';

  @override
  String get connection_error => '连接错误。请检查您的服务器。';

  @override
  String get disconnected => '与服务器断开连接。';

  @override
  String get configure => '配置';

  @override
  String get select_model => '选择模型';

  @override
  String get select_persona => '选择角色';

  @override
  String get manage_personas => '管理角色';

  @override
  String get personas_combine_hint => '选定的角色将被合并';

  @override
  String get start_conversation => '开始对话';

  @override
  String get recent_chats => '最近聊天';

  @override
  String get see_all => '查看全部';

  @override
  String get quick_write => '帮我写一个函数';

  @override
  String get quick_explain => '解释这段代码';

  @override
  String get quick_debug => '帮我调试这个';

  @override
  String get quick_async => '我该如何使用 async/await？';

  @override
  String get history_missing_title => '历史记录丢失';

  @override
  String get history_missing_desc => '此聊天中的消息已被删除，或历史记录已损坏。';

  @override
  String get technical_details => '技术细节';

  @override
  String get last_error => '上次错误:';

  @override
  String get copy_info => '复制信息';

  @override
  String get conversation_id => '对话 ID';

  @override
  String get created_at => '创建于';

  @override
  String get expected_messages => '预期消息';

  @override
  String get debug_dialog_desc => '用以帮助识别同步问题的诊断信息。';

  @override
  String get chat_input_hint => '问任何问题';

  @override
  String get send_message_tooltip => '发送消息';

  @override
  String get stop_generation_tooltip => '停止生成';

  @override
  String get attach_images_tooltip => '附加图片';

  @override
  String get start_listening_tooltip => '开始聆听';

  @override
  String get stop_listening_tooltip => '停止聆听';

  @override
  String tool_label(String toolCallId) {
    return '工具: $toolCallId';
  }

  @override
  String get tool_unknown => '工具: 未知';

  @override
  String get message_options => '消息选项';

  @override
  String get copy_markdown => '复制为 Markdown';

  @override
  String get copied_markdown => '已复制为 Markdown';

  @override
  String get read_aloud => '朗读';

  @override
  String get stop_reading => '停止朗读';

  @override
  String get more => '更多';

  @override
  String character_count(int length) {
    return '$length 个字符';
  }

  @override
  String get edit_message => '编辑消息';

  @override
  String get edit_message_desc => '保存将移除下方助手的回复并重新生成。';

  @override
  String get save_regenerate => '保存并重新生成';

  @override
  String get chat_settings_title => '聊天设置';

  @override
  String get reset_defaults => '重置默认值';

  @override
  String get parameters_tab => '参数';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => '温度';

  @override
  String get temperature_desc => '控制随机性：较高 = 创意，较低 = 专注';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => '核采样阈值';

  @override
  String get max_tokens => '最大 Token 数';

  @override
  String get max_tokens_desc => '响应限制';

  @override
  String get context_length => '上下文长度';

  @override
  String get context_length_desc => '历史窗口';

  @override
  String get mcp_disabled_warning => 'MCP 已在全局被禁用。请在设置中启用以使用这些功能。';

  @override
  String get mcp_enable_chat => '为此聊天启用 MCP';

  @override
  String get auto_execute_tools => '自动执行工具';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => '实验性';

  @override
  String get add_ephemeral_mcp => '添加临时 MCP 服务器';

  @override
  String get mcp_label_placeholder => '标签';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => '活动集成';

  @override
  String get import_mcp_json => 'Import JSON';

  @override
  String get import_mcp_json_dialog_title => 'Import MCP Config JSON';

  @override
  String get import_mcp_json_instructions =>
      'Copy your mcpServers JSON directly from LM Studio (mcp.json) or paste a plugin array below:';

  @override
  String get import_mcp_json_placeholder =>
      'Paste mcpServers JSON or plugin list here...';

  @override
  String mcp_import_success(int count) {
    return 'Successfully imported $count integration(s)';
  }

  @override
  String get mcp_import_failed => 'No valid MCP integrations found in JSON';

  @override
  String get enable_notifications => '启用通知';

  @override
  String get enable_notifications_desc => '在模型下载完成时获得通知。';

  @override
  String get chat_history_title => '聊天历史';

  @override
  String get conversation_just_now => '刚刚';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes分钟前';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours小时前';
  }

  @override
  String get conversation_yesterday => '昨天';

  @override
  String conversation_days_ago(int days) {
    return '$days天前';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => '选项';

  @override
  String get no_results_found => '未找到结果';

  @override
  String get no_conversations_yet => '尚无对话';

  @override
  String get try_different_search => '尝试不同的搜索词';

  @override
  String get start_new_conversation => '开始新对话';

  @override
  String get rename_conversation => '重命名对话';

  @override
  String get enter_new_title => '输入新标题';

  @override
  String get pinned_section => '已 pin';

  @override
  String get today_section => '今天';

  @override
  String get yesterday_section => '昨天';

  @override
  String get previous_7_days => '前 7 天';

  @override
  String get previous_30_days => '前 30 天';

  @override
  String get older_section => '更早';

  @override
  String get onboarding_choose_language => '选择语言';

  @override
  String get onboarding_choose_language_desc => '选择您首选的语言。您随时可以在设置中更改此项。';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => '连接您的\n服务器';

  @override
  String get onboarding_connect_desc =>
      '连接到 LM Studio、Ollama 或\nOpenRouter，开启您的私有 AI\n体验。';

  @override
  String get openai_compatible_api => 'OpenAI 兼容 API';

  @override
  String get https_requires_ssl => 'HTTPS 需要 SSL';

  @override
  String get most_local_setups_use_http => '大多数本地配置使用 http://';

  @override
  String get onboarding_welcome => '欢迎使用 LocalMind';

  @override
  String get server_type_on_device => '设备端';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'CLOUD MANAGED';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'By connecting Ollama Cloud, your chat messages and inputs are sent to Ollama\'s managed servers for inference. LocalMind does not track or store your conversations. You can revoke this key any time at ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud =>
      'API Key required for Ollama Cloud';

  @override
  String get api_key_hint_ollama_cloud => 'Paste your Ollama Cloud API key';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Connect to Ollama Cloud with an API key from ollama.com/settings/keys to access managed cloud models.';

  @override
  String get add_server_openrouter_subtitle =>
      'Connect through OpenRouter with a valid API key and keep this profile ready for model routing.';

  @override
  String get add_server_endpoint_subtitle =>
      'Configure a local or self-hosted endpoint, then verify the connection before saving.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => '统一云';

  @override
  String get ready_continue => '准备好继续';

  @override
  String get waiting_selection => '等待选择';

  @override
  String get setup_connection => '设置连接';

  @override
  String setup_connection_desc(String server) {
    return '配置您的 $server 服务器以开始聊天。';
  }

  @override
  String get server_name => '服务器名称';

  @override
  String get name_required => '需要名称';

  @override
  String get name_max_50 => '最多 50 个字符';

  @override
  String get host_label => '主机 / IP 地址';

  @override
  String get host_required => '需要主机地址';

  @override
  String get port_label => '端口';

  @override
  String get port_required => '需要端口';

  @override
  String get port_invalid => '必须是数字';

  @override
  String get port_range => '输入有效的端口号 (1-65535)';

  @override
  String get api_key_required => 'API 密钥 *';

  @override
  String get api_key_optional => 'API 密钥 (可选)';

  @override
  String get api_key_required_openrouter => 'OpenRouter 需要 API 密钥';

  @override
  String get api_key_format => 'OpenRouter API 密钥以 sk- 开头';

  @override
  String get my_server_hint => '我的服务器';

  @override
  String get name_length_validation => '名称必须在 50 个字符以内';

  @override
  String get host_valid => '输入有效的主机名或 IP 地址';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => '适用于已验证的服务器';

  @override
  String get update_server => '更新服务器';

  @override
  String get save_server => '保存服务器';

  @override
  String get server_updated => '服务器已更新';

  @override
  String get server_added => '服务器已添加';

  @override
  String get download_model_title => '下载模型';

  @override
  String get download_model_desc => '选择要下载的模型。\n它将在您的设备上本地运行。';

  @override
  String get on_device_android_only => '设备端推理当前仅可在 Android 上使用。';

  @override
  String get total_ram => '总内存';

  @override
  String get available => '可用';

  @override
  String ram_min_required(String fileSize) {
    return '最低要求 $fileSize GB 内存 (RAM)';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return '预计剩余时间: $eta';
  }

  @override
  String paused_progress(String percent) {
    return '已暂停 - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return '此模型需要至少 $ram GB 内存，但您的设备仅有 $totalMemory。它可能无法正常运行，或会导致应用崩溃。';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return '您的设备当前有 $availableRAM 可用内存，但此模型推荐至少 $ram GB。加载它可能会失败或导致系统不稳定。';
  }

  @override
  String get choose_theme => '选择主题';

  @override
  String get choose_theme_desc => '个性化应用程序外观。您随时可以在设置中更改此项。';

  @override
  String get theme_card_system => '系统';

  @override
  String get theme_card_system_sub => '匹配您的设备设置';

  @override
  String get theme_card_light => '亮色';

  @override
  String get theme_card_light_sub => '干净明亮';

  @override
  String get theme_card_dark => '暗色';

  @override
  String get theme_card_dark_sub => '保护眼睛';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => '温馨的桃色色调主题';

  @override
  String get stay_updated => '保持更新';

  @override
  String get stay_updated_desc => '在您的 AI 模型下载完成或长时间运行的任务结束时获得通知。';

  @override
  String get notification_benefit_downloads => '模型下载进度';

  @override
  String get notification_benefit_completions => '生成完成';

  @override
  String get notification_benefit_background => '后台任务状态';

  @override
  String get allow_notifications => '允许通知';

  @override
  String get servers_title => '服务器';

  @override
  String get no_servers_yet => '尚无服务器';

  @override
  String get no_servers_desc => '添加您的首个服务器以开始与 AI 模型聊天。';

  @override
  String get add_server => '添加服务器';

  @override
  String switched_to_server(String name) {
    return '已切换到 $name';
  }

  @override
  String get edit_server => '编辑服务器';

  @override
  String get add_server_title => '添加服务器';

  @override
  String get server_type_label => '服务器类型';

  @override
  String get server_icon_label => '服务器图标';

  @override
  String get default_icon => '默认图标';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => '兼容 OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => '设备端';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => '本地推理';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => '默认';

  @override
  String get set_as_default => '设为默认';

  @override
  String get select_icon => '选择图标';

  @override
  String get select_icon_desc => '为您的服务器选择一个图标';

  @override
  String get search_icons_hint => '搜索图标...';

  @override
  String get server_icon_stack => '服务器堆栈';

  @override
  String get server_icon_stack2 => '服务器堆栈 02';

  @override
  String get server_icon_stack3 => '服务器堆栈 03';

  @override
  String get server_icon_cloud => '云';

  @override
  String get server_icon_cloud_server => '云端服务器';

  @override
  String get server_icon_mcp => 'MCP 服务器';

  @override
  String get server_icon_database => '数据库';

  @override
  String get server_icon_database1 => '数据库 01';

  @override
  String get server_icon_database2 => '数据库 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => '芯片';

  @override
  String get server_icon_chip2 => '芯片 02';

  @override
  String get server_icon_computer => '电脑';

  @override
  String get server_icon_laptop => '笔记本电脑';

  @override
  String get server_icon_terminal => '电脑终端';

  @override
  String get server_icon_code => '代码';

  @override
  String get server_icon_ai_brain => 'AI 大脑';

  @override
  String get server_icon_ai_brain2 => 'AI 大脑 02';

  @override
  String get server_icon_ai_cloud => 'AI 云端';

  @override
  String get server_icon_ai_network => 'AI 网络';

  @override
  String get server_icon_ai_chat => 'AI 聊天';

  @override
  String get server_icon_cellular => '蜂窝网络';

  @override
  String get server_icon_plug1 => '插头 01';

  @override
  String get server_icon_plug2 => '插头 02';

  @override
  String get server_icon_bot => '机器人';

  @override
  String get server_icon_bot2 => '机器人 02';

  @override
  String get server_icon_robotic => '机器人声音';

  @override
  String get server_icon_rocket => '火箭';

  @override
  String get server_icon_star => 'Star';

  @override
  String get server_icon_settings1 => '设置 01';

  @override
  String get server_icon_settings2 => '设置 02';

  @override
  String get server_icon_home1 => '主页 01';

  @override
  String get server_icon_home2 => '主页 02';

  @override
  String get server_icon_folder1 => '文件夹 01';

  @override
  String get server_icon_folder2 => '文件夹 02';

  @override
  String get server_icon_file1 => '文件 01';

  @override
  String get server_icon_lock => '锁';

  @override
  String get server_icon_key => '钥匙 01';

  @override
  String get server_icon_link => '链接 01';

  @override
  String get server_icon_globe => '地球仪';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => '右箭头 01';

  @override
  String get server_icon_check => '勾选圆圈';

  @override
  String get server_icon_alert => '警报圆圈';

  @override
  String get server_icon_info => '信息圆圈';

  @override
  String get server_icon_zap => 'Zap';

  @override
  String get server_icon_cloud_upload => '云端上传';

  @override
  String get server_icon_cloud_download => '云端下载';

  @override
  String get server_icon_refresh => '刷新';

  @override
  String get server_icon_hard_drive => '硬盘';

  @override
  String get server_icon_drive => '驱动器';

  @override
  String get personas_title => '角色';

  @override
  String get persona_category_general => '通用';

  @override
  String get persona_category_coding => '编程';

  @override
  String get persona_category_education => '教育';

  @override
  String get persona_category_creative => '创意';

  @override
  String get persona_builtin_section => '内置';

  @override
  String get persona_my_section => '我的角色';

  @override
  String get clone_edit => '克隆并编辑';

  @override
  String get builtin_badge => '内置';

  @override
  String get no_personas_found => '未找到任何角色';

  @override
  String get no_personas_desc => '创建您的第一个角色以定制 AI 行为。';

  @override
  String get edit_persona => '编辑角色';

  @override
  String get create_persona => '创建角色';

  @override
  String get create_persona_button => '创建';

  @override
  String get emoji_label => '表情符号';

  @override
  String get name_label => '名称';

  @override
  String get my_persona_hint => '我的角色';

  @override
  String get category_label => '分类';

  @override
  String get description_optional => '描述 (可选)';

  @override
  String get description_hint => '此角色要做的是...';

  @override
  String get system_prompt => '系统提示词';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => '尚无提示词...';

  @override
  String get prompt_hint => '你是一个得力的助手...';

  @override
  String get prompt_required => '需要系统提示词';

  @override
  String get prompt_max_chars => '最多 4000 个字符';

  @override
  String get advanced_settings => '高级设置';

  @override
  String get temperature_label => '温度 (0.0-2.0)';

  @override
  String get top_p_label => 'Top P (0.0-1.0)';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0.9';

  @override
  String get range_0_2 => '0.0-2.0';

  @override
  String get range_0_1 => '0.0-1.0';

  @override
  String get persona_updated => '角色已更新';

  @override
  String get persona_created => '角色已创建';

  @override
  String get tts_models_title => '语音合成模型';

  @override
  String get always_available => '始终可用';

  @override
  String get tts_system_desc => '使用您设备内置的语音合成引擎。\n无需额外下载。语音选择依赖您的设备系统设置。';

  @override
  String get downloading_status => '正在下载...';

  @override
  String tts_kitten_desc(String size) {
    return '拥有 8 种表现力声音的闪电般高速神经网络 TTS。\n需要下载 $size。';
  }

  @override
  String tts_piper_desc(String size) {
    return '快速离线 Piper 语音，拥有 2 种极具表现力的声音。\n每个声音需要下载 $size。';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB 内存 · $voiceCount 种语音';
  }

  @override
  String get on_device_models_title => '设备端模型';

  @override
  String get settings_huggingface_token => 'Hugging Face 令牌（可选）';

  @override
  String get settings_huggingface_token_desc =>
      '仅对受限模型必需（例如 Gemma）。可在 huggingface.co/settings/tokens 获取令牌。';

  @override
  String get settings_huggingface_token_set => '令牌已保存';

  @override
  String get settings_huggingface_token_cleared => '令牌已清除';

  @override
  String get model_requires_huggingface_token => '需要 Hugging Face 令牌';

  @override
  String get model_missing_huggingface_token =>
      '此模型在 Hugging Face 上受限。请在“设置 → 设备端推理”中添加令牌后再下载。';

  @override
  String get set_huggingface_token => '设置令牌';

  @override
  String get clear_huggingface_token => '清除';

  @override
  String get edit_huggingface_token_dialog_title => 'Hugging Face 访问令牌';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc => '本地 AI 引擎。无需 API 密钥。';

  @override
  String get server_type_on_device_desc => '在您的手机上运行。某些模型需要 Hugging Face 令牌。';

  @override
  String get server_type_lm_studio_desc => '本地 API 服务器。无需 API 密钥。';

  @override
  String get available_models => '可用模型';

  @override
  String get device_memory => '设备内存';

  @override
  String get ram_usage => '内存占用';

  @override
  String get memory_healthy => '健康';

  @override
  String get memory_critical => '严重警告';

  @override
  String get memory_low => '偏低';

  @override
  String ram_used(String percent) {
    return '已使用 $percent%';
  }

  @override
  String get available_ram => '可用内存';

  @override
  String get total_capacity => '总容量';

  @override
  String get loaded_status => '已加载';

  @override
  String get inference_backend => '推理后端';

  @override
  String get backend_ios_notice => 'iOS 上仅支持 CPU 后端。';

  @override
  String get backend_cpu_desc => '适用于所有设备。兼容性最好。';

  @override
  String get backend_gpu_desc => 'OpenCL 加速。在支持 of 设备上运行更快。';

  @override
  String get backend_npu_desc => '厂商 NPU (高通/联发科)。最快的推理速度。';

  @override
  String get select_model_title => '选择模型';

  @override
  String get refresh_models => '刷新模型';

  @override
  String get search_models_hint => '搜索模型...';

  @override
  String get no_server_connected => '未连接服务器';

  @override
  String get add_server_first => '请先添加服务器以查看可用模型。';

  @override
  String get failed_load_models => '加载模型失败';

  @override
  String get no_models_available => '无可用模型';

  @override
  String no_models_match(String searchQuery) {
    return '没有匹配 \"$searchQuery\" 的模型';
  }

  @override
  String model_load_failed(String error) {
    return '加载模型失败: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return '在 keep-alive 时间过去后，$name 将被自动卸载';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name 已成功卸载';
  }

  @override
  String model_unload_failed(String error) {
    return '卸载模型失败: $error';
  }

  @override
  String get unload_from_server => '从服务器卸载';

  @override
  String context_chip(String ctx) {
    return '$ctx 上下文 (ctx)';
  }

  @override
  String get unload_all_models => '卸载所有模型';

  @override
  String loaded_models_count(int count) {
    return '已加载 $count 个模型';
  }

  @override
  String get all_models_unloaded => '所有模型已卸载';

  @override
  String get branch_chat => '分支聊天';

  @override
  String get branch_chat_desc => '从此消息开始新建聊天';

  @override
  String get edit_assistant_message_desc => '编辑助手消息的内容';

  @override
  String switch_to_model(String modelName, Object model) {
    return '切换到模型 $model';
  }

  @override
  String download_notification_title(String modelName) {
    return '正在下载 $modelName...';
  }

  @override
  String get download_complete_notification => '下载完成！';

  @override
  String download_complete_body(String modelName) {
    return '$modelName 已成功下载。';
  }

  @override
  String download_failed_notification(String error) {
    return '下载失败: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return '下载 $modelName 失败。';
  }

  @override
  String get engine_name_system => '系统 TTS';

  @override
  String get engine_tagline_system => '内置设备引擎';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => '高速神经网络 TTS';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => '离线 Piper 语音';

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
  String get voice_lessac => 'Lessac (美音)';

  @override
  String get voice_ryan => 'Ryan (美音)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc => '最小的通用聊天模型。响应速度快，内存消耗低。';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc => '平衡的质量和大小。适合一般对话。';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc => '推理与思维链模型。最适合逻辑任务。';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc => 'Google 旗舰模型。最高质量，需要更多内存。';

  @override
  String export_header(String date) {
    return '*导出自 LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 用户';

  @override
  String get export_role_assistant => '## 🤖 助手';

  @override
  String get export_role_system => '## ⚙️ 系统';

  @override
  String get export_role_tool => '## 🔧 工具';

  @override
  String get export_text_user => '[用户]';

  @override
  String get export_text_assistant => '[助手]';

  @override
  String get export_text_system => '[系统]';

  @override
  String get export_text_tool => '[工具]';

  @override
  String get export_label_user => '用户';

  @override
  String get export_label_assistant => '助手';

  @override
  String get export_label_system => '系统';

  @override
  String get export_label_tool => '工具';

  @override
  String get select_model_hint => '选择一个模型以开始聊天';

  @override
  String get test_notification_title => '测试通知';

  @override
  String get test_notification_body => '这是用于展示模型下载进度的测试通知。';

  @override
  String get tts_supports_background => '支持后台播放（原生音频格式）';

  @override
  String get tts_other_services_background_note => '注意：其他TTS服务支持后台播放（原生音频格式）。';

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
  String get model_favorite_toggle => '切换收藏';

  @override
  String get model_set_default => 'Set as default model';

  @override
  String get model_clear_default => 'Remove as default model';

  @override
  String get model_default_badge => 'Default';

  @override
  String get model_note_label => '备注';

  @override
  String get model_note_hint => '为此模型添加个人备注...';

  @override
  String get unload_models_before_load => '加载前卸载模型';

  @override
  String get temp_chat_keyboard_incognito => '临时聊天中的隐私键盘';

  @override
  String get temp_chat_keyboard_incognito_desc => '请求系统键盘在临时聊天期间不保存输入历史记录';

  @override
  String get resume_last_chat => '恢复上次聊天';

  @override
  String get resume_last_chat_desc => '启动时自动打开您上次活跃的对话';

  @override
  String get export_all_data => '导出所有数据';

  @override
  String get import_all_data => '导入所有数据';

  @override
  String get export_data_success => '数据导出成功';

  @override
  String get import_data_success => '数据导入成功';

  @override
  String import_data_failed(String error) {
    return '导入数据失败';
  }

  @override
  String get import_data_confirm => '这将用导入的数据替换您当前的所有数据。是否继续？';

  @override
  String get import_settings_confirm => '这将用导入的设置替换您当前的设置。是否继续？';

  @override
  String get export_conversations => '导出对话';

  @override
  String get import_conversations => '导入对话';

  @override
  String get export_personas => '导出角色';

  @override
  String get import_personas => '导入角色';

  @override
  String get export_settings => '导出设置';

  @override
  String get import_settings => '导入设置';

  @override
  String get export_all_zip => '导出全部 (ZIP)';

  @override
  String get import_all_zip => '导入全部 (ZIP)';

  @override
  String get duplicate_chat => '复制聊天';

  @override
  String get duplicate_chat_success => '聊天复制成功';

  @override
  String get move_to_folder => '移动到文件夹';

  @override
  String get remove_from_folder => '从文件夹中移除';

  @override
  String get create_folder => '创建文件夹';

  @override
  String get new_folder => '新文件夹';

  @override
  String get folder_name_hint => '输入文件夹名称...';

  @override
  String get all_chats => '所有聊天';

  @override
  String get unfiled_chats => '未分类聊天';

  @override
  String get create => '创建';

  @override
  String get server_path_prefix_label => '服务器路径前缀';

  @override
  String get server_path_prefix_hint => '服务器 API 路径的可选前缀 (例如 /v1)';

  @override
  String get search_message_contents => '搜索消息内容...';

  @override
  String get message_search_results => '消息搜索结果';

  @override
  String get saved_messages_title => '已保存的消息';

  @override
  String get nav_saved_messages => '保存消息';

  @override
  String get saved_messages_empty => '尚无保存的消息';

  @override
  String get save_message => '保存消息';

  @override
  String get message_saved => '消息已保存';

  @override
  String token_count(int count) {
    return 'Token 数: $count';
  }

  @override
  String estimated_token_count(int count) {
    return '预估 Token 数: $count';
  }

  @override
  String get test_tts_section_title => '文字转语音测试';

  @override
  String get test_tts_hint => '输入内容以测试声音...';

  @override
  String get test_speak_button => '朗读';

  @override
  String get scroll_to_bottom => '滚动到底部';

  @override
  String get generate_ai_response => '生成 AI 回复';

  @override
  String get no_response => '无回复';

  @override
  String get export => '导出';

  @override
  String get import => '导入';

  @override
  String get conversations_label => '对话';

  @override
  String get personas_label => '角色';

  @override
  String get settings_label => '设置';

  @override
  String get export_conversation => '导出对话';

  @override
  String get tts_process_markdown => '处理 Markdown';

  @override
  String get tts_process_markdown_desc => '在朗读前去除 **加粗** 等格式标记';

  @override
  String get tts_skip_seconds => '跳过秒数';

  @override
  String get tts_skip_seconds_desc => '语音播放器中快进/快退的时间';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$seconds秒';
  }

  @override
  String get preview_system_prompts => '预览系统提示词';

  @override
  String get welcome_message_1 => '你好！我是您的本地 AI 助手。';

  @override
  String get welcome_message_2 => '问我任何问题——我随时恭候。';

  @override
  String get welcome_message_3 => '您的数据完全在本地处理，绝不会离开您的设备。';

  @override
  String get welcome_message_4 => '要开始，请从顶部栏中选择一个模型，或在模型管理部分中添加一个新模型。';

  @override
  String get temporary_chat => '临时聊天';

  @override
  String get temporary_chat_desc => '此聊天中的消息不会保存到历史记录中';

  @override
  String get temporary_chat_banner => '临时聊天处于活动状态——消息将不保存到历史记录';

  @override
  String get temporary_chat_save_warning_title => '保存临时聊天？';

  @override
  String get temporary_chat_save_warning_body => '此聊天未保存到您的历史记录中。您想现在保存吗？';

  @override
  String get save_to_history => '保存到历史记录';

  @override
  String get share_conversation => '分享对话';

  @override
  String get download_tts_audio => '下载音频';

  @override
  String get tts_download_unavailable => '音频下载不可用';

  @override
  String get tts_download_no_audio => '没有生成的可供下载的音频';

  @override
  String get tts_download_success => '音频保存成功';

  @override
  String get return_to_chat => '返回聊天';

  @override
  String get return_to_temp_chat => '返回临时聊天';

  @override
  String get insert_saved_message => '插入已保存的消息';

  @override
  String get insert_saved_message_desc => '将您已保存的文本片段添加到聊天中';

  @override
  String get model_info => '模型信息';

  @override
  String get model_name => '模型名称';

  @override
  String get model_identifier => '模型标识符';

  @override
  String get model_capabilities => 'Capabilities';

  @override
  String get model_api_pricing => 'API pricing (per 1M tokens)';

  @override
  String get not_available => '不可用';

  @override
  String get save_message_folders => '保存到文件夹';

  @override
  String get remove_from_saved => '从已保存中移除';

  @override
  String get message_already_saved => '消息已保存';

  @override
  String get stream_ttft => '首个 Token 延迟';

  @override
  String get stream_tokens_per_sec => '每秒 Token 数';

  @override
  String get stream_stop_reason => '停止原因';

  @override
  String get stream_input_tokens => '输入 Token 数';

  @override
  String get stream_output_tokens => '输出 Token 数';

  @override
  String get stream_generation_time => '生成时间';

  @override
  String get attach_image => '附加图片';

  @override
  String get attach_text_document => '附加文本文件';

  @override
  String get attach_shortcut_images => '照片';

  @override
  String get attach_shortcut_documents => '文件';

  @override
  String get attach_shortcut_saved => '已保存';

  @override
  String get add_attachment => '添加附件';

  @override
  String get add_to_chat => '添加到聊天';

  @override
  String get choose_what_to_attach => '您想添加什么？';

  @override
  String get choose_attachment_subtitle => '选择要附加到消息的来源';

  @override
  String get photo_permission_denied => '相册权限被拒绝';

  @override
  String get select_model_prompt => '选择模型';

  @override
  String get characters_label => '字符数';

  @override
  String get exit_temporary_chat_title => '退出临时聊天？';

  @override
  String get exit_temporary_chat_body => '这将永久删除当前的对话。是否继续？';

  @override
  String get saved_message_temp_snap_unavailable => '临时聊天中不支持消息快照';

  @override
  String get filter_title => '筛选聊天';

  @override
  String get filter_pinned => '已置顶';

  @override
  String get filter_archived => '已归档';

  @override
  String get filter_temp_chats => '临时聊天';

  @override
  String get filter_user_messages => '用户消息';

  @override
  String get filter_assistant_messages => '助手消息';

  @override
  String get archive_chat => '归档聊天';

  @override
  String get unarchive_chat => '取消归档';

  @override
  String conversation_message_count(int count) {
    return '$count 条消息';
  }

  @override
  String conversation_character_count(int count) {
    return '$count 个字符';
  }

  @override
  String get generate_title_with_ai => '使用 AI 生成标题';

  @override
  String get generating_title => '正在生成标题...';

  @override
  String get generate_title_failed => '无法生成标题';

  @override
  String get lm_studio_model_browser_title => '模型浏览器';

  @override
  String get lm_studio_model_search_hint => '搜索模型...';

  @override
  String get lm_studio_staff_picks => '编辑精选';

  @override
  String get lm_studio_community_models => '社区模型';

  @override
  String get lm_studio_no_models => '未找到模型';

  @override
  String lm_studio_models_count(int count) {
    return '$count 个模型';
  }

  @override
  String get lm_studio_browse_models => '在 LM Studio 中浏览模型';

  @override
  String get lm_studio_model_search => '模型搜索';

  @override
  String get lm_studio_downloads_title => '下载';

  @override
  String get lm_studio_choose_quant => '选择量化版本';

  @override
  String get lm_studio_use_default_quant => '使用默认量化版本';

  @override
  String get lm_studio_recommended => '推荐';

  @override
  String get lm_studio_clear_downloads => '清除已完成的下载';

  @override
  String get lm_studio_no_downloads => '无活动中的下载';

  @override
  String get lm_studio_downloads_disclaimer => '模型下载直接从 Hugging Face 获取。';

  @override
  String get lm_studio_staff_pick => '推荐模型';

  @override
  String get lm_studio_params => '参数';

  @override
  String get lm_studio_arch => '架构';

  @override
  String get lm_studio_domain => '领域';

  @override
  String get lm_studio_format => '格式';

  @override
  String get lm_studio_vision => '视觉能力';

  @override
  String get lm_studio_tool_use => '工具调用';

  @override
  String get lm_studio_reasoning => '推理能力';

  @override
  String get openrouter_pricing_free => 'Free';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Input $input / Output $output per 1M tokens';
  }

  @override
  String get lm_studio_download_options => '下载选项';

  @override
  String get lm_studio_download => '下载';

  @override
  String lm_studio_download_size(String size) {
    return '下载大小';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return '正在下载: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable => '此模型无 README 说明文件。';

  @override
  String get lm_studio_full_gpu_offload => '支持完全 GPU 卸载';

  @override
  String get lm_studio_partial_gpu_offload => '支持部分 GPU 卸载';

  @override
  String get lm_studio_likely_too_large => '可能过大';

  @override
  String get lm_studio_available_ram_gb => '可用 RAM (GB, 可选)';

  @override
  String get lm_studio_available_vram_gb => '可用 VRAM (GB, 可选)';

  @override
  String get lm_studio_memory_settings_title => '用于推荐的内存大小';

  @override
  String get lm_studio_memory_settings_desc => '用于在模型浏览器中预估模型是否可以在您的设备上运行。';

  @override
  String get think_button_label => '思考';

  @override
  String get thinking_mode_title => '思考模式';

  @override
  String get reasoning_effort_low => '低';

  @override
  String get reasoning_effort_medium => '中';

  @override
  String get reasoning_effort_high => '高';

  @override
  String get could_not_read_file => '无法读取文件';

  @override
  String get server_offline => '服务器已离线';

  @override
  String get could_not_establish_connection =>
      '无法与服务器建立连接。请检查您的服务器是否正在运行，以及主机/端口设置是否正确。';

  @override
  String get retry_connection => '重试连接';

  @override
  String get tokens_label => 'Token 数';

  @override
  String get enter_context_length => '输入上下文长度...';

  @override
  String get openrouter_disclosure =>
      '连接此提供商后，您的聊天消息和输入将被发送到他们的服务器。LocalMind 不会跟踪或存储您的对话。';

  @override
  String get welcome_message_cloud => '您的消息将发送到您连接的提供商。';

  @override
  String get privacy_policy => '隐私政策';

  @override
  String get cloud_sync => 'S3 云同步';

  @override
  String get cloud_sync_description => '与您自己的 S3 兼容服务器进行端到端加密同步';

  @override
  String get cloud_sync_endpoint => '端点 URL';

  @override
  String get cloud_sync_bucket => '存储桶';

  @override
  String get cloud_sync_region => '区域';

  @override
  String get cloud_sync_prefix => '前缀';

  @override
  String get cloud_sync_access_key => '访问密钥 ID';

  @override
  String get cloud_sync_secret_key => '秘密访问密钥';

  @override
  String get cloud_sync_session_token => '会话令牌（可选）';

  @override
  String get cloud_sync_passphrase => '加密密码短语';

  @override
  String get cloud_sync_confirm_passphrase => '确认密码短语';

  @override
  String get cloud_sync_path_style => '使用路径样式寻址';

  @override
  String get cloud_sync_allow_http => '允许不安全的 HTTP';

  @override
  String get cloud_sync_http_warning => 'HTTP 会向网络暴露请求信息和凭据。仅在可信的本地 S3 服务器上使用。';

  @override
  String get cloud_sync_test => '测试连接';

  @override
  String get cloud_sync_enable => '启用加密同步';

  @override
  String get cloud_sync_now => '立即同步';

  @override
  String get cloud_sync_disconnect => '断开此设备';

  @override
  String get cloud_sync_last_synced => '上次同步';

  @override
  String get cloud_sync_never => '从未';

  @override
  String get cloud_sync_conflicts => '已保留冲突';

  @override
  String get cloud_sync_passphrase_mismatch => '密码短语不匹配';

  @override
  String get crash_report_title => '出了点问题';

  @override
  String get crash_report_stack_trace => '堆栈跟踪';

  @override
  String get crash_report_tap_to_expand => '点击展开';

  @override
  String get crash_report_button => '报告此崩溃';

  @override
  String get crash_try_again => '重试';

  @override
  String get crash_report_empty_stack => '<空>';

  @override
  String get crash_report_disclaimer =>
      '报告将打开已预填诊断信息的 GitHub。由您掌控 — 不会自动提交任何内容。请在提交前检查并删除敏感内容。';

  @override
  String get crash_report_copied => '已复制到剪贴板';

  @override
  String get report_a_problem => '报告问题';

  @override
  String get rename_folder => '重命名文件夹';

  @override
  String get delete_folder => '删除文件夹';

  @override
  String get delete_folder_title => '删除文件夹？';

  @override
  String delete_folder_body(String name) {
    return '确定要删除\"$name\"吗？其中的对话或已保存的消息将移回\"未分类\"。此操作无法撤销。';
  }

  @override
  String get folder_name_required => '请输入文件夹名称';

  @override
  String get model_required_toast => '您需要先选择一个模型';
}

/// The translations for Chinese, as used in Taiwan (`zh_TW`).
class AppLocalizationsZhTw extends AppLocalizationsZh {
  AppLocalizationsZhTw() : super('zh_TW');

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => '您的 AI。您的裝置。您的規則。';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '確認';

  @override
  String get delete => '刪除';

  @override
  String get save => '儲存';

  @override
  String get retry => '重試';

  @override
  String get close => '關閉';

  @override
  String get done => '完成';

  @override
  String get continue_action => '繼續';

  @override
  String get skip => '跳過';

  @override
  String get install => '安裝';

  @override
  String get download => '下載';

  @override
  String get resume => '繼續';

  @override
  String get pause => '暫停';

  @override
  String get stop => '停止';

  @override
  String get edit => '編輯';

  @override
  String get preview => '預覽';

  @override
  String get unload => '卸載';

  @override
  String get load => '載入';

  @override
  String get rename => '重新命名';

  @override
  String get pin => '釘選';

  @override
  String get unpin => '取消釘選';

  @override
  String get share => '分享';

  @override
  String get copy => '複製';

  @override
  String get copied => '已複製！';

  @override
  String get copied_to_clipboard => '已複製到剪貼簿';

  @override
  String get select => '選擇';

  @override
  String get active => '已啟用';

  @override
  String get all => '全部';

  @override
  String get none => '無';

  @override
  String get none_selected => '未選擇';

  @override
  String get online => '線上';

  @override
  String get connected => '已連線';

  @override
  String get checking => '正在檢查';

  @override
  String get offline => '離線';

  @override
  String get error => '錯誤';

  @override
  String get unknown_error => '未知錯誤';

  @override
  String get not_now => '暫不';

  @override
  String get enable => '啟用';

  @override
  String get proceed_anyway => '仍然繼續';

  @override
  String get test_connection => '測試連線';

  @override
  String get testing => '正在測試...';

  @override
  String get connection_successful => '連線成功！';

  @override
  String get connection_failed => '連線失敗。請檢查您的設定。';

  @override
  String get save_continue => '儲存並繼續';

  @override
  String get save_changes => '儲存變更';

  @override
  String get finish_setup => '完成設定';

  @override
  String get start_new_chat => '開始新對話';

  @override
  String get cannot_undo => '此操作無法復原。';

  @override
  String get ram_warning => '記憶體警告';

  @override
  String get recommended => '推薦';

  @override
  String get may_be_large => '可能對此裝置來說過大';

  @override
  String get calculating => '正在計算...';

  @override
  String get download_failed => '下載失敗';

  @override
  String get downloaded => '已下載';

  @override
  String get not_downloaded => '未下載';

  @override
  String get installed => '已安裝';

  @override
  String get not_installed => '未安裝';

  @override
  String get loading => '正在載入...';

  @override
  String get thinking => '正在思考';

  @override
  String get processing => '正在處理...';

  @override
  String get initializing => '正在初始化...';

  @override
  String get ready => '就緒';

  @override
  String get preparing_app => '正在準備應用程式...';

  @override
  String get initializing_services => '正在初始化服務...';

  @override
  String get configuring_server => '正在設定伺服器...';

  @override
  String get startup_failed => '啟動失敗';

  @override
  String get something_went_wrong => '出了點問題';

  @override
  String get delete_model_title => '刪除模型';

  @override
  String delete_model_body(String name) {
    return '您確定要刪除 $name 嗎？';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return '您確定要刪除 $name 嗎？這將釋放約 $size 的空間。\n\n如有需要，您稍後可以重新下載此模型。';
  }

  @override
  String get delete_voice_title => '刪除語音';

  @override
  String delete_voice_body(String name, String size) {
    return '您確定要刪除 $name 嗎？這將釋放約 $size 的空間。\n\n如有需要，您稍後可以重新下載此語音。';
  }

  @override
  String get delete_server_title => '刪除伺服器';

  @override
  String delete_server_body(String name) {
    return '您確定要刪除 \"$name\" 嗎？此操作無法復原。';
  }

  @override
  String get delete_conversation_title => '要刪除對話嗎？';

  @override
  String delete_conversation_body(String title) {
    return '您確定要刪除 \"$title\" 嗎？此操作無法復原。';
  }

  @override
  String get delete_message_title => '要刪除訊息嗎？';

  @override
  String delete_persona_title(String name) {
    return '要刪除 \"$name\" 嗎？';
  }

  @override
  String get delete_persona_body => '此操作無法復原。';

  @override
  String get delete_builtin_persona_body => '這是一個內置角色。您稍後可以在「設定」中將其恢復。';

  @override
  String get restore_builtin_personas => '恢復預設角色';

  @override
  String get restore_builtin_personas_desc => '重新添加您已刪除的任何內置角色';

  @override
  String get restore_builtin_personas_success => '已恢復預設角色';

  @override
  String get clear_personas => '清除角色';

  @override
  String get enable_image_compression => '發送前壓縮圖片';

  @override
  String get enable_image_compression_desc => '調整並壓縮附加圖片的大小，以使上傳大小保持在伺服器限制內';

  @override
  String get image_compression_level => '壓縮強度';

  @override
  String get image_compression_level_desc => '較高的壓縮強度會生成質量較低但上傳更小的圖片';

  @override
  String get image_compression_level_low => '低';

  @override
  String get image_compression_level_medium => '中';

  @override
  String get image_compression_level_high => '高';

  @override
  String get sort_models_tooltip => '排序模型';

  @override
  String get sort_by_favorites => '收藏優先';

  @override
  String get sort_by_name => '名稱 (A-Z)';

  @override
  String get sort_by_size_smallest => '大小 (從小到大)';

  @override
  String get sort_by_size_largest => '大小 (從大到小)';

  @override
  String get sort_by_context_length => '上下文長度';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return '正在重命名 $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '已選擇 $count 個';
  }

  @override
  String get ai_rename_tooltip => '使用 AI 重命名所選內容';

  @override
  String get new_chat_in_folder_tooltip => '在此資料夾中新建聊天';

  @override
  String total_tokens_count(int count) {
    return '$count 個 Token';
  }

  @override
  String get smart_replies_use_persona => '在智能回覆中應用角色';

  @override
  String get smart_replies_use_persona_desc => '建議的回覆將符合當前啟用角色的語氣，而不是通用的助手語氣';

  @override
  String get keep_persona_on_new_chat => '新聊天保留角色';

  @override
  String get keep_persona_on_new_chat_desc => '開始新聊天時不要清除選定的角色';

  @override
  String get role_swap_button_enabled => '顯示角色切換按鈕';

  @override
  String get role_swap_button_enabled_desc =>
      '在聊天輸入框中顯示一個按鈕，允許您以助手而非用戶的身份發送消息，而不生成任何回覆';

  @override
  String get send_as_user_tooltip => '以用戶身份發送';

  @override
  String get send_as_assistant_tooltip => '以助手身份發送 (無回覆)';

  @override
  String get insert_without_generating_tooltip => '僅插入不生成回覆';

  @override
  String get token_usage_title => 'Token 使用情況';

  @override
  String get total_tokens_label => '已用 Token';

  @override
  String get usage_percent_label => '已用上下文';

  @override
  String get export_choice_title => '匯出';

  @override
  String get export_choice_body => '您希望如何匯出此內容？';

  @override
  String get copy_to_clipboard => '複製到剪貼簿';

  @override
  String bulk_export_conversations_success(int count) {
    return '已成功匯出 $count 個對話';
  }

  @override
  String get bulk_ai_rename_confirm_title => '使用 AI 重命名？';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return '這將請求 AI 為每個選定的 $count 個對話生成新標題，替換其當前的標題。此操作可能需要一些時間，且無法撤銷。';
  }

  @override
  String get sort_by_modified_date => '最近修改';

  @override
  String get sort_by_created_date => '創建日期';

  @override
  String get sort_title => '排序';

  @override
  String get clear_conversation_title => '要清除對話嗎？';

  @override
  String get clear_conversation_body => '這會刪除此對話中的所有訊息。';

  @override
  String get clear => '清除';

  @override
  String label_completed(String label) {
    return '$label 已完成';
  }

  @override
  String error_with_message(String error) {
    return '錯誤: $error';
  }

  @override
  String preview_failed(String error) {
    return '預覽失敗: $error';
  }

  @override
  String loading_model(String modelId) {
    return '正在載入 $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return '模型已載入: $modelId ($backend)';
  }

  @override
  String get no_model_loaded => '未載入任何模型。點擊「管理裝置端模型」以下載並載入模型。';

  @override
  String loading_model_error(String error) {
    return '錯誤: $error';
  }

  @override
  String get delete_conversation => '要刪除對話嗎？';

  @override
  String get nav_history => '歷史';

  @override
  String get nav_servers => '伺服器';

  @override
  String get nav_local_models => '本機模型';

  @override
  String get nav_tts => '語音合成';

  @override
  String get nav_personas => '角色';

  @override
  String get nav_settings => '設定';

  @override
  String get nav_new_chat => '新對話';

  @override
  String get search_hint => '搜尋對話...';

  @override
  String get no_server_selected => '未選擇伺服器';

  @override
  String get switch_server => '切換伺服器';

  @override
  String get switch_server_subtitle => '選擇要連線的伺服器';

  @override
  String get manage_servers => '管理伺服器';

  @override
  String get open_source => '開源';

  @override
  String get open_source_desc => 'LocalMind 是開源專案。可在 GitHub 上關注我們的進展或參與貢獻。';

  @override
  String get star_on_github => '在 GitHub 上點亮 Star';

  @override
  String get add_more => '新增更多';

  @override
  String get on_github => '在 GitHub 上';

  @override
  String get could_not_open_github => '無法開啟 GitHub。';

  @override
  String get settings_title => '設定';

  @override
  String get settings_appearance => '外觀';

  @override
  String get settings_language => '語言';

  @override
  String get language_system_default => '系統預設';

  @override
  String get settings_tts => '語音合成 (TTS)';

  @override
  String get settings_behavior => '行為';

  @override
  String get settings_on_device => '裝置端推論';

  @override
  String get settings_default_server => '預設伺服器';

  @override
  String get settings_default_persona => '預設角色';

  @override
  String get settings_privacy => '隱私';

  @override
  String get settings_data_management => '資料管理';

  @override
  String get settings_about => '關於';

  @override
  String get theme => '主題';

  @override
  String get theme_system => '系統';

  @override
  String get theme_light => '淺色';

  @override
  String get theme_dark => '深色';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => '字型大小';

  @override
  String get font_size_desc => '調整對話中的文字大小。';

  @override
  String get font_preview => '敏捷的棕色狐狸跳過那隻懶狗。';

  @override
  String get code_theme_dark => '程式碼主題 (深色)';

  @override
  String get code_theme_light => '程式碼主題 (淺色)';

  @override
  String get code_theme_desc => '選擇程式碼區塊的語法醒目提示主題。';

  @override
  String get tts_engine => 'TTS 引擎';

  @override
  String get tts_engine_system => '系統 TTS';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => '語音';

  @override
  String get voice_female => '女聲';

  @override
  String get voice_male => '男聲';

  @override
  String get voice_other => '其他';

  @override
  String get tts_speed => 'TTS 速度';

  @override
  String get tts_speed_desc => '調整播放速率。';

  @override
  String get manage_tts_models => '管理 TTS 模型';

  @override
  String get manage_on_device_models => '管理裝置端模型';

  @override
  String get enable_smart_reply => '裝置端智慧回覆';

  @override
  String get ai_user_response_enabled => 'AI 用戶消息 (長按發送)';

  @override
  String get ai_user_response_enabled_desc => '長按發送按鈕 3 秒鐘以讓 AI 撰寫並發送您的下一條消息';

  @override
  String get ai_user_response_tooltip => '使用 AI 生成用戶消息';

  @override
  String get streaming_responses => '串流響應';

  @override
  String get auto_generate_titles => '自動生成標題';

  @override
  String get send_on_enter => '按 Enter 鍵發送';

  @override
  String get show_system_messages => '顯示系統訊息';

  @override
  String get show_system_messages_desc => '當沒有選定角色時，每次請求都發送預設的助手系統提示詞';

  @override
  String get show_system_messages_in_chat => '在聊天中顯示系統消息';

  @override
  String get show_system_messages_in_chat_desc =>
      '將系統消息 (例如來自導入的備份) 作為對話中的可見氣泡顯示';

  @override
  String get haptic_feedback => '觸覺回饋';

  @override
  String get enable_mcp => '啟用 MCP';

  @override
  String get new_chat_mcp_default => '新對話預設啟用 MCP';

  @override
  String get show_data_indicator => '顯示數據指示器';

  @override
  String get privacy_info => '「LocalMind 絕不查看您的數據」';

  @override
  String get delete_all_conversations => '刪除所有對話';

  @override
  String get reset_settings_defaults => '重設設定至預設值';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => '對話參數';

  @override
  String get change_persona => '更換角色';

  @override
  String get set_persona => '設定角色';

  @override
  String get remove_persona => '刪除角色';

  @override
  String get clear_conversation => '清除對話';

  @override
  String get connection_error => '連線錯誤。請檢查您的伺服器。';

  @override
  String get disconnected => '與伺服器斷開連線。';

  @override
  String get configure => '設定';

  @override
  String get select_model => '選擇模型';

  @override
  String get select_persona => '選擇角色';

  @override
  String get manage_personas => '管理角色';

  @override
  String get personas_combine_hint => '選定的角色將被合併';

  @override
  String get start_conversation => '開始對話';

  @override
  String get recent_chats => '最近對話';

  @override
  String get see_all => '查看全部';

  @override
  String get quick_write => '幫我寫一個函式';

  @override
  String get quick_explain => '解釋這段程式碼';

  @override
  String get quick_debug => '幫我偵錯這個';

  @override
  String get quick_async => '我該如何使用 async/await？';

  @override
  String get history_missing_title => '歷史紀錄遺失';

  @override
  String get history_missing_desc => '此對話中的訊息已被刪除，或歷史紀錄已損壞。';

  @override
  String get technical_details => '技術細節';

  @override
  String get last_error => '上次錯誤:';

  @override
  String get copy_info => '複製資訊';

  @override
  String get conversation_id => '對話 ID';

  @override
  String get created_at => '建立於';

  @override
  String get expected_messages => '預期訊息';

  @override
  String get debug_dialog_desc => '用以協助識別同步問題的診斷資訊。';

  @override
  String get chat_input_hint => '詢問任何問題';

  @override
  String get send_message_tooltip => '發送訊息';

  @override
  String get stop_generation_tooltip => '停止生成';

  @override
  String get attach_images_tooltip => '附加圖片';

  @override
  String get start_listening_tooltip => '開始聆聽';

  @override
  String get stop_listening_tooltip => '停止聆聽';

  @override
  String tool_label(String toolCallId) {
    return '工具: $toolCallId';
  }

  @override
  String get tool_unknown => '工具: 未知';

  @override
  String get message_options => '訊息選項';

  @override
  String get copy_markdown => '複製為 Markdown';

  @override
  String get copied_markdown => '已複製為 Markdown';

  @override
  String get read_aloud => '朗讀';

  @override
  String get stop_reading => '停止朗讀';

  @override
  String get more => '更多';

  @override
  String character_count(int length) {
    return '$length 個字元';
  }

  @override
  String get edit_message => '編輯訊息';

  @override
  String get edit_message_desc => '儲存將移除下方助理的回覆並重新生成。';

  @override
  String get save_regenerate => '儲存並重新生成';

  @override
  String get chat_settings_title => '對話設定';

  @override
  String get reset_defaults => '重設預設值';

  @override
  String get parameters_tab => '參數';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => '溫度';

  @override
  String get temperature_desc => '控制隨機性：較高 = 創意，較低 = 專注';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => '核取樣門檻';

  @override
  String get max_tokens => '最大 Token 數';

  @override
  String get max_tokens_desc => '回應限制';

  @override
  String get context_length => '上下文長度';

  @override
  String get context_length_desc => '歷史視窗';

  @override
  String get mcp_disabled_warning => 'MCP 已在全域被停用。請在設定中啟用以使用這些功能。';

  @override
  String get mcp_enable_chat => '為此對話啟用 MCP';

  @override
  String get auto_execute_tools => '自動執行工具';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => '實驗性';

  @override
  String get add_ephemeral_mcp => '新增臨時 MCP 伺服器';

  @override
  String get mcp_label_placeholder => '標籤';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => '活動整合';

  @override
  String get enable_notifications => '啟用通知';

  @override
  String get enable_notifications_desc => '在模型下載完成時獲得通知。';

  @override
  String get chat_history_title => '對話歷史';

  @override
  String get conversation_just_now => '剛剛';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes分鐘前';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours小時前';
  }

  @override
  String get conversation_yesterday => '昨天';

  @override
  String conversation_days_ago(int days) {
    return '$days天前';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => '選項';

  @override
  String get no_results_found => '未找到結果';

  @override
  String get no_conversations_yet => '尚無對話';

  @override
  String get try_different_search => '嘗試不同的搜尋詞';

  @override
  String get start_new_conversation => '開始新對話';

  @override
  String get rename_conversation => '重新命名對話';

  @override
  String get enter_new_title => '輸入新標題';

  @override
  String get pinned_section => '已釘選';

  @override
  String get today_section => '今天';

  @override
  String get yesterday_section => '昨天';

  @override
  String get previous_7_days => '前 7 天';

  @override
  String get previous_30_days => '前 30 天';

  @override
  String get older_section => '更早';

  @override
  String get onboarding_choose_language => '選擇語言';

  @override
  String get onboarding_choose_language_desc => '選擇您偏好的語言。您隨時可以在設定中變更此項。';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => '連線您的\n伺服器';

  @override
  String get onboarding_connect_desc =>
      '連線到 LM Studio、Ollama 或\nOpenRouter，開啟您的私有 AI\n體驗。';

  @override
  String get openai_compatible_api => 'OpenAI 相容 API';

  @override
  String get https_requires_ssl => 'HTTPS 需要 SSL';

  @override
  String get most_local_setups_use_http => '大多數本機配置使用 http://';

  @override
  String get onboarding_welcome => '歡迎使用 LocalMind';

  @override
  String get server_type_on_device => '裝置端';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => '統一雲端';

  @override
  String get ready_continue => '準備好繼續';

  @override
  String get waiting_selection => '等待選擇';

  @override
  String get setup_connection => '設定連線';

  @override
  String setup_connection_desc(String server) {
    return '設定您的 $server 伺服器以開始對話。';
  }

  @override
  String get server_name => '伺服器名稱';

  @override
  String get name_required => '需要名稱';

  @override
  String get name_max_50 => '最多 50 個字元';

  @override
  String get host_label => '主機 / IP 地址';

  @override
  String get host_required => '需要主機地址';

  @override
  String get port_label => '連接埠';

  @override
  String get port_required => '需要連接埠';

  @override
  String get port_invalid => '必須是數字';

  @override
  String get port_range => '輸入有效的連接埠號碼 (1-65535)';

  @override
  String get api_key_required => 'API 金鑰 *';

  @override
  String get api_key_optional => 'API 金鑰 (選填)';

  @override
  String get api_key_required_openrouter => 'OpenRouter 需要 API 金鑰';

  @override
  String get api_key_format => 'OpenRouter API 金鑰以 sk- 開頭';

  @override
  String get my_server_hint => '我的伺服器';

  @override
  String get name_length_validation => '名稱必須在 50 個字元以內';

  @override
  String get host_valid => '輸入有效的主機名稱或 IP 地址';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => '適用於已驗證的伺服器';

  @override
  String get update_server => '更新伺服器';

  @override
  String get save_server => '儲存伺服器';

  @override
  String get server_updated => '伺服器已更新';

  @override
  String get server_added => '伺服器已新增';

  @override
  String get download_model_title => '下載模型';

  @override
  String get download_model_desc => '選擇要下載的模型。\n它將在您的裝置上本機執行。';

  @override
  String get on_device_android_only => '裝置端推論目前僅可在 Android 上使用。';

  @override
  String get total_ram => '總記憶體';

  @override
  String get available => '可用';

  @override
  String ram_min_required(String fileSize) {
    return '最低要求 $fileSize GB 記憶體 (RAM)';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return '預計剩餘時間: $eta';
  }

  @override
  String paused_progress(String percent) {
    return '已暫停 - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return '此模型需要至少 $ram GB 記憶體，但您的裝置僅有 $totalMemory。它可能無法正常執行，或會導致應用程式當機。';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return '您的裝置目前有 $availableRAM 可用記憶體，但此模型推薦至少 $ram GB。載入它可能會失敗或導致系統不穩定。';
  }

  @override
  String get choose_theme => '選擇主題';

  @override
  String get choose_theme_desc => '個人化應用程式外觀。您隨時可以在設定中變更此項。';

  @override
  String get theme_card_system => '系統';

  @override
  String get theme_card_system_sub => '符合您的裝置設定';

  @override
  String get theme_card_light => '淺色';

  @override
  String get theme_card_light_sub => '乾淨明亮';

  @override
  String get theme_card_dark => '深色';

  @override
  String get theme_card_dark_sub => '保護眼睛';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => '溫馨的桃色色調主題';

  @override
  String get stay_updated => '保持更新';

  @override
  String get stay_updated_desc => '在您的 AI 模型下載完成或長時間執行的任務結束時獲得通知。';

  @override
  String get notification_benefit_downloads => '模型下載進度';

  @override
  String get notification_benefit_completions => '生成完成';

  @override
  String get notification_benefit_background => '背景工作狀態';

  @override
  String get allow_notifications => '允許通知';

  @override
  String get servers_title => '伺服器';

  @override
  String get no_servers_yet => '尚無伺服器';

  @override
  String get no_servers_desc => '新增您的首個伺服器以開始與 AI 模型對話。';

  @override
  String get add_server => '新增伺服器';

  @override
  String switched_to_server(String name) {
    return '已切換到 $name';
  }

  @override
  String get edit_server => '編輯伺服器';

  @override
  String get add_server_title => '新增伺服器';

  @override
  String get server_type_label => '伺服器類型';

  @override
  String get server_icon_label => '伺服器圖示';

  @override
  String get default_icon => '預設圖示';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => '相容 OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => '裝置端';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => '本機推論';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => '預設';

  @override
  String get set_as_default => '設為預設';

  @override
  String get select_icon => '選擇圖示';

  @override
  String get select_icon_desc => '為您的伺服器選擇一個圖示';

  @override
  String get search_icons_hint => '搜尋圖示...';

  @override
  String get server_icon_stack => '伺服器堆疊';

  @override
  String get server_icon_stack2 => '伺服器堆疊 02';

  @override
  String get server_icon_stack3 => '伺服器堆疊 03';

  @override
  String get server_icon_cloud => '雲端';

  @override
  String get server_icon_cloud_server => '雲端伺服器';

  @override
  String get server_icon_mcp => 'MCP 伺服器';

  @override
  String get server_icon_database => '資料庫';

  @override
  String get server_icon_database1 => '資料庫 01';

  @override
  String get server_icon_database2 => '資料庫 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => '晶片';

  @override
  String get server_icon_chip2 => '晶片 02';

  @override
  String get server_icon_computer => '電腦';

  @override
  String get server_icon_laptop => '筆記型電腦';

  @override
  String get server_icon_terminal => '終端機';

  @override
  String get server_icon_code => '程式碼';

  @override
  String get server_icon_ai_brain => 'AI 大腦';

  @override
  String get server_icon_ai_brain2 => 'AI 大腦 02';

  @override
  String get server_icon_ai_cloud => 'AI 雲端';

  @override
  String get server_icon_ai_network => 'AI 網路';

  @override
  String get server_icon_ai_chat => 'AI 對話';

  @override
  String get server_icon_cellular => '蜂窩網路';

  @override
  String get server_icon_plug1 => '插頭 01';

  @override
  String get server_icon_plug2 => '插頭 02';

  @override
  String get server_icon_bot => '機器人';

  @override
  String get server_icon_bot2 => '機器人 02';

  @override
  String get server_icon_robotic => '機器人聲音';

  @override
  String get server_icon_rocket => '火箭';

  @override
  String get server_icon_star => 'Star';

  @override
  String get server_icon_settings1 => '設定 01';

  @override
  String get server_icon_settings2 => '設定 02';

  @override
  String get server_icon_home1 => '首頁 01';

  @override
  String get server_icon_home2 => '首頁 02';

  @override
  String get server_icon_folder1 => '資料夾 01';

  @override
  String get server_icon_folder2 => '資料夾 02';

  @override
  String get server_icon_file1 => '檔案 01';

  @override
  String get server_icon_lock => '鎖';

  @override
  String get server_icon_key => '鑰匙 01';

  @override
  String get server_icon_link => '連結 01';

  @override
  String get server_icon_globe => '地球儀';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => '右箭頭 01';

  @override
  String get server_icon_check => '勾選圓圈';

  @override
  String get server_icon_alert => '警報圓圈';

  @override
  String get server_icon_info => '資訊圓圈';

  @override
  String get server_icon_zap => 'Zap';

  @override
  String get server_icon_cloud_upload => '雲端上傳';

  @override
  String get server_icon_cloud_download => '雲端下載';

  @override
  String get server_icon_refresh => '重新整理';

  @override
  String get server_icon_hard_drive => '硬碟';

  @override
  String get server_icon_drive => '磁碟機';

  @override
  String get personas_title => '角色';

  @override
  String get persona_category_general => '通用';

  @override
  String get persona_category_coding => '程式設計';

  @override
  String get persona_category_education => '教育';

  @override
  String get persona_category_creative => '創意';

  @override
  String get persona_builtin_section => '內建';

  @override
  String get persona_my_section => '我的角色';

  @override
  String get clone_edit => '複製並編輯';

  @override
  String get builtin_badge => '內建';

  @override
  String get no_personas_found => '未找到任何角色';

  @override
  String get no_personas_desc => '建立您的第一個角色以定制 AI 行為。';

  @override
  String get edit_persona => '編輯角色';

  @override
  String get create_persona => '建立角色';

  @override
  String get create_persona_button => '建立';

  @override
  String get emoji_label => '表情符號';

  @override
  String get name_label => '名稱';

  @override
  String get my_persona_hint => '我的角色';

  @override
  String get category_label => '分類';

  @override
  String get description_optional => '描述 (選填)';

  @override
  String get description_hint => '此角色要做的是...';

  @override
  String get system_prompt => '系統提示詞';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => '尚無提示詞...';

  @override
  String get prompt_hint => '你是一個得力的助手...';

  @override
  String get prompt_required => '需要系統提示詞';

  @override
  String get prompt_max_chars => '最多 4000 個字元';

  @override
  String get advanced_settings => '進階設定';

  @override
  String get temperature_label => '溫度 (0.0-2.0)';

  @override
  String get top_p_label => 'Top P (0.0-1.0)';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0.9';

  @override
  String get range_0_2 => '0.0-2.0';

  @override
  String get range_0_1 => '0.0-1.0';

  @override
  String get persona_updated => '角色已更新';

  @override
  String get persona_created => '角色已建立';

  @override
  String get tts_models_title => '語音合成模型';

  @override
  String get always_available => '始終可用';

  @override
  String get tts_system_desc => '使用您裝置內建的語音合成引擎。\n無需額外下載。語音選擇依賴您的裝置系統設定。';

  @override
  String get downloading_status => '正在下載...';

  @override
  String tts_kitten_desc(String size) {
    return '擁有 8 種表現力聲音的閃電般高速類神經網路 TTS。\n需要下載 $size。';
  }

  @override
  String tts_piper_desc(String size) {
    return '快速離線 Piper 語音，擁有 2 種極極具表現力的聲音。\n每個聲音需要下載 $size。';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB 記憶體 · $voiceCount 種語音';
  }

  @override
  String get on_device_models_title => '裝置端模型';

  @override
  String get settings_huggingface_token => 'Hugging Face 權杖（選用）';

  @override
  String get settings_huggingface_token_desc =>
      '僅限受限制模型需要（例如 Gemma）。可在 huggingface.co/settings/tokens 取得權杖。';

  @override
  String get settings_huggingface_token_set => '權杖已儲存';

  @override
  String get settings_huggingface_token_cleared => '權杖已清除';

  @override
  String get model_requires_huggingface_token => '需要 Hugging Face 權杖';

  @override
  String get model_missing_huggingface_token =>
      '此模型在 Hugging Face 上受限制。請在「設定 → 裝置端推論」中加入權杖後再下載。';

  @override
  String get set_huggingface_token => '設定權杖';

  @override
  String get clear_huggingface_token => '清除';

  @override
  String get edit_huggingface_token_dialog_title => 'Hugging Face 存取權杖';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc => '本機 AI 引擎。不需要 API 金鑰。';

  @override
  String get server_type_on_device_desc => '在您的手機上執行。某些模型需要 Hugging Face 權杖。';

  @override
  String get server_type_lm_studio_desc => '本機 API 伺服器。不需要 API 金鑰。';

  @override
  String get available_models => '可用模型';

  @override
  String get device_memory => '裝置記憶體';

  @override
  String get ram_usage => '記憶體佔用';

  @override
  String get memory_healthy => '健康';

  @override
  String get memory_critical => '嚴重警告';

  @override
  String get memory_low => '偏低';

  @override
  String ram_used(String percent) {
    return '已使用 $percent%';
  }

  @override
  String get available_ram => '可用記憶體';

  @override
  String get total_capacity => '總容量';

  @override
  String get loaded_status => '已載入';

  @override
  String get inference_backend => '推論後端';

  @override
  String get backend_ios_notice => 'iOS 上僅支援 CPU 後端。';

  @override
  String get backend_cpu_desc => '適用於所有裝置。相容性最好。';

  @override
  String get backend_gpu_desc => 'OpenCL 加速。在支援的裝置上執行更快。';

  @override
  String get backend_npu_desc => '廠商 NPU (高通/聯發科)。最快的推論速度。';

  @override
  String get select_model_title => '選擇模型';

  @override
  String get refresh_models => '重新整理模型';

  @override
  String get search_models_hint => '搜尋模型...';

  @override
  String get no_server_connected => '未連線伺服器';

  @override
  String get add_server_first => '請先新增伺服器以查看可用模型。';

  @override
  String get failed_load_models => '載入模型失敗';

  @override
  String get no_models_available => '無可用模型';

  @override
  String no_models_match(String searchQuery) {
    return '沒有符合 \"$searchQuery\" 的模型';
  }

  @override
  String model_load_failed(String error) {
    return '載入模型失敗: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return '在 keep-alive 時間過去後，$name 將被自動卸載';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name 已成功卸載';
  }

  @override
  String model_unload_failed(String error) {
    return '卸載模型失敗: $error';
  }

  @override
  String get unload_from_server => '從伺服器卸載';

  @override
  String context_chip(String ctx) {
    return '$ctx 上下文 (ctx)';
  }

  @override
  String get unload_all_models => '卸載所有模型';

  @override
  String loaded_models_count(int count) {
    return '已載入 $count 個模型';
  }

  @override
  String get all_models_unloaded => '所有模型已卸載';

  @override
  String get branch_chat => '分支聊天';

  @override
  String get branch_chat_desc => '從此消息開始新建聊天';

  @override
  String get edit_assistant_message_desc => '編輯助手消息的內容';

  @override
  String switch_to_model(String modelName, Object model) {
    return '切換到模型 $model';
  }

  @override
  String download_notification_title(String modelName) {
    return '正在下載 $modelName...';
  }

  @override
  String get download_complete_notification => '下載完成！';

  @override
  String download_complete_body(String modelName) {
    return '$modelName 已成功下載。';
  }

  @override
  String download_failed_notification(String error) {
    return '下載失敗: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return '下載 $modelName 失敗。';
  }

  @override
  String get engine_name_system => '系統 TTS';

  @override
  String get engine_tagline_system => '內建裝置引擎';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => '高速類神經網路 TTS';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => '離線 Piper 語音';

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
  String get voice_lessac => 'Lessac (美音)';

  @override
  String get voice_ryan => 'Ryan (美音)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc => '最小的通用對話模型。回應速度快，記憶體消耗低。';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc => '平衡的品質和大小。適合一般對話。';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc => '推論與思考鏈模型。最適合邏輯任務。';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc => 'Google 旗艦模型。最高品質，需要更多記憶體。';

  @override
  String export_header(String date) {
    return '*匯出自 LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 使用者';

  @override
  String get export_role_assistant => '## 🤖 助理';

  @override
  String get export_role_system => '## ⚙️ 系統';

  @override
  String get export_role_tool => '## 🔧 工具';

  @override
  String get export_text_user => '[使用者]';

  @override
  String get export_text_assistant => '[助理]';

  @override
  String get export_text_system => '[系統]';

  @override
  String get export_text_tool => '[工具]';

  @override
  String get export_label_user => '使用者';

  @override
  String get export_label_assistant => '助理';

  @override
  String get export_label_system => '系統';

  @override
  String get export_label_tool => '工具';

  @override
  String get select_model_hint => '選擇一個模型以開始對話';

  @override
  String get test_notification_title => '測試通知';

  @override
  String get test_notification_body => '這是用於展示模型下載進度的測試通知。';

  @override
  String get tts_supports_background => '支援背景播放（原生音訊格式）';

  @override
  String get tts_other_services_background_note =>
      '注意：其他 TTS 服務支援背景播放（原生音訊格式）。';

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
  String get model_favorite_toggle => '切換收藏';

  @override
  String get model_note_label => '備註';

  @override
  String get model_note_hint => '為此模型添加個人備註...';

  @override
  String get unload_models_before_load => '載入前卸載模型';

  @override
  String get temp_chat_keyboard_incognito => '臨時聊天中的隱私鍵盤';

  @override
  String get temp_chat_keyboard_incognito_desc => '請求系統鍵盤在臨時聊天期間不保存輸入歷史記錄';

  @override
  String get resume_last_chat => '恢復上次聊天';

  @override
  String get resume_last_chat_desc => '啟動時自動打開您上次活躍的對話';

  @override
  String get export_all_data => '匯出所有數據';

  @override
  String get import_all_data => '導入所有數據';

  @override
  String get export_data_success => '數據匯出成功';

  @override
  String get import_data_success => '數據導入成功';

  @override
  String import_data_failed(String error) {
    return '導入數據失敗';
  }

  @override
  String get import_data_confirm => '這將用導入的數據替換您當前的所有數據。是否繼續？';

  @override
  String get import_settings_confirm => '這將用導入的設定替換您當前的設定。是否繼續？';

  @override
  String get export_conversations => '匯出對話';

  @override
  String get import_conversations => '導入對話';

  @override
  String get export_personas => '匯出角色';

  @override
  String get import_personas => '導入角色';

  @override
  String get export_settings => '匯出設定';

  @override
  String get import_settings => '導入設定';

  @override
  String get export_all_zip => '匯出全部 (ZIP)';

  @override
  String get import_all_zip => '導入全部 (ZIP)';

  @override
  String get duplicate_chat => '複製聊天';

  @override
  String get duplicate_chat_success => '聊天複製成功';

  @override
  String get move_to_folder => '移動到資料夾';

  @override
  String get remove_from_folder => '從資料夾中移除';

  @override
  String get create_folder => '創建資料夾';

  @override
  String get new_folder => '新資料夾';

  @override
  String get folder_name_hint => '輸入資料夾名稱...';

  @override
  String get all_chats => '所有聊天';

  @override
  String get unfiled_chats => '未分類聊天';

  @override
  String get create => '創建';

  @override
  String get server_path_prefix_label => '伺服器路徑前綴';

  @override
  String get server_path_prefix_hint => '伺服器 API 路徑的可選前綴 (例如 /v1)';

  @override
  String get search_message_contents => '搜尋消息內容...';

  @override
  String get message_search_results => '消息搜尋結果';

  @override
  String get saved_messages_title => '已保存的消息';

  @override
  String get nav_saved_messages => '保存消息';

  @override
  String get saved_messages_empty => '尚無保存的消息';

  @override
  String get save_message => '保存消息';

  @override
  String get message_saved => '消息已保存';

  @override
  String token_count(int count) {
    return 'Token 數: $count';
  }

  @override
  String estimated_token_count(int count) {
    return '預估 Token 數: $count';
  }

  @override
  String get test_tts_section_title => '文字轉語音測試';

  @override
  String get test_tts_hint => '輸入內容以測試聲音...';

  @override
  String get test_speak_button => '朗讀';

  @override
  String get scroll_to_bottom => '滾動到底部';

  @override
  String get generate_ai_response => '生成 AI 回覆';

  @override
  String get no_response => '無回覆';

  @override
  String get export => '匯出';

  @override
  String get import => '導入';

  @override
  String get conversations_label => '對話';

  @override
  String get personas_label => '角色';

  @override
  String get settings_label => '設定';

  @override
  String get export_conversation => '匯出對話';

  @override
  String get tts_process_markdown => '處理 Markdown';

  @override
  String get tts_process_markdown_desc => '在朗讀前去除 **加粗** 等格式標記';

  @override
  String get tts_skip_seconds => '跳過秒數';

  @override
  String get tts_skip_seconds_desc => '語音播放器中快進/快退的時間';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$seconds秒';
  }

  @override
  String get preview_system_prompts => '預覽系統提示詞';

  @override
  String get welcome_message_1 => '你好！我是您的本地 AI 助手。';

  @override
  String get welcome_message_2 => '問我任何問題——我隨時恭候。';

  @override
  String get welcome_message_3 => '您的數據完全在本地處理，絕不會離開您的設備。';

  @override
  String get welcome_message_4 => '要開始，請從頂部欄中選擇一個模型，或在模型管理部分中添加一個新模型。';

  @override
  String get temporary_chat => '臨時聊天';

  @override
  String get temporary_chat_desc => '此聊天中的消息不會保存到歷史記錄中';

  @override
  String get temporary_chat_banner => '臨時聊天處於活動狀態——消息將不保存到歷史記錄';

  @override
  String get temporary_chat_save_warning_title => '保存臨時聊天？';

  @override
  String get temporary_chat_save_warning_body => '此聊天未保存到您的歷史記錄中。您想現在保存嗎？';

  @override
  String get save_to_history => '保存到歷史記錄';

  @override
  String get share_conversation => '分享對話';

  @override
  String get download_tts_audio => '下載音訊';

  @override
  String get tts_download_unavailable => '音訊下載不可用';

  @override
  String get tts_download_no_audio => '沒有生成的可供下載的音訊';

  @override
  String get tts_download_success => '音訊保存成功';

  @override
  String get return_to_chat => '返回聊天';

  @override
  String get return_to_temp_chat => '返回臨時聊天';

  @override
  String get insert_saved_message => '插入已保存的消息';

  @override
  String get insert_saved_message_desc => '將您已保存的文字片段添加到聊天中';

  @override
  String get model_info => '模型資訊';

  @override
  String get model_name => '模型名稱';

  @override
  String get model_identifier => '模型識別碼';

  @override
  String get not_available => '不可用';

  @override
  String get save_message_folders => '保存到資料夾';

  @override
  String get remove_from_saved => '從已保存中移除';

  @override
  String get message_already_saved => '消息已保存';

  @override
  String get stream_ttft => '首個 Token 延遲';

  @override
  String get stream_tokens_per_sec => '每秒 Token 數';

  @override
  String get stream_stop_reason => '停止原因';

  @override
  String get stream_input_tokens => '輸入 Token 數';

  @override
  String get stream_output_tokens => '輸出 Token 數';

  @override
  String get stream_generation_time => '生成時間';

  @override
  String get attach_image => '附加圖片';

  @override
  String get attach_text_document => '附加文字檔案';

  @override
  String get attach_shortcut_images => '相片';

  @override
  String get attach_shortcut_documents => '檔案';

  @override
  String get attach_shortcut_saved => '已儲存';

  @override
  String get add_attachment => '添加附件';

  @override
  String get add_to_chat => '新增至聊天';

  @override
  String get choose_what_to_attach => '您想新增什麼？';

  @override
  String get choose_attachment_subtitle => '選擇要附加到訊息的來源';

  @override
  String get photo_permission_denied => '相簿權限被拒絕';

  @override
  String get select_model_prompt => '選擇模型';

  @override
  String get characters_label => '字元數';

  @override
  String get exit_temporary_chat_title => '退出臨時聊天？';

  @override
  String get exit_temporary_chat_body => '這將永久刪除當前的對話。是否繼續？';

  @override
  String get saved_message_temp_snap_unavailable => '臨時聊天中不支援消息快照';

  @override
  String get filter_title => '篩選聊天';

  @override
  String get filter_pinned => '已置頂';

  @override
  String get filter_archived => '已封存';

  @override
  String get filter_temp_chats => '臨時聊天';

  @override
  String get filter_user_messages => '用戶消息';

  @override
  String get filter_assistant_messages => '助手消息';

  @override
  String get archive_chat => '封存聊天';

  @override
  String get unarchive_chat => '取消封存';

  @override
  String conversation_message_count(int count) {
    return '$count 條消息';
  }

  @override
  String conversation_character_count(int count) {
    return '$count 個字元';
  }

  @override
  String get generate_title_with_ai => '使用 AI 生成標題';

  @override
  String get generating_title => '正在生成標題...';

  @override
  String get generate_title_failed => '無法生成標題';

  @override
  String get lm_studio_model_browser_title => '模型瀏覽器';

  @override
  String get lm_studio_model_search_hint => '搜尋模型...';

  @override
  String get lm_studio_staff_picks => '編輯精選';

  @override
  String get lm_studio_community_models => '社區模型';

  @override
  String get lm_studio_no_models => '未找到模型';

  @override
  String lm_studio_models_count(int count) {
    return '$count 個模型';
  }

  @override
  String get lm_studio_browse_models => '在 LM Studio 中瀏覽模型';

  @override
  String get lm_studio_model_search => '模型搜尋';

  @override
  String get lm_studio_downloads_title => '下載';

  @override
  String get lm_studio_choose_quant => '選擇量化版本';

  @override
  String get lm_studio_use_default_quant => '使用預設量化版本';

  @override
  String get lm_studio_recommended => '推薦';

  @override
  String get lm_studio_clear_downloads => '清除已完成的下載';

  @override
  String get lm_studio_no_downloads => '無活動中的下載';

  @override
  String get lm_studio_downloads_disclaimer => '模型下載直接從 Hugging Face 獲取。';

  @override
  String get lm_studio_staff_pick => '推薦模型';

  @override
  String get lm_studio_params => '參數';

  @override
  String get lm_studio_arch => '架構';

  @override
  String get lm_studio_domain => '領域';

  @override
  String get lm_studio_format => '格式';

  @override
  String get lm_studio_vision => '視覺能力';

  @override
  String get lm_studio_tool_use => '工具調用';

  @override
  String get lm_studio_reasoning => '推理能力';

  @override
  String get lm_studio_download_options => '下載選項';

  @override
  String get lm_studio_download => '下載';

  @override
  String lm_studio_download_size(String size) {
    return '下載大小';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return '正在下載: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable => '此模型無 README 說明檔案。';

  @override
  String get lm_studio_full_gpu_offload => '支援完全 GPU 卸載';

  @override
  String get lm_studio_partial_gpu_offload => '支援部分 GPU 卸載';

  @override
  String get lm_studio_likely_too_large => '可能過大';

  @override
  String get lm_studio_available_ram_gb => '可用 RAM (GB, 可選)';

  @override
  String get lm_studio_available_vram_gb => '可用 VRAM (GB, 可选)';

  @override
  String get lm_studio_memory_settings_title => '用於推薦的記憶體大小';

  @override
  String get lm_studio_memory_settings_desc => '用於在模型瀏覽器中預估模型是否可以在您的設備上運行。';

  @override
  String get think_button_label => '思考';

  @override
  String get thinking_mode_title => '思考模式';

  @override
  String get reasoning_effort_low => '低';

  @override
  String get reasoning_effort_medium => '中';

  @override
  String get reasoning_effort_high => '高';

  @override
  String get could_not_read_file => '無法讀取檔案';

  @override
  String get server_offline => '伺服器已離線';

  @override
  String get could_not_establish_connection =>
      '無法與伺服器建立連線。請檢查您的伺服器是否正在運行，以及主機/埠設定是否正確。';

  @override
  String get retry_connection => '重試連線';

  @override
  String get tokens_label => 'Token 數';

  @override
  String get enter_context_length => '輸入上下文長度...';

  @override
  String get openrouter_disclosure =>
      '連接此提供者後，您的聊天訊息和輸入將被發送到他們的伺服器。LocalMind 不會追蹤或儲存您的對話。';

  @override
  String get welcome_message_cloud => '您的訊息將發送到您連接的提供者。';

  @override
  String get privacy_policy => '隱私權政策';

  @override
  String get cloud_sync => 'S3 雲端同步';

  @override
  String get cloud_sync_description => '與您自己的 S3 相容伺服器進行端對端加密同步';

  @override
  String get cloud_sync_endpoint => '端點 URL';

  @override
  String get cloud_sync_bucket => '儲存桶';

  @override
  String get cloud_sync_region => '區域';

  @override
  String get cloud_sync_prefix => '前綴';

  @override
  String get cloud_sync_access_key => '存取金鑰 ID';

  @override
  String get cloud_sync_secret_key => '秘密存取金鑰';

  @override
  String get cloud_sync_session_token => '工作階段權杖（選填）';

  @override
  String get cloud_sync_passphrase => '加密密碼片語';

  @override
  String get cloud_sync_confirm_passphrase => '確認密碼片語';

  @override
  String get cloud_sync_path_style => '使用路徑樣式定址';

  @override
  String get cloud_sync_allow_http => '允許不安全的 HTTP';

  @override
  String get cloud_sync_http_warning => 'HTTP 會向網路公開請求資訊與憑證。僅限可信任的本機 S3 伺服器使用。';

  @override
  String get cloud_sync_test => '測試連線';

  @override
  String get cloud_sync_enable => '啟用加密同步';

  @override
  String get cloud_sync_now => '立即同步';

  @override
  String get cloud_sync_disconnect => '中斷此裝置連線';

  @override
  String get cloud_sync_last_synced => '上次同步';

  @override
  String get cloud_sync_never => '從未';

  @override
  String get cloud_sync_conflicts => '已保留衝突';

  @override
  String get cloud_sync_passphrase_mismatch => '密碼片語不相符';

  @override
  String get crash_report_title => '出了點問題';

  @override
  String get crash_report_stack_trace => '堆疊追蹤';

  @override
  String get crash_report_tap_to_expand => '點擊展開';

  @override
  String get crash_report_button => '回報此當機';

  @override
  String get crash_try_again => '重試';

  @override
  String get crash_report_empty_stack => '<空>';

  @override
  String get crash_report_disclaimer =>
      '回報將開啟已預先填入診斷資訊的 GitHub。由您掌控 — 不會自動提交任何內容。請在提交前檢查並移除敏感內容。';

  @override
  String get crash_report_copied => '已複製到剪貼簿';

  @override
  String get report_a_problem => '回報問題';

  @override
  String get rename_folder => '重新命名資料夾';

  @override
  String get delete_folder => '刪除資料夾';

  @override
  String get delete_folder_title => '刪除資料夾？';

  @override
  String delete_folder_body(String name) {
    return '確定要刪除「$name」嗎?其中的對話或已儲存的訊息將移回「未分類」。此操作無法復原。';
  }

  @override
  String get folder_name_required => '請輸入資料夾名稱';

  @override
  String get model_required_toast => '您需要先選擇一個模型';
}
