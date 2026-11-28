// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'Twoja AI. Twoje urządzenie. Twoje zasady.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Anuluj';

  @override
  String get confirm => 'Potwierdź';

  @override
  String get delete => 'Usuń';

  @override
  String get save => 'Zapisz';

  @override
  String get retry => 'Spróbuj ponownie';

  @override
  String get close => 'Zamknij';

  @override
  String get done => 'Gotowe';

  @override
  String get continue_action => 'Kontynuuj';

  @override
  String get skip => 'Pomiń';

  @override
  String get install => 'Zainstaluj';

  @override
  String get download => 'Pobierz';

  @override
  String get resume => 'Wznów';

  @override
  String get pause => 'Wstrzymaj';

  @override
  String get stop => 'Zatrzymaj';

  @override
  String get edit => 'Edytuj';

  @override
  String get preview => 'Podgląd';

  @override
  String get unload => 'Usuń z pamięci';

  @override
  String get load => 'Załaduj';

  @override
  String get rename => 'Zmień nazwę';

  @override
  String get pin => 'Przypnij';

  @override
  String get unpin => 'Odepnij';

  @override
  String get share => 'Udostępnij';

  @override
  String get copy => 'Kopiuj';

  @override
  String get copied => 'Skopiowano!';

  @override
  String get copied_to_clipboard => 'Skopiowano do schowka';

  @override
  String get select => 'Wybierz';

  @override
  String get active => 'Aktywne';

  @override
  String get all => 'Wszystkie';

  @override
  String get none => 'Brak';

  @override
  String get none_selected => 'Nic nie wybrano';

  @override
  String get online => 'Online';

  @override
  String get connected => 'Połączono';

  @override
  String get checking => 'Sprawdzanie';

  @override
  String get offline => 'Offline';

  @override
  String get error => 'Błąd';

  @override
  String get unknown_error => 'Nieznany błąd';

  @override
  String get not_now => 'Nie teraz';

  @override
  String get enable => 'Włącz';

  @override
  String get proceed_anyway => 'Kontynuuj mimo to';

  @override
  String get test_connection => 'Sprawdź połączenie';

  @override
  String get testing => 'Sprawdzanie…';

  @override
  String get connection_successful => 'Połączenie działa!';

  @override
  String get connection_failed =>
      'Połączenie nie powiodło się. Sprawdź ustawienia.';

  @override
  String get connection_failed_unreachable =>
      'Nie udało się połączyć z serwerem. Sprawdź adres i port, upewnij się, że serwer nasłuchuje w Twojej sieci (także poza localhost) i że LocalMind ma dostęp do sieci lokalnej.';

  @override
  String get connection_failed_timeout =>
      'Serwer nie odpowiedział na czas. Sprawdź, czy urządzenie i serwer są w tej samej sieci lub korzystają z tego samego VPN.';

  @override
  String get connection_failed_tls =>
      'Nie udało się nawiązać bezpiecznego połączenia. Sprawdź certyfikat serwera lub użyj http://, jeśli serwer nie obsługuje HTTPS.';

  @override
  String connection_failed_unauthorized(int status) {
    return 'Serwer odrzucił żądanie (HTTP $status). Sprawdź klucz API.';
  }

  @override
  String get connection_failed_not_found =>
      'Serwer odpowiedział, ale nie pod oczekiwanymi ścieżkami API. Sprawdź typ serwera, port i prefiks ścieżki.';

  @override
  String connection_failed_status(int status) {
    return 'Serwer zwrócił kod HTTP $status.';
  }

  @override
  String get connection_failed_missing_key => 'Ten dostawca wymaga klucza API.';

  @override
  String get connection_warning_lmstudio_native =>
      'Połączono tylko przez ścieżki /v1 zgodne z OpenAI. Czat używa natywnych ścieżek /api/v1 LM Studio. Upewnij się, że serwer proxy przekazuje do nich ruch.';

  @override
  String get context_length_server_default => 'Domyślna wartość serwera';

  @override
  String get context_length_use_server_default =>
      'Użyj domyślnej wartości serwera';

  @override
  String get save_continue => 'Zapisz i kontynuuj';

  @override
  String get save_changes => 'Zapisz zmiany';

  @override
  String get finish_setup => 'Zakończ konfigurację';

  @override
  String get start_new_chat => 'Rozpocznij nowy czat';

  @override
  String get cannot_undo => 'Tej czynności nie można cofnąć.';

  @override
  String get ram_warning => 'Ostrzeżenie dotyczące pamięci RAM';

  @override
  String get recommended => 'ZALECANE';

  @override
  String get may_be_large => 'Może być zbyt duży dla tego urządzenia';

  @override
  String get calculating => 'Obliczanie…';

  @override
  String get download_failed => 'Pobieranie nie powiodło się';

  @override
  String get downloaded => 'Pobrano';

  @override
  String get not_downloaded => 'Nie pobrano';

  @override
  String get installed => 'Zainstalowano';

  @override
  String get not_installed => 'Nie zainstalowano';

  @override
  String get loading => 'Ładowanie…';

  @override
  String get thinking => 'Rozumowanie';

  @override
  String get processing => 'Przetwarzanie…';

  @override
  String get initializing => 'Inicjowanie…';

  @override
  String get ready => 'Gotowe do użycia';

  @override
  String get preparing_app => 'Przygotowywanie aplikacji…';

  @override
  String get initializing_services => 'Uruchamianie usług…';

  @override
  String get configuring_server => 'Konfigurowanie serwera…';

  @override
  String get startup_failed => 'Nie udało się uruchomić';

  @override
  String get something_went_wrong => 'Coś poszło nie tak';

  @override
  String get delete_model_title => 'Usuń model';

  @override
  String delete_model_body(String name) {
    return 'Czy na pewno chcesz usunąć $name?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Czy na pewno chcesz usunąć $name? Zwolni to około $size miejsca.\n\nW razie potrzeby możesz ponownie pobrać ten model.';
  }

  @override
  String get delete_voice_title => 'Usuń głos';

  @override
  String delete_voice_body(String name, String size) {
    return 'Czy na pewno chcesz usunąć $name? Zwolni to około $size miejsca.\n\nW razie potrzeby możesz ponownie pobrać ten głos.';
  }

  @override
  String get delete_server_title => 'Usuń serwer';

  @override
  String delete_server_body(String name) {
    return 'Czy na pewno chcesz usunąć „$name”? Tej czynności nie można cofnąć.';
  }

  @override
  String get delete_conversation_title => 'Usunąć rozmowę?';

  @override
  String delete_conversation_body(String title) {
    return 'Czy na pewno chcesz usunąć „$title”? Tej czynności nie można cofnąć.';
  }

  @override
  String get delete_message_title => 'Usunąć wiadomość?';

  @override
  String delete_persona_title(String name) {
    return 'Usunąć „$name”?';
  }

  @override
  String get delete_persona_body => 'Tej czynności nie można cofnąć.';

  @override
  String get delete_builtin_persona_body =>
      'To wbudowana postać. Możesz ją później przywrócić w ustawieniach.';

  @override
  String get restore_builtin_personas => 'Przywróć domyślne postacie';

  @override
  String get restore_builtin_personas_desc =>
      'Dodaj ponownie usunięte wbudowane postacie';

  @override
  String get restore_builtin_personas_success =>
      'Przywrócono domyślne postacie';

  @override
  String get clear_personas => 'Usuń wszystkie postacie';

  @override
  String get enable_image_compression => 'Kompresuj obrazy przed wysłaniem';

  @override
  String get enable_image_compression_desc =>
      'Zmieniaj rozmiar i kompresuj załączone obrazy, aby mieściły się w limitach serwera';

  @override
  String get image_compression_level => 'Poziom kompresji';

  @override
  String get image_compression_level_desc =>
      'Wyższy poziom zmniejsza rozmiar plików kosztem jakości';

  @override
  String get image_compression_level_low => 'Niski';

  @override
  String get image_compression_level_medium => 'Średni';

  @override
  String get image_compression_level_high => 'Wysoki';

  @override
  String get sort_models_tooltip => 'Sortuj modele';

  @override
  String get sort_by_favorites => 'Najpierw ulubione';

  @override
  String get sort_by_name => 'Nazwa (A–Z)';

  @override
  String get sort_by_size_smallest => 'Rozmiar (od najmniejszego)';

  @override
  String get sort_by_size_largest => 'Rozmiar (od największego)';

  @override
  String get sort_by_context_length => 'Długość kontekstu';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Zmienianie nazw $done/$total…';
  }

  @override
  String selected_count(int count) {
    return 'Wybrano: $count';
  }

  @override
  String get ai_rename_tooltip => 'Zmień nazwy wybranych czatów za pomocą AI';

  @override
  String get new_chat_in_folder_tooltip => 'Nowy czat w tym folderze';

  @override
  String total_tokens_count(int count) {
    return 'Tokeny: $count';
  }

  @override
  String get smart_replies_use_persona =>
      'Uwzględniaj postać w inteligentnych odpowiedziach';

  @override
  String get smart_replies_use_persona_desc =>
      'Sugerowane odpowiedzi przyjmują styl aktywnej postaci zamiast standardowego stylu asystenta';

  @override
  String get keep_persona_on_new_chat => 'Zachowuj postać w nowym czacie';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Nie usuwaj wybranych postaci po rozpoczęciu nowego czatu';

  @override
  String get role_swap_button_enabled => 'Pokaż przycisk zmiany roli';

  @override
  String get role_swap_button_enabled_desc =>
      'Pokazuje przycisk w polu wiadomości, który pozwala wysłać wiadomość jako asystent zamiast użytkownika, bez generowania odpowiedzi';

  @override
  String get processing_prompt_label => 'Przetwarzanie polecenia…';

  @override
  String get generating_label => 'Generowanie…';

  @override
  String get prompts_processed_label => 'Przetworzone polecenia';

  @override
  String get prompt_processing_indicator_enabled =>
      'Pokaż wskaźnik przetwarzania poleceń';

  @override
  String get prompt_processing_indicator_enabled_desc =>
      'Pokazuj nad polem wiadomości bieżący postęp przetwarzania i liczbę przetworzonych poleceń w tym czacie.';

  @override
  String get send_as_user_tooltip => 'Wyślij jako użytkownik';

  @override
  String get send_as_assistant_tooltip =>
      'Wyślij jako asystent (bez odpowiedzi)';

  @override
  String get insert_without_generating_tooltip => 'Wstaw bez generowania';

  @override
  String get token_usage_title => 'Użycie tokenów';

  @override
  String get total_tokens_label => 'Wykorzystane tokeny';

  @override
  String get usage_percent_label => 'Wykorzystany kontekst';

  @override
  String get export_choice_title => 'Eksportuj';

  @override
  String get export_choice_body => 'Jak chcesz to wyeksportować?';

  @override
  String get copy_to_clipboard => 'Kopiuj do schowka';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Wyeksportowano rozmowy: $count';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Zmienić nazwy za pomocą AI?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'AI wygeneruje nowe tytuły dla wybranych rozmów ($count), zastępując obecne tytuły. Może to potrwać i nie można tego cofnąć.';
  }

  @override
  String get sort_by_modified_date => 'Ostatnia modyfikacja';

  @override
  String get sort_by_created_date => 'Data utworzenia';

  @override
  String get sort_title => 'Sortuj';

  @override
  String get clear_conversation_title => 'Wyczyścić rozmowę?';

  @override
  String get clear_conversation_body =>
      'Spowoduje to usunięcie wszystkich wiadomości w tej rozmowie.';

  @override
  String get clear => 'Wyczyść';

  @override
  String label_completed(String label) {
    return 'Zakończono: $label';
  }

  @override
  String error_with_message(String error) {
    return 'Błąd: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Nie udało się wyświetlić podglądu: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Ładowanie modelu $modelId…';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Załadowano model: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Nie załadowano modelu. Wybierz „Zarządzaj modelami na urządzeniu”, aby pobrać i załadować model.';

  @override
  String loading_model_error(String error) {
    return 'Błąd: $error';
  }

  @override
  String get delete_conversation => 'Usunąć rozmowę?';

  @override
  String get nav_history => 'Historia';

  @override
  String get nav_servers => 'Serwery';

  @override
  String get nav_local_models => 'Modele lokalne';

  @override
  String get nav_tts => 'Synteza mowy';

  @override
  String get nav_personas => 'Postacie';

  @override
  String get nav_settings => 'Ustawienia';

  @override
  String get nav_new_chat => 'Nowy czat';

  @override
  String get search_hint => 'Szukaj rozmów…';

  @override
  String get no_server_selected => 'Nie wybrano serwera';

  @override
  String get switch_server => 'Zmień serwer';

  @override
  String get switch_server_subtitle => 'Wybierz serwer do połączenia';

  @override
  String get manage_servers => 'Zarządzaj serwerami';

  @override
  String get open_source => 'Otwarty kod źródłowy';

  @override
  String get open_source_desc =>
      'LocalMind ma otwarty kod źródłowy. Śledź postępy lub pomóż w rozwoju na GitHubie.';

  @override
  String get star_on_github => 'Dodaj gwiazdkę na GitHubie';

  @override
  String get add_more => 'Dodaj więcej';

  @override
  String get on_github => 'na GitHubie';

  @override
  String get could_not_open_github => 'Nie udało się otworzyć GitHuba.';

  @override
  String get settings_title => 'Ustawienia';

  @override
  String get settings_appearance => 'Wygląd';

  @override
  String get settings_language => 'Język';

  @override
  String get language_system_default => 'Domyślny język systemu';

  @override
  String get settings_tts => 'Synteza mowy';

  @override
  String get settings_android_assistant => 'Asystent Androida';

  @override
  String get assistant_default_title => 'Używaj LocalMind jako asystenta';

  @override
  String get assistant_default_description =>
      'Uruchamiaj tryb głosowy gestem asystenta Androida lub skrótem przycisku zasilania.';

  @override
  String get assistant_status_active => 'Aktywne';

  @override
  String get assistant_status_available => 'Nieaktywny';

  @override
  String get assistant_status_manual => 'Sprawdź ustawienia';

  @override
  String get assistant_status_unsupported => 'Niedostępne';

  @override
  String get assistant_status_checking => 'Sprawdzanie…';

  @override
  String get assistant_set_default => 'Ustaw jako domyślnego asystenta';

  @override
  String get assistant_open_settings => 'Otwórz ustawienia asystenta Androida';

  @override
  String assistant_error(Object error) {
    return 'Nie udało się otworzyć ustawień asystenta Androida.';
  }

  @override
  String get settings_behavior => 'Zachowanie';

  @override
  String get settings_on_device => 'Wnioskowanie na urządzeniu';

  @override
  String get settings_default_server => 'Domyślny serwer';

  @override
  String get settings_default_persona => 'Domyślna postać';

  @override
  String get settings_default_model => 'Domyślny model';

  @override
  String get settings_default_model_desc =>
      'Wybierany automatycznie przy rozpoczynaniu nowego czatu.';

  @override
  String get settings_privacy => 'Prywatność';

  @override
  String get settings_data_management => 'Zarządzanie danymi';

  @override
  String get settings_about => 'O aplikacji';

  @override
  String get theme => 'Motyw';

  @override
  String get theme_system => 'Systemowy';

  @override
  String get theme_light => 'Jasny';

  @override
  String get theme_dark => 'Ciemny';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'Rozmiar czcionki';

  @override
  String get font_size_desc => 'Dostosuj rozmiar tekstu w czacie.';

  @override
  String get font_preview => 'Zażółć gęślą jaźń.';

  @override
  String get code_theme_dark => 'Motyw kodu (ciemny)';

  @override
  String get code_theme_light => 'Motyw kodu (jasny)';

  @override
  String get code_theme_desc =>
      'Wybierz motyw podświetlania składni w blokach kodu.';

  @override
  String get tts_engine => 'Silnik syntezy mowy';

  @override
  String get tts_engine_system => 'Systemowa synteza mowy';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => 'Głos';

  @override
  String get voice_female => 'Żeński';

  @override
  String get voice_male => 'Męski';

  @override
  String get voice_other => 'Inny';

  @override
  String get tts_speed => 'Szybkość syntezy mowy';

  @override
  String get tts_speed_desc => 'Dostosuj szybkość odtwarzania.';

  @override
  String get manage_tts_models => 'Zarządzaj modelami syntezy mowy';

  @override
  String get manage_on_device_models => 'Zarządzaj modelami na urządzeniu';

  @override
  String get enable_smart_reply => 'Inteligentne odpowiedzi';

  @override
  String get ai_user_response_enabled =>
      'Wiadomość użytkownika pisana przez AI (przytrzymaj przycisk wysyłania)';

  @override
  String get ai_user_response_enabled_desc =>
      'Przytrzymaj przycisk wysyłania przez 3 sekundy, aby AI napisała i wysłała kolejną wiadomość';

  @override
  String get ai_user_response_tooltip =>
      'Wygeneruj wiadomość użytkownika za pomocą AI';

  @override
  String get streaming_responses => 'Wyświetlaj odpowiedzi na bieżąco';

  @override
  String get auto_generate_titles => 'Automatyczne tworzenie tytułów';

  @override
  String get send_on_enter => 'Wysyłaj klawiszem Enter';

  @override
  String get show_system_messages => 'Wysyłaj domyślne polecenie systemowe';

  @override
  String get show_system_messages_desc =>
      'Gdy nie wybrano postaci, wysyłaj z każdym żądaniem domyślne polecenie systemowe asystenta';

  @override
  String get show_system_messages_in_chat =>
      'Pokaż wiadomości systemowe w czacie';

  @override
  String get show_system_messages_in_chat_desc =>
      'Wyświetlaj wiadomości systemowe (np. z zaimportowanej kopii zapasowej) w dymkach w rozmowie';

  @override
  String get auto_collapse_thinking => 'Automatycznie zwijaj rozumowanie';

  @override
  String get auto_collapse_thinking_desc =>
      'Po zakończeniu generowania automatycznie zwiń proces rozumowania, jeśli model podał główną odpowiedź';

  @override
  String get haptic_feedback => 'Wibracje przy dotyku';

  @override
  String get enable_mcp => 'Włącz MCP';

  @override
  String get new_chat_mcp_default => 'Domyślne MCP dla nowego czatu';

  @override
  String get show_data_indicator => 'Pokaż wskaźnik transferu danych';

  @override
  String get privacy_info => '„LocalMind nigdy nie ma wglądu w Twoje dane”';

  @override
  String get delete_all_conversations => 'Usuń wszystkie rozmowy';

  @override
  String get reset_settings_defaults => 'Przywróć ustawienia domyślne';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Parametry czatu';

  @override
  String get change_persona => 'Zmień postać';

  @override
  String get set_persona => 'Ustaw postać';

  @override
  String get remove_persona => 'Usuń postać';

  @override
  String get clear_conversation => 'Wyczyść rozmowę';

  @override
  String get connection_error => 'Błąd połączenia. Sprawdź serwer.';

  @override
  String get disconnected => 'Rozłączono z serwerem.';

  @override
  String get configure => 'Skonfiguruj';

  @override
  String get select_model => 'Wybierz model';

  @override
  String get select_persona => 'Wybierz postać';

  @override
  String get manage_personas => 'Zarządzaj postaciami';

  @override
  String get personas_combine_hint =>
      'Wybierz kilka postaci w czacie, aby połączyć ich polecenia systemowe.';

  @override
  String get start_conversation => 'Rozpocznij rozmowę';

  @override
  String get recent_chats => 'Ostatnie czaty';

  @override
  String get see_all => 'Zobacz wszystkie';

  @override
  String get quick_write => 'Pomóż mi napisać funkcję';

  @override
  String get quick_explain => 'Wyjaśnij ten kod';

  @override
  String get quick_debug => 'Pomóż mi znaleźć błąd';

  @override
  String get quick_async => 'Jak używać async/await?';

  @override
  String get history_missing_title => 'Brak historii';

  @override
  String get history_missing_desc =>
      'Wiadomości na tym czacie zostały usunięte lub wpis historii jest uszkodzony.';

  @override
  String get technical_details => 'Szczegóły techniczne';

  @override
  String get last_error => 'Ostatni błąd:';

  @override
  String get copy_info => 'Kopiuj informacje';

  @override
  String get conversation_id => 'Identyfikator rozmowy';

  @override
  String get created_at => 'Utworzono';

  @override
  String get expected_messages => 'Oczekiwana liczba wiadomości';

  @override
  String get debug_dialog_desc =>
      'Dane diagnostyczne pomagające wykryć problemy z synchronizacją.';

  @override
  String get chat_input_hint => 'Zapytaj o cokolwiek';

  @override
  String get send_message_tooltip => 'Wyślij wiadomość';

  @override
  String get stop_generation_tooltip => 'Zatrzymaj generowanie';

  @override
  String get attach_images_tooltip => 'Dołącz obrazy lub tekst';

  @override
  String get start_listening_tooltip => 'Zacznij nasłuchiwać';

  @override
  String get stop_listening_tooltip => 'Przestań nasłuchiwać';

  @override
  String tool_label(String toolCallId) {
    return 'Narzędzie: $toolCallId';
  }

  @override
  String get tool_unknown => 'Narzędzie: nieznane';

  @override
  String get message_options => 'Opcje wiadomości';

  @override
  String get copy_markdown => 'Kopiuj jako Markdown';

  @override
  String get copied_markdown => 'Skopiowano jako Markdown';

  @override
  String get read_aloud => 'Czytaj na głos';

  @override
  String get stop_reading => 'Zatrzymaj czytanie';

  @override
  String get more => 'Więcej';

  @override
  String character_count(int length) {
    return 'Liczba znaków: $length';
  }

  @override
  String get edit_message => 'Edytuj wiadomość';

  @override
  String get edit_message_desc =>
      'Zapisanie usunie poniższą odpowiedź asystenta i wygeneruje ją ponownie.';

  @override
  String get save_regenerate => 'Zapisz i wygeneruj ponownie';

  @override
  String get chat_settings_title => 'Ustawienia czatu';

  @override
  String get reset_defaults => 'Przywróć wartości domyślne';

  @override
  String get parameters_tab => 'Parametry';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'Temperatura';

  @override
  String get temperature_desc =>
      'Steruje losowością: wyższa sprzyja kreatywności, niższa zwiększa przewidywalność';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'Próg próbkowania jądrowego';

  @override
  String get max_tokens => 'Maks. liczba tokenów';

  @override
  String get max_tokens_desc => 'Limit długości odpowiedzi';

  @override
  String get context_length => 'Długość kontekstu';

  @override
  String get context_length_desc => 'Zakres historii rozmowy';

  @override
  String get mcp_disabled_warning =>
      'Protokół MCP jest wyłączony dla całej aplikacji. Włącz go w ustawieniach, aby korzystać z tych funkcji.';

  @override
  String get mcp_enable_chat => 'Włącz MCP w tym czacie';

  @override
  String mcp_connection_failed(String error) {
    return 'Nie udało się połączyć: $error';
  }

  @override
  String get mcp_tools_unsupported_runtime =>
      'Środowisko wykonawcze tego modelu nie obsługuje jeszcze wywołań narzędzi. Przełącz na model Gemma (LiteRT) lub model serwerowy, aby używać narzędzi MCP.';

  @override
  String get auto_execute_tools => 'Uruchamiaj narzędzia automatycznie';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Eksperymentalne';

  @override
  String get add_ephemeral_mcp => 'Dodaj tymczasowy serwer MCP';

  @override
  String get mcp_label_placeholder => 'Etykieta';

  @override
  String get mcp_url_placeholder => 'Adres URL (https://…)';

  @override
  String get active_integrations => 'Aktywne integracje';

  @override
  String get import_mcp_json => 'Importuj JSON';

  @override
  String get import_mcp_json_dialog_title => 'Importuj konfigurację MCP z JSON';

  @override
  String get import_mcp_json_instructions =>
      'Skopiuj JSON mcpServers bezpośrednio z LM Studio (mcp.json) lub wklej poniżej tablicę wtyczek:';

  @override
  String get import_mcp_json_placeholder =>
      'Wklej tu JSON mcpServers lub listę wtyczek…';

  @override
  String mcp_import_success(int count) {
    return 'Zaimportowano integracje: $count';
  }

  @override
  String get mcp_import_failed =>
      'Nie znaleziono prawidłowych integracji MCP w pliku JSON';

  @override
  String get enable_notifications => 'Włącz powiadomienia';

  @override
  String get enable_notifications_desc =>
      'Otrzymuj powiadomienia po pobraniu modeli.';

  @override
  String get chat_history_title => 'Historia czatów';

  @override
  String get conversation_just_now => 'Przed chwilą';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes min temu';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours godz. temu';
  }

  @override
  String get conversation_yesterday => 'Wczoraj';

  @override
  String conversation_days_ago(int days) {
    return '$days dni temu';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$day.$month.$year';
  }

  @override
  String get options_tooltip => 'Opcje';

  @override
  String get no_results_found => 'Nie znaleziono wyników';

  @override
  String get no_conversations_yet => 'Nie ma jeszcze żadnych rozmów';

  @override
  String get try_different_search => 'Spróbuj użyć innego hasła';

  @override
  String get start_new_conversation => 'Rozpocznij nową rozmowę';

  @override
  String get rename_conversation => 'Zmień nazwę rozmowy';

  @override
  String get enter_new_title => 'Wpisz nowy tytuł';

  @override
  String get pinned_section => 'PRZYPIĘTE';

  @override
  String get today_section => 'DZISIAJ';

  @override
  String get yesterday_section => 'WCZORAJ';

  @override
  String get previous_7_days => 'OSTATNIE 7 DNI';

  @override
  String get previous_30_days => 'OSTATNIE 30 DNI';

  @override
  String get older_section => 'STARSZE';

  @override
  String get onboarding_choose_language => 'Wybierz język';

  @override
  String get onboarding_choose_language_desc =>
      'Wybierz preferowany język. W każdej chwili możesz go zmienić w ustawieniach.';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'Połącz się ze\nswoim serwerem';

  @override
  String get onboarding_connect_desc =>
      'Połącz się z LM Studio, Ollama,\nOllama Cloud lub OpenRouter, aby\nzacząć korzystać z prywatnej AI.';

  @override
  String get openai_compatible_api => 'API zgodne z OpenAI';

  @override
  String get https_requires_ssl => 'HTTPS wymaga SSL';

  @override
  String get most_local_setups_use_http =>
      'Większość konfiguracji lokalnych używa http://';

  @override
  String get onboarding_welcome => 'Witaj w LocalMind';

  @override
  String get server_type_on_device => 'Na urządzeniu';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'ZARZĄDZANA CHMURA';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Po połączeniu z Ollama Cloud wiadomości i dane wejściowe są wysyłane na serwery Ollama w celu przetworzenia. LocalMind nie śledzi ani nie przechowuje Twoich rozmów. Możesz w dowolnym momencie unieważnić klucz na ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud => 'Ollama Cloud wymaga klucza API';

  @override
  String get api_key_hint_ollama_cloud => 'Wklej klucz API Ollama Cloud';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Połącz się z Ollama Cloud za pomocą klucza API z ollama.com/settings/keys, aby uzyskać dostęp do zarządzanych modeli w chmurze.';

  @override
  String get add_server_openrouter_subtitle =>
      'Połącz się z OpenRouter za pomocą prawidłowego klucza API, aby móc kierować zapytania do modeli przez ten profil.';

  @override
  String get add_server_requesty_subtitle =>
      'Połącz się z Requesty za pomocą prawidłowego klucza API, aby móc kierować zapytania do modeli przez ten profil.';

  @override
  String get add_server_standard_compute_subtitle =>
      'Połącz się ze Standard Compute za pomocą prawidłowego klucza API, aby móc kierować zapytania do modeli przez ten profil.';

  @override
  String get add_server_endpoint_subtitle =>
      'Skonfiguruj lokalny lub samodzielnie hostowany punkt końcowy i sprawdź połączenie przed zapisaniem.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_requesty => 'Requesty';

  @override
  String get server_type_standard_compute => 'Standard Compute';

  @override
  String get server_type_openrouter_sub => 'UJEDNOLICONA CHMURA';

  @override
  String get server_type_requesty_sub => 'UJEDNOLICONA CHMURA';

  @override
  String get server_type_standard_compute_sub => 'UJEDNOLICONA CHMURA';

  @override
  String get ready_continue => 'MOŻESZ KONTYNUOWAĆ';

  @override
  String get waiting_selection => 'OCZEKIWANIE NA WYBÓR';

  @override
  String get setup_connection => 'Skonfiguruj połączenie';

  @override
  String setup_connection_desc(String server) {
    return 'Skonfiguruj serwer $server, aby zacząć rozmawiać.';
  }

  @override
  String get server_name => 'Nazwa serwera';

  @override
  String get name_required => 'Nazwa jest wymagana';

  @override
  String get name_max_50 => 'Maks. 50 znaków';

  @override
  String get host_label => 'Host / adres IP';

  @override
  String get host_required => 'Adres hosta jest wymagany';

  @override
  String get port_label => 'Port';

  @override
  String get port_required => 'Port jest wymagany';

  @override
  String get port_invalid => 'Wpisz liczbę';

  @override
  String get port_range => 'Wpisz prawidłowy numer portu (1–65535)';

  @override
  String get api_key_required => 'Klucz API *';

  @override
  String get api_key_optional => 'Klucz API (opcjonalnie)';

  @override
  String get api_key_required_openrouter => 'OpenRouter wymaga klucza API';

  @override
  String get api_key_required_requesty => 'Requesty wymaga klucza API';

  @override
  String get api_key_required_standard_compute =>
      'Standard Compute wymaga klucza API';

  @override
  String get api_key_format => 'Klucze API OpenRouter zaczynają się od sk-';

  @override
  String get my_server_hint => 'Mój serwer';

  @override
  String get name_length_validation => 'Nazwa może mieć najwyżej 50 znaków';

  @override
  String get host_valid => 'Wpisz prawidłową nazwę hosta lub adres IP';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_requesty => 'rqsty-...';

  @override
  String get api_key_hint_standard_compute => 'sk_live_...';

  @override
  String get api_key_hint_generic =>
      'Dla serwerów wymagających uwierzytelnienia';

  @override
  String get update_server => 'Zaktualizuj serwer';

  @override
  String get save_server => 'Zapisz serwer';

  @override
  String get server_updated => 'Zaktualizowano serwer';

  @override
  String get server_added => 'Dodano serwer';

  @override
  String get download_model_title => 'Pobierz model';

  @override
  String get download_model_desc =>
      'Wybierz model do pobrania.\nBędzie działać lokalnie na tym urządzeniu.';

  @override
  String get no_model_downloaded_title => 'Nie pobrano żadnego modelu';

  @override
  String get no_model_downloaded_desc =>
      'Aby używać AI na urządzeniu, pobierz lub wybierz co najmniej jeden model. Możesz to zrobić teraz albo pominąć ten krok i pobrać model później w ustawieniach.';

  @override
  String get choose_a_model => 'Wybierz model';

  @override
  String get skip_for_now => 'Pomiń na razie';

  @override
  String get download_in_progress_title => 'Pobieranie w toku';

  @override
  String get download_in_progress_desc =>
      'Trwa pobieranie modelu. Możesz poczekać na zakończenie lub kontynuować pobieranie w tle.';

  @override
  String get wait_for_download => 'Poczekaj';

  @override
  String get continue_anyway => 'Kontynuuj mimo to';

  @override
  String get download_model_required_hint =>
      'Do czatu na urządzeniu potrzebujesz co najmniej jednego pobranego modelu.';

  @override
  String get on_device_android_only =>
      'Wnioskowanie na urządzeniu jest obecnie dostępne tylko na Androidzie.';

  @override
  String get total_ram => 'Całkowita pamięć RAM';

  @override
  String get available => 'Dostępne';

  @override
  String ram_min_required(String fileSize) {
    return 'Min. $fileSize GB RAM';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Pozostało: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'Wstrzymano – $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Ten model wymaga co najmniej $ram GB RAM, a urządzenie ma $totalMemory. Model może działać nieprawidłowo lub spowodować awarię aplikacji.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Urządzenie ma $availableRAM wolnej pamięci RAM, a dla tego modelu zalecane jest co najmniej $ram GB. Ładowanie może się nie udać lub spowodować niestabilne działanie.';
  }

  @override
  String get choose_theme => 'Wybierz motyw';

  @override
  String get choose_theme_desc =>
      'Dostosuj wygląd aplikacji. Możesz go później zmienić w ustawieniach.';

  @override
  String get theme_card_system => 'Systemowy';

  @override
  String get theme_card_system_sub => 'Zgodny z ustawieniami urządzenia';

  @override
  String get theme_card_light => 'Jasny';

  @override
  String get theme_card_light_sub => 'Przejrzysty i jasny';

  @override
  String get theme_card_dark => 'Ciemny';

  @override
  String get theme_card_dark_sub => 'Łagodny dla oczu';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'Ciepły motyw w odcieniach brzoskwini';

  @override
  String get stay_updated => 'Bądź na bieżąco';

  @override
  String get stay_updated_desc =>
      'Otrzymuj powiadomienia, gdy modele AI się pobiorą lub zakończą się długotrwałe zadania.';

  @override
  String get notification_benefit_downloads => 'Postęp pobierania modeli';

  @override
  String get notification_benefit_completions => 'Zakończenie generowania';

  @override
  String get notification_benefit_background => 'Stan zadań w tle';

  @override
  String get allow_notifications => 'Zezwól na powiadomienia';

  @override
  String get servers_title => 'Serwery';

  @override
  String get no_servers_yet => 'Nie ma jeszcze serwerów';

  @override
  String get no_servers_desc =>
      'Dodaj pierwszy serwer, aby zacząć rozmawiać z modelami AI.';

  @override
  String get add_server => 'Dodaj serwer';

  @override
  String switched_to_server(String name) {
    return 'Przełączono na $name';
  }

  @override
  String get edit_server => 'Edytuj serwer';

  @override
  String get add_server_title => 'Dodaj serwer';

  @override
  String get server_type_label => 'Typ serwera';

  @override
  String get server_icon_label => 'Ikona serwera';

  @override
  String get default_icon => 'Domyślna ikona';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'Zgodny z OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_requesty_display => 'Requesty';

  @override
  String get server_type_standard_compute_display => 'Standard Compute';

  @override
  String get server_type_on_device_display => 'Na urządzeniu';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_requesty => 'router.requesty.ai';

  @override
  String get server_address_standard_compute => 'api.stdcmpt.com';

  @override
  String get server_address_on_device => 'Wnioskowanie lokalne';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Domyślne';

  @override
  String get set_as_default => 'Ustaw jako domyślne';

  @override
  String get select_icon => 'Wybierz ikonę';

  @override
  String get select_icon_desc => 'Wybierz ikonę serwera';

  @override
  String get search_icons_hint => 'Szukaj ikon…';

  @override
  String get server_icon_stack => 'Stos serwerów';

  @override
  String get server_icon_stack2 => 'Stos serwerów 02';

  @override
  String get server_icon_stack3 => 'Stos serwerów 03';

  @override
  String get server_icon_cloud => 'Chmura';

  @override
  String get server_icon_cloud_server => 'Serwer w chmurze';

  @override
  String get server_icon_mcp => 'Serwer MCP';

  @override
  String get server_icon_database => 'Baza danych';

  @override
  String get server_icon_database1 => 'Baza danych 01';

  @override
  String get server_icon_database2 => 'Baza danych 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'Układ scalony';

  @override
  String get server_icon_chip2 => 'Układ scalony 02';

  @override
  String get server_icon_computer => 'Komputer';

  @override
  String get server_icon_laptop => 'Laptop';

  @override
  String get server_icon_terminal => 'Terminal';

  @override
  String get server_icon_code => 'Kod';

  @override
  String get server_icon_ai_brain => 'Mózg AI';

  @override
  String get server_icon_ai_brain2 => 'Mózg AI 02';

  @override
  String get server_icon_ai_cloud => 'Chmura AI';

  @override
  String get server_icon_ai_network => 'Sieć AI';

  @override
  String get server_icon_ai_chat => 'Czat AI';

  @override
  String get server_icon_cellular => 'Sieć komórkowa';

  @override
  String get server_icon_plug1 => 'Wtyczka 01';

  @override
  String get server_icon_plug2 => 'Wtyczka 02';

  @override
  String get server_icon_bot => 'Bot';

  @override
  String get server_icon_bot2 => 'Bot 02';

  @override
  String get server_icon_robotic => 'Robot';

  @override
  String get server_icon_rocket => 'Rakieta';

  @override
  String get server_icon_star => 'Gwiazda';

  @override
  String get server_icon_settings1 => 'Ustawienia 01';

  @override
  String get server_icon_settings2 => 'Ustawienia 02';

  @override
  String get server_icon_home1 => 'Dom 01';

  @override
  String get server_icon_home2 => 'Dom 02';

  @override
  String get server_icon_folder1 => 'Folder 01';

  @override
  String get server_icon_folder2 => 'Folder 02';

  @override
  String get server_icon_file1 => 'Plik 01';

  @override
  String get server_icon_lock => 'Kłódka';

  @override
  String get server_icon_key => 'Klucz 01';

  @override
  String get server_icon_link => 'Łącze 01';

  @override
  String get server_icon_globe => 'Globus';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Strzałka w prawo 01';

  @override
  String get server_icon_check => 'Znacznik wyboru w okręgu';

  @override
  String get server_icon_alert => 'Alert w okręgu';

  @override
  String get server_icon_info => 'Informacja w okręgu';

  @override
  String get server_icon_zap => 'Błyskawica';

  @override
  String get server_icon_cloud_upload => 'Przesyłanie do chmury';

  @override
  String get server_icon_cloud_download => 'Pobieranie z chmury';

  @override
  String get server_icon_refresh => 'Odśwież';

  @override
  String get server_icon_hard_drive => 'Dysk twardy';

  @override
  String get server_icon_drive => 'Dysk';

  @override
  String get personas_title => 'Postacie';

  @override
  String get persona_category_general => 'Ogólne';

  @override
  String get persona_category_coding => 'Programowanie';

  @override
  String get persona_category_education => 'Edukacja';

  @override
  String get persona_category_creative => 'Twórczość';

  @override
  String get persona_builtin_section => 'WBUDOWANE';

  @override
  String get persona_my_section => 'MOJE POSTACIE';

  @override
  String get clone_edit => 'Skopiuj i edytuj';

  @override
  String get builtin_badge => 'Wbudowane';

  @override
  String get no_personas_found => 'Nie znaleziono postaci';

  @override
  String get no_personas_desc =>
      'Utwórz pierwszą postać, aby dostosować zachowanie AI.';

  @override
  String get edit_persona => 'Edytuj postać';

  @override
  String get create_persona => 'Utwórz postać';

  @override
  String get create_persona_button => 'Utwórz';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'Nazwa';

  @override
  String get my_persona_hint => 'Moja postać';

  @override
  String get category_label => 'Kategoria';

  @override
  String get description_optional => 'Opis (opcjonalnie)';

  @override
  String get description_hint => 'Rola tej postaci…';

  @override
  String get system_prompt => 'Polecenie systemowe';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Nie ma jeszcze polecenia…';

  @override
  String get prompt_hint => 'Jesteś pomocnym asystentem…';

  @override
  String get prompt_required => 'Polecenie systemowe jest wymagane';

  @override
  String get prompt_max_chars => 'Maks. 4000 znaków';

  @override
  String prompt_length_warning(int count) {
    return 'Długie polecenia ($count znaków) zajmują więcej miejsca w oknie kontekstu modelu. Mogą spowolnić odpowiedzi lub powodować błędy w mniejszych modelach.';
  }

  @override
  String get advanced_settings => 'Ustawienia zaawansowane';

  @override
  String get temperature_label => 'Temperatura (0.0–2.0)';

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
  String get persona_updated => 'Zaktualizowano postać';

  @override
  String get persona_created => 'Utworzono postać';

  @override
  String get tts_models_title => 'Modele syntezy mowy';

  @override
  String get always_available => 'Zawsze dostępne';

  @override
  String get tts_system_desc =>
      'Korzysta z wbudowanego silnika syntezy mowy urządzenia.\nNie wymaga pobierania. Wybór głosu zależy od ustawień systemowych.';

  @override
  String get downloading_status => 'Pobieranie…';

  @override
  String tts_kitten_desc(String size) {
    return 'Bardzo szybka neuronowa synteza mowy z 8 wyrazistymi głosami.\nWymaga pobrania $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Szybka synteza mowy Piper offline z 2 wyrazistymi głosami.\nWymaga pobrania $size na głos.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · Liczba głosów: $voiceCount';
  }

  @override
  String get on_device_models_title => 'Modele na urządzeniu';

  @override
  String get settings_huggingface_token => 'Token Hugging Face (opcjonalnie)';

  @override
  String get settings_huggingface_token_desc =>
      'Wymagany tylko dla modeli o ograniczonym dostępie (np. Gemma). Uzyskaj token na huggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Zapisano token';

  @override
  String get settings_huggingface_token_cleared => 'Usunięto token';

  @override
  String get model_requires_huggingface_token => 'Wymaga tokena Hugging Face';

  @override
  String get model_missing_huggingface_token =>
      'Ten model ma ograniczony dostęp na Hugging Face. Aby go pobrać, dodaj token w sekcji Ustawienia → Wnioskowanie na urządzeniu.';

  @override
  String get set_huggingface_token => 'Ustaw token';

  @override
  String get clear_huggingface_token => 'Wyczyść';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Token dostępu Hugging Face';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc =>
      'Lokalny silnik AI. Klucz API nie jest wymagany.';

  @override
  String get server_type_on_device_desc =>
      'Działa na telefonie. Niektóre modele wymagają tokena Hugging Face.';

  @override
  String get server_type_lm_studio_desc =>
      'Lokalny serwer API. Klucz API nie jest wymagany.';

  @override
  String get available_models => 'Dostępne modele';

  @override
  String get device_memory => 'Pamięć urządzenia';

  @override
  String get ram_usage => 'Użycie pamięci RAM';

  @override
  String get memory_healthy => 'W normie';

  @override
  String get memory_critical => 'Poziom krytyczny';

  @override
  String get memory_low => 'Niski';

  @override
  String ram_used(String percent) {
    return 'W użyciu: $percent%';
  }

  @override
  String get available_ram => 'Dostępna pamięć RAM';

  @override
  String get total_capacity => 'Całkowita pojemność';

  @override
  String get loaded_status => 'Załadowano';

  @override
  String get inference_backend => 'Mechanizm wnioskowania';

  @override
  String get backend_ios_notice =>
      'Na iOS dostępne jest tylko wnioskowanie na CPU.';

  @override
  String get backend_cpu_desc =>
      'Działa na wszystkich urządzeniach. Najszersza zgodność.';

  @override
  String get backend_gpu_desc =>
      'Przyspieszenie OpenCL. Szybsze na obsługiwanych urządzeniach.';

  @override
  String get backend_npu_desc =>
      'Układ NPU producenta (Qualcomm/MediaTek). Najszybsze wnioskowanie.';

  @override
  String get select_model_title => 'Wybierz model';

  @override
  String get refresh_models => 'Odśwież modele';

  @override
  String get search_models_hint => 'Szukaj modeli…';

  @override
  String get no_server_connected => 'Nie połączono z serwerem';

  @override
  String get add_server_first =>
      'Najpierw dodaj serwer, aby wyświetlić dostępne modele.';

  @override
  String get failed_load_models => 'Nie udało się wczytać modeli';

  @override
  String get no_models_available => 'Brak dostępnych modeli';

  @override
  String no_models_match(String searchQuery) {
    return 'Żaden model nie pasuje do „$searchQuery”';
  }

  @override
  String model_load_failed(String error) {
    return 'Nie udało się załadować modelu: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'Zażądano usunięcia modelu $name z pamięci. Jeśli Ollama jest osiągalna, model zostanie od razu zwolniony.';
  }

  @override
  String model_unloaded_success(String name) {
    return 'Usunięto $name z pamięci';
  }

  @override
  String model_unload_failed(String error) {
    return 'Nie udało się usunąć modelu z pamięci: $error';
  }

  @override
  String get unload_from_server => 'Usuń z pamięci serwera';

  @override
  String context_chip(String ctx) {
    return 'Kontekst: $ctx';
  }

  @override
  String get unload_all_models => 'Usuń wszystkie z pamięci';

  @override
  String loaded_models_count(int count) {
    return 'Załadowano: $count';
  }

  @override
  String get all_models_unloaded => 'Usunięto wszystkie modele z pamięci';

  @override
  String get branch_chat => 'Utwórz odgałęzienie czatu';

  @override
  String get branch_chat_desc => 'Rozpocznij nową rozmowę od tej wiadomości';

  @override
  String get edit_assistant_message_desc =>
      'Edytuj tekst odpowiedzi asystenta.';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Przełącz na $modelName';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Pobieranie $modelName…';
  }

  @override
  String get download_complete_notification => 'Pobieranie zakończone!';

  @override
  String download_complete_body(String modelName) {
    return 'Pobrano model $modelName.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Nie udało się pobrać: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Nie udało się pobrać modelu $modelName.';
  }

  @override
  String get engine_name_system => 'Systemowa synteza mowy';

  @override
  String get engine_tagline_system => 'Silnik wbudowany w urządzenie';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => 'Szybka neuronowa synteza mowy';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'Głosy Piper dostępne offline';

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
  String get voice_lessac => 'Lessac (USA)';

  @override
  String get voice_ryan => 'Ryan (USA)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc =>
      'Najmniejszy uniwersalny model do czatu. Szybko odpowiada i zużywa mało pamięci.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'Dobry kompromis między jakością a rozmiarem. Sprawdza się w codziennych rozmowach.';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Model rozumujący krok po kroku. Najlepszy do zadań logicznych.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'Flagowy model Google. Najwyższa jakość, wyższe wymagania dotyczące pamięci RAM.';

  @override
  String export_header(String date) {
    return '*Wyeksportowano z LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Użytkownik';

  @override
  String get export_role_assistant => '## 🤖 Asystent';

  @override
  String get export_role_system => '## ⚙️ System';

  @override
  String get export_role_tool => '## 🔧 Narzędzie';

  @override
  String get export_text_user => '[UŻYTKOWNIK]';

  @override
  String get export_text_assistant => '[ASYSTENT]';

  @override
  String get export_text_system => '[SYSTEM]';

  @override
  String get export_text_tool => '[NARZĘDZIE]';

  @override
  String get export_label_user => 'UŻYTKOWNIK';

  @override
  String get export_label_assistant => 'ASYSTENT';

  @override
  String get export_label_system => 'SYSTEM';

  @override
  String get export_label_tool => 'NARZĘDZIE';

  @override
  String get select_model_hint => 'Wybierz model, aby rozpocząć czat';

  @override
  String get test_notification_title => 'Powiadomienie testowe';

  @override
  String get test_notification_body =>
      'To powiadomienie testowe o postępie pobierania modelu.';

  @override
  String get tts_supports_background => 'Obsługuje odtwarzanie dźwięku w tle';

  @override
  String get tts_other_services_background_note =>
      'Pozostałe usługi syntezy mowy obsługują odtwarzanie dźwięku w tle.';

  @override
  String get gguf_imported_models_title => 'Zaimportowane modele GGUF';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Zaimportuj plik GGUF z urządzenia lub dodaj go z Hugging Face. Zaimportowane modele działają lokalnie dzięki llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      '— modele gotowe do wnioskowania lokalnego.';

  @override
  String get gguf_curated_models_subtitle =>
      'Wybrane modele, które możesz pobierać i obsługiwać na urządzeniu w LocalMind.';

  @override
  String get gguf_only_supported =>
      'W tym trybie można importować tylko modele GGUF.';

  @override
  String get gguf_imported_from_local_file =>
      'zaimportowano z pliku lokalnego.';

  @override
  String get gguf_import_failed => 'Nie udało się zaimportować modelu GGUF';

  @override
  String get gguf_imported_from_huggingface => 'zaimportowano z Hugging Face.';

  @override
  String get gguf_import_canceled => 'Anulowano import GGUF.';

  @override
  String get gguf_enter_huggingface_url =>
      'Wpisz adres URL pliku GGUF z Hugging Face.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Obsługiwane są tylko oficjalne adresy URL plików GGUF w Hugging Face.';

  @override
  String get gguf_use_https_url =>
      'Do importu GGUF użyj adresu HTTPS z Hugging Face.';

  @override
  String get gguf_url_must_point_to_file =>
      'Adres URL Hugging Face musi wskazywać bezpośrednio plik .gguf.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Nie udało się ustalić nazwy pliku GGUF.';

  @override
  String get gguf_download_empty =>
      'Pobrany plik GGUF jest pusty lub go brakuje.';

  @override
  String get gguf_selected_file_missing => 'Wybrany plik modelu nie istnieje.';

  @override
  String get gguf_import_action => 'Importuj GGUF';

  @override
  String get gguf_overview_title => 'Dodaj lub zaimportuj własne modele';

  @override
  String get gguf_overview_subtitle =>
      'Zaimportuj model GGUF lub LiteRT z pamięci urządzenia lub adresu URL albo wyszukaj go w Hugging Face. Zaimportowane modele pozostają na urządzeniu.';

  @override
  String get gguf_imported_count_label => 'zaimportowano';

  @override
  String get gguf_local_files_label => 'pliki lokalne';

  @override
  String get gguf_huggingface_label => 'Hugging Face';

  @override
  String get gguf_import_local_title => 'Importuj lokalny plik GGUF';

  @override
  String get gguf_import_local_subtitle =>
      'Skopiuj plik .gguf z tego urządzenia';

  @override
  String get gguf_import_huggingface_title => 'Importuj z Hugging Face';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Wklej adres URL pliku GGUF lub ścieżkę repozytorium';

  @override
  String get gguf_no_imported_title => 'Nie zaimportowano jeszcze modeli GGUF';

  @override
  String get gguf_no_imported_subtitle =>
      'Użyj własnego pliku GGUF z pamięci urządzenia lub wklej adres URL z Hugging Face albo ścieżkę repozytorium wskazującą plik .gguf.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Importuj GGUF z Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Wklej bezpośredni adres URL pliku GGUF lub ścieżkę repozytorium Hugging Face, np. owner/repo/blob/main/model.gguf. Łącza typu blob są automatycznie konwertowane.';

  @override
  String get gguf_url_or_repo_path => 'Adres URL GGUF lub ścieżka repozytorium';

  @override
  String get paste => 'Wklej';

  @override
  String get gguf_browse => 'Przeglądaj modele GGUF';

  @override
  String get gguf_huggingface_token_ready => 'Token Hugging Face jest gotowy';

  @override
  String get gguf_huggingface_token_optional =>
      'Token opcjonalny, ale zalecany';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Zapisany token będzie używany automatycznie w przypadku prywatnych repozytoriów lub repozytoriów z ograniczonym dostępem.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Wymaga tokena Hugging Face. Dodaj go w ustawieniach, jeśli ten model GGUF jest prywatny lub ma ograniczony dostęp.';

  @override
  String get gguf_downloading => 'Pobieranie GGUF';

  @override
  String get gguf_preparing => 'Przygotowywanie';

  @override
  String get gguf_preparing_download => 'Przygotowywanie pobierania…';

  @override
  String get gguf_cancel_import => 'Anuluj import';

  @override
  String get clipboard_empty => 'Schowek jest pusty.';

  @override
  String get could_not_open_huggingface =>
      'Nie udało się otworzyć Hugging Face.';

  @override
  String get gguf_paste_url_error =>
      'Wklej adres URL pliku GGUF z Hugging Face lub ścieżkę repozytorium.';

  @override
  String get gguf_blob_link => 'Łącze typu blob';

  @override
  String get gguf_repository_label => 'Repozytorium';

  @override
  String get gguf_detected_path_label => 'Wykryta ścieżka';

  @override
  String get gguf_imported_section_label => 'Zaimportowane GGUF';

  @override
  String get gguf_already_available => 'Już dostępny na tym urządzeniu';

  @override
  String get gguf_curated_models_short => 'Wybrane modele na urządzeniu';

  @override
  String get gguf_vision_projector => 'Projektor obrazu';

  @override
  String get gguf_attach_projector => 'Dołącz projektor obrazu';

  @override
  String get gguf_change_projector => 'Zmień projektor obrazu';

  @override
  String get gguf_remove_projector => 'Usuń projektor';

  @override
  String get gguf_projector_attached => 'Dołączono projektor obrazu';

  @override
  String get gguf_projector_removed => 'Usunięto projektor obrazu';

  @override
  String gguf_projector_auto_detected(String name) {
    return 'Automatycznie wykryto i połączono projektor obrazu: $name';
  }

  @override
  String get gguf_is_projector_file =>
      'Wybrany plik to projektor obrazu (mmproj), a nie samodzielny model.';

  @override
  String get gguf_projector_url_label =>
      'Adres URL projektora obrazu (opcjonalny mmproj)';

  @override
  String get gguf_projector_url_hint =>
      'https://huggingface.co/.../mmproj-...gguf';

  @override
  String get gguf_vision_not_supported_error =>
      'Aktywny model nie obsługuje załączników graficznych. Dołącz projektor obrazu (mmproj) lub wybierz model obsługujący obrazy.';

  @override
  String get execute_tool_title => 'Uruchom narzędzie';

  @override
  String get execute_tool_request_desc =>
      'Model prosi o uruchomienie tego narzędzia:';

  @override
  String get reject => 'Odrzuć';

  @override
  String get approve => 'Zatwierdź';

  @override
  String get server_type_help =>
      'Wybierz dostawcę przed wpisaniem danych połączenia.';

  @override
  String get server_identity_title => 'Dane serwera';

  @override
  String get server_identity_desc =>
      'Nadaj nazwę serwerowi i wybierz jego wygląd na liście.';

  @override
  String get server_connection_title => 'Połączenie';

  @override
  String get server_connection_desc =>
      'Użyj adresu i portu udostępnianych przez serwer.';

  @override
  String get server_authentication_title => 'Uwierzytelnianie';

  @override
  String get server_authentication_required_desc =>
      'Aby sprawdzić połączenie z OpenRouter, podaj klucz API.';

  @override
  String get server_authentication_required_desc_requesty =>
      'Aby sprawdzić połączenie z Requesty, podaj klucz API.';

  @override
  String get server_authentication_required_desc_standard_compute =>
      'Aby sprawdzić połączenie ze Standard Compute, podaj klucz API.';

  @override
  String get server_authentication_optional_desc =>
      'Jeśli serwer nie wymaga klucza API, pozostaw to pole puste.';

  @override
  String get mcp_tools_title => 'Narzędzia MCP';

  @override
  String get available_tools => 'Dostępne narzędzia';

  @override
  String get unable_load_tools => 'Nie udało się wczytać narzędzi';

  @override
  String get no_tools_registered => 'Nie zarejestrowano narzędzi';

  @override
  String get no_tools_registered_desc =>
      'Włącz przykładowy serwer MCP lub dodaj integracje MCP w ustawieniach czatu.';

  @override
  String get example_mcp_server_title => 'Przykładowy serwer MCP';

  @override
  String get example_mcp_server_desc =>
      'Rejestruje example.echo i example.word_count przez tego samego dostawcę narzędzi MCP, z którego korzystają serwery zewnętrzne.';

  @override
  String get disable_example_server => 'Wyłącz przykładowy serwer';

  @override
  String get enable_example_server => 'Włącz przykładowy serwer';

  @override
  String get built_in_label => 'Wbudowane';

  @override
  String get highlights_label => 'Najważniejsze cechy';

  @override
  String get built_with_label => 'Wykorzystane technologie';

  @override
  String get local_label => 'Lokalne';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => 'Zażądano';

  @override
  String get tool_status_approved => 'Zatwierdzono';

  @override
  String get tool_status_rejected => 'Odrzucono';

  @override
  String get tool_status_running => 'W toku';

  @override
  String get tool_status_done => 'Gotowe';

  @override
  String get tool_status_failed => 'Niepowodzenie';

  @override
  String get model_favorite_toggle => 'Dodaj do ulubionych lub usuń';

  @override
  String get model_set_default => 'Ustaw jako model domyślny';

  @override
  String get model_clear_default => 'Zrezygnuj z tego modelu jako domyślnego';

  @override
  String get model_default_badge => 'Domyślne';

  @override
  String get model_note_label => 'Notatka';

  @override
  String get model_note_hint => 'Dodaj notatkę o tym modelu…';

  @override
  String get model_update_available => 'Dostępna aktualizacja';

  @override
  String get model_update_button => 'Zaktualizuj';

  @override
  String get unload_models_before_load =>
      'Usuń wszystkie modele z pamięci przed załadowaniem nowego';

  @override
  String get settings_allow_background_downloads =>
      'Zezwalaj na pobieranie w tle';

  @override
  String get settings_allow_background_downloads_desc =>
      'Kontynuuj pobieranie modeli nawet po przełączeniu aplikacji lub zablokowaniu ekranu.';

  @override
  String get settings_download_over_wifi_only => 'Pobieraj tylko przez Wi‑Fi';

  @override
  String get settings_download_over_wifi_only_desc =>
      'Pobieraj modele tylko wtedy, gdy dostępne jest odpowiednie połączenie Wi‑Fi lub połączenie bez limitu danych.';

  @override
  String get temp_chat_keyboard_incognito =>
      'Klawiatura incognito w czacie tymczasowym';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Wyłącza uczenie się i sugestie klawiatury w czatach tymczasowych (np. tryb incognito SwiftKey).';

  @override
  String get resume_last_chat => 'Wznawiaj ostatni czat po uruchomieniu';

  @override
  String get resume_last_chat_desc =>
      'Przywróć ostatnią otwartą rozmowę po ponownym otwarciu aplikacji.';

  @override
  String get export_all_data => 'Eksportuj wszystkie dane';

  @override
  String get import_all_data => 'Importuj wszystkie dane';

  @override
  String get export_data_success => 'Wyeksportowano kopię zapasową';

  @override
  String get import_data_success => 'Zaimportowano kopię zapasową';

  @override
  String import_data_failed(String error) {
    return 'Nie udało się zaimportować kopii zapasowej: $error';
  }

  @override
  String get import_data_confirm =>
      'Zaimportować rozmowy i własne postacie z tej kopii zapasowej? Istniejące elementy o tych samych identyfikatorach zostaną zaktualizowane.';

  @override
  String get import_settings_confirm =>
      'Zastąpić bieżące ustawienia tymi z kopii zapasowej?';

  @override
  String get export_conversations => 'Eksportuj rozmowy';

  @override
  String get import_conversations => 'Importuj rozmowy';

  @override
  String get export_personas => 'Eksportuj postacie';

  @override
  String get import_personas => 'Importuj postacie';

  @override
  String get export_settings => 'Eksportuj ustawienia';

  @override
  String get import_settings => 'Importuj ustawienia';

  @override
  String get export_all_zip => 'Eksportuj wszystko (ZIP)';

  @override
  String get import_all_zip => 'Importuj wszystko (ZIP)';

  @override
  String get duplicate_chat => 'Powiel czat';

  @override
  String get duplicate_chat_success => 'Powielono czat';

  @override
  String get move_to_folder => 'Przenieś do folderu';

  @override
  String get remove_from_folder => 'Usuń z folderu';

  @override
  String get create_folder => 'Utwórz folder';

  @override
  String get new_folder => 'Nowy folder';

  @override
  String get folder_name_hint => 'Nazwa folderu';

  @override
  String get all_chats => 'Wszystkie';

  @override
  String get unfiled_chats => 'Bez folderu';

  @override
  String get create => 'Utwórz';

  @override
  String get server_path_prefix_label => 'Prefiks ścieżki API';

  @override
  String get server_path_prefix_hint => '/your-secret-token';

  @override
  String get search_message_contents => 'Szukaj w treści wiadomości';

  @override
  String get message_search_results => 'Pasujące wiadomości';

  @override
  String get saved_messages_title => 'Zapisane wiadomości';

  @override
  String get nav_saved_messages => 'Zapisane wiadomości';

  @override
  String get saved_messages_empty =>
      'Nie ma jeszcze zapisanych wiadomości. Zapisz wiadomość z jej menu opcji.';

  @override
  String get save_message => 'Zapisz wiadomość';

  @override
  String get message_saved => 'Zapisano wiadomość';

  @override
  String token_count(int count) {
    return 'Tokeny: $count';
  }

  @override
  String estimated_token_count(int count) {
    return 'Około $count tokenów';
  }

  @override
  String get test_tts_section_title => 'Przetestuj głos';

  @override
  String get test_tts_hint =>
      'Wpisz tekst, aby usłyszeć obecny głos syntezatora…';

  @override
  String get test_speak_button => 'Przeczytaj';

  @override
  String get scroll_to_bottom => 'Przewiń na dół';

  @override
  String get generate_ai_response => 'Wygeneruj odpowiedź AI';

  @override
  String get no_response => 'Brak odpowiedzi';

  @override
  String get export => 'Eksportuj';

  @override
  String get import => 'Importuj';

  @override
  String get conversations_label => 'Rozmowy';

  @override
  String get personas_label => 'Postacie';

  @override
  String get settings_label => 'Ustawienia';

  @override
  String get export_conversation => 'Eksportuj rozmowę';

  @override
  String get tts_process_markdown => 'Usuń znaczniki Markdown przy czytaniu';

  @override
  String get tts_process_markdown_desc =>
      'Usuwa formatowanie, np. **pogrubienie**, przed odczytaniem na głos';

  @override
  String get tts_skip_seconds => 'Czas przewijania';

  @override
  String get tts_skip_seconds_desc =>
      'Czas przeskoku do przodu lub do tyłu podczas odtwarzania';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '$seconds s';
  }

  @override
  String get preview_system_prompts => 'Podgląd poleceń systemowych';

  @override
  String get welcome_message_1 => 'W czym mogę Ci dzisiaj pomóc?';

  @override
  String get welcome_message_2 =>
      'Zapytaj o cokolwiek. Zaczniemy, gdy zechcesz.';

  @override
  String get welcome_message_3 =>
      'Twoje dane są przetwarzane lokalnie i nie opuszczają urządzenia.';

  @override
  String get welcome_message_4 =>
      'Szukasz pomysłu? Wypróbuj jedno z gotowych poleceń.';

  @override
  String get temporary_chat => 'Czat tymczasowy';

  @override
  String get temporary_chat_desc => 'Rozmowy nie są zapisywane w historii.';

  @override
  String get temporary_chat_banner => 'Czat tymczasowy · bez zapisu w historii';

  @override
  String get temporary_chat_save_warning_title =>
      'Zapisać wiadomość z czatu tymczasowego?';

  @override
  String get temporary_chat_save_warning_body =>
      'Ten czat jest tymczasowy i nie pojawia się w historii. Wiadomość znajdziesz w zapisanych wiadomościach.';

  @override
  String get save_to_history => 'Zapisz w historii';

  @override
  String get share_conversation => 'Udostępnij rozmowę';

  @override
  String get download_tts_audio => 'Pobierz dźwięk';

  @override
  String get tts_download_unavailable =>
      'Pobieranie jest dostępne tylko dla Piper i Kitten TTS';

  @override
  String get tts_download_no_audio => 'Nie ma jeszcze dźwięku do pobrania';

  @override
  String get tts_download_success => 'Zapisano dźwięk';

  @override
  String get return_to_chat => 'Wróć do czatu';

  @override
  String get return_to_temp_chat => 'Wróć do czatu tymczasowego';

  @override
  String get insert_saved_message => 'Wstaw zapisaną wiadomość';

  @override
  String get insert_saved_message_desc =>
      'Wybierz zapisaną wiadomość, aby dodać ją do pola tekstowego';

  @override
  String get model_info => 'Informacje o modelu';

  @override
  String get model_name => 'Nazwa modelu';

  @override
  String get model_identifier => 'Identyfikator';

  @override
  String get model_capabilities => 'Możliwości';

  @override
  String get model_api_pricing => 'Ceny API (za 1 mln tokenów)';

  @override
  String get not_available => 'Niedostępne';

  @override
  String get save_message_folders => 'Zapisz wiadomość';

  @override
  String get remove_from_saved => 'Usuń z zapisanych';

  @override
  String get message_already_saved => 'Zapisano';

  @override
  String get stream_ttft => 'Czas do pierwszego tokena';

  @override
  String get stream_tokens_per_sec => 'Tokeny na sekundę';

  @override
  String get stream_stop_reason => 'Powód zakończenia';

  @override
  String get stream_input_tokens => 'Tokeny wejściowe';

  @override
  String get stream_output_tokens => 'Tokeny wyjściowe';

  @override
  String get stream_generation_time => 'Czas generowania';

  @override
  String get attach_image => 'Zdjęcia';

  @override
  String get attach_text_document => 'Dokumenty';

  @override
  String get attach_shortcut_camera => 'Aparat';

  @override
  String get attach_shortcut_images => 'Zdjęcia';

  @override
  String get attach_shortcut_documents => 'Pliki';

  @override
  String get attach_shortcut_saved => 'Zapisano';

  @override
  String get add_attachment => 'Dodaj załącznik';

  @override
  String get add_to_chat => 'Dodaj do czatu';

  @override
  String get choose_what_to_attach => 'Co chcesz dodać?';

  @override
  String get choose_attachment_subtitle =>
      'Wybierz źródło załącznika do wiadomości';

  @override
  String get photo_permission_denied =>
      'Aby załączyć obrazy, zezwól na dostęp do zdjęć';

  @override
  String get select_model_prompt => 'Wybierz model';

  @override
  String get characters_label => 'Znaki';

  @override
  String get exit_temporary_chat_title => 'Opuścić czat tymczasowy?';

  @override
  String get exit_temporary_chat_body =>
      'Spowoduje to porzucenie bieżącego czatu tymczasowego i otwarcie nowego czatu.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Tę wiadomość zapisano z czatu tymczasowego. Nie można jej otworzyć w pierwotnej rozmowie.';

  @override
  String get filter_title => 'Filtruj';

  @override
  String get filter_pinned => 'Przypięte';

  @override
  String get filter_archived => 'Zarchiwizowane';

  @override
  String get filter_temp_chats => 'Czaty tymczasowe';

  @override
  String get filter_user_messages => 'Wiadomości użytkownika';

  @override
  String get filter_assistant_messages => 'Wiadomości asystenta';

  @override
  String get archive_chat => 'Archiwizuj';

  @override
  String get unarchive_chat => 'Przywróć z archiwum';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wiadomości',
      many: '$count wiadomości',
      few: '$count wiadomości',
      one: '1 wiadomość',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return '$count zn.';
  }

  @override
  String get generate_title_with_ai => 'Wygeneruj za pomocą AI';

  @override
  String get generating_title => 'Generowanie…';

  @override
  String get generate_title_failed => 'Nie udało się wygenerować tytułu';

  @override
  String get lm_studio_model_browser_title => 'Przeglądaj modele';

  @override
  String get lm_studio_model_search_hint =>
      'Szukaj modeli według nazwy lub autora…';

  @override
  String get lm_studio_staff_picks => 'Polecane przez zespół';

  @override
  String get lm_studio_community_models => 'Modele społeczności';

  @override
  String get lm_studio_no_models => 'Nie znaleziono modeli';

  @override
  String lm_studio_models_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count modelu',
      many: '$count modeli',
      few: '$count modele',
      one: '1 model',
    );
    return '$_temp0';
  }

  @override
  String get lm_studio_browse_models => 'Przeglądaj i pobieraj';

  @override
  String get lm_studio_model_search => 'Wyszukiwanie modeli LMS';

  @override
  String get lm_studio_downloads_title => 'Pobrane pliki';

  @override
  String get lm_studio_choose_quant => 'Wybierz wariant do pobrania';

  @override
  String get lm_studio_use_default_quant => 'Użyj wartości domyślnej';

  @override
  String get lm_studio_recommended => 'Zalecane';

  @override
  String get lm_studio_clear_downloads => 'Wyczyść ukończone';

  @override
  String get lm_studio_no_downloads => 'Nie ma jeszcze pobrań';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Pobieranie odbywa się na hoście LM Studio. Wstrzymywanie, zatrzymywanie i usuwanie modeli jest możliwe tylko na tym komputerze.';

  @override
  String get lm_studio_staff_pick => 'Wybór zespołu';

  @override
  String get lm_studio_params => 'PARAMETRY';

  @override
  String get lm_studio_arch => 'ARCHITEKTURA';

  @override
  String get lm_studio_domain => 'DZIEDZINA';

  @override
  String get lm_studio_format => 'FORMAT';

  @override
  String get lm_studio_vision => 'Obsługa obrazów';

  @override
  String get lm_studio_tool_use => 'Używanie narzędzi';

  @override
  String get lm_studio_reasoning => 'Rozumowanie';

  @override
  String get openrouter_pricing_free => 'Bezpłatny';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Wejście $input / wyjście $output za 1 mln tokenów';
  }

  @override
  String get lm_studio_download_options => 'Opcje pobierania';

  @override
  String get lm_studio_download => 'Pobierz';

  @override
  String lm_studio_download_size(String size) {
    return 'Pobierz ($size)';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Pobieranie: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'Plik README jest niedostępny dla tego modelu.';

  @override
  String get lm_studio_full_gpu_offload =>
      'Możliwe pełne przeniesienie obliczeń na GPU';

  @override
  String get lm_studio_partial_gpu_offload =>
      'Możliwe częściowe przeniesienie obliczeń na GPU';

  @override
  String get lm_studio_likely_too_large => 'Prawdopodobnie za duży';

  @override
  String get lm_studio_available_ram_gb =>
      'Dostępna pamięć RAM (GB, opcjonalnie)';

  @override
  String get lm_studio_available_vram_gb =>
      'Dostępna pamięć VRAM (GB, opcjonalnie)';

  @override
  String get lm_studio_memory_settings_title =>
      'Pamięć uwzględniana przy rekomendacjach';

  @override
  String get lm_studio_memory_settings_desc =>
      'Służy do oceny, czy modele z przeglądarki zmieszczą się w pamięci komputera.';

  @override
  String get think_button_label => 'Rozumuj';

  @override
  String get thinking_mode_title => 'Tryb rozumowania';

  @override
  String get reasoning_effort_low => 'Niski';

  @override
  String get reasoning_effort_medium => 'Średni';

  @override
  String get reasoning_effort_high => 'Wysoki';

  @override
  String get reasoning_effort_minimal => 'Minimalny';

  @override
  String get reasoning_effort_xhigh => 'Bardzo wysoki';

  @override
  String get reasoning_effort_max => 'Maksymalny';

  @override
  String get reasoning_effort_off => 'Wył.';

  @override
  String get could_not_read_file => 'Nie udało się odczytać pliku';

  @override
  String get server_offline => 'Serwer jest offline';

  @override
  String get could_not_establish_connection =>
      'Nie udało się nawiązać połączenia z serwerem. Sprawdź, czy serwer działa i czy ustawienia hosta oraz portu są poprawne.';

  @override
  String get retry_connection => 'Ponów połączenie';

  @override
  String get tokens_label => 'Tokeny';

  @override
  String get enter_context_length => 'Wpisz długość kontekstu…';

  @override
  String get openrouter_disclosure =>
      'Po połączeniu z tym dostawcą wiadomości i dane wejściowe będą wysyłane na jego serwery. LocalMind nie śledzi ani nie przechowuje Twoich rozmów.';

  @override
  String get requesty_disclosure =>
      'Po połączeniu z tym dostawcą wiadomości i dane wejściowe będą wysyłane na jego serwery. LocalMind nie śledzi ani nie przechowuje Twoich rozmów.';

  @override
  String get standard_compute_disclosure =>
      'Po połączeniu z tym dostawcą wiadomości i dane wejściowe będą wysyłane na jego serwery. LocalMind nie śledzi ani nie przechowuje Twoich rozmów.';

  @override
  String get welcome_message_cloud =>
      'Wiadomości są wysyłane do połączonego dostawcy.';

  @override
  String get privacy_policy => 'Polityka prywatności';

  @override
  String get cloud_sync => 'Synchronizacja S3';

  @override
  String get cloud_sync_description =>
      'Synchronizacja z własnym serwerem zgodnym z S3, z szyfrowaniem od końca do końca';

  @override
  String get cloud_sync_endpoint => 'Adres URL punktu końcowego';

  @override
  String get cloud_sync_bucket => 'Zasobnik';

  @override
  String get cloud_sync_region => 'Region';

  @override
  String get cloud_sync_prefix => 'Prefiks';

  @override
  String get cloud_sync_access_key => 'Identyfikator klucza dostępu';

  @override
  String get cloud_sync_secret_key => 'Tajny klucz dostępu';

  @override
  String get cloud_sync_session_token => 'Token sesji (opcjonalnie)';

  @override
  String get cloud_sync_passphrase => 'Hasło szyfrowania';

  @override
  String get cloud_sync_confirm_passphrase => 'Potwierdź hasło szyfrowania';

  @override
  String get cloud_sync_path_style => 'Użyj adresowania w stylu ścieżki';

  @override
  String get cloud_sync_allow_http => 'Zezwól na niezabezpieczony HTTP';

  @override
  String get cloud_sync_http_warning =>
      'Protokół HTTP ujawnia w sieci metadane żądań i dane uwierzytelniające. Używaj go tylko z zaufanym lokalnym serwerem S3.';

  @override
  String get cloud_sync_test => 'Sprawdź połączenie';

  @override
  String get cloud_sync_enable => 'Włącz szyfrowaną synchronizację';

  @override
  String get cloud_sync_now => 'Synchronizuj teraz';

  @override
  String get cloud_sync_disconnect => 'Odłącz to urządzenie';

  @override
  String get cloud_sync_last_synced => 'Ostatnia synchronizacja';

  @override
  String get cloud_sync_never => 'Nigdy';

  @override
  String get cloud_sync_conflicts => 'Zachowano wersje w konflikcie';

  @override
  String get cloud_sync_passphrase_mismatch => 'Hasła szyfrowania są różne';

  @override
  String get crash_report_title => 'Coś poszło nie tak';

  @override
  String get crash_report_stack_trace => 'Ślad stosu';

  @override
  String get crash_report_tap_to_expand => 'Dotknij, aby rozwinąć';

  @override
  String get crash_report_button => 'Zgłoś tę awarię';

  @override
  String get crash_try_again => 'Spróbuj ponownie';

  @override
  String get crash_report_empty_stack => '<pusto>';

  @override
  String get crash_report_disclaimer =>
      'Zgłoszenie otwiera GitHuba ze wstępnie wypełnionymi danymi diagnostycznymi. Nic nie zostanie przesłane automatycznie. Sprawdź treść i usuń poufne informacje przed wysłaniem.';

  @override
  String get crash_report_copied => 'Skopiowano do schowka';

  @override
  String get report_a_problem => 'Zgłoś problem';

  @override
  String get rename_folder => 'Zmień nazwę folderu';

  @override
  String get delete_folder => 'Usuń folder';

  @override
  String get delete_folder_title => 'Usunąć folder?';

  @override
  String delete_folder_body(String name) {
    return 'Czy na pewno chcesz usunąć „$name”? Rozmowy i zapisane wiadomości z folderu trafią z powrotem do sekcji „Bez folderu”. Tej czynności nie można cofnąć.';
  }

  @override
  String get folder_name_required => 'Wpisz nazwę folderu';

  @override
  String get model_required_toast => 'Najpierw wybierz model';

  @override
  String get settings_concise_voice_responses =>
      'Zwięzłe odpowiedzi w trybie głosowym';

  @override
  String get settings_concise_voice_responses_desc =>
      'W trybie głosowym model odpowiada krótko (jeden zwięzły akapit) i zadaje pytania uzupełniające.';

  @override
  String get s3_connection_succeeded => 'Połączono z S3.';

  @override
  String failed_to_open_url(String error) {
    return 'Nie udało się otworzyć adresu URL: $error';
  }

  @override
  String failed_to_copy(String error) {
    return 'Nie udało się skopiować: $error';
  }

  @override
  String get file_explorer_not_found =>
      'Nie znaleziono menedżera plików. Upewnij się, że na urządzeniu zainstalowano i włączono aplikację do zarządzania plikami.';

  @override
  String export_data_failed(String error) {
    return 'Nie udało się wyeksportować kopii zapasowej: $error';
  }

  @override
  String file_pick_failed(String error) {
    return 'Nie udało się wybrać pliku: $error';
  }

  @override
  String image_pick_failed(String error) {
    return 'Nie udało się wybrać obrazu: $error';
  }

  @override
  String get calendar_access => 'Dostęp do kalendarza';

  @override
  String get calendar_access_desc =>
      'Zezwól AI na odczytywanie i tworzenie wydarzeń w kalendarzu';

  @override
  String get calendar_permission_denied =>
      'Odmówiono dostępu do kalendarza. Zezwól na dostęp w ustawieniach urządzenia.';

  @override
  String get location_access => 'Dostęp do lokalizacji';

  @override
  String get location_access_desc =>
      'Zezwól AI na pobieranie bieżącej lokalizacji i nazwy miejsca';

  @override
  String get location_permission_denied =>
      'Odmówiono dostępu do lokalizacji. Zezwól na dostęp w ustawieniach urządzenia.';

  @override
  String get builtin_ai_not_supported =>
      'To urządzenie nie obsługuje wbudowanej AI.';

  @override
  String get builtin_ai_unsupported_desc =>
      'Sprzęt lub system operacyjny nie obsługuje systemowej AI na urządzeniu (np. Gemini Nano lub Apple Intelligence). Wybierz model dostępny do pobrania.';

  @override
  String get builtin_ai_unsupported_chip => 'Nieobsługiwane';

  @override
  String get builtin_ai_enable => 'Włącz';

  @override
  String get model_reasoning_default => 'Domyślne ustawienie modelu';

  @override
  String get model_reasoning_on => 'Wł.';

  @override
  String get model_reasoning_help =>
      'Dotyczy następnej odpowiedzi. Opcja „Wył.” wyłącza rozumowanie, jeśli szablon czatu modelu to obsługuje.';

  @override
  String get model_reasoning_save_error =>
      'Nie udało się zapisać trybu rozumowania. Spróbuj ponownie.';

  @override
  String get on_device_engine_failed_error =>
      'Model na urządzeniu przestał odpowiadać. Zwykle dzieje się tak, gdy rozmowa przekroczy okno kontekstu. Model jest ładowany ponownie. Spróbuj ponownie, rozpocznij nowy czat lub zwiększ długość kontekstu w ustawieniach.';

  @override
  String get stt_error_no_match =>
      'Nie rozpoznano mowy. Dotknij, aby spróbować ponownie.';

  @override
  String get stt_error_speech_timeout =>
      'Nie wykryto mowy. Dotknij, aby spróbować ponownie.';

  @override
  String get stt_error_permission => 'Odmówiono dostępu do mikrofonu.';

  @override
  String get stt_error_busy =>
      'Usługa rozpoznawania mowy jest zajęta. Spróbuj ponownie.';

  @override
  String get stt_error_network =>
      'Błąd sieci. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get stt_error_audio => 'Błąd nagrywania dźwięku. Sprawdź mikrofon.';

  @override
  String get stt_error_client =>
      'Nie udało się uruchomić usługi rozpoznawania mowy. Upewnij się, że zainstalowano aplikację do wprowadzania głosowego i ustawiono ją jako domyślną usługę rozpoznawania mowy, a następnie spróbuj ponownie.';

  @override
  String get stt_error_language =>
      'Usługa rozpoznawania mowy na tym urządzeniu nie obsługuje Twojego języka.';

  @override
  String get stt_error_unavailable =>
      'Na urządzeniu nie znaleziono usługi rozpoznawania mowy. Zainstaluj aplikację do wprowadzania głosowego (np. FUTO Voice Input) i ustaw ją jako domyślną usługę rozpoznawania mowy.';

  @override
  String stt_error_generic(String code) {
    return 'Błąd rozpoznawania mowy: $code';
  }

  @override
  String get send_temperature_to_api => 'Wysyłaj temperaturę';

  @override
  String get send_top_p_to_api => 'Wysyłaj Top P';

  @override
  String get send_sampling_params_desc =>
      'Wyłącz tę opcję dla dostawców lub modeli odrzucających ten parametr (np. niektórych modeli rozumujących). Dotyczy wszystkich czatów z serwerami zdalnymi.';

  @override
  String get default_system_prompt => 'Domyślne polecenie systemowe';

  @override
  String get default_system_prompt_desc =>
      'Używane w czatach bez postaci i bez własnego polecenia systemowego.';

  @override
  String get default_system_prompt_hint => 'Jesteś pomocnym asystentem…';

  @override
  String background_generation_notice(String title) {
    return 'W czacie „$title” nadal powstaje odpowiedź. Po jej zakończeniu możesz wysłać wiadomość tutaj. Dotknij, aby otworzyć czat.';
  }

  @override
  String get background_generation_notice_untitled =>
      'W innym czacie nadal powstaje odpowiedź. Po jej zakończeniu możesz wysłać wiadomość tutaj. Dotknij, aby otworzyć czat.';

  @override
  String background_generation_notice_info(String title) {
    return 'W czacie „$title” powstaje odpowiedź w tle. Dotknij, aby go otworzyć.';
  }

  @override
  String get background_generation_notice_info_untitled =>
      'W innym czacie powstaje odpowiedź w tle. Dotknij, aby go otworzyć.';

  @override
  String background_generation_notice_multiple(int count) {
    return 'Czaty z odpowiedzią generowaną w tle: $count.';
  }

  @override
  String get background_generation_chat_untitled => 'Czat bez tytułu';

  @override
  String get model_loaded_status => 'Załadowano';

  @override
  String get new_chat_title => 'Zapytaj o cokolwiek.';

  @override
  String get new_chat_on_device_headline =>
      'Wszystko pozostaje na tym telefonie.';

  @override
  String get new_chat_on_device_detail =>
      'Odpowiedzi powstają na urządzeniu. Bez wysyłania danych i bez konta, także offline.';

  @override
  String new_chat_self_hosted_headline(String server) {
    return 'Odpowiedzi z $server.';
  }

  @override
  String get new_chat_self_hosted_detail =>
      'Wiadomości trafiają wyłącznie na Twój serwer.';

  @override
  String new_chat_endpoint_detail(String server) {
    return 'Wiadomości są wysyłane do $server, punktu końcowego zgodnego z OpenAI.';
  }

  @override
  String get new_chat_cloud_headline => 'Odpowiedzi z chmury.';

  @override
  String new_chat_router_detail(String provider) {
    return 'Wiadomości są wysyłane do $provider oraz do dostawcy modelu wybranego przez tę usługę.';
  }

  @override
  String get new_chat_ollama_cloud_detail =>
      'Wiadomości są wysyłane do usługi chmurowej Ollama.';

  @override
  String get new_chat_no_server_headline => 'Wybierz model, aby zacząć.';

  @override
  String get new_chat_no_server_detail =>
      'Uruchom model na tym telefonie lub połącz się z serwerem.';

  @override
  String get new_chat_works_offline => 'Działa offline';

  @override
  String get new_chat_no_model => 'Nie wybrano modelu';

  @override
  String get new_chat_not_connected => 'Brak połączenia';

  @override
  String get attach_send_as_assistant => 'Wyślij jako asystent';

  @override
  String get attach_send_as_assistant_desc =>
      'Dodaje wiadomość jako odpowiedź bez generowania nowej treści.';

  @override
  String get chat_input_hint_assistant => 'Napisz odpowiedź asystenta';

  @override
  String get settings_section_general => 'Ogólne';

  @override
  String get settings_section_chat => 'Czat';

  @override
  String get settings_section_voice => 'Głos';

  @override
  String get settings_section_models => 'Modele';

  @override
  String get settings_section_data => 'Prywatność i dane';

  @override
  String get settings_search_hint => 'Szukaj w ustawieniach';

  @override
  String get settings_more_chat_options => 'Więcej opcji czatu';

  @override
  String get settings_group_replies => 'Odpowiedzi';

  @override
  String get settings_group_prompt => 'Polecenie systemowe i parametry';

  @override
  String get settings_group_composer => 'Pole wiadomości';

  @override
  String get sidebar_section_chats => 'Czaty';

  @override
  String get sidebar_section_models => 'Modele';

  @override
  String get sidebar_section_app => 'Aplikacja';

  @override
  String get add_models_button => 'Dodaj modele';

  @override
  String get curated_models_title => 'Polecane modele';

  @override
  String curated_models_count(Object count) {
    return 'Modele: $count';
  }

  @override
  String get your_models_title => 'Twoje modele';

  @override
  String your_models_count(Object count) {
    return 'Dodano: $count';
  }

  @override
  String get remove_model_from_list => 'Usuń z listy';

  @override
  String get delete_model_file_first => 'Najpierw usuń plik modelu';

  @override
  String get add_model_title => 'Dodaj model';

  @override
  String get add_model_gguf_tab => 'GGUF';

  @override
  String get add_model_litert_tab => 'LiteRT';

  @override
  String get add_model_gguf_url_label => 'Adres URL GGUF z Hugging Face';

  @override
  String get add_model_litert_url_label => 'Adres URL LiteRT z Hugging Face';

  @override
  String get add_model_add_from_url => 'Dodaj z adresu URL';

  @override
  String get add_model_pick_local_file => 'Wybierz plik lokalny';

  @override
  String get add_model_search_gguf => 'Szukaj modeli GGUF';

  @override
  String get add_model_search_litert => 'Szukaj modeli LiteRT';

  @override
  String get add_model_searching => 'Wyszukiwanie…';

  @override
  String get add_model_search => 'Szukaj';

  @override
  String get add_model_loading_files => 'Wczytywanie plików…';

  @override
  String get add_model_cancel => 'Anuluj';

  @override
  String add_model_files_in(Object repo) {
    return 'Pliki w $repo';
  }

  @override
  String get add_model_no_gguf_files => 'Nie znaleziono plików GGUF.';

  @override
  String get add_model_no_litert_files => 'Nie znaleziono plików LiteRT.';

  @override
  String get add_model_added => 'Dodano';

  @override
  String get add_model_add => 'Dodaj';

  @override
  String get add_model_gguf_added => 'Dodano model GGUF';

  @override
  String get add_model_litert_added => 'Dodano model LiteRT';

  @override
  String add_model_file_added(Object name) {
    return 'Dodano $name';
  }

  @override
  String get add_model_already_added => 'Model został już dodany';

  @override
  String get model_still_stopping =>
      'Model nadal się zatrzymuje. Poczekaj chwilę i spróbuj ponownie.';

  @override
  String get localApiTitle => 'Lokalne API';

  @override
  String get localApiIntro =>
      'Używaj załadowanego modelu w innych aplikacjach przez API zgodne z OpenAI. Uruchom serwer przed przełączeniem aplikacji.';

  @override
  String get localApiRunning => 'Lokalne API działa';

  @override
  String get localApiStopped => 'Serwer zatrzymany';

  @override
  String get localApiStarting => 'Uruchamianie serwera…';

  @override
  String get localApiStopping => 'Zatrzymywanie serwera…';

  @override
  String get localApiRotating => 'Wymiana klucza API…';

  @override
  String get localApiModelRequired =>
      'Najpierw załaduj pobrany model LiteRT lub zaimportowany model GGUF.';

  @override
  String get localApiInvalidPort => 'Wpisz numer portu od 1024 do 65535.';

  @override
  String get localApiStartFailed =>
      'Android nie mógł uruchomić serwera. Spróbuj ponownie, gdy LocalMind jest otwarty.';

  @override
  String get localApiPortUnavailable =>
      'Nie można nasłuchiwać na tym porcie. Użyj innego portu.';

  @override
  String get localApiKeyFailed =>
      'Nie udało się uzyskać dostępu do klucza API.';

  @override
  String get localApiModelId => 'Identyfikator modelu';

  @override
  String get localApiTextAndTools => 'Tekst i wywołania narzędzi';

  @override
  String get localApiTextOnly => 'Tylko tekst';

  @override
  String get localApiPort => 'Port';

  @override
  String get localApiLan =>
      'Zezwól na dostęp innym urządzeniom w sieci lokalnej';

  @override
  String get localApiLanHint =>
      'Używaj tylko w zaufanej sieci. HTTP nie szyfruje poleceń ani klucza API.';

  @override
  String get localApiStart => 'Uruchom serwer';

  @override
  String get localApiStop => 'Zatrzymaj serwer';

  @override
  String get localApiUrl => 'Bazowy adres URL na tym urządzeniu';

  @override
  String get localApiLanUrl => 'Bazowy adres URL w sieci lokalnej';

  @override
  String get localApiNoLan => 'Brak dostępnego adresu w sieci lokalnej.';

  @override
  String get localApiKey => 'Klucz API';

  @override
  String get localApiShowKey => 'Pokaż klucz API';

  @override
  String get localApiHideKey => 'Ukryj klucz API';

  @override
  String get localApiRotateKey => 'Wymień klucz API';

  @override
  String get localApiRotateHint =>
      'Obecny klucz przestanie działać. Zaktualizuj klucz w połączonych aplikacjach.';

  @override
  String localApiCopy(String label) {
    return 'Skopiuj $label';
  }

  @override
  String get localApiCopied => 'Skopiowano do schowka';

  @override
  String get image_generation => 'Generowanie obrazów';

  @override
  String get image_model_ids => 'Identyfikatory modeli obrazów';

  @override
  String get image_model_ids_hint =>
      'Wpisz własne identyfikatory, oddzielając je przecinkami lub znakami nowego wiersza.';

  @override
  String get image_generation_prompt => 'Opisz obraz, który chcesz utworzyć';

  @override
  String get image_generation_temporary =>
      'Generowanie obrazów jest dostępne w zapisywanych czatach. Rozpocznij zapisywany czat, aby utworzyć obraz.';

  @override
  String get image_generation_remove_attachments =>
      'Usuń załączniki przed wygenerowaniem obrazu.';

  @override
  String get image_generation_unavailable =>
      'Ten serwer lub model nie udostępnia zgodnego interfejsu Images API. Sprawdź adres URL serwera i identyfikator modelu.';

  @override
  String get image_generation_auth =>
      'Sprawdź klucz API i upewnij się, że umożliwia dostęp do tego modelu obrazów.';

  @override
  String get image_generation_quota =>
      'Wyczerpano limit częstotliwości lub limit użycia u dostawcy. Sprawdź konto, zanim spróbujesz ponownie.';

  @override
  String get image_generation_rejected =>
      'Dostawca odrzucił żądanie utworzenia obrazu. Sprawdź polecenie i spróbuj ponownie.';

  @override
  String get image_generation_timeout =>
      'Upłynął limit czasu na wygenerowanie obrazu. Spróbuj ponownie, gdy usługa dostawcy będzie dostępna.';

  @override
  String get image_generation_invalid =>
      'Dostawca zwrócił nieprawidłowy lub nieobsługiwany obraz.';

  @override
  String get image_generation_failed =>
      'Nie udało się wygenerować obrazu. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get image_generation_save_failed =>
      'Nie udało się zapisać wygenerowanego obrazu. Sprawdź wolne miejsce i spróbuj ponownie.';

  @override
  String get image_generation_share => 'Udostępnij obraz';

  @override
  String get onDeviceSearchModels => 'Szukaj modeli';

  @override
  String get onDeviceSearching => 'Wyszukiwanie…';

  @override
  String get onDeviceSearch => 'Szukaj';

  @override
  String get onDeviceModelTypeBoth => 'Oba';

  @override
  String get onDeviceModelTypeLitert => 'LiteRT';

  @override
  String get onDeviceModelTypeGguf => 'Llama.cpp (GGUF)';

  @override
  String get onDeviceModelTypeNone => 'Brak';

  @override
  String get onDeviceModalityAll => 'Wszystkie';

  @override
  String get onDeviceModalityText => 'Tekst';

  @override
  String get onDeviceModalityVision => 'Obsługa obrazów';

  @override
  String get onDeviceModalityAudio => 'Dźwięk';

  @override
  String get onDeviceModalityEmbedding => 'Osadzenia';

  @override
  String get onDeviceModalityOmni => 'Omni';

  @override
  String get onDeviceModalityUnknown => 'Nieznane';

  @override
  String get downloadBackgroundActive => 'W tle';

  @override
  String get downloadBackgroundDescription =>
      'Android zarządza tym pobieraniem, które może trwać po zamknięciu LocalMind. System może wstrzymać lub odłożyć pobieranie w zależności od warunków.';

  @override
  String get downloadQueued => 'W kolejce';

  @override
  String get downloadWaitingToRetry => 'Oczekiwanie na ponowną próbę';

  @override
  String get onDeviceEnterSearchTerm => 'Wpisz szukaną frazę';

  @override
  String get onDeviceFilters => 'Filtry';

  @override
  String get onDeviceFramework => 'Środowisko';

  @override
  String get onDeviceModality => 'Modalność';

  @override
  String get onDeviceParameterSize => 'Liczba parametrów';

  @override
  String get onDeviceMinParam => 'Min. (mld)';

  @override
  String get onDeviceMaxParam => 'Maks. (mld)';

  @override
  String get onDeviceIncludeUnknownSizes =>
      'Uwzględnij modele o nieznanym rozmiarze';

  @override
  String get onDeviceSplitModels => 'Modele wieloczęściowe';

  @override
  String get onDeviceImportFromUrl => 'Importuj z adresu URL';

  @override
  String get onDeviceImportFromDevice => 'Importuj z urządzenia';

  @override
  String get onDeviceAddModelFromUrl => 'Dodaj model z adresu URL';

  @override
  String get onDeviceHuggingFaceUrl => 'Adres URL Hugging Face';

  @override
  String get onDeviceUpdateAvailable => 'Dostępna aktualizacja';

  @override
  String get onDeviceCheckForUpdates => 'Sprawdź dostępność aktualizacji';

  @override
  String get onDeviceAdded => 'Dodano';

  @override
  String get onDeviceSplitModel => 'Model wieloczęściowy';

  @override
  String get onDevicePickGguf => 'Wybierz GGUF';

  @override
  String get onDevicePickLitert => 'Wybierz LiteRT';

  @override
  String onDeviceUnknownSizeHidden(int count) {
    return 'Ukryto modele o nieznanym rozmiarze: $count';
  }

  @override
  String get conversation_tags => 'Tagi';

  @override
  String get conversation_tags_desc =>
      'Grupuj czaty według tematu. Rozmowa może mieć kilka tagów i należeć do folderu.';

  @override
  String get conversation_tags_add_hint => 'Wpisz tag i naciśnij Enter';

  @override
  String get conversation_tags_existing => 'Twoje tagi';

  @override
  String get conversation_tags_add => 'Dodaj tagi';

  @override
  String get conversation_tags_edit => 'Edytuj tagi';

  @override
  String get turn_instruction_title => 'Instrukcja do następnej odpowiedzi';

  @override
  String get turn_instruction_desc =>
      'Uzupełnia polecenie czatu tylko przy wysyłaniu następnej wiadomości.';

  @override
  String get turn_instruction_hint => 'Np. Odpowiedz w trzech punktach';

  @override
  String get turn_instruction_remove => 'Usuń instrukcję';

  @override
  String get turn_instruction_chip_label => 'Następna odpowiedź:';

  @override
  String get read_images_on_device => 'Odczytuj zdjęcia dla modeli tekstowych';

  @override
  String get read_images_on_device_desc =>
      'Gdy model na urządzeniu nie obsługuje obrazów, rozpoznawaj tekst i obiekty na zdjęciu na tym urządzeniu i przekazuj je jako tekst. Żadne dane nie opuszczają telefonu.';

  @override
  String get web_search_title => 'Wyszukiwanie w sieci';

  @override
  String get web_search_enable_desc =>
      'Pozwól rozmowom wyszukiwać informacje w sieci. Zapytania trafiają do wybranego dostawcy, a strony są pobierane z tego urządzenia. Domyślnie wyłączone.';

  @override
  String get web_search_provider => 'Dostawca wyszukiwania';

  @override
  String get web_search_searxng_url => 'Adres SearXNG';

  @override
  String get web_search_searxng_hint => 'https://searx.example.com';

  @override
  String get web_search_searxng_help =>
      'Użyj własnej instancji SearXNG. W jej pliku settings.yml włącz format JSON w sekcji search → formats.';

  @override
  String get web_search_api_key => 'Klucz API';

  @override
  String get web_search_api_key_saved =>
      'Klucz jest zapisany. Wpisz nowy, aby go zastąpić.';

  @override
  String get web_search_remove_key => 'Usuń zapisany klucz';

  @override
  String get web_search_test => 'Sprawdź wyszukiwanie';

  @override
  String web_search_test_ok(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wyszukiwanie działa: $count wyniku.',
      many: 'Wyszukiwanie działa: $count wyników.',
      few: 'Wyszukiwanie działa: $count wyniki.',
      one: 'Wyszukiwanie działa: 1 wynik.',
      zero: 'Wyszukiwanie działa, ale nie zwróciło wyników.',
    );
    return '$_temp0';
  }

  @override
  String web_search_test_failed(String error) {
    return 'Wyszukiwanie nie powiodło się: $error';
  }

  @override
  String get web_search_tools_note =>
      'Modele obsługujące narzędzia mogą też wywoływać web.search i web.fetch, jeśli włączono narzędzia w czacie. Każde wywołanie wymaga Twojej zgody.';

  @override
  String get attach_search_web => 'Szukaj w sieci';

  @override
  String get attach_search_web_desc =>
      'Wyszukaj informacje o tej wiadomości w sieci przed odpowiedzią';

  @override
  String get web_search_next_chip =>
      'Wyszukiwanie w sieci włączone dla tej wiadomości';

  @override
  String get web_search_next_off => 'Wyłącz wyszukiwanie w sieci';
}
