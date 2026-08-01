// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'Ваш ИИ. Ваше устройство. Ваши правила.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Отмена';

  @override
  String get confirm => 'Подтверждать';

  @override
  String get delete => 'Удалить';

  @override
  String get save => 'Сохранять';

  @override
  String get retry => 'Повторить попытку';

  @override
  String get close => 'Закрывать';

  @override
  String get done => 'Сделанный';

  @override
  String get continue_action => 'Продолжать';

  @override
  String get skip => 'Пропускать';

  @override
  String get install => 'Установить';

  @override
  String get download => 'Скачать';

  @override
  String get resume => 'Продолжить';

  @override
  String get pause => 'Пауза';

  @override
  String get stop => 'Останавливаться';

  @override
  String get edit => 'Редактировать';

  @override
  String get preview => 'Предварительный просмотр';

  @override
  String get unload => 'Разгрузить';

  @override
  String get load => 'Нагрузка';

  @override
  String get rename => 'Переименовать';

  @override
  String get pin => 'Приколоть';

  @override
  String get unpin => 'Открепить';

  @override
  String get share => 'Делиться';

  @override
  String get copy => 'Копировать';

  @override
  String get copied => 'Скопировано!';

  @override
  String get copied_to_clipboard => 'Скопировано в буфер обмена';

  @override
  String get select => 'Выбирать';

  @override
  String get active => 'Активный';

  @override
  String get all => 'Все';

  @override
  String get none => 'Никто';

  @override
  String get none_selected => 'Ничего не выбрано';

  @override
  String get online => 'Онлайн';

  @override
  String get connected => 'Подключено';

  @override
  String get checking => 'Проверка';

  @override
  String get offline => 'Оффлайн';

  @override
  String get error => 'Ошибка';

  @override
  String get unknown_error => 'Неизвестная ошибка';

  @override
  String get not_now => 'Не сейчас';

  @override
  String get enable => 'Давать возможность';

  @override
  String get proceed_anyway => 'Продолжить в любом случае';

  @override
  String get test_connection => 'Тестовое соединение';

  @override
  String get testing => 'Тестирование...';

  @override
  String get connection_successful => 'Подключение успешно!';

  @override
  String get connection_failed =>
      'Соединение не удалось. Проверьте свои настройки.';

  @override
  String get save_continue => 'Сохранить и продолжить';

  @override
  String get save_changes => 'Сохранить изменения';

  @override
  String get finish_setup => 'Завершить настройку';

  @override
  String get start_new_chat => 'Начать новый чат';

  @override
  String get cannot_undo => 'Это действие невозможно отменить.';

  @override
  String get ram_warning => 'Предупреждение об оперативной памяти';

  @override
  String get recommended => 'РЕКОМЕНДУЕТСЯ';

  @override
  String get may_be_large => 'Может быть слишком большим для этого устройства';

  @override
  String get calculating => 'Расчет...';

  @override
  String get download_failed => 'Загрузка не удалась';

  @override
  String get downloaded => 'Скачано';

  @override
  String get not_downloaded => 'Не загружено';

  @override
  String get installed => 'Установлено';

  @override
  String get not_installed => 'Не установлено';

  @override
  String get loading => 'Загрузка...';

  @override
  String get thinking => 'мышление';

  @override
  String get processing => 'Обработка...';

  @override
  String get initializing => 'Инициализация...';

  @override
  String get ready => 'Готовый';

  @override
  String get preparing_app => 'Подготовка приложения...';

  @override
  String get initializing_services => 'Инициализация служб...';

  @override
  String get configuring_server => 'Настройка сервера...';

  @override
  String get startup_failed => 'Запуск не удался';

  @override
  String get something_went_wrong => 'Что-то пошло не так';

  @override
  String get delete_model_title => 'Удалить модель';

  @override
  String delete_model_body(String name) {
    return 'Вы уверены, что хотите удалить $name?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Вы уверены, что хотите удалить $name? Это освободит примерно $size места.\n\nПри необходимости вы сможете загрузить эту модель позже.';
  }

  @override
  String get delete_voice_title => 'Удалить голос';

  @override
  String delete_voice_body(String name, String size) {
    return 'Вы уверены, что хотите удалить $name? Это освободит примерно $size места.\n\nПри необходимости вы сможете скачать этот голос позже.';
  }

  @override
  String get delete_server_title => 'Удалить сервер';

  @override
  String delete_server_body(String name) {
    return 'Вы уверены, что хотите удалить \"$name\"? Это невозможно отменить.';
  }

  @override
  String get delete_conversation_title => 'Удалить разговор?';

  @override
  String delete_conversation_body(String title) {
    return 'Вы уверены, что хотите удалить \"$title\"? Это невозможно отменить.';
  }

  @override
  String get delete_message_title => 'Удалить сообщение?';

  @override
  String delete_persona_title(String name) {
    return 'Удалить \"$name\"?';
  }

  @override
  String get delete_persona_body => 'Это невозможно отменить.';

  @override
  String get delete_builtin_persona_body =>
      'Это встроенный персонаж. Вы можете восстановить его позже в Настройках.';

  @override
  String get restore_builtin_personas => 'Восстановить стандартных персонажей';

  @override
  String get restore_builtin_personas_desc =>
      'Заново добавить всех удаленных встроенных персонажей';

  @override
  String get restore_builtin_personas_success =>
      'Персонажи по умолчанию восстановлены';

  @override
  String get clear_personas => 'Сбросить персонажей';

  @override
  String get enable_image_compression => 'Сжимать изображения перед отправкой';

  @override
  String get enable_image_compression_desc =>
      'Изменять размер и сжимать прикрепленные изображения, чтобы размер загрузки оставался в пределах лимитов сервера';

  @override
  String get image_compression_level => 'Агрессивность сжатия';

  @override
  String get image_compression_level_desc =>
      'Более высокая агрессивность дает файлы меньшего размера при более низком качестве';

  @override
  String get image_compression_level_low => 'Низкая';

  @override
  String get image_compression_level_medium => 'Средняя';

  @override
  String get image_compression_level_high => 'Высокая';

  @override
  String get sort_models_tooltip => 'Сортировка моделей';

  @override
  String get sort_by_favorites => 'Сначала избранные';

  @override
  String get sort_by_name => 'По имени (А-Я)';

  @override
  String get sort_by_size_smallest => 'Размер (сначала меньшие)';

  @override
  String get sort_by_size_largest => 'Размер (сначала большие)';

  @override
  String get sort_by_context_length => 'Длина контекста';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Переименование $done/$total...';
  }

  @override
  String selected_count(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get ai_rename_tooltip => 'Переименовать выбранные с помощью ИИ';

  @override
  String get new_chat_in_folder_tooltip => 'Новый чат в этой папке';

  @override
  String total_tokens_count(int count) {
    return 'Токенов: $count';
  }

  @override
  String get smart_replies_use_persona =>
      'Использовать персонаж в умных ответах';

  @override
  String get smart_replies_use_persona_desc =>
      'Предлагаемые ответы будут соответствовать тону активного персонажа, а не общего ассистента';

  @override
  String get keep_persona_on_new_chat => 'Сохранять персонаж при новом чате';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Не сбрасывать выбранных персонажей при создании нового чата';

  @override
  String get role_swap_button_enabled => 'Показывать кнопку смены ролей';

  @override
  String get role_swap_button_enabled_desc =>
      'Показывать кнопку в поле ввода чата для отправки сообщения от лица ассистента, а не пользователя (без генерации ответа)';

  @override
  String get send_as_user_tooltip => 'Отправить от пользователя';

  @override
  String get send_as_assistant_tooltip =>
      'Отправить от ассистента (без ответа)';

  @override
  String get insert_without_generating_tooltip => 'Вставить без генерации';

  @override
  String get token_usage_title => 'Использование токенов';

  @override
  String get total_tokens_label => 'Использовано токенов';

  @override
  String get usage_percent_label => 'Использовано контекста';

  @override
  String get export_choice_title => 'Экспорт';

  @override
  String get export_choice_body => 'Как вы хотите это экспортировать?';

  @override
  String get copy_to_clipboard => 'Копировать в буфер обмена';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Экспортировано чатов: $count';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Переименовать с помощью ИИ?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'ИИ сгенерирует новые заголовки для $count выбранных чатов, заменив текущие. Это может занять некоторое время и действие нельзя отменить.';
  }

  @override
  String get sort_by_modified_date => 'Последнее изменение';

  @override
  String get sort_by_created_date => 'Дата создания';

  @override
  String get sort_title => 'Сортировка';

  @override
  String get clear_conversation_title => 'Ясный разговор?';

  @override
  String get clear_conversation_body =>
      'Это приведет к удалению всех сообщений в этом разговоре.';

  @override
  String get clear => 'Прозрачный';

  @override
  String label_completed(String label) {
    return '$label завершено';
  }

  @override
  String error_with_message(String error) {
    return 'Ошибка: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Не удалось выполнить предварительный просмотр: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Загрузка $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Модель загружена: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Ни одна модель не загружена. Нажмите «Управление моделями на устройстве», чтобы скачать и загрузить модель.';

  @override
  String loading_model_error(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get delete_conversation => 'Удалить разговор?';

  @override
  String get nav_history => 'История';

  @override
  String get nav_servers => 'Серверы';

  @override
  String get nav_local_models => 'Локальные модели';

  @override
  String get nav_tts => 'Текст в речь';

  @override
  String get nav_personas => 'Персоны';

  @override
  String get nav_settings => 'Настройки';

  @override
  String get nav_new_chat => 'Новый чат';

  @override
  String get search_hint => 'Поиск разговоров...';

  @override
  String get no_server_selected => 'Сервер не выбран';

  @override
  String get switch_server => 'Переключить сервер';

  @override
  String get switch_server_subtitle => 'Выберите сервер для подключения';

  @override
  String get manage_servers => 'Управление серверами';

  @override
  String get open_source => 'Открытый исходный код';

  @override
  String get open_source_desc =>
      'LocalMind имеет открытый исходный код. Следите за нашим прогрессом или вносите свой вклад на GitHub.';

  @override
  String get star_on_github => 'Звезда на GitHub';

  @override
  String get add_more => 'Добавить еще';

  @override
  String get on_github => 'на GitHub';

  @override
  String get could_not_open_github => 'Не удалось открыть GitHub.';

  @override
  String get settings_title => 'Настройки';

  @override
  String get settings_appearance => 'Появление';

  @override
  String get settings_language => 'Язык';

  @override
  String get language_system_default => 'Системные настройки по умолчанию';

  @override
  String get settings_tts => 'Преобразование текста в речь';

  @override
  String get settings_behavior => 'Поведение';

  @override
  String get settings_on_device => 'Вывод на устройстве';

  @override
  String get settings_default_server => 'Сервер по умолчанию';

  @override
  String get settings_default_persona => 'Персона по умолчанию';

  @override
  String get settings_privacy => 'Конфиденциальность';

  @override
  String get settings_data_management => 'Управление данными';

  @override
  String get settings_about => 'О';

  @override
  String get theme => 'Тема';

  @override
  String get theme_system => 'Система';

  @override
  String get theme_light => 'Свет';

  @override
  String get theme_dark => 'Темный';

  @override
  String get theme_claude => 'Клод';

  @override
  String get font_size => 'Размер шрифта';

  @override
  String get font_size_desc => 'Настройте размер текста в чате.';

  @override
  String get font_preview =>
      'Быстрая бурая лиса перепрыгивает через ленивую собаку.';

  @override
  String get code_theme_dark => 'Кодовая тема (темная)';

  @override
  String get code_theme_light => 'Тема кода (светлая)';

  @override
  String get code_theme_desc =>
      'Выберите тему подсветки синтаксиса для блоков кода.';

  @override
  String get tts_engine => 'Двигатель ТТС';

  @override
  String get tts_engine_system => 'Система ТТС';

  @override
  String get tts_engine_kitten => 'Котенок ТТС';

  @override
  String get voice => 'Голос';

  @override
  String get voice_female => 'Женский';

  @override
  String get voice_male => 'Мужской';

  @override
  String get voice_other => 'Другой';

  @override
  String get tts_speed => 'Скорость TTS';

  @override
  String get tts_speed_desc => 'Отрегулируйте скорость воспроизведения.';

  @override
  String get manage_tts_models => 'Управление моделями TTS';

  @override
  String get manage_on_device_models => 'Управление моделями на устройстве';

  @override
  String get enable_smart_reply => 'Умные ответы на устройстве';

  @override
  String get ai_user_response_enabled =>
      'Сообщение пользователя через ИИ (зажать кнопку)';

  @override
  String get ai_user_response_enabled_desc =>
      'Зажмите кнопку отправки на 3 секунды, чтобы ИИ написал и отправил следующее сообщение за вас';

  @override
  String get ai_user_response_tooltip =>
      'Сгенерировать сообщение пользователя с помощью ИИ';

  @override
  String get streaming_responses => 'Потоковая передача ответов';

  @override
  String get auto_generate_titles => 'Автоматическое создание заголовков';

  @override
  String get send_on_enter => 'Отправить при вводе';

  @override
  String get show_system_messages => 'Показать системные сообщения';

  @override
  String get show_system_messages_desc =>
      'Если персонаж не выбран, отправлять стандартный системный промпт ассистента с каждым запросом';

  @override
  String get show_system_messages_in_chat =>
      'Показывать системные сообщения в чате';

  @override
  String get show_system_messages_in_chat_desc =>
      'Отображать системные сообщения (например, из импортированной резервной копии) в виде облачков сообщений в чате';

  @override
  String get haptic_feedback => 'Тактильная обратная связь';

  @override
  String get enable_mcp => 'Включить MCP';

  @override
  String get new_chat_mcp_default => 'Новый чат MCP по умолчанию';

  @override
  String get show_data_indicator => 'Показать индикатор данных';

  @override
  String get privacy_info => '«LocalMind никогда не видит ваши данные»';

  @override
  String get delete_all_conversations => 'Удалить все разговоры';

  @override
  String get reset_settings_defaults =>
      'Сброс настроек к значениям по умолчанию';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Параметры чата';

  @override
  String get change_persona => 'Изменить личность';

  @override
  String get set_persona => 'Установить Персону';

  @override
  String get remove_persona => 'Удалить персону';

  @override
  String get clear_conversation => 'Чистый разговор';

  @override
  String get connection_error => 'Ошибка подключения. Проверьте свой сервер.';

  @override
  String get disconnected => 'Отключился от сервера.';

  @override
  String get configure => 'Настроить';

  @override
  String get select_model => 'Выберите модель';

  @override
  String get select_persona => 'Выберите Персону';

  @override
  String get manage_personas => 'Управление персонажами';

  @override
  String get personas_combine_hint => 'Выбранные персонажи будут объединены';

  @override
  String get start_conversation => 'Начать разговор';

  @override
  String get recent_chats => 'Недавние чаты';

  @override
  String get see_all => 'Посмотреть все';

  @override
  String get quick_write => 'Помогите мне написать функцию';

  @override
  String get quick_explain => 'Объясните этот код';

  @override
  String get quick_debug => 'Отладьте это для меня';

  @override
  String get quick_async => 'Как использовать async/await?';

  @override
  String get history_missing_title => 'История отсутствует';

  @override
  String get history_missing_desc =>
      'Либо сообщения в этом чате были удалены, либо запись истории повреждена.';

  @override
  String get technical_details => 'Технические детали';

  @override
  String get last_error => 'Последняя ошибка:';

  @override
  String get copy_info => 'Копировать информацию';

  @override
  String get conversation_id => 'Идентификатор беседы';

  @override
  String get created_at => 'Создано в';

  @override
  String get expected_messages => 'Ожидаемые сообщения';

  @override
  String get debug_dialog_desc =>
      'Диагностическая информация, помогающая выявить проблемы синхронизации.';

  @override
  String get chat_input_hint => 'Спроси что-нибудь';

  @override
  String get send_message_tooltip => 'Отправить сообщение';

  @override
  String get stop_generation_tooltip => 'Остановить генерацию';

  @override
  String get attach_images_tooltip => 'Прикрепите изображения или текст';

  @override
  String get start_listening_tooltip => 'Начать слушать';

  @override
  String get stop_listening_tooltip => 'Хватит слушать';

  @override
  String tool_label(String toolCallId) {
    return 'Инструмент: $toolCallId';
  }

  @override
  String get tool_unknown => 'Инструмент: Неизвестно';

  @override
  String get message_options => 'Параметры сообщения';

  @override
  String get copy_markdown => 'Скопировать как Markdown';

  @override
  String get copied_markdown => 'Скопировано как Markdown';

  @override
  String get read_aloud => 'Читать вслух';

  @override
  String get stop_reading => 'Хватит читать';

  @override
  String get more => 'Более';

  @override
  String character_count(int length) {
    return '$length символов';
  }

  @override
  String get edit_message => 'Редактировать сообщение';

  @override
  String get edit_message_desc =>
      'При сохранении ответ помощника ниже будет удален и восстановлен.';

  @override
  String get save_regenerate => 'Сохранить и восстановить';

  @override
  String get chat_settings_title => 'Настройки чата';

  @override
  String get reset_defaults => 'Сбросить настройки по умолчанию';

  @override
  String get parameters_tab => 'Параметры';

  @override
  String get mcp_tab => 'МКП';

  @override
  String get temperature => 'Температура';

  @override
  String get temperature_desc =>
      'Управляет случайностью: выше = креативно, ниже = сосредоточено.';

  @override
  String get top_p => 'Топ П';

  @override
  String get top_p_desc => 'Порог выборки ядра';

  @override
  String get max_tokens => 'Макс. жетонов';

  @override
  String get max_tokens_desc => 'Предел ответа';

  @override
  String get context_length => 'Длина контекста';

  @override
  String get context_length_desc => 'Окно истории';

  @override
  String get mcp_disabled_warning =>
      'MCP отключен глобально. Включите его в настройках, чтобы использовать эти функции.';

  @override
  String get mcp_enable_chat => 'Включите MCP для этого чата';

  @override
  String get auto_execute_tools => 'Инструменты автоматического выполнения';

  @override
  String get beta_label => 'Бета';

  @override
  String get experimental_label => 'Экспериментальный';

  @override
  String get add_ephemeral_mcp => 'Добавить эфемерный сервер MCP';

  @override
  String get mcp_label_placeholder => 'Этикетка';

  @override
  String get mcp_url_placeholder => 'URL-адрес (https://...)';

  @override
  String get active_integrations => 'Активная интеграция';

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
  String get enable_notifications => 'Включить уведомления';

  @override
  String get enable_notifications_desc =>
      'Получайте уведомления, когда модели завершают загрузку.';

  @override
  String get chat_history_title => 'История чата';

  @override
  String get conversation_just_now => 'Прямо сейчас';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes мин назад';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hoursч назад';
  }

  @override
  String get conversation_yesterday => 'Вчера';

  @override
  String conversation_days_ago(int days) {
    return '$daysд назад';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => 'Параметры';

  @override
  String get no_results_found => 'Результаты не найдены';

  @override
  String get no_conversations_yet => 'Пока нет разговоров';

  @override
  String get try_different_search => 'Попробуйте другой поисковый запрос';

  @override
  String get start_new_conversation => 'Начать новый разговор';

  @override
  String get rename_conversation => 'Переименовать беседу';

  @override
  String get enter_new_title => 'Введите новое название';

  @override
  String get pinned_section => 'ПРИКРЕПЛЕНО';

  @override
  String get today_section => 'СЕГОДНЯ';

  @override
  String get yesterday_section => 'ВЧЕРА';

  @override
  String get previous_7_days => 'ПРЕДЫДУЩИЕ 7 ДНЕЙ';

  @override
  String get previous_30_days => 'ПРЕДЫДУЩИЕ 30 ДНЕЙ';

  @override
  String get older_section => 'СТАРШЕ';

  @override
  String get onboarding_choose_language => 'Выберите язык';

  @override
  String get onboarding_choose_language_desc =>
      'Выберите предпочитаемый язык. Вы можете изменить это в любое время в настройках.';

  @override
  String get onboarding_localmind => 'МЕСТНЫЙ РАЗУМ';

  @override
  String get onboarding_connect_server => 'Подключите свой\nСервер';

  @override
  String get onboarding_connect_desc =>
      'Подключитесь к LM Studio, Ollama или\nOpenRouter для запуска вашего частного ИИ\nопыт.';

  @override
  String get openai_compatible_api => 'OpenAI-совместимый API';

  @override
  String get https_requires_ssl => 'HTTPS требует SSL';

  @override
  String get most_local_setups_use_http =>
      'Большинство локальных установок используют http://';

  @override
  String get onboarding_welcome => 'Добро пожаловать в LocalMind';

  @override
  String get server_type_on_device => 'На устройстве';

  @override
  String get server_type_lm_studio => 'ЛМ Студия';

  @override
  String get server_type_ollama => 'Оллама';

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
  String get server_type_openrouter_sub => 'ЕДИНОЕ ОБЛАКО';

  @override
  String get ready_continue => 'ГОТОВЫ ПРОДОЛЖИТЬ';

  @override
  String get waiting_selection => 'ОЖИДАНИЕ ВЫБОРА';

  @override
  String get setup_connection => 'Настройка соединения';

  @override
  String setup_connection_desc(String server) {
    return 'Настройте свой сервер $server, чтобы начать общение.';
  }

  @override
  String get server_name => 'Имя сервера';

  @override
  String get name_required => 'Требуется имя';

  @override
  String get name_max_50 => 'Макс. 50 символов.';

  @override
  String get host_label => 'Хост/IP-адрес';

  @override
  String get host_required => 'Требуется хост';

  @override
  String get port_label => 'Порт';

  @override
  String get port_required => 'Требуется порт';

  @override
  String get port_invalid => 'Должно быть число';

  @override
  String get port_range => 'Введите действительный порт (1-65535).';

  @override
  String get api_key_required => 'API-ключ *';

  @override
  String get api_key_optional => 'Ключ API (необязательно)';

  @override
  String get api_key_required_openrouter =>
      'Ключ API, необходимый для OpenRouter';

  @override
  String get api_key_format => 'Ключи API OpenRouter начинаются с sk-';

  @override
  String get my_server_hint => 'Мой сервер';

  @override
  String get name_length_validation =>
      'Имя должно содержать не более 50 символов.';

  @override
  String get host_valid => 'Введите действительное имя хоста или IP-адрес.';

  @override
  String get api_key_hint_openrouter => 'ск-...';

  @override
  String get api_key_hint_generic => 'Для аутентифицированных серверов';

  @override
  String get update_server => 'Обновление сервера';

  @override
  String get save_server => 'Сохранить сервер';

  @override
  String get server_updated => 'Сервер обновлен';

  @override
  String get server_added => 'Сервер добавлен';

  @override
  String get download_model_title => 'Скачать модель';

  @override
  String get download_model_desc =>
      'Выберите модель для загрузки.\nОн будет работать локально на вашем устройстве.';

  @override
  String get on_device_android_only =>
      'Вывод на устройстве в настоящее время доступен только на Android.';

  @override
  String get total_ram => 'Общий объем оперативной памяти';

  @override
  String get available => 'Доступный';

  @override
  String ram_min_required(String fileSize) {
    return '$fileSize ГБ ОЗУ мин.';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Оставшееся время: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'Приостановлено – $percent %';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Для этой модели требуется не менее $ram ГБ ОЗУ, но на вашем устройстве имеется $totalMemory. Оно может работать неправильно или привести к сбою приложения.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'На вашем устройстве доступно ОЗУ $availableRAM, но для этой модели рекомендуется не менее $ram ГБ. Загрузка может привести к сбою или вызвать нестабильность.';
  }

  @override
  String get choose_theme => 'Выбрать тему';

  @override
  String get choose_theme_desc =>
      'Персонализируйте внешний вид приложения. Вы всегда можете изменить это позже в настройках.';

  @override
  String get theme_card_system => 'Система';

  @override
  String get theme_card_system_sub =>
      'Соответствует настройкам вашего устройства';

  @override
  String get theme_card_light => 'Свет';

  @override
  String get theme_card_light_sub => 'Чистый и светлый';

  @override
  String get theme_card_dark => 'Темный';

  @override
  String get theme_card_dark_sub => 'Легко для глаз';

  @override
  String get theme_card_claude => 'Клод';

  @override
  String get theme_card_claude_sub => 'Теплая тема персикового оттенка.';

  @override
  String get stay_updated => 'Оставайтесь в курсе';

  @override
  String get stay_updated_desc =>
      'Получайте уведомления, когда ваши модели ИИ завершают загрузку или завершаются длительные задачи.';

  @override
  String get notification_benefit_downloads => 'Ход загрузки модели';

  @override
  String get notification_benefit_completions => 'Завершения генерации';

  @override
  String get notification_benefit_background => 'Статус фоновых задач';

  @override
  String get allow_notifications => 'Разрешить уведомления';

  @override
  String get servers_title => 'Серверы';

  @override
  String get no_servers_yet => 'Серверов пока нет';

  @override
  String get no_servers_desc =>
      'Добавьте свой первый сервер, чтобы начать общаться с моделями ИИ.';

  @override
  String get add_server => 'Добавить сервер';

  @override
  String switched_to_server(String name) {
    return 'Переключено на $name';
  }

  @override
  String get edit_server => 'Редактировать сервер';

  @override
  String get add_server_title => 'Добавить сервер';

  @override
  String get server_type_label => 'Тип сервера';

  @override
  String get server_icon_label => 'Значок сервера';

  @override
  String get default_icon => 'Значок по умолчанию';

  @override
  String get server_type_lm_studio_display => 'ЛМ Студия';

  @override
  String get server_type_openai_display => 'Совместимость с OpenAI';

  @override
  String get server_type_ollama_display => 'Оллама';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'На устройстве';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'Локальный вывод';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'По умолчанию';

  @override
  String get set_as_default => 'Установить по умолчанию';

  @override
  String get select_icon => 'Выберите значок';

  @override
  String get select_icon_desc => 'Выберите значок для своего сервера';

  @override
  String get search_icons_hint => 'Иконки поиска...';

  @override
  String get server_icon_stack => 'Серверный стек';

  @override
  String get server_icon_stack2 => 'Серверный стек 02';

  @override
  String get server_icon_stack3 => 'Серверный стек 03';

  @override
  String get server_icon_cloud => 'Облако';

  @override
  String get server_icon_cloud_server => 'Облачный сервер';

  @override
  String get server_icon_mcp => 'MCP-сервер';

  @override
  String get server_icon_database => 'База данных';

  @override
  String get server_icon_database1 => 'База данных 01';

  @override
  String get server_icon_database2 => 'База данных 02';

  @override
  String get server_icon_cpu => 'Процессор';

  @override
  String get server_icon_chip => 'Чип';

  @override
  String get server_icon_chip2 => 'Чип 02';

  @override
  String get server_icon_computer => 'Компьютер';

  @override
  String get server_icon_laptop => 'Ноутбук';

  @override
  String get server_icon_terminal => 'Компьютерный терминал';

  @override
  String get server_icon_code => 'Код';

  @override
  String get server_icon_ai_brain => 'ИИ Мозг';

  @override
  String get server_icon_ai_brain2 => 'ИИ Мозг 02';

  @override
  String get server_icon_ai_cloud => 'Облако ИИ';

  @override
  String get server_icon_ai_network => 'Сеть искусственного интеллекта';

  @override
  String get server_icon_ai_chat => 'AI-чат';

  @override
  String get server_icon_cellular => 'Сотовая сеть';

  @override
  String get server_icon_plug1 => 'Вилка 01';

  @override
  String get server_icon_plug2 => 'Вилка 02';

  @override
  String get server_icon_bot => 'Бот';

  @override
  String get server_icon_bot2 => 'Бот 02';

  @override
  String get server_icon_robotic => 'Роботизированный';

  @override
  String get server_icon_rocket => 'Ракета';

  @override
  String get server_icon_star => 'Звезда';

  @override
  String get server_icon_settings1 => 'Настройки 01';

  @override
  String get server_icon_settings2 => 'Настройки 02';

  @override
  String get server_icon_home1 => 'Дом 01';

  @override
  String get server_icon_home2 => 'Дом 02';

  @override
  String get server_icon_folder1 => 'Папка 01';

  @override
  String get server_icon_folder2 => 'Папка 02';

  @override
  String get server_icon_file1 => 'Файл 01';

  @override
  String get server_icon_lock => 'Замок';

  @override
  String get server_icon_key => 'Ключ 01';

  @override
  String get server_icon_link => 'Ссылка 01';

  @override
  String get server_icon_globe => 'Глобус';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Стрелка вправо 01';

  @override
  String get server_icon_check => 'Проверить круг';

  @override
  String get server_icon_alert => 'Круг оповещения';

  @override
  String get server_icon_info => 'Информационный круг';

  @override
  String get server_icon_zap => 'Зап';

  @override
  String get server_icon_cloud_upload => 'Загрузка в облако';

  @override
  String get server_icon_cloud_download => 'Облачная загрузка';

  @override
  String get server_icon_refresh => 'Обновить';

  @override
  String get server_icon_hard_drive => 'Жесткий диск';

  @override
  String get server_icon_drive => 'Водить машину';

  @override
  String get personas_title => 'Персоны';

  @override
  String get persona_category_general => 'Общий';

  @override
  String get persona_category_coding => 'Кодирование';

  @override
  String get persona_category_education => 'Образование';

  @override
  String get persona_category_creative => 'Креатив';

  @override
  String get persona_builtin_section => 'ВСТРОЕННЫЙ';

  @override
  String get persona_my_section => 'МОИ ПЕРСОНАЛЫ';

  @override
  String get clone_edit => 'Клонировать и редактировать';

  @override
  String get builtin_badge => 'Встроенный';

  @override
  String get no_personas_found => 'Персоны не найдены';

  @override
  String get no_personas_desc =>
      'Создайте свою первую личность, чтобы настроить поведение ИИ.';

  @override
  String get edit_persona => 'Изменить личность';

  @override
  String get create_persona => 'Создать Персону';

  @override
  String get create_persona_button => 'Создавать';

  @override
  String get emoji_label => 'Эмодзи';

  @override
  String get name_label => 'Имя';

  @override
  String get my_persona_hint => 'Моя Персона';

  @override
  String get category_label => 'Категория';

  @override
  String get description_optional => 'Описание (необязательно)';

  @override
  String get description_hint => 'Что делает эта личность...';

  @override
  String get system_prompt => 'Системная подсказка';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Пока нет подсказки...';

  @override
  String get prompt_hint => 'Вы полезный помощник...';

  @override
  String get prompt_required => 'Требуется системное приглашение';

  @override
  String get prompt_max_chars => 'Макс. 4000 символов.';

  @override
  String get advanced_settings => 'Расширенные настройки';

  @override
  String get temperature_label => 'Температура (0,0-2,0)';

  @override
  String get top_p_label => 'Топ П (0,0-1,0)';

  @override
  String get temp_hint => '0,7';

  @override
  String get top_p_hint => '0,9';

  @override
  String get range_0_2 => '0,0-2,0';

  @override
  String get range_0_1 => '0,0-1,0';

  @override
  String get persona_updated => 'Персона обновлена';

  @override
  String get persona_created => 'Персона создана';

  @override
  String get tts_models_title => 'Модели преобразования текста в речь';

  @override
  String get always_available => 'Всегда доступен';

  @override
  String get tts_system_desc =>
      'Использует встроенный в ваше устройство механизм преобразования текста в речь.\nНикаких загрузок не требуется. Выбор голоса использует системные настройки вашего устройства.';

  @override
  String get downloading_status => 'Загрузка...';

  @override
  String tts_kitten_desc(String size) {
    return 'Молниеносный нейронный TTS с 8 выразительными голосами.\nТребуется загрузка $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Быстрые офлайн-голоса Пайпер с двумя выразительными голосами.\nТребуется загрузка $size на голос.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb МБ · $ramMb МБ ОЗУ · $voiceCount голосов';
  }

  @override
  String get on_device_models_title => 'Модели на устройстве';

  @override
  String get settings_huggingface_token =>
      'Жетон «Обнимающее лицо» (необязательно)';

  @override
  String get settings_huggingface_token_desc =>
      'Требуется только для закрытых моделей (например, Gemma). Получите токен на сайтеhuggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Токен сохранен.';

  @override
  String get settings_huggingface_token_cleared => 'Токен очищен';

  @override
  String get model_requires_huggingface_token =>
      'Требуется жетон «Обнимающее лицо».';

  @override
  String get model_missing_huggingface_token =>
      'Данная модель изготовлена ​​на Hugging Face. Добавьте токен в «Настройки» → «Вывод на устройстве», чтобы загрузить его.';

  @override
  String get set_huggingface_token => 'Установить токен';

  @override
  String get clear_huggingface_token => 'Прозрачный';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Токен доступа «Обнимающее лицо»';

  @override
  String get huggingface_token_dialog_hint => 'хф_…';

  @override
  String get server_type_ollama_desc =>
      'Локальный ИИ-движок. Ключ API не требуется.';

  @override
  String get server_type_on_device_desc =>
      'Работает на вашем телефоне. Некоторым моделям нужен жетон «Обнимающее лицо».';

  @override
  String get server_type_lm_studio_desc =>
      'Локальный API-сервер. Ключ API не требуется.';

  @override
  String get available_models => 'Доступные модели';

  @override
  String get device_memory => 'Память устройства';

  @override
  String get ram_usage => 'Использование оперативной памяти';

  @override
  String get memory_healthy => 'Здоровый';

  @override
  String get memory_critical => 'Критический';

  @override
  String get memory_low => 'Низкий';

  @override
  String ram_used(String percent) {
    return '$percent % использовано';
  }

  @override
  String get available_ram => 'Доступная оперативная память';

  @override
  String get total_capacity => 'Общая емкость';

  @override
  String get loaded_status => 'Загружено';

  @override
  String get inference_backend => 'Серверная часть вывода';

  @override
  String get backend_ios_notice => 'В iOS доступен только серверный процессор.';

  @override
  String get backend_cpu_desc =>
      'Работает на всех устройствах. Наиболее совместим.';

  @override
  String get backend_gpu_desc =>
      'Ускорение OpenCL. Быстрее на поддерживаемых устройствах.';

  @override
  String get backend_npu_desc =>
      'Поставщик НПУ (Qualcomm/MediaTek). Самый быстрый вывод.';

  @override
  String get select_model_title => 'Выберите модель';

  @override
  String get refresh_models => 'Обновить модели';

  @override
  String get search_models_hint => 'Поиск моделей...';

  @override
  String get no_server_connected => 'Сервер не подключен';

  @override
  String get add_server_first =>
      'Сначала добавьте сервер, чтобы увидеть доступные модели.';

  @override
  String get failed_load_models => 'Не удалось загрузить модели.';

  @override
  String get no_models_available => 'Нет доступных моделей';

  @override
  String no_models_match(String searchQuery) {
    return 'Нет моделей, соответствующих запросу \"$searchQuery\".';
  }

  @override
  String model_load_failed(String error) {
    return 'Не удалось загрузить модель: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'Выгрузка запрошена для $name. Если Оллама доступен, модель выпускается немедленно.';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name успешно выгружено';
  }

  @override
  String model_unload_failed(String error) {
    return 'Не удалось выгрузить модель: $error';
  }

  @override
  String get unload_from_server => 'Выгрузить с сервера';

  @override
  String context_chip(String ctx) {
    return '$ctx ctx';
  }

  @override
  String get unload_all_models => 'Выгрузить все модели';

  @override
  String loaded_models_count(int count) {
    return 'Загружено моделей: $count';
  }

  @override
  String get all_models_unloaded => 'Все модели выгружены';

  @override
  String get branch_chat => 'Создать ветку чата';

  @override
  String get branch_chat_desc => 'Создать новый чат на основе этого сообщения';

  @override
  String get edit_assistant_message_desc =>
      'Редактировать текст сообщения ассистента';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Переключить на модель $model';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Загрузка $modelName...';
  }

  @override
  String get download_complete_notification => 'Загрузка завершена!';

  @override
  String download_complete_body(String modelName) {
    return 'Модель $modelName успешно загружена.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Загрузка не удалась: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Не удалось загрузить $modelName.';
  }

  @override
  String get engine_name_system => 'Система ТТС';

  @override
  String get engine_tagline_system => 'Встроенный движок устройства';

  @override
  String get engine_name_kitten => 'Котенок ТТС';

  @override
  String get engine_tagline_kitten => 'Высокоскоростная нейронная TTS';

  @override
  String get engine_name_sherpa => 'Шерпа ОННКС ВИТС';

  @override
  String get engine_tagline_sherpa => 'Оффлайн голоса Пайпер';

  @override
  String get voice_jasper => 'Джаспер';

  @override
  String get voice_bella => 'Белла';

  @override
  String get voice_bruno => 'Бруно';

  @override
  String get voice_luna => 'Луна';

  @override
  String get voice_hugo => 'Хьюго';

  @override
  String get voice_rosie => 'Рози';

  @override
  String get voice_leo => 'Лео';

  @override
  String get voice_kiki => 'Кики';

  @override
  String get voice_lessac => 'Лессак (США)';

  @override
  String get voice_ryan => 'Райан (США)';

  @override
  String get model_qwen_3 => 'Квен 3 0.6Б';

  @override
  String get model_qwen_3_desc =>
      'Самая маленькая модель чата общего назначения. Быстрые ответы, низкое использование памяти.';

  @override
  String get model_license_apache => 'Апач-2.0';

  @override
  String get model_qwen_25 => 'Квен 2.5 1.5B Инструктировать';

  @override
  String get model_qwen_25_desc =>
      'Сбалансированное качество и размер. Подходит для общего разговора.';

  @override
  String get model_deepseek => 'DeepSeek R1 Дистилл Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Модель рассуждения и цепочки мыслей. Лучше всего подходит для логических задач.';

  @override
  String get model_license_mit => 'Массачусетский технологический институт';

  @override
  String get model_gemma => 'Джемма 4 E2B Инструктирует';

  @override
  String get model_gemma_desc =>
      'Флагманская модель Google. Высочайшее качество, требует больше оперативной памяти.';

  @override
  String export_header(String date) {
    return '*Экспортировано из LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Пользователь';

  @override
  String get export_role_assistant => '## 🤖 Помощник';

  @override
  String get export_role_system => '## ⚙️ Система';

  @override
  String get export_role_tool => '## 🔧 Инструмент';

  @override
  String get export_text_user => '[ПОЛЬЗОВАТЕЛЬ]';

  @override
  String get export_text_assistant => '[ПОМОЩНИК]';

  @override
  String get export_text_system => '[СИСТЕМА]';

  @override
  String get export_text_tool => '[ИНСТРУМЕНТ]';

  @override
  String get export_label_user => 'ПОЛЬЗОВАТЕЛЬ';

  @override
  String get export_label_assistant => 'ПОМОЩНИК';

  @override
  String get export_label_system => 'СИСТЕМА';

  @override
  String get export_label_tool => 'ИНСТРУМЕНТ';

  @override
  String get select_model_hint => 'Выберите модель, чтобы начать общение';

  @override
  String get test_notification_title => 'Уведомление о тестировании';

  @override
  String get test_notification_body =>
      'Это тестовое уведомление о ходе загрузки модели.';

  @override
  String get tts_supports_background =>
      'Поддерживает фоновое воспроизведение как собственный звук';

  @override
  String get tts_other_services_background_note =>
      'Примечание. Другие службы TTS поддерживают фоновое воспроизведение как собственный звук.';

  @override
  String get gguf_imported_models_title => 'Импортированные модели GGUF';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Импортируйте GGUF со своего устройства или добавьте его из Hugging Face. Импортированные модели запускаются локально с помощью llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      'импортированные модели готовы для локального вывода.';

  @override
  String get gguf_curated_models_subtitle =>
      'Рекомендуемые модели на устройстве, которые вы можете загружать и управлять ими внутри LocalMind.';

  @override
  String get gguf_only_supported =>
      'Для этого импорта поддерживаются только модели GGUF.';

  @override
  String get gguf_imported_from_local_file =>
      'импортировано из локального файла.';

  @override
  String get gguf_import_failed => 'Не удалось импортировать модель GGUF.';

  @override
  String get gguf_imported_from_huggingface => 'импортировано из Hugging Face.';

  @override
  String get gguf_import_canceled => 'Импорт GGUF отменен.';

  @override
  String get gguf_enter_huggingface_url =>
      'Введите URL-адрес GGUF «Обнимающее лицо».';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Поддерживаются только официальные URL-адреса Hugging Face GGUF.';

  @override
  String get gguf_use_https_url =>
      'Используйте URL-адрес обнимающего лица HTTPS для импорта GGUF.';

  @override
  String get gguf_url_must_point_to_file =>
      'URL-адрес «Обнимающего лица» должен указывать непосредственно на файл .gguf.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Невозможно определить имя файла GGUF.';

  @override
  String get gguf_download_empty =>
      'Загруженный файл GGUF был пуст или отсутствовал.';

  @override
  String get gguf_selected_file_missing =>
      'Выбранный файл модели не существует.';

  @override
  String get gguf_import_action => 'Импортировать GGUF';

  @override
  String get gguf_overview_title => 'Принесите свои собственные модели GGUF';

  @override
  String get gguf_overview_subtitle =>
      'Импортируйте .gguf из локального хранилища или загрузите его прямо с Hugging Face. Импортированные модели остаются на этом устройстве и загружаются с помощью llama.cpp.';

  @override
  String get gguf_imported_count_label => 'импортированный';

  @override
  String get gguf_local_files_label => 'локальные файлы';

  @override
  String get gguf_huggingface_label => 'Обнимающее лицо';

  @override
  String get gguf_import_local_title => 'Импортировать локальный GGUF';

  @override
  String get gguf_import_local_subtitle =>
      'Скопируйте файл .gguf с этого устройства.';

  @override
  String get gguf_import_huggingface_title => 'Импорт из «Обнимающего лица»';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Вставьте URL-адрес GGUF или путь к репозиторию.';

  @override
  String get gguf_no_imported_title => 'Импортированных моделей GGUF пока нет.';

  @override
  String get gguf_no_imported_subtitle =>
      'Вы можете перенести свой собственный файл GGUF из хранилища устройства или вставить URL-адрес Hugging Face или путь к репозиторию, указывающий на файл .gguf.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Импортировать GGUF из Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Вставьте прямой URL-адрес GGUF или путь репозитория Hugging Face, например `owner/repo/blob/main/model.gguf`. Ссылки на большие двоичные объекты преобразуются автоматически.';

  @override
  String get gguf_url_or_repo_path => 'URL-адрес GGUF или путь к репозиторию';

  @override
  String get paste => 'Вставить';

  @override
  String get gguf_browse => 'Просмотр GGUF';

  @override
  String get gguf_huggingface_token_ready => 'Жетон «Обнимающее лицо» готов.';

  @override
  String get gguf_huggingface_token_optional =>
      'Токен необязателен, но рекомендуется';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Ваш сохраненный токен будет автоматически использоваться для закрытых или частных репозиториев.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Требуется жетон «Обнимающее лицо». Добавьте его в настройках, если этот GGUF является закрытым или частным.';

  @override
  String get gguf_downloading => 'Загрузка GGUF';

  @override
  String get gguf_preparing => 'Подготовка';

  @override
  String get gguf_preparing_download => 'Подготовка загрузки...';

  @override
  String get gguf_cancel_import => 'Отменить импорт';

  @override
  String get clipboard_empty => 'Буфер обмена пуст.';

  @override
  String get could_not_open_huggingface =>
      'Не удалось открыть «Обнимающее лицо».';

  @override
  String get gguf_paste_url_error =>
      'Вставьте URL-адрес GGUF Hugging Face или путь к репозиторию.';

  @override
  String get gguf_blob_link => 'Ссылка на BLOB-объект';

  @override
  String get gguf_repository_label => 'Репозиторий';

  @override
  String get gguf_detected_path_label => 'Обнаруженный путь';

  @override
  String get gguf_imported_section_label => 'Импортированный GGUF';

  @override
  String get gguf_already_available => 'Уже доступно на этом устройстве';

  @override
  String get gguf_curated_models_short => 'Кураторские модели на устройстве';

  @override
  String get execute_tool_title => 'Выполнить инструмент';

  @override
  String get execute_tool_request_desc =>
      'Модель запрашивает выполнение следующего инструмента:';

  @override
  String get reject => 'Отклонять';

  @override
  String get approve => 'Утвердить';

  @override
  String get server_type_help =>
      'Прежде чем заполнять данные подключения, выберите провайдера.';

  @override
  String get server_identity_title => 'Личность';

  @override
  String get server_identity_desc =>
      'Назовите этот сервер и выберите, как он будет отображаться в списке.';

  @override
  String get server_connection_title => 'Связь';

  @override
  String get server_connection_desc =>
      'Используйте адрес и порт, предоставленные вашим сервером.';

  @override
  String get server_authentication_title => 'Аутентификация';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter требует ключ API перед тестированием.';

  @override
  String get server_authentication_optional_desc =>
      'Оставьте ключ API пустым, если этот сервер не требует его.';

  @override
  String get mcp_tools_title => 'Инструменты MCP';

  @override
  String get available_tools => 'Доступные инструменты';

  @override
  String get unable_load_tools => 'Невозможно загрузить инструменты';

  @override
  String get no_tools_registered => 'Инструменты не зарегистрированы';

  @override
  String get no_tools_registered_desc =>
      'Включите пример сервера MCP или добавьте интеграцию MCP из настроек чата.';

  @override
  String get example_mcp_server_title => 'Пример MCP-сервера';

  @override
  String get example_mcp_server_desc =>
      'Регистрирует example.echo и example.word_count через того же поставщика инструментов MCP, который используется внешними серверами.';

  @override
  String get disable_example_server => 'Отключить пример сервера';

  @override
  String get enable_example_server => 'Включить пример сервера';

  @override
  String get built_in_label => 'Встроенный';

  @override
  String get highlights_label => 'Основные моменты';

  @override
  String get built_with_label => 'Построен с';

  @override
  String get local_label => 'Местный';

  @override
  String get gguf_format_label => 'ГГУФ';

  @override
  String get tool_status_requested => 'Запрошено';

  @override
  String get tool_status_approved => 'Одобренный';

  @override
  String get tool_status_rejected => 'Отклоненный';

  @override
  String get tool_status_running => 'Бег';

  @override
  String get tool_status_done => 'Сделанный';

  @override
  String get tool_status_failed => 'Неуспешный';

  @override
  String get model_favorite_toggle => 'Добавить в избранное';

  @override
  String get model_note_label => 'Заметка';

  @override
  String get model_note_hint => 'Добавить личную заметку для этой модели...';

  @override
  String get unload_models_before_load => 'Выгружать модели перед загрузкой';

  @override
  String get temp_chat_keyboard_incognito =>
      'Режим инкогнито клавиатуры во временном чате';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Запрашивать у клавиатуры системы не сохранять историю ввода во временных чатах';

  @override
  String get resume_last_chat => 'Возобновить последний чат';

  @override
  String get resume_last_chat_desc =>
      'Автоматически открывать последний активный чат при запуске';

  @override
  String get export_all_data => 'Экспортировать все данные';

  @override
  String get import_all_data => 'Импортировать все данные';

  @override
  String get export_data_success => 'Данные успешно экспортированы';

  @override
  String get import_data_success => 'Данные успешно импортированы';

  @override
  String import_data_failed(String error) {
    return 'Не удалось импортировать данные';
  }

  @override
  String get import_data_confirm =>
      'Это заменит все ваши текущие данные импортированными. Продолжить?';

  @override
  String get import_settings_confirm =>
      'Это заменит ваши текущие настройки импортированными. Продолжить?';

  @override
  String get export_conversations => 'Экспорт чатов';

  @override
  String get import_conversations => 'Импорт чатов';

  @override
  String get export_personas => 'Экспорт персонажей';

  @override
  String get import_personas => 'Импорт персонажей';

  @override
  String get export_settings => 'Экспорт настроек';

  @override
  String get import_settings => 'Импорт настроек';

  @override
  String get export_all_zip => 'Экспортировать все (ZIP)';

  @override
  String get import_all_zip => 'Импортировать все (ZIP)';

  @override
  String get duplicate_chat => 'Дублировать чат';

  @override
  String get duplicate_chat_success => 'Чат успешно продублирован';

  @override
  String get move_to_folder => 'Переместить в папку';

  @override
  String get remove_from_folder => 'Удалить из папки';

  @override
  String get create_folder => 'Создать папку';

  @override
  String get new_folder => 'Новая папка';

  @override
  String get folder_name_hint => 'Введите имя папки...';

  @override
  String get all_chats => 'Все чаты';

  @override
  String get unfiled_chats => 'Чаты без папки';

  @override
  String get create => 'Создать';

  @override
  String get server_path_prefix_label => 'Префикс пути сервера';

  @override
  String get server_path_prefix_hint =>
      'Необязательный префикс для путей API сервера (например, /v1)';

  @override
  String get search_message_contents => 'Поиск по тексту сообщений...';

  @override
  String get message_search_results => 'Результаты поиска сообщений';

  @override
  String get saved_messages_title => 'Сохраненные сообщения';

  @override
  String get nav_saved_messages => 'Сохраненные сообщения';

  @override
  String get saved_messages_empty => 'Нет сохраненных сообщений';

  @override
  String get save_message => 'Сохранить сообщение';

  @override
  String get message_saved => 'Сообщение сохранено';

  @override
  String token_count(int count) {
    return 'Токенов: $count';
  }

  @override
  String estimated_token_count(int count) {
    return 'Оценка токенов: $count';
  }

  @override
  String get test_tts_section_title => 'Проверка озвучки текста';

  @override
  String get test_tts_hint => 'Введите текст для проверки голоса...';

  @override
  String get test_speak_button => 'Озвучить';

  @override
  String get scroll_to_bottom => 'Прокрутить вниз';

  @override
  String get generate_ai_response => 'Сгенерировать ответ ИИ';

  @override
  String get no_response => 'Нет ответа';

  @override
  String get export => 'Экспорт';

  @override
  String get import => 'Импорт';

  @override
  String get conversations_label => 'Чаты';

  @override
  String get personas_label => 'Персонажи';

  @override
  String get settings_label => 'Настройки';

  @override
  String get export_conversation => 'Экспортировать чат';

  @override
  String get tts_process_markdown => 'Обрабатывать Markdown';

  @override
  String get tts_process_markdown_desc =>
      'Удалять форматирование вроде **жирного** перед озвучкой';

  @override
  String get tts_skip_seconds => 'Секунды перемотки';

  @override
  String get tts_skip_seconds_desc =>
      'Время для перемотки вперед/назад в аудиоплеере';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$secondsс';
  }

  @override
  String get preview_system_prompts => 'Предпросмотр системных промптов';

  @override
  String get welcome_message_1 => 'Привет! Я твой локальный ИИ-ассистент.';

  @override
  String get welcome_message_2 => 'Спрашивай о чем угодно — я готов к работе.';

  @override
  String get welcome_message_3 =>
      'Твои данные обрабатываются локально и никогда не покидают устройство.';

  @override
  String get welcome_message_4 =>
      'Для начала выбери модель на верхней панели или добавь новую в разделе управления моделями.';

  @override
  String get temporary_chat => 'Временный чат';

  @override
  String get temporary_chat_desc =>
      'Сообщения из этого чата не будут сохранены в истории';

  @override
  String get temporary_chat_banner =>
      'Активен временный чат — история не сохраняется';

  @override
  String get temporary_chat_save_warning_title => 'Сохранить временный чат?';

  @override
  String get temporary_chat_save_warning_body =>
      'Этот чат не сохранен в истории. Хотите сохранить его сейчас?';

  @override
  String get save_to_history => 'Сохранить в историю';

  @override
  String get share_conversation => 'Поделиться чатом';

  @override
  String get download_tts_audio => 'Скачать аудио';

  @override
  String get tts_download_unavailable => 'Скачивание аудио недоступно';

  @override
  String get tts_download_no_audio =>
      'Нет сгенерированного аудио для скачивания';

  @override
  String get tts_download_success => 'Аудиофайл успешно сохранен';

  @override
  String get return_to_chat => 'Вернуться в чат';

  @override
  String get return_to_temp_chat => 'Вернуться во временный чат';

  @override
  String get insert_saved_message => 'Вставить сохраненное сообщение';

  @override
  String get insert_saved_message_desc =>
      'Добавить фрагмент из сохраненных сообщений в чат';

  @override
  String get model_info => 'Информация о модели';

  @override
  String get model_name => 'Имя модели';

  @override
  String get model_identifier => 'Идентификатор модели';

  @override
  String get not_available => 'Недоступно';

  @override
  String get save_message_folders => 'Сохранить в папки';

  @override
  String get remove_from_saved => 'Удалить из сохраненных';

  @override
  String get message_already_saved => 'Сообщение уже сохранено';

  @override
  String get stream_ttft => 'Время до первого токена';

  @override
  String get stream_tokens_per_sec => 'Токенов в секунду';

  @override
  String get stream_stop_reason => 'Причина остановки';

  @override
  String get stream_input_tokens => 'Входные токены';

  @override
  String get stream_output_tokens => 'Выходные токены';

  @override
  String get stream_generation_time => 'Время генерации';

  @override
  String get attach_image => 'Прикрепить изображение';

  @override
  String get attach_text_document => 'Прикрепить текстовый документ';

  @override
  String get attach_shortcut_images => 'Фото';

  @override
  String get attach_shortcut_documents => 'Файлы';

  @override
  String get attach_shortcut_saved => 'Сохраненные';

  @override
  String get add_attachment => 'Добавить вложение';

  @override
  String get add_to_chat => 'Добавить в чат';

  @override
  String get choose_what_to_attach => 'Что вы хотите добавить?';

  @override
  String get choose_attachment_subtitle =>
      'Выберите источник, чтобы прикрепить к сообщению';

  @override
  String get photo_permission_denied => 'Доступ к фото отклонен';

  @override
  String get select_model_prompt => 'Выбрать модель';

  @override
  String get characters_label => 'Символы';

  @override
  String get exit_temporary_chat_title => 'Выйти из временного чата?';

  @override
  String get exit_temporary_chat_body =>
      'Это навсегда удалит текущий чат. Продолжить?';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Снимки сообщений недоступны во временных чатах';

  @override
  String get filter_title => 'Фильтр чатов';

  @override
  String get filter_pinned => 'Закрепленные';

  @override
  String get filter_archived => 'Архивные';

  @override
  String get filter_temp_chats => 'Временные чаты';

  @override
  String get filter_user_messages => 'Сообщения пользователя';

  @override
  String get filter_assistant_messages => 'Сообщения ассистента';

  @override
  String get archive_chat => 'Архивировать чат';

  @override
  String get unarchive_chat => 'Разархивировать чат';

  @override
  String conversation_message_count(int count) {
    return 'Сообщений: $count';
  }

  @override
  String conversation_character_count(int count) {
    return 'Символов: $count';
  }

  @override
  String get generate_title_with_ai => 'Создать заголовок с помощью ИИ';

  @override
  String get generating_title => 'Создание заголовка...';

  @override
  String get generate_title_failed => 'Не удалось создать заголовок';

  @override
  String get lm_studio_model_browser_title => 'Обзор моделей';

  @override
  String get lm_studio_model_search_hint => 'Поиск моделей...';

  @override
  String get lm_studio_staff_picks => 'Выбор редакции';

  @override
  String get lm_studio_community_models => 'Модели сообщества';

  @override
  String get lm_studio_no_models => 'Модели не найдены';

  @override
  String lm_studio_models_count(int count) {
    return 'Моделей: $count';
  }

  @override
  String get lm_studio_browse_models => 'Найти модели в LM Studio';

  @override
  String get lm_studio_model_search => 'Поиск моделей';

  @override
  String get lm_studio_downloads_title => 'Загрузки';

  @override
  String get lm_studio_choose_quant => 'Выбрать квантование';

  @override
  String get lm_studio_use_default_quant =>
      'Использовать стандартное квантование';

  @override
  String get lm_studio_recommended => 'Рекомендуется';

  @override
  String get lm_studio_clear_downloads => 'Очистить завершенные загрузки';

  @override
  String get lm_studio_no_downloads => 'Нет активных загрузок';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Загрузка моделей производится напрямую с Hugging Face.';

  @override
  String get lm_studio_staff_pick => 'Рекомендуемая модель';

  @override
  String get lm_studio_params => 'Параметры';

  @override
  String get lm_studio_arch => 'Архитектура';

  @override
  String get lm_studio_domain => 'Область применения';

  @override
  String get lm_studio_format => 'Формат';

  @override
  String get lm_studio_vision => 'Зрение';

  @override
  String get lm_studio_tool_use => 'Вызов инструментов';

  @override
  String get lm_studio_reasoning => 'Рассуждение';

  @override
  String get lm_studio_download_options => 'Параметры загрузки';

  @override
  String get lm_studio_download => 'Скачать';

  @override
  String lm_studio_download_size(String size) {
    return 'Размер файла';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Загрузка: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'README недоступен для этой модели.';

  @override
  String get lm_studio_full_gpu_offload => 'Возможен полный перенос на GPU';

  @override
  String get lm_studio_partial_gpu_offload =>
      'Возможен частичный перенос на GPU';

  @override
  String get lm_studio_likely_too_large => 'Возможно, слишком велика';

  @override
  String get lm_studio_available_ram_gb => 'Доступная ОЗУ (ГБ, необязательно)';

  @override
  String get lm_studio_available_vram_gb =>
      'Доступная видеопамять (ГБ, необязательно)';

  @override
  String get lm_studio_memory_settings_title => 'Память для рекомендаций';

  @override
  String get lm_studio_memory_settings_desc =>
      'Используется для оценки того, подходят ли модели для вашего устройства.';

  @override
  String get think_button_label => 'Мыслить';

  @override
  String get thinking_mode_title => 'Режим мышления';

  @override
  String get reasoning_effort_low => 'Низкая';

  @override
  String get reasoning_effort_medium => 'Средняя';

  @override
  String get reasoning_effort_high => 'Высокая';

  @override
  String get could_not_read_file => 'Не удалось прочитать файл';

  @override
  String get server_offline => 'Сервер офлайн';

  @override
  String get could_not_establish_connection =>
      'Не удалось подключиться к серверу. Убедитесь, что сервер запущен, а настройки хоста и порта указаны верно.';

  @override
  String get retry_connection => 'Повторить подключение';

  @override
  String get tokens_label => 'Токены';

  @override
  String get enter_context_length => 'Введите длину контекста...';

  @override
  String get openrouter_disclosure =>
      'Подключая этого поставщика, ваши сообщения чата и вводные данные будут отправлены на их серверы. LocalMind не отслеживает и не хранит ваши разговоры.';

  @override
  String get welcome_message_cloud =>
      'Ваши сообщения отправляются вашему подключенному поставщику.';

  @override
  String get privacy_policy => 'Политика конфиденциальности';

  @override
  String get cloud_sync => 'Синхронизация S3';

  @override
  String get cloud_sync_description =>
      'Сквозное шифрование и синхронизация с вашим S3-совместимым сервером';

  @override
  String get cloud_sync_endpoint => 'URL-адрес сервера';

  @override
  String get cloud_sync_bucket => 'Бакет';

  @override
  String get cloud_sync_region => 'Регион';

  @override
  String get cloud_sync_prefix => 'Префикс';

  @override
  String get cloud_sync_access_key => 'ID ключа доступа';

  @override
  String get cloud_sync_secret_key => 'Секретный ключ доступа';

  @override
  String get cloud_sync_session_token => 'Токен сеанса (необязательно)';

  @override
  String get cloud_sync_passphrase => 'Пароль шифрования';

  @override
  String get cloud_sync_confirm_passphrase => 'Подтвердите пароль';

  @override
  String get cloud_sync_path_style => 'Использовать адресацию по пути';

  @override
  String get cloud_sync_allow_http => 'Разрешить небезопасный HTTP';

  @override
  String get cloud_sync_http_warning =>
      'HTTP раскрывает сетевые метаданные и учётные данные. Используйте его только для доверенного локального S3-сервера.';

  @override
  String get cloud_sync_test => 'Проверить подключение';

  @override
  String get cloud_sync_enable => 'Включить зашифрованную синхронизацию';

  @override
  String get cloud_sync_now => 'Синхронизировать сейчас';

  @override
  String get cloud_sync_disconnect => 'Отключить это устройство';

  @override
  String get cloud_sync_last_synced => 'Последняя синхронизация';

  @override
  String get cloud_sync_never => 'Никогда';

  @override
  String get cloud_sync_conflicts => 'Сохранённые конфликты';

  @override
  String get cloud_sync_passphrase_mismatch => 'Пароли не совпадают';

  @override
  String get crash_report_title => 'Что-то пошло не так';

  @override
  String get crash_report_stack_trace => 'Трассировка стека';

  @override
  String get crash_report_tap_to_expand => 'Нажмите, чтобы развернуть';

  @override
  String get crash_report_button => 'Сообщить об этом сбое';

  @override
  String get crash_try_again => 'Попробовать снова';

  @override
  String get crash_report_empty_stack => '<пусто>';

  @override
  String get crash_report_disclaimer =>
      'Отчёт откроет GitHub с уже заполненной диагностикой. Контроль остаётся за вами — ничего не отправляется автоматически. Перед отправкой проверьте и удалите конфиденциальные данные.';

  @override
  String get crash_report_copied => 'Скопировано в буфер обмена';

  @override
  String get report_a_problem => 'Сообщить о проблеме';

  @override
  String get rename_folder => 'Переименовать папку';

  @override
  String get delete_folder => 'Удалить папку';

  @override
  String get delete_folder_title => 'Удалить папку?';

  @override
  String delete_folder_body(String name) {
    return 'Удалить папку «$name»? Содержащиеся в ней беседы и сохранённые сообщения будут перенесены в «Без папки». Это действие нельзя отменить.';
  }

  @override
  String get folder_name_required => 'Введите название папки';

  @override
  String get model_required_toast => 'Сначала выберите модель';
}
