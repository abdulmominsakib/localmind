// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Romanian Moldavian Moldovan (`ro`).
class AppLocalizationsRo extends AppLocalizations {
  AppLocalizationsRo([String locale = 'ro']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'AI-ul tău. Dispozitivul tău. Regulile tale.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Anulează';

  @override
  String get confirm => 'Confirmă';

  @override
  String get delete => 'Șterge';

  @override
  String get save => 'Salvează';

  @override
  String get retry => 'Reîncearcă';

  @override
  String get close => 'Închide';

  @override
  String get done => 'Gata';

  @override
  String get continue_action => 'Continuă';

  @override
  String get skip => 'Omite';

  @override
  String get install => 'Instalează';

  @override
  String get download => 'Descarcă';

  @override
  String get resume => 'Reia';

  @override
  String get pause => 'Pune pe pauză';

  @override
  String get stop => 'Oprește';

  @override
  String get edit => 'Editează';

  @override
  String get preview => 'Previzualizează';

  @override
  String get unload => 'Descarcă din memorie';

  @override
  String get load => 'Încarcă';

  @override
  String get rename => 'Redenumește';

  @override
  String get pin => 'Fixează';

  @override
  String get unpin => 'Anulează fixarea';

  @override
  String get share => 'Partajează';

  @override
  String get copy => 'Copiază';

  @override
  String get copied => 'Copiat!';

  @override
  String get copied_to_clipboard => 'Copiat în clipboard';

  @override
  String get select => 'Selectează';

  @override
  String get active => 'Activ';

  @override
  String get all => 'Toate';

  @override
  String get none => 'Niciuna';

  @override
  String get none_selected => 'Nimic selectat';

  @override
  String get online => 'Online';

  @override
  String get connected => 'Conectat';

  @override
  String get checking => 'Se verifică';

  @override
  String get offline => 'Offline';

  @override
  String get error => 'Eroare';

  @override
  String get unknown_error => 'Eroare necunoscută';

  @override
  String get not_now => 'Nu acum';

  @override
  String get enable => 'Activează';

  @override
  String get proceed_anyway => 'Continuă oricum';

  @override
  String get test_connection => 'Testează conexiunea';

  @override
  String get testing => 'Se testează...';

  @override
  String get connection_successful => 'Conexiune reușită!';

  @override
  String get connection_failed => 'Conexiunea a eșuat. Verifică setările.';

  @override
  String get connection_failed_unreachable =>
      'Nu s-a putut contacta serverul. Verifică adresa și portul, dacă serverul acceptă conexiuni din rețeaua ta (nu doar de pe localhost) și dacă accesul la rețeaua locală este permis pentru LocalMind.';

  @override
  String get connection_failed_timeout =>
      'Serverul nu a răspuns la timp. Verifică dacă dispozitivul și serverul sunt conectate la aceeași rețea sau VPN.';

  @override
  String get connection_failed_tls =>
      'Conexiunea securizată a eșuat. Verifică certificatul serverului sau folosește http:// dacă serverul nu utilizează HTTPS.';

  @override
  String connection_failed_unauthorized(int status) {
    return 'Serverul a respins solicitarea (HTTP $status). Verifică cheia API.';
  }

  @override
  String get connection_failed_not_found =>
      'Serverul a răspuns, dar rutele API așteptate nu au fost găsite. Verifică tipul serverului, portul și prefixul căii.';

  @override
  String connection_failed_status(int status) {
    return 'Serverul a răspuns cu HTTP $status.';
  }

  @override
  String get connection_failed_missing_key =>
      'Acest furnizor necesită o cheie API.';

  @override
  String get connection_warning_lmstudio_native =>
      'Conectat, dar numai prin rutele compatibile cu OpenAI /v1. Chatul folosește rutele native /api/v1 din LM Studio, așa că asigură-te că proxy-ul le redirecționează.';

  @override
  String get context_length_server_default => 'Valoarea implicită a serverului';

  @override
  String get context_length_use_server_default =>
      'Folosește valoarea implicită a serverului';

  @override
  String get save_continue => 'Salvează și continuă';

  @override
  String get save_changes => 'Salvează modificările';

  @override
  String get finish_setup => 'Finalizează configurarea';

  @override
  String get start_new_chat => 'Începe un chat nou';

  @override
  String get cannot_undo => 'Această acțiune nu poate fi anulată.';

  @override
  String get ram_warning => 'Avertisment privind RAM-ul';

  @override
  String get recommended => 'RECOMANDAT';

  @override
  String get may_be_large =>
      'Este posibil să fie prea mare pentru acest dispozitiv';

  @override
  String get calculating => 'Se calculează...';

  @override
  String get download_failed => 'Descărcarea a eșuat';

  @override
  String get downloaded => 'Descărcat';

  @override
  String get not_downloaded => 'Nedescărcat';

  @override
  String get installed => 'Instalat';

  @override
  String get not_installed => 'Neinstalat';

  @override
  String get loading => 'Se încarcă...';

  @override
  String get thinking => 'Se gândește';

  @override
  String get processing => 'Se procesează...';

  @override
  String get initializing => 'Se inițializează...';

  @override
  String get ready => 'Gata';

  @override
  String get preparing_app => 'Se pregătește aplicația...';

  @override
  String get initializing_services => 'Se inițializează serviciile...';

  @override
  String get configuring_server => 'Se configurează serverul...';

  @override
  String get startup_failed => 'Pornirea a eșuat';

  @override
  String get something_went_wrong => 'Ceva nu a funcționat';

  @override
  String get delete_model_title => 'Șterge modelul';

  @override
  String delete_model_body(String name) {
    return 'Sigur vrei să ștergi $name?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Sigur vrei să ștergi $name? Vei elibera aproximativ $size de spațiu.\n\nPoți descărca din nou acest model mai târziu, dacă ai nevoie.';
  }

  @override
  String get delete_voice_title => 'Șterge vocea';

  @override
  String delete_voice_body(String name, String size) {
    return 'Sigur vrei să ștergi $name? Vei elibera aproximativ $size de spațiu.\n\nPoți descărca din nou această voce mai târziu, dacă ai nevoie.';
  }

  @override
  String get delete_server_title => 'Șterge serverul';

  @override
  String delete_server_body(String name) {
    return 'Sigur vrei să ștergi \"$name\"? Această acțiune nu poate fi anulată.';
  }

  @override
  String get delete_conversation_title => 'Ștergi conversația?';

  @override
  String delete_conversation_body(String title) {
    return 'Sigur vrei să ștergi \"$title\"? Această acțiune nu poate fi anulată.';
  }

  @override
  String get delete_message_title => 'Ștergi mesajul?';

  @override
  String delete_persona_title(String name) {
    return 'Ștergi \"$name\"?';
  }

  @override
  String get delete_persona_body => 'Această acțiune nu poate fi anulată.';

  @override
  String get delete_builtin_persona_body =>
      'Aceasta este o personalitate inclusă în aplicație. O poți restaura mai târziu din Setări.';

  @override
  String get restore_builtin_personas =>
      'Restaurează personalitățile implicite';

  @override
  String get restore_builtin_personas_desc =>
      'Adaugă din nou personalitățile incluse în aplicație pe care le-ai șters';

  @override
  String get restore_builtin_personas_success =>
      'Personalități implicite restaurate';

  @override
  String get clear_personas => 'Șterge selecția de personalități';

  @override
  String get enable_image_compression =>
      'Comprimă imaginile înainte de trimitere';

  @override
  String get enable_image_compression_desc =>
      'Redimensionează și comprimă imaginile atașate, astfel încât încărcările să respecte limitele serverului';

  @override
  String get image_compression_level => 'Nivelul de comprimare';

  @override
  String get image_compression_level_desc =>
      'Un nivel mai ridicat reduce dimensiunea încărcărilor, dar și calitatea';

  @override
  String get image_compression_level_low => 'Redus';

  @override
  String get image_compression_level_medium => 'Mediu';

  @override
  String get image_compression_level_high => 'Ridicat';

  @override
  String get sort_models_tooltip => 'Sortează modelele';

  @override
  String get sort_by_favorites => 'Favoritele primele';

  @override
  String get sort_by_name => 'Nume (A-Z)';

  @override
  String get sort_by_size_smallest => 'Dimensiune (de la mic la mare)';

  @override
  String get sort_by_size_largest => 'Dimensiune (de la mare la mic)';

  @override
  String get sort_by_context_length => 'Lungimea contextului';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Se redenumesc $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '$count selectate';
  }

  @override
  String get ai_rename_tooltip => 'Redenumește selecția cu AI';

  @override
  String get new_chat_in_folder_tooltip => 'Chat nou în acest dosar';

  @override
  String total_tokens_count(int count) {
    return '$count tokenuri';
  }

  @override
  String get smart_replies_use_persona =>
      'Folosește personalitatea pentru răspunsuri inteligente';

  @override
  String get smart_replies_use_persona_desc =>
      'Răspunsurile sugerate se potrivesc tonului personalității active, în loc să folosească un asistent generic';

  @override
  String get keep_persona_on_new_chat =>
      'Păstrează personalitatea în chatul nou';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Nu șterge personalitățile selectate după ce începi un chat nou';

  @override
  String get role_swap_button_enabled =>
      'Afișează butonul de schimbare a rolului';

  @override
  String get role_swap_button_enabled_desc =>
      'Afișează în câmpul de chat un buton care îți permite să trimiți mesajul ca asistent, nu ca utilizator, fără a genera un răspuns';

  @override
  String get processing_prompt_label => 'Se procesează promptul…';

  @override
  String get generating_label => 'Se generează…';

  @override
  String get prompts_processed_label => 'Prompturi procesate';

  @override
  String get prompt_processing_indicator_enabled =>
      'Afișează indicatorul de procesare a promptului';

  @override
  String get prompt_processing_indicator_enabled_desc =>
      'Afișează progresul procesării promptului în timp real și numărul de prompturi procesate pentru chatul curent, deasupra câmpului de introducere.';

  @override
  String get send_as_user_tooltip => 'Trimite ca utilizator';

  @override
  String get send_as_assistant_tooltip => 'Trimite ca asistent (fără răspuns)';

  @override
  String get insert_without_generating_tooltip => 'Inserează fără a genera';

  @override
  String get token_usage_title => 'Utilizarea tokenurilor';

  @override
  String get total_tokens_label => 'Tokenuri utilizate';

  @override
  String get usage_percent_label => 'Context utilizat';

  @override
  String get export_choice_title => 'Exportă';

  @override
  String get export_choice_body => 'Cum vrei să exporți acest conținut?';

  @override
  String get copy_to_clipboard => 'Copiază în clipboard';

  @override
  String bulk_export_conversations_success(int count) {
    return 'S-au exportat $count conversații';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Redenumești cu AI?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'AI-ul va genera un titlu nou pentru fiecare dintre cele $count conversații selectate, înlocuindu-le pe cele actuale. Operația poate dura și nu poate fi anulată.';
  }

  @override
  String get sort_by_modified_date => 'Modificate ultima dată';

  @override
  String get sort_by_created_date => 'Data creării';

  @override
  String get sort_title => 'Sortează';

  @override
  String get clear_conversation_title => 'Ștergi conversația?';

  @override
  String get clear_conversation_body =>
      'Toate mesajele din această conversație vor fi șterse.';

  @override
  String get clear => 'Șterge conținutul';

  @override
  String label_completed(String label) {
    return '$label s-a finalizat';
  }

  @override
  String error_with_message(String error) {
    return 'Eroare: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Previzualizarea a eșuat: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Se încarcă $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Model încărcat: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Niciun model încărcat. Apasă pe „Gestionează modelele de pe dispozitiv” pentru a descărca și încărca un model.';

  @override
  String loading_model_error(String error) {
    return 'Eroare: $error';
  }

  @override
  String get delete_conversation => 'Ștergi conversația?';

  @override
  String get nav_history => 'Istoric';

  @override
  String get nav_servers => 'Servere';

  @override
  String get nav_local_models => 'Modele locale';

  @override
  String get nav_tts => 'Text-to-speech';

  @override
  String get nav_personas => 'Personaje';

  @override
  String get nav_settings => 'Setări';

  @override
  String get nav_new_chat => 'Chat nou';

  @override
  String get search_hint => 'Caută conversații...';

  @override
  String get no_server_selected => 'Niciun server selectat';

  @override
  String get switch_server => 'Schimbă serverul';

  @override
  String get switch_server_subtitle =>
      'Alege un server la care să te conectezi';

  @override
  String get manage_servers => 'Gestionează serverele';

  @override
  String get open_source => 'Open source';

  @override
  String get open_source_desc =>
      'LocalMind este open source. Urmărește evoluția proiectului sau contribuie pe GitHub.';

  @override
  String get star_on_github => 'Acordă o stea pe GitHub';

  @override
  String get add_more => 'Adaugă mai multe';

  @override
  String get on_github => 'pe GitHub';

  @override
  String get could_not_open_github => 'Nu s-a putut deschide GitHub.';

  @override
  String get settings_title => 'Setări';

  @override
  String get settings_appearance => 'Aspect';

  @override
  String get settings_language => 'Limbă';

  @override
  String get language_system_default => 'Implicită a sistemului';

  @override
  String get settings_tts => 'Text-to-speech';

  @override
  String get settings_android_assistant => 'Asistent Android';

  @override
  String get assistant_default_title => 'Folosește LocalMind ca asistent';

  @override
  String get assistant_default_description =>
      'Pornește modul vocal folosind gestul asistentului Android sau comanda rapidă a butonului de pornire.';

  @override
  String get assistant_status_active => 'Activ';

  @override
  String get assistant_status_available => 'Inactiv';

  @override
  String get assistant_status_manual => 'Verifică setările';

  @override
  String get assistant_status_unsupported => 'Indisponibil';

  @override
  String get assistant_status_checking => 'Se verifică…';

  @override
  String get assistant_set_default => 'Setează ca asistent implicit';

  @override
  String get assistant_open_settings =>
      'Deschide setările asistentului Android';

  @override
  String assistant_error(Object error) {
    return 'Nu s-au putut deschide setările asistentului Android.';
  }

  @override
  String get settings_behavior => 'Comportament';

  @override
  String get settings_on_device => 'Inferență pe dispozitiv';

  @override
  String get settings_default_server => 'Server implicit';

  @override
  String get settings_default_persona => 'Personaj implicit';

  @override
  String get settings_default_model => 'Model implicit';

  @override
  String get settings_default_model_desc =>
      'Selectat automat când începi un chat nou.';

  @override
  String get settings_privacy => 'Confidențialitate';

  @override
  String get settings_data_management => 'Gestionarea datelor';

  @override
  String get settings_about => 'Despre';

  @override
  String get theme => 'Temă';

  @override
  String get theme_system => 'Sistem';

  @override
  String get theme_light => 'Deschisă';

  @override
  String get theme_dark => 'Întunecată';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'Dimensiunea fontului';

  @override
  String get font_size_desc => 'Ajustează dimensiunea textului din chat.';

  @override
  String get font_preview => 'Vulpea maro și iute sare peste câinele leneș.';

  @override
  String get code_theme_dark => 'Temă de cod (întunecată)';

  @override
  String get code_theme_light => 'Temă de cod (deschisă)';

  @override
  String get code_theme_desc =>
      'Alege tema de evidențiere a sintaxei pentru blocurile de cod.';

  @override
  String get tts_engine => 'Motor TTS';

  @override
  String get tts_engine_system => 'TTS de sistem';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => 'Voce';

  @override
  String get voice_female => 'Femeie';

  @override
  String get voice_male => 'Bărbat';

  @override
  String get voice_other => 'Alta';

  @override
  String get tts_speed => 'Viteza TTS';

  @override
  String get tts_speed_desc => 'Ajustează viteza de redare.';

  @override
  String get manage_tts_models => 'Gestionează modelele TTS';

  @override
  String get manage_on_device_models => 'Gestionează modelele de pe dispozitiv';

  @override
  String get enable_smart_reply => 'Răspunsuri inteligente';

  @override
  String get ai_user_response_enabled =>
      'Mesaj de la utilizator generat de AI (ține apăsat pe trimitere)';

  @override
  String get ai_user_response_enabled_desc =>
      'Ține apăsat butonul de trimitere timp de 3 secunde pentru ca AI-ul să scrie și să trimită următorul tău mesaj';

  @override
  String get ai_user_response_tooltip =>
      'Generează mesajul utilizatorului cu AI';

  @override
  String get streaming_responses => 'Răspunsuri în flux continuu';

  @override
  String get auto_generate_titles => 'Generează automat titluri';

  @override
  String get send_on_enter => 'Trimite la apăsarea tastei Enter';

  @override
  String get show_system_messages => 'Trimite promptul de sistem implicit';

  @override
  String get show_system_messages_desc =>
      'Când nu este selectat niciun personaj, trimite un prompt de sistem implicit pentru asistent la fiecare solicitare';

  @override
  String get show_system_messages_in_chat =>
      'Afișează mesajele de sistem în chat';

  @override
  String get show_system_messages_in_chat_desc =>
      'Afișează mesajele de sistem (de exemplu, dintr-o copie de siguranță importată) ca bule vizibile în conversație';

  @override
  String get auto_collapse_thinking => 'Restrânge automat raționamentul';

  @override
  String get auto_collapse_thinking_desc =>
      'Restrânge automat procesul de raționare după generarea răspunsului, dacă este prezent un răspuns principal';

  @override
  String get haptic_feedback => 'Feedback haptic';

  @override
  String get enable_mcp => 'Activează MCP';

  @override
  String get new_chat_mcp_default => 'MCP activ implicit în chat-urile noi';

  @override
  String get show_data_indicator => 'Afișează indicatorul de date';

  @override
  String get privacy_info => '„LocalMind nu îți vede niciodată datele”';

  @override
  String get delete_all_conversations => 'Șterge toate conversațiile';

  @override
  String get reset_settings_defaults =>
      'Resetează setările la valorile implicite';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Parametrii chatului';

  @override
  String get change_persona => 'Schimbă personajul';

  @override
  String get set_persona => 'Setează personajul';

  @override
  String get remove_persona => 'Elimină personajul';

  @override
  String get clear_conversation => 'Șterge conversația';

  @override
  String get connection_error => 'Eroare de conectare. Verifică serverul.';

  @override
  String get disconnected => 'Deconectat de la server.';

  @override
  String get configure => 'Configurează';

  @override
  String get select_model => 'Selectează modelul';

  @override
  String get select_persona => 'Selectează un personaj';

  @override
  String get manage_personas => 'Gestionează personajele';

  @override
  String get personas_combine_hint =>
      'Selectează mai multe personaje în chat pentru a combina prompturile lor de sistem.';

  @override
  String get start_conversation => 'Începe o conversație';

  @override
  String get recent_chats => 'Chat-uri recente';

  @override
  String get see_all => 'Vezi tot';

  @override
  String get quick_write => 'Ajută-mă să scriu o funcție';

  @override
  String get quick_explain => 'Explică acest cod';

  @override
  String get quick_debug => 'Depanează acest cod';

  @override
  String get quick_async => 'Cum folosesc async/await?';

  @override
  String get history_missing_title => 'Istoric indisponibil';

  @override
  String get history_missing_desc =>
      'Fie mesajele din acest chat au fost șterse, fie înregistrarea istoricului este coruptă.';

  @override
  String get technical_details => 'Detalii tehnice';

  @override
  String get last_error => 'Ultima eroare:';

  @override
  String get copy_info => 'Copiază informațiile';

  @override
  String get conversation_id => 'ID conversație';

  @override
  String get created_at => 'Creat la';

  @override
  String get expected_messages => 'Mesaje așteptate';

  @override
  String get debug_dialog_desc =>
      'Informații de diagnosticare pentru identificarea problemelor de sincronizare.';

  @override
  String get chat_input_hint => 'Întreabă orice';

  @override
  String get send_message_tooltip => 'Trimite mesajul';

  @override
  String get stop_generation_tooltip => 'Oprește generarea';

  @override
  String get attach_images_tooltip => 'Atașează imagini sau text';

  @override
  String get start_listening_tooltip => 'Începe ascultarea';

  @override
  String get stop_listening_tooltip => 'Oprește ascultarea';

  @override
  String tool_label(String toolCallId) {
    return 'Instrument: $toolCallId';
  }

  @override
  String get tool_unknown => 'Instrument: necunoscut';

  @override
  String get message_options => 'Opțiuni pentru mesaj';

  @override
  String get copy_markdown => 'Copiază ca Markdown';

  @override
  String get copied_markdown => 'Copiat ca Markdown';

  @override
  String get read_aloud => 'Citește cu voce tare';

  @override
  String get stop_reading => 'Oprește citirea';

  @override
  String get more => 'Mai multe';

  @override
  String character_count(int length) {
    return '$length caractere';
  }

  @override
  String get edit_message => 'Editează mesajul';

  @override
  String get edit_message_desc =>
      'Salvarea va elimina răspunsul asistentului de mai jos și îl va genera din nou.';

  @override
  String get save_regenerate => 'Salvează și regenerează';

  @override
  String get chat_settings_title => 'Setări chat';

  @override
  String get reset_defaults => 'Resetează la valorile implicite';

  @override
  String get parameters_tab => 'Parametri';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'Temperatură';

  @override
  String get temperature_desc =>
      'Controlează caracterul aleatoriu: mai mare = creativ, mai mică = concentrat';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'Pragul eșantionării nucleu';

  @override
  String get max_tokens => 'Număr maxim de tokenuri';

  @override
  String get max_tokens_desc => 'Limită de răspuns';

  @override
  String get context_length => 'Lungimea contextului';

  @override
  String get context_length_desc => 'Fereastra istoricului';

  @override
  String get mcp_disabled_warning =>
      'MCP este dezactivat global. Activează-l din Setări pentru a folosi aceste funcții.';

  @override
  String get mcp_enable_chat => 'Activează MCP pentru acest chat';

  @override
  String mcp_connection_failed(String error) {
    return 'Conectarea a eșuat: $error';
  }

  @override
  String get mcp_tools_unsupported_runtime =>
      'Mediul de execuție al acestui model nu poate folosi încă instrumente. Schimbă la un model Gemma (LiteRT) sau la un model de server pentru a folosi instrumentele MCP.';

  @override
  String get auto_execute_tools => 'Execută automat instrumentele';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Experimental';

  @override
  String get add_ephemeral_mcp => 'Adaugă un server MCP temporar';

  @override
  String get mcp_label_placeholder => 'Etichetă';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => 'Integrări active';

  @override
  String get import_mcp_json => 'Importă JSON';

  @override
  String get import_mcp_json_dialog_title => 'Importă configurația MCP JSON';

  @override
  String get import_mcp_json_instructions =>
      'Copiază direct JSON-ul mcpServers din LM Studio (mcp.json) sau lipește mai jos o listă de pluginuri:';

  @override
  String get import_mcp_json_placeholder =>
      'Lipește aici JSON-ul mcpServers sau lista de pluginuri...';

  @override
  String mcp_import_success(int count) {
    return '$count integrări importate cu succes';
  }

  @override
  String get mcp_import_failed => 'Nu s-au găsit integrări MCP valide în JSON';

  @override
  String get enable_notifications => 'Activează notificările';

  @override
  String get enable_notifications_desc =>
      'Primește o notificare când se termină descărcarea modelelor.';

  @override
  String get chat_history_title => 'Istoricul chatului';

  @override
  String get conversation_just_now => 'Chiar acum';

  @override
  String conversation_minutes_ago(int minutes) {
    return 'Acum $minutes min';
  }

  @override
  String conversation_hours_ago(int hours) {
    return 'Acum $hours h';
  }

  @override
  String get conversation_yesterday => 'Ieri';

  @override
  String conversation_days_ago(int days) {
    return 'Acum $days zile';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$day/$month/$year';
  }

  @override
  String get options_tooltip => 'Opțiuni';

  @override
  String get no_results_found => 'Nu s-au găsit rezultate';

  @override
  String get no_conversations_yet => 'Încă nu există conversații';

  @override
  String get try_different_search => 'Încearcă un alt termen de căutare';

  @override
  String get start_new_conversation => 'Începe o conversație nouă';

  @override
  String get rename_conversation => 'Redenumește conversația';

  @override
  String get enter_new_title => 'Introdu un titlu nou';

  @override
  String get pinned_section => 'FIXATE';

  @override
  String get today_section => 'ASTĂZI';

  @override
  String get yesterday_section => 'IERI';

  @override
  String get previous_7_days => 'ULTIMELE 7 ZILE';

  @override
  String get previous_30_days => 'ULTIMELE 30 DE ZILE';

  @override
  String get older_section => 'MAI VECHI';

  @override
  String get onboarding_choose_language => 'Alege limba';

  @override
  String get onboarding_choose_language_desc =>
      'Selectează limba preferată. O poți schimba oricând din setări.';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'Conectează-ți\nserverul';

  @override
  String get onboarding_connect_desc =>
      'Conectează-te la LM Studio, Ollama,\nOllama Cloud sau OpenRouter pentru\na începe să folosești AI în privat.';

  @override
  String get openai_compatible_api => 'API compatibil cu OpenAI';

  @override
  String get https_requires_ssl => 'HTTPS necesită SSL';

  @override
  String get most_local_setups_use_http =>
      'Majoritatea configurațiilor locale folosesc http://';

  @override
  String get onboarding_welcome => 'Bun venit în LocalMind';

  @override
  String get server_type_on_device => 'Pe dispozitiv';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'GESTIONAT ÎN CLOUD';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Conectându-te la Ollama Cloud, mesajele și datele introduse în chat sunt trimise către serverele gestionate de Ollama pentru procesare. LocalMind nu urmărește și nu stochează conversațiile. Poți revoca această cheie oricând la ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud =>
      'Este necesară o cheie API pentru Ollama Cloud';

  @override
  String get api_key_hint_ollama_cloud => 'Lipește cheia API Ollama Cloud';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Conectează-te la Ollama Cloud cu o cheie API de la ollama.com/settings/keys pentru a accesa modelele gestionate în cloud.';

  @override
  String get add_server_openrouter_subtitle =>
      'Conectează-te prin OpenRouter cu o cheie API validă și păstrează acest profil pregătit pentru rutarea modelelor.';

  @override
  String get add_server_requesty_subtitle =>
      'Conectează-te prin Requesty cu o cheie API validă și păstrează acest profil pregătit pentru rutarea modelelor.';

  @override
  String get add_server_standard_compute_subtitle =>
      'Conectează-te prin Standard Compute cu o cheie API validă și păstrează acest profil pregătit pentru rutarea modelelor.';

  @override
  String get add_server_endpoint_subtitle =>
      'Configurează un endpoint local sau găzduit de tine, apoi verifică conexiunea înainte de salvare.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_requesty => 'Requesty';

  @override
  String get server_type_standard_compute => 'Standard Compute';

  @override
  String get server_type_openrouter_sub => 'CLOUD UNIFICAT';

  @override
  String get server_type_requesty_sub => 'CLOUD UNIFICAT';

  @override
  String get server_type_standard_compute_sub => 'CLOUD UNIFICAT';

  @override
  String get ready_continue => 'GATA DE CONTINUARE';

  @override
  String get waiting_selection => 'SE AȘTEAPTĂ SELECTAREA';

  @override
  String get setup_connection => 'Configurează conexiunea';

  @override
  String setup_connection_desc(String server) {
    return 'Configurează serverul $server pentru a începe să conversezi.';
  }

  @override
  String get server_name => 'Numele serverului';

  @override
  String get name_required => 'Numele este obligatoriu';

  @override
  String get name_max_50 => 'Maximum 50 de caractere';

  @override
  String get host_label => 'Gazdă / adresă IP';

  @override
  String get host_required => 'Gazda este obligatorie';

  @override
  String get port_label => 'Port';

  @override
  String get port_required => 'Portul este obligatoriu';

  @override
  String get port_invalid => 'Trebuie să fie un număr';

  @override
  String get port_range => 'Introdu un port valid (1-65535)';

  @override
  String get api_key_required => 'Cheie API *';

  @override
  String get api_key_optional => 'Cheie API (opțională)';

  @override
  String get api_key_required_openrouter =>
      'Este necesară o cheie API pentru OpenRouter';

  @override
  String get api_key_required_requesty =>
      'Este necesară o cheie API pentru Requesty';

  @override
  String get api_key_required_standard_compute =>
      'Este necesară o cheie API pentru Standard Compute';

  @override
  String get api_key_format => 'Cheile API OpenRouter încep cu sk-';

  @override
  String get my_server_hint => 'Serverul meu';

  @override
  String get name_length_validation =>
      'Numele trebuie să aibă cel mult 50 de caractere';

  @override
  String get host_valid => 'Introdu un nume de gazdă sau o adresă IP validă';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_requesty => 'rqsty-...';

  @override
  String get api_key_hint_standard_compute => 'sk_live_...';

  @override
  String get api_key_hint_generic => 'Pentru servere cu autentificare';

  @override
  String get update_server => 'Actualizează serverul';

  @override
  String get save_server => 'Salvează serverul';

  @override
  String get server_updated => 'Server actualizat';

  @override
  String get server_added => 'Server adăugat';

  @override
  String get download_model_title => 'Descarcă un model';

  @override
  String get download_model_desc =>
      'Alege un model de descărcat.\nVa rula local pe dispozitivul tău.';

  @override
  String get no_model_downloaded_title => 'Niciun model descărcat';

  @override
  String get no_model_downloaded_desc =>
      'Pentru a folosi AI pe dispozitiv, trebuie să descarci sau să selectezi cel puțin un model. Poți alege un model acum sau poți sări peste acest pas și să descarci unul mai târziu din setări.';

  @override
  String get choose_a_model => 'Alege un model';

  @override
  String get skip_for_now => 'Omite deocamdată';

  @override
  String get download_in_progress_title => 'Descărcare în curs';

  @override
  String get download_in_progress_desc =>
      'Un model se descarcă acum. Poți aștepta să se termine sau poți continua în fundal.';

  @override
  String get wait_for_download => 'Așteaptă';

  @override
  String get continue_anyway => 'Continuă oricum';

  @override
  String get download_model_required_hint =>
      'Este necesar cel puțin un model descărcat pentru chatul pe dispozitiv.';

  @override
  String get on_device_android_only =>
      'Procesarea pe dispozitiv este disponibilă momentan doar pe Android.';

  @override
  String get total_ram => 'RAM totală';

  @override
  String get available => 'Disponibilă';

  @override
  String ram_min_required(String fileSize) {
    return 'Minimum $fileSize GB RAM';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Timp rămas: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'În pauză - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Acest model necesită cel puțin $ram GB RAM, dar dispozitivul tău are $totalMemory. Este posibil să nu funcționeze corect sau să provoace blocarea aplicației.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Dispozitivul tău are $availableRAM RAM disponibilă, dar acest model recomandă cel puțin $ram GB. Încărcarea lui poate eșua sau poate cauza instabilitate.';
  }

  @override
  String get choose_theme => 'Alege tema';

  @override
  String get choose_theme_desc =>
      'Personalizează aspectul aplicației. Poți schimba tema oricând mai târziu din setări.';

  @override
  String get theme_card_system => 'Sistem';

  @override
  String get theme_card_system_sub => 'Urmează setările dispozitivului';

  @override
  String get theme_card_light => 'Luminoasă';

  @override
  String get theme_card_light_sub => 'Simplă și luminoasă';

  @override
  String get theme_card_dark => 'Întunecată';

  @override
  String get theme_card_dark_sub => 'Mai odihnitoare pentru ochi';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'O temă caldă, în nuanțe de piersică';

  @override
  String get stay_updated => 'Rămâi la curent';

  @override
  String get stay_updated_desc =>
      'Primește notificări când se termină descărcarea modelelor AI sau când se finalizează sarcini de lungă durată.';

  @override
  String get notification_benefit_downloads =>
      'Progresul descărcării modelului';

  @override
  String get notification_benefit_completions => 'Finalizarea generării';

  @override
  String get notification_benefit_background => 'Starea sarcinilor din fundal';

  @override
  String get allow_notifications => 'Permite notificările';

  @override
  String get servers_title => 'Servere';

  @override
  String get no_servers_yet => 'Încă nu există servere';

  @override
  String get no_servers_desc =>
      'Adaugă primul server pentru a începe să conversezi cu modele AI.';

  @override
  String get add_server => 'Adaugă server';

  @override
  String switched_to_server(String name) {
    return 'S-a trecut la $name';
  }

  @override
  String get edit_server => 'Editează serverul';

  @override
  String get add_server_title => 'Adaugă server';

  @override
  String get server_type_label => 'Tipul serverului';

  @override
  String get server_icon_label => 'Pictograma serverului';

  @override
  String get default_icon => 'Pictogramă implicită';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'Compatibil cu OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_requesty_display => 'Requesty';

  @override
  String get server_type_standard_compute_display => 'Standard Compute';

  @override
  String get server_type_on_device_display => 'Pe dispozitiv';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_requesty => 'router.requesty.ai';

  @override
  String get server_address_standard_compute => 'api.stdcmpt.com';

  @override
  String get server_address_on_device => 'Inferență locală';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Implicit';

  @override
  String get set_as_default => 'Setează ca implicit';

  @override
  String get select_icon => 'Selectează pictograma';

  @override
  String get select_icon_desc => 'Alege o pictogramă pentru server';

  @override
  String get search_icons_hint => 'Caută pictograme...';

  @override
  String get server_icon_stack => 'Stivă de servere';

  @override
  String get server_icon_stack2 => 'Stivă de servere 02';

  @override
  String get server_icon_stack3 => 'Stivă de servere 03';

  @override
  String get server_icon_cloud => 'Cloud';

  @override
  String get server_icon_cloud_server => 'Server cloud';

  @override
  String get server_icon_mcp => 'Server MCP';

  @override
  String get server_icon_database => 'Bază de date';

  @override
  String get server_icon_database1 => 'Bază de date 01';

  @override
  String get server_icon_database2 => 'Bază de date 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'Cip';

  @override
  String get server_icon_chip2 => 'Cip 02';

  @override
  String get server_icon_computer => 'Computer';

  @override
  String get server_icon_laptop => 'Laptop';

  @override
  String get server_icon_terminal => 'Terminal de computer';

  @override
  String get server_icon_code => 'Cod';

  @override
  String get server_icon_ai_brain => 'Creier AI';

  @override
  String get server_icon_ai_brain2 => 'Creier AI 02';

  @override
  String get server_icon_ai_cloud => 'Cloud AI';

  @override
  String get server_icon_ai_network => 'Rețea AI';

  @override
  String get server_icon_ai_chat => 'Chat AI';

  @override
  String get server_icon_cellular => 'Rețea celulară';

  @override
  String get server_icon_plug1 => 'Ștecher 01';

  @override
  String get server_icon_plug2 => 'Ștecher 02';

  @override
  String get server_icon_bot => 'Bot';

  @override
  String get server_icon_bot2 => 'Bot 02';

  @override
  String get server_icon_robotic => 'Robotizat';

  @override
  String get server_icon_rocket => 'Rachetă';

  @override
  String get server_icon_star => 'Stea';

  @override
  String get server_icon_settings1 => 'Setări 01';

  @override
  String get server_icon_settings2 => 'Setări 02';

  @override
  String get server_icon_home1 => 'Acasă 01';

  @override
  String get server_icon_home2 => 'Acasă 02';

  @override
  String get server_icon_folder1 => 'Dosar 01';

  @override
  String get server_icon_folder2 => 'Dosar 02';

  @override
  String get server_icon_file1 => 'Fișier 01';

  @override
  String get server_icon_lock => 'Lacăt';

  @override
  String get server_icon_key => 'Cheie 01';

  @override
  String get server_icon_link => 'Link 01';

  @override
  String get server_icon_globe => 'Glob';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Săgeată la dreapta 01';

  @override
  String get server_icon_check => 'Cerc cu bifă';

  @override
  String get server_icon_alert => 'Cerc de avertizare';

  @override
  String get server_icon_info => 'Cerc informativ';

  @override
  String get server_icon_zap => 'Fulger';

  @override
  String get server_icon_cloud_upload => 'Încărcare în cloud';

  @override
  String get server_icon_cloud_download => 'Descărcare din cloud';

  @override
  String get server_icon_refresh => 'Reîmprospătare';

  @override
  String get server_icon_hard_drive => 'Hard disk';

  @override
  String get server_icon_drive => 'Unitate de stocare';

  @override
  String get personas_title => 'Personaje';

  @override
  String get persona_category_general => 'General';

  @override
  String get persona_category_coding => 'Programare';

  @override
  String get persona_category_education => 'Educație';

  @override
  String get persona_category_creative => 'Creativitate';

  @override
  String get persona_builtin_section => 'INCLUSE';

  @override
  String get persona_my_section => 'PERSONAJELE MELE';

  @override
  String get clone_edit => 'Clonează și editează';

  @override
  String get builtin_badge => 'Inclus';

  @override
  String get no_personas_found => 'Nu s-au găsit personaje';

  @override
  String get no_personas_desc =>
      'Creează primul personaj pentru a personaliza comportamentul AI.';

  @override
  String get edit_persona => 'Editează personajul';

  @override
  String get create_persona => 'Creează un personaj';

  @override
  String get create_persona_button => 'Creează';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'Nume';

  @override
  String get my_persona_hint => 'Personajul meu';

  @override
  String get category_label => 'Categorie';

  @override
  String get description_optional => 'Descriere (opțională)';

  @override
  String get description_hint => 'Ce face acest personaj...';

  @override
  String get system_prompt => 'Prompt de sistem';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Niciun prompt încă...';

  @override
  String get prompt_hint => 'Ești un asistent util...';

  @override
  String get prompt_required => 'Promptul de sistem este obligatoriu';

  @override
  String get prompt_max_chars => 'Maximum 4000 de caractere';

  @override
  String prompt_length_warning(int count) {
    return 'Prompturile lungi ($count caractere) ocupă mai mult din fereastra de context a modelului și pot încetini răspunsurile sau provoca erori pe modelele mai mici.';
  }

  @override
  String get advanced_settings => 'Setări avansate';

  @override
  String get temperature_label => 'Temperatură (0.0-2.0)';

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
  String get persona_updated => 'Personaj actualizat';

  @override
  String get persona_created => 'Personaj creat';

  @override
  String get tts_models_title => 'Modele de sinteză vocală';

  @override
  String get always_available => 'Disponibil întotdeauna';

  @override
  String get tts_system_desc =>
      'Folosește motorul de sinteză vocală integrat în dispozitivul tău.\nNu sunt necesare descărcări. Selectarea vocii folosește setările de sistem ale dispozitivului.';

  @override
  String get downloading_status => 'Se descarcă...';

  @override
  String tts_kitten_desc(String size) {
    return 'Sinteză vocală neuronală ultrarapidă, cu 8 voci expresive.\nNecesită o descărcare de $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Voci Piper rapide, disponibile offline, cu 2 voci expresive.\nNecesită o descărcare de $size pentru fiecare voce.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount voci';
  }

  @override
  String get on_device_models_title => 'Modele pe dispozitiv';

  @override
  String get settings_huggingface_token => 'Token Hugging Face (opțional)';

  @override
  String get settings_huggingface_token_desc =>
      'Necesar doar pentru modelele cu acces restricționat (de ex. Gemma). Obține un token la huggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Token salvat';

  @override
  String get settings_huggingface_token_cleared => 'Token șters';

  @override
  String get model_requires_huggingface_token =>
      'Necesită un token Hugging Face';

  @override
  String get model_missing_huggingface_token =>
      'Acest model are acces restricționat pe Hugging Face. Adaugă un token în Setări → Inferență pe dispozitiv pentru a-l descărca.';

  @override
  String get set_huggingface_token => 'Setează tokenul';

  @override
  String get clear_huggingface_token => 'Șterge';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Token de acces Hugging Face';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc =>
      'Motor AI local. Nu este necesară o cheie API.';

  @override
  String get server_type_on_device_desc =>
      'Rulează pe telefonul tău. Unele modele necesită un token Hugging Face.';

  @override
  String get server_type_lm_studio_desc =>
      'Server API local. Nu este necesară o cheie API.';

  @override
  String get available_models => 'Modele disponibile';

  @override
  String get device_memory => 'Memoria dispozitivului';

  @override
  String get ram_usage => 'Utilizare RAM';

  @override
  String get memory_healthy => 'Normală';

  @override
  String get memory_critical => 'Critică';

  @override
  String get memory_low => 'Scăzută';

  @override
  String ram_used(String percent) {
    return '$percent% utilizată';
  }

  @override
  String get available_ram => 'RAM disponibilă';

  @override
  String get total_capacity => 'Capacitate totală';

  @override
  String get loaded_status => 'Încărcat';

  @override
  String get inference_backend => 'Backend de inferență';

  @override
  String get backend_ios_notice => 'Pe iOS este disponibil doar backendul CPU.';

  @override
  String get backend_cpu_desc =>
      'Funcționează pe toate dispozitivele. Cea mai compatibilă opțiune.';

  @override
  String get backend_gpu_desc =>
      'Accelerare OpenCL. Mai rapid pe dispozitivele compatibile.';

  @override
  String get backend_npu_desc =>
      'NPU de la producător (Qualcomm/MediaTek). Cea mai rapidă inferență.';

  @override
  String get select_model_title => 'Selectează modelul';

  @override
  String get refresh_models => 'Reîmprospătează modelele';

  @override
  String get search_models_hint => 'Caută modele...';

  @override
  String get no_server_connected => 'Niciun server conectat';

  @override
  String get add_server_first =>
      'Adaugă mai întâi un server pentru a vedea modelele disponibile.';

  @override
  String get failed_load_models => 'Nu s-au putut încărca modelele';

  @override
  String get no_models_available => 'Nu sunt modele disponibile';

  @override
  String no_models_match(String searchQuery) {
    return 'Niciun model nu corespunde căutării „$searchQuery”';
  }

  @override
  String model_load_failed(String error) {
    return 'Nu s-a putut încărca modelul: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'S-a solicitat descărcarea modelului $name. Dacă Ollama este accesibil, modelul este eliberat imediat.';
  }

  @override
  String model_unloaded_success(String name) {
    return 'Modelul $name a fost descărcat cu succes';
  }

  @override
  String model_unload_failed(String error) {
    return 'Nu s-a putut descărca modelul: $error';
  }

  @override
  String get unload_from_server => 'Descarcă de pe server';

  @override
  String context_chip(String ctx) {
    return '$ctx context';
  }

  @override
  String get unload_all_models => 'Descarcă tot';

  @override
  String loaded_models_count(int count) {
    return '$count încărcate';
  }

  @override
  String get all_models_unloaded => 'Toate modelele au fost descărcate';

  @override
  String get branch_chat => 'Continuă conversația separat';

  @override
  String get branch_chat_desc => 'Începe o conversație nouă de la acest mesaj';

  @override
  String get edit_assistant_message_desc =>
      'Editează textul răspunsului asistentului.';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Treci la $modelName';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Se descarcă $modelName...';
  }

  @override
  String get download_complete_notification => 'Descărcare finalizată!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName a fost descărcat cu succes.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Descărcarea a eșuat: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Nu s-a putut descărca $modelName.';
  }

  @override
  String get engine_name_system => 'TTS de sistem';

  @override
  String get engine_tagline_system => 'Motor integrat în dispozitiv';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => 'TTS neuronal de mare viteză';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'Voci Piper offline';

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
  String get voice_lessac => 'Lessac (US)';

  @override
  String get voice_ryan => 'Ryan (US)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc =>
      'Cel mai mic model de chat cu uz general. Răspunsuri rapide, consum redus de memorie.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'Echilibru între calitate și dimensiune. Potrivit pentru conversații generale.';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Model de raționament și lanț de gândire. Ideal pentru sarcini logice.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'Modelul de top Google. Calitate maximă, necesită mai multă memorie RAM.';

  @override
  String export_header(String date) {
    return '*Exportat din LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Utilizator';

  @override
  String get export_role_assistant => '## 🤖 Asistent';

  @override
  String get export_role_system => '## ⚙️ Sistem';

  @override
  String get export_role_tool => '## 🔧 Instrument';

  @override
  String get export_text_user => '[UTILIZATOR]';

  @override
  String get export_text_assistant => '[ASISTENT]';

  @override
  String get export_text_system => '[SISTEM]';

  @override
  String get export_text_tool => '[INSTRUMENT]';

  @override
  String get export_label_user => 'UTILIZATOR';

  @override
  String get export_label_assistant => 'ASISTENT';

  @override
  String get export_label_system => 'SISTEM';

  @override
  String get export_label_tool => 'INSTRUMENT';

  @override
  String get select_model_hint =>
      'Selectează un model pentru a începe conversația';

  @override
  String get test_notification_title => 'Notificare de test';

  @override
  String get test_notification_body =>
      'Aceasta este o notificare de test pentru progresul descărcării modelului.';

  @override
  String get tts_supports_background =>
      'Acceptă redarea în fundal ca audio nativ';

  @override
  String get tts_other_services_background_note =>
      'Notă: celelalte servicii TTS acceptă redarea în fundal ca audio nativ.';

  @override
  String get gguf_imported_models_title => 'Modele GGUF importate';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Importă un fișier GGUF de pe dispozitiv sau adaugă unul de pe Hugging Face. Modelele importate rulează local cu llama.cpp.';

  @override
  String get gguf_imported_models_ready =>
      'modele importate gata pentru inferență locală.';

  @override
  String get gguf_curated_models_subtitle =>
      'Modele pentru dispozitiv selectate, pe care le poți descărca și gestiona în LocalMind.';

  @override
  String get gguf_only_supported =>
      'Pentru acest import sunt acceptate doar modelele GGUF.';

  @override
  String get gguf_imported_from_local_file => 'importat dintr-un fișier local.';

  @override
  String get gguf_import_failed => 'Nu s-a putut importa modelul GGUF';

  @override
  String get gguf_imported_from_huggingface => 'importat de pe Hugging Face.';

  @override
  String get gguf_import_canceled => 'Importul GGUF a fost anulat.';

  @override
  String get gguf_enter_huggingface_url =>
      'Introdu un URL GGUF de pe Hugging Face.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Sunt acceptate doar URL-urile GGUF oficiale de pe Hugging Face.';

  @override
  String get gguf_use_https_url =>
      'Folosește un URL HTTPS de pe Hugging Face pentru a importa GGUF.';

  @override
  String get gguf_url_must_point_to_file =>
      'URL-ul Hugging Face trebuie să trimită direct la un fișier .gguf.';

  @override
  String get gguf_unable_to_detect_file_name =>
      'Nu s-a putut determina numele fișierului GGUF.';

  @override
  String get gguf_download_empty =>
      'Fișierul GGUF descărcat este gol sau lipsește.';

  @override
  String get gguf_selected_file_missing =>
      'Fișierul de model selectat nu există.';

  @override
  String get gguf_import_action => 'Importă GGUF';

  @override
  String get gguf_overview_title => 'Adaugă/importă modele';

  @override
  String get gguf_overview_subtitle =>
      'Importă un model GGUF sau LiteRT din stocarea locală, de la un URL sau caută pe Hugging Face. Modelele importate rămân pe acest dispozitiv.';

  @override
  String get gguf_imported_count_label => 'importate';

  @override
  String get gguf_local_files_label => 'fișiere locale';

  @override
  String get gguf_huggingface_label => 'Hugging Face';

  @override
  String get gguf_import_local_title => 'Importă GGUF local';

  @override
  String get gguf_import_local_subtitle =>
      'Copiază un fișier .gguf de pe acest dispozitiv';

  @override
  String get gguf_import_huggingface_title => 'Importă de pe Hugging Face';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Lipește un URL GGUF sau calea unui depozit';

  @override
  String get gguf_no_imported_title => 'Încă nu ai modele GGUF importate';

  @override
  String get gguf_no_imported_subtitle =>
      'Poți adăuga propriul fișier GGUF din stocarea dispozitivului sau poți lipi un URL Hugging Face ori calea unui depozit care duce la un fișier .gguf.';

  @override
  String get gguf_import_huggingface_dialog_title =>
      'Importă GGUF de pe Hugging Face';

  @override
  String get gguf_import_huggingface_dialog_subtitle =>
      'Lipește un URL GGUF direct sau calea unui depozit Hugging Face, precum `owner/repo/blob/main/model.gguf`. Linkurile Blob sunt convertite automat.';

  @override
  String get gguf_url_or_repo_path => 'URL GGUF sau cale depozit';

  @override
  String get paste => 'Lipește';

  @override
  String get gguf_browse => 'Răsfoiește GGUF-uri';

  @override
  String get gguf_huggingface_token_ready => 'Token Hugging Face disponibil';

  @override
  String get gguf_huggingface_token_optional =>
      'Token opțional, dar recomandat';

  @override
  String get gguf_huggingface_token_ready_desc =>
      'Tokenul salvat va fi folosit automat pentru depozitele cu acces restricționat sau private.';

  @override
  String get gguf_huggingface_token_optional_desc =>
      'Este necesar un token Hugging Face. Adaugă unul în Setări dacă acest GGUF are acces restricționat sau este privat.';

  @override
  String get gguf_downloading => 'Se descarcă GGUF';

  @override
  String get gguf_preparing => 'Se pregătește';

  @override
  String get gguf_preparing_download => 'Se pregătește descărcarea...';

  @override
  String get gguf_cancel_import => 'Anulează importul';

  @override
  String get clipboard_empty => 'Clipboardul este gol.';

  @override
  String get could_not_open_huggingface =>
      'Nu s-a putut deschide Hugging Face.';

  @override
  String get gguf_paste_url_error =>
      'Lipește un URL GGUF Hugging Face sau calea unui depozit.';

  @override
  String get gguf_blob_link => 'Link Blob';

  @override
  String get gguf_repository_label => 'Depozit';

  @override
  String get gguf_detected_path_label => 'Cale detectată';

  @override
  String get gguf_imported_section_label => 'GGUF importat';

  @override
  String get gguf_already_available => 'Deja disponibil pe acest dispozitiv';

  @override
  String get gguf_curated_models_short => 'Modele pentru dispozitiv selectate';

  @override
  String get gguf_vision_projector => 'Proiector vizual';

  @override
  String get gguf_attach_projector => 'Atașează proiectorul vizual';

  @override
  String get gguf_change_projector => 'Schimbă proiectorul vizual';

  @override
  String get gguf_remove_projector => 'Elimină proiectorul';

  @override
  String get gguf_projector_attached =>
      'Proiectorul vizual a fost atașat cu succes';

  @override
  String get gguf_projector_removed => 'Proiectorul vizual a fost eliminat';

  @override
  String gguf_projector_auto_detected(String name) {
    return 'Proiector vizual detectat și asociat automat: $name';
  }

  @override
  String get gguf_is_projector_file =>
      'Fișierul selectat este un proiector vizual (mmproj), nu un model autonom.';

  @override
  String get gguf_projector_url_label =>
      'URL proiector vizual (mmproj opțional)';

  @override
  String get gguf_projector_url_hint =>
      'https://huggingface.co/.../mmproj-...gguf';

  @override
  String get gguf_vision_not_supported_error =>
      'Modelul activ nu acceptă atașamente de imagini. Atașează un proiector vizual (mmproj) sau selectează un model cu suport pentru imagini.';

  @override
  String get execute_tool_title => 'Execută instrumentul';

  @override
  String get execute_tool_request_desc =>
      'Modelul solicită executarea următorului instrument:';

  @override
  String get reject => 'Respinge';

  @override
  String get approve => 'Aprobă';

  @override
  String get server_type_help =>
      'Alege furnizorul înainte de a completa detaliile conexiunii.';

  @override
  String get server_identity_title => 'Identitate';

  @override
  String get server_identity_desc =>
      'Dă un nume acestui server și alege cum apare în listă.';

  @override
  String get server_connection_title => 'Conexiune';

  @override
  String get server_connection_desc =>
      'Folosește adresa și portul expuse de serverul tău.';

  @override
  String get server_authentication_title => 'Autentificare';

  @override
  String get server_authentication_required_desc =>
      'OpenRouter necesită o cheie API înainte de testare.';

  @override
  String get server_authentication_required_desc_requesty =>
      'Requesty necesită o cheie API înainte de testare.';

  @override
  String get server_authentication_required_desc_standard_compute =>
      'Standard Compute necesită o cheie API înainte de testare.';

  @override
  String get server_authentication_optional_desc =>
      'Lasă cheia API necompletată dacă serverul nu necesită una.';

  @override
  String get mcp_tools_title => 'Instrumente MCP';

  @override
  String get available_tools => 'Instrumente disponibile';

  @override
  String get unable_load_tools => 'Nu s-au putut încărca instrumentele';

  @override
  String get no_tools_registered => 'Nu sunt înregistrate instrumente';

  @override
  String get no_tools_registered_desc =>
      'Activează serverul MCP demonstrativ sau adaugă integrări MCP din setările chatului.';

  @override
  String get example_mcp_server_title => 'Server MCP demonstrativ';

  @override
  String get example_mcp_server_desc =>
      'Înregistrează example.echo și example.word_count prin același furnizor de instrumente MCP folosit de serverele externe.';

  @override
  String get disable_example_server => 'Dezactivează serverul demonstrativ';

  @override
  String get enable_example_server => 'Activează serverul demonstrativ';

  @override
  String get built_in_label => 'Integrat';

  @override
  String get highlights_label => 'Puncte forte';

  @override
  String get built_with_label => 'Creat cu';

  @override
  String get local_label => 'Local';

  @override
  String get gguf_format_label => 'GGUF';

  @override
  String get tool_status_requested => 'Solicitat';

  @override
  String get tool_status_approved => 'Aprobat';

  @override
  String get tool_status_rejected => 'Respins';

  @override
  String get tool_status_running => 'În curs';

  @override
  String get tool_status_done => 'Gata';

  @override
  String get tool_status_failed => 'Eșuat';

  @override
  String get model_favorite_toggle => 'Adaugă sau elimină de la favorite';

  @override
  String get model_set_default => 'Setează ca model implicit';

  @override
  String get model_clear_default => 'Elimină ca model implicit';

  @override
  String get model_default_badge => 'Implicit';

  @override
  String get model_note_label => 'Notă';

  @override
  String get model_note_hint => 'Adaugă o notă despre acest model…';

  @override
  String get model_update_available => 'Actualizare disponibilă';

  @override
  String get model_update_button => 'Actualizează';

  @override
  String get unload_models_before_load =>
      'Descarcă toate modelele înainte de a încărca unul nou';

  @override
  String get settings_allow_background_downloads =>
      'Permite descărcările în fundal';

  @override
  String get settings_allow_background_downloads_desc =>
      'Continuă descărcarea modelelor când schimbi aplicația sau blochezi ecranul.';

  @override
  String get settings_download_over_wifi_only => 'Descarcă doar prin Wi-Fi';

  @override
  String get settings_download_over_wifi_only_desc =>
      'Descarcă modele doar când este disponibilă o conexiune Wi-Fi eligibilă sau fără tarifare.';

  @override
  String get temp_chat_keyboard_incognito =>
      'Tastatură incognito în chatul temporar';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Dezactivează învățarea și sugestiile tastaturii în chaturile temporare (de ex., modul incognito SwiftKey).';

  @override
  String get resume_last_chat => 'Reia ultimul chat la pornire';

  @override
  String get resume_last_chat_desc =>
      'Restabilește ultima conversație deschisă când redeschizi aplicația.';

  @override
  String get export_all_data => 'Exportă toate datele';

  @override
  String get import_all_data => 'Importă toate datele';

  @override
  String get export_data_success => 'Backupul a fost exportat cu succes';

  @override
  String get import_data_success => 'Backupul a fost importat cu succes';

  @override
  String import_data_failed(String error) {
    return 'Importul backupului a eșuat: $error';
  }

  @override
  String get import_data_confirm =>
      'Importi conversațiile și personajele personalizate din acest backup? Elementele existente cu aceleași ID-uri vor fi actualizate.';

  @override
  String get import_settings_confirm =>
      'Înlocuiești setările actuale cu cele din backupul importat?';

  @override
  String get export_conversations => 'Exportă conversațiile';

  @override
  String get import_conversations => 'Importă conversațiile';

  @override
  String get export_personas => 'Exportă personajele';

  @override
  String get import_personas => 'Importă personajele';

  @override
  String get export_settings => 'Exportă setările';

  @override
  String get import_settings => 'Importă setările';

  @override
  String get export_all_zip => 'Exportă tot (ZIP)';

  @override
  String get import_all_zip => 'Importă tot (ZIP)';

  @override
  String get duplicate_chat => 'Duplică chatul';

  @override
  String get duplicate_chat_success => 'Chat duplicat';

  @override
  String get move_to_folder => 'Mută în dosar';

  @override
  String get remove_from_folder => 'Elimină din dosar';

  @override
  String get create_folder => 'Creează dosar';

  @override
  String get new_folder => 'Dosar nou';

  @override
  String get folder_name_hint => 'Numele dosarului';

  @override
  String get all_chats => 'Toate';

  @override
  String get unfiled_chats => 'Fără dosar';

  @override
  String get create => 'Creează';

  @override
  String get server_path_prefix_label => 'Prefixul căii API';

  @override
  String get server_path_prefix_hint => '/your-secret-token';

  @override
  String get search_message_contents => 'Caută în conținutul mesajelor';

  @override
  String get message_search_results => 'Potriviri în mesaje';

  @override
  String get saved_messages_title => 'Mesaje salvate';

  @override
  String get nav_saved_messages => 'Mesaje salvate';

  @override
  String get saved_messages_empty =>
      'Nu ai încă mesaje salvate. Salvează un mesaj din meniul său de opțiuni.';

  @override
  String get save_message => 'Salvează mesajul';

  @override
  String get message_saved => 'Mesaj salvat';

  @override
  String token_count(int count) {
    return '$count tokenuri';
  }

  @override
  String estimated_token_count(int count) {
    return '~$count tokenuri (estimare)';
  }

  @override
  String get test_tts_section_title => 'Testează vocea';

  @override
  String get test_tts_hint =>
      'Introdu text pentru a asculta motorul TTS actual…';

  @override
  String get test_speak_button => 'Vorbește';

  @override
  String get scroll_to_bottom => 'Derulează în jos';

  @override
  String get generate_ai_response => 'Generează răspuns AI';

  @override
  String get no_response => 'Niciun răspuns';

  @override
  String get export => 'Exportă';

  @override
  String get import => 'Importă';

  @override
  String get conversations_label => 'Conversații';

  @override
  String get personas_label => 'Personaje';

  @override
  String get settings_label => 'Setări';

  @override
  String get export_conversation => 'Exportă conversația';

  @override
  String get tts_process_markdown => 'Procesează Markdown pentru citire vocală';

  @override
  String get tts_process_markdown_desc =>
      'Elimină formatarea, precum **aldinul**, înainte de a citi cu voce tare';

  @override
  String get tts_skip_seconds => 'Interval de salt';

  @override
  String get tts_skip_seconds_desc =>
      'Mărimea saltului înainte sau înapoi în timpul redării';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}s';
  }

  @override
  String get preview_system_prompts =>
      'Previzualizează instrucțiunile de sistem';

  @override
  String get welcome_message_1 => 'Cu ce te pot ajuta astăzi?';

  @override
  String get welcome_message_2 =>
      'Întreabă-mă orice — sunt gata când ești și tu.';

  @override
  String get welcome_message_3 =>
      'Datele tale sunt procesate local și nu părăsesc niciodată dispozitivul.';

  @override
  String get welcome_message_4 =>
      'Ai nevoie de idei? Încearcă una dintre sugestiile rapide.';

  @override
  String get temporary_chat => 'Chat temporar';

  @override
  String get temporary_chat_desc => 'Chaturile nu se salvează în istoric.';

  @override
  String get temporary_chat_banner =>
      'Chat temporar — nu se salvează în istoric';

  @override
  String get temporary_chat_save_warning_title =>
      'Salvezi mesajul din chatul temporar?';

  @override
  String get temporary_chat_save_warning_body =>
      'Acest chat este temporar și ascuns din istoric. Mesajul salvat va apărea în continuare la Mesaje salvate.';

  @override
  String get save_to_history => 'Salvează în istoric';

  @override
  String get share_conversation => 'Partajează conversația';

  @override
  String get download_tts_audio => 'Descarcă audio';

  @override
  String get tts_download_unavailable =>
      'Descărcarea este disponibilă doar pentru Piper și Kitten TTS';

  @override
  String get tts_download_no_audio =>
      'Nu există încă audio disponibil pentru descărcare';

  @override
  String get tts_download_success => 'Audio salvat';

  @override
  String get return_to_chat => 'Revino la chat';

  @override
  String get return_to_temp_chat => 'Revino la chatul temporar';

  @override
  String get insert_saved_message => 'Inserează mesaj salvat';

  @override
  String get insert_saved_message_desc =>
      'Alege un mesaj salvat pentru a-l adăuga la textul introdus';

  @override
  String get model_info => 'Informații despre model';

  @override
  String get model_name => 'Numele modelului';

  @override
  String get model_identifier => 'Identificator';

  @override
  String get model_capabilities => 'Capabilități';

  @override
  String get model_api_pricing => 'Tarife API (per 1M tokenuri)';

  @override
  String get not_available => 'Indisponibil';

  @override
  String get save_message_folders => 'Salvează mesajul';

  @override
  String get remove_from_saved => 'Elimină din mesajele salvate';

  @override
  String get message_already_saved => 'Salvat';

  @override
  String get stream_ttft => 'Timp până la primul token';

  @override
  String get stream_tokens_per_sec => 'Tokenuri pe secundă';

  @override
  String get stream_stop_reason => 'Motivul opririi';

  @override
  String get stream_input_tokens => 'Tokenuri de intrare';

  @override
  String get stream_output_tokens => 'Tokenuri de ieșire';

  @override
  String get stream_generation_time => 'Timp de generare';

  @override
  String get attach_image => 'Fotografii';

  @override
  String get attach_text_document => 'Documente';

  @override
  String get attach_shortcut_camera => 'Cameră';

  @override
  String get attach_shortcut_images => 'Fotografii';

  @override
  String get attach_shortcut_documents => 'Fișiere';

  @override
  String get attach_shortcut_saved => 'Salvate';

  @override
  String get add_attachment => 'Adaugă atașament';

  @override
  String get add_to_chat => 'Adaugă la chat';

  @override
  String get choose_what_to_attach => 'Ce vrei să adaugi?';

  @override
  String get choose_attachment_subtitle => 'Alege o sursă de atașat la mesaj';

  @override
  String get photo_permission_denied =>
      'Este necesar accesul la fotografii pentru a atașa imagini';

  @override
  String get select_model_prompt => 'Selectează un model';

  @override
  String get characters_label => 'Caractere';

  @override
  String get exit_temporary_chat_title => 'Ieși din chatul temporar?';

  @override
  String get exit_temporary_chat_body =>
      'Chatul temporar actual va fi șters și vei reveni la un chat nou.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Acest mesaj a fost salvat dintr-un chat temporar și nu poate fi deschis în conversația sa originală.';

  @override
  String get filter_title => 'Filtru';

  @override
  String get filter_pinned => 'Fixate';

  @override
  String get filter_archived => 'Arhivate';

  @override
  String get filter_temp_chats => 'Chaturi temporare';

  @override
  String get filter_user_messages => 'Mesaje de la utilizator';

  @override
  String get filter_assistant_messages => 'Mesaje de la asistent';

  @override
  String get archive_chat => 'Arhivează';

  @override
  String get unarchive_chat => 'Dezarhivează';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count de mesaje',
      few: '$count mesaje',
      one: '1 mesaj',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return '$count caractere';
  }

  @override
  String get generate_title_with_ai => 'Generează cu AI';

  @override
  String get generating_title => 'Se generează…';

  @override
  String get generate_title_failed => 'Titlul nu a putut fi generat';

  @override
  String get lm_studio_model_browser_title => 'Răsfoiește modelele';

  @override
  String get lm_studio_model_search_hint => 'Caută modele după nume sau autor…';

  @override
  String get lm_studio_staff_picks => 'Recomandările echipei';

  @override
  String get lm_studio_community_models => 'Modele ale comunității';

  @override
  String get lm_studio_no_models => 'Nu s-au găsit modele';

  @override
  String lm_studio_models_count(int count) {
    return '$count modele';
  }

  @override
  String get lm_studio_browse_models => 'Răsfoiește și descarcă';

  @override
  String get lm_studio_model_search => 'Căutare modele LMS';

  @override
  String get lm_studio_downloads_title => 'Descărcări';

  @override
  String get lm_studio_choose_quant => 'Alege o opțiune de descărcare';

  @override
  String get lm_studio_use_default_quant => 'Folosește valoarea implicită';

  @override
  String get lm_studio_recommended => 'Recomandat';

  @override
  String get lm_studio_clear_downloads => 'Șterge descărcările finalizate';

  @override
  String get lm_studio_no_downloads => 'Nicio descărcare încă';

  @override
  String get lm_studio_downloads_disclaimer =>
      'Descărcările rulează pe gazda LM Studio. Întreruperea, oprirea și ștergerea modelelor trebuie făcute pe acel computer — nu din această aplicație.';

  @override
  String get lm_studio_staff_pick => 'Recomandarea echipei';

  @override
  String get lm_studio_params => 'PARAMETRI';

  @override
  String get lm_studio_arch => 'ARHITECTURĂ';

  @override
  String get lm_studio_domain => 'DOMENIU';

  @override
  String get lm_studio_format => 'FORMAT';

  @override
  String get lm_studio_vision => 'Viziune';

  @override
  String get lm_studio_tool_use => 'Utilizarea instrumentelor';

  @override
  String get lm_studio_reasoning => 'Raționament';

  @override
  String get openrouter_pricing_free => 'Gratuit';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Intrare $input / Ieșire $output per 1M tokenuri';
  }

  @override
  String get lm_studio_download_options => 'Opțiuni de descărcare';

  @override
  String get lm_studio_download => 'Descarcă';

  @override
  String lm_studio_download_size(String size) {
    return 'Descarcă $size';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Se descarcă $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'Fișierul README nu este disponibil pentru acest model.';

  @override
  String get lm_studio_full_gpu_offload =>
      'Este posibilă descărcarea completă pe GPU';

  @override
  String get lm_studio_partial_gpu_offload =>
      'Este posibilă descărcarea parțială pe GPU';

  @override
  String get lm_studio_likely_too_large => 'Probabil prea mare';

  @override
  String get lm_studio_available_ram_gb => 'RAM disponibilă (GB, opțional)';

  @override
  String get lm_studio_available_vram_gb => 'VRAM disponibilă (GB, opțional)';

  @override
  String get lm_studio_memory_settings_title => 'Memorie pentru recomandări';

  @override
  String get lm_studio_memory_settings_desc =>
      'Folosită pentru a estima dacă modelele încap pe dispozitivul tău în browserul de modele.';

  @override
  String get think_button_label => 'Gândește';

  @override
  String get thinking_mode_title => 'Mod de gândire';

  @override
  String get reasoning_effort_low => 'Scăzut';

  @override
  String get reasoning_effort_medium => 'Mediu';

  @override
  String get reasoning_effort_high => 'Ridicat';

  @override
  String get reasoning_effort_minimal => 'Minim';

  @override
  String get reasoning_effort_xhigh => 'Foarte ridicat';

  @override
  String get reasoning_effort_max => 'Maxim';

  @override
  String get reasoning_effort_off => 'Dezactivat';

  @override
  String get could_not_read_file => 'Fișierul nu a putut fi citit';

  @override
  String get server_offline => 'Server offline';

  @override
  String get could_not_establish_connection =>
      'Nu s-a putut stabili o conexiune cu serverul. Verifică dacă serverul rulează și dacă setările pentru gazdă/port sunt corecte.';

  @override
  String get retry_connection => 'Încearcă din nou conexiunea';

  @override
  String get tokens_label => 'Tokenuri';

  @override
  String get enter_context_length => 'Introdu lungimea contextului...';

  @override
  String get openrouter_disclosure =>
      'Prin conectarea acestui furnizor, mesajele și datele introduse în chat vor fi trimise către serverele sale. LocalMind nu urmărește și nu stochează conversațiile tale.';

  @override
  String get requesty_disclosure =>
      'Prin conectarea acestui furnizor, mesajele și datele introduse în chat vor fi trimise către serverele sale. LocalMind nu urmărește și nu stochează conversațiile tale.';

  @override
  String get standard_compute_disclosure =>
      'Prin conectarea acestui furnizor, mesajele și datele introduse în chat vor fi trimise către serverele sale. LocalMind nu urmărește și nu stochează conversațiile tale.';

  @override
  String get welcome_message_cloud =>
      'Mesajele tale sunt trimise furnizorului conectat.';

  @override
  String get privacy_policy => 'Politica de confidențialitate';

  @override
  String get cloud_sync => 'Sincronizare în cloud S3';

  @override
  String get cloud_sync_description =>
      'Sincronizare criptată de la un capăt la altul cu propriul server compatibil cu S3';

  @override
  String get cloud_sync_endpoint => 'URL endpoint';

  @override
  String get cloud_sync_bucket => 'Bucket';

  @override
  String get cloud_sync_region => 'Regiune';

  @override
  String get cloud_sync_prefix => 'Prefix';

  @override
  String get cloud_sync_access_key => 'ID cheie de acces';

  @override
  String get cloud_sync_secret_key => 'Cheie secretă de acces';

  @override
  String get cloud_sync_session_token => 'Token de sesiune (opțional)';

  @override
  String get cloud_sync_passphrase => 'Frază de acces pentru criptare';

  @override
  String get cloud_sync_confirm_passphrase => 'Confirmă fraza de acces';

  @override
  String get cloud_sync_path_style => 'Folosește adresarea de tip path-style';

  @override
  String get cloud_sync_allow_http => 'Permite HTTP nesecurizat';

  @override
  String get cloud_sync_http_warning =>
      'HTTP expune metadatele cererilor și acreditările în rețea. Folosește-l doar pentru un server S3 local de încredere.';

  @override
  String get cloud_sync_test => 'Testează conexiunea';

  @override
  String get cloud_sync_enable => 'Activează sincronizarea criptată';

  @override
  String get cloud_sync_now => 'Sincronizează acum';

  @override
  String get cloud_sync_disconnect => 'Deconectează acest dispozitiv';

  @override
  String get cloud_sync_last_synced => 'Ultima sincronizare';

  @override
  String get cloud_sync_never => 'Niciodată';

  @override
  String get cloud_sync_conflicts => 'Conflicte păstrate';

  @override
  String get cloud_sync_passphrase_mismatch =>
      'Frazele de acces nu se potrivesc';

  @override
  String get crash_report_title => 'Ceva nu a mers bine';

  @override
  String get crash_report_stack_trace => 'Urmărirea stivei';

  @override
  String get crash_report_tap_to_expand => 'Atinge pentru extindere';

  @override
  String get crash_report_button => 'Raportează această eroare';

  @override
  String get crash_try_again => 'Încearcă din nou';

  @override
  String get crash_report_empty_stack => '<empty>';

  @override
  String get crash_report_disclaimer =>
      'Raportarea deschide GitHub cu diagnosticele completate. Tu decizi — nimic nu este trimis automat. Verifică și elimină orice conținut sensibil înainte de trimitere.';

  @override
  String get crash_report_copied => 'Copiat în clipboard';

  @override
  String get report_a_problem => 'Raportează o problemă';

  @override
  String get rename_folder => 'Redenumește folderul';

  @override
  String get delete_folder => 'Șterge folderul';

  @override
  String get delete_folder_title => 'Ștergi folderul?';

  @override
  String delete_folder_body(String name) {
    return 'Sigur vrei să ștergi „$name”? Conversațiile sau mesajele salvate din interior vor fi mutate înapoi la „Necatalogate”. Acțiunea nu poate fi anulată.';
  }

  @override
  String get folder_name_required => 'Introdu un nume pentru folder';

  @override
  String get model_required_toast => 'Mai întâi trebuie să selectezi un model';

  @override
  String get settings_concise_voice_responses => 'Răspunsuri vocale concise';

  @override
  String get settings_concise_voice_responses_desc =>
      'Păstrează răspunsurile LLM scurte (un paragraf scurt) și pune întrebări de continuare în modul vocal.';

  @override
  String get s3_connection_succeeded => 'Conexiunea S3 a reușit.';

  @override
  String failed_to_open_url(String error) {
    return 'Nu s-a putut deschide URL-ul: $error';
  }

  @override
  String failed_to_copy(String error) {
    return 'Copierea a eșuat: $error';
  }

  @override
  String get file_explorer_not_found =>
      'Nu a fost găsit niciun explorator de fișiere. Asigură-te că pe dispozitiv este instalată și activată o aplicație de gestionare a fișierelor.';

  @override
  String export_data_failed(String error) {
    return 'Exportul copiei de rezervă a eșuat: $error';
  }

  @override
  String file_pick_failed(String error) {
    return 'Selectarea fișierului a eșuat: $error';
  }

  @override
  String image_pick_failed(String error) {
    return 'Selectarea imaginii a eșuat: $error';
  }

  @override
  String get calendar_access => 'Acces la calendar';

  @override
  String get calendar_access_desc =>
      'Permite AI-ului să citească și să creeze evenimente în calendar';

  @override
  String get calendar_permission_denied =>
      'Permisiunea pentru calendar a fost refuzată. Acordă acces la calendar din setările dispozitivului.';

  @override
  String get location_access => 'Acces la locație';

  @override
  String get location_access_desc =>
      'Permite AI-ului să obțină locația ta actuală și numele locului';

  @override
  String get location_permission_denied =>
      'Permisiunea pentru locație a fost refuzată. Acordă acces la locație din setările dispozitivului.';

  @override
  String get builtin_ai_not_supported =>
      'AI-ul integrat nu este compatibil cu acest dispozitiv.';

  @override
  String get builtin_ai_unsupported_desc =>
      'Hardware-ul sau sistemul de operare al dispozitivului nu acceptă AI-ul de sistem pe dispozitiv (de ex. Gemini Nano / Apple Intelligence). Alege în schimb un model care poate fi descărcat.';

  @override
  String get builtin_ai_unsupported_chip => 'Necompatibil';

  @override
  String get builtin_ai_enable => 'Activează';

  @override
  String get model_reasoning_default => 'Implicit pentru model';

  @override
  String get model_reasoning_on => 'Activat';

  @override
  String get model_reasoning_help =>
      'Se aplică următorului răspuns. Dezactivarea oprește gândirea dacă șablonul de chat al modelului permite acest lucru.';

  @override
  String get model_reasoning_save_error =>
      'Modul de gândire nu a putut fi salvat. Încearcă din nou.';

  @override
  String get on_device_engine_failed_error =>
      'Modelul de pe dispozitiv nu a mai răspuns, de obicei pentru că discuția a depășit fereastra de context. Modelul se reîncarcă. Încearcă din nou, începe un chat nou sau mărește lungimea contextului din setări.';

  @override
  String get stt_error_no_match =>
      'Nu a fost recunoscută nicio vorbire. Atinge pentru a încerca din nou.';

  @override
  String get stt_error_speech_timeout =>
      'Nu a fost detectată vorbire. Atinge pentru a încerca din nou.';

  @override
  String get stt_error_permission =>
      'Permisiunea pentru microfon a fost refuzată.';

  @override
  String get stt_error_busy =>
      'Recunoașterea vocală este ocupată. Încearcă din nou.';

  @override
  String get stt_error_network =>
      'Eroare de rețea. Verifică conexiunea și încearcă din nou.';

  @override
  String get stt_error_audio =>
      'Eroare la înregistrarea audio. Verifică microfonul.';

  @override
  String get stt_error_client =>
      'Serviciul de recunoaștere vocală nu a pornit. Asigură-te că este instalată o aplicație de introducere vocală și setată ca recunoaștere vocală implicită, apoi încearcă din nou.';

  @override
  String get stt_error_language =>
      'Recunoașterea vocală de pe acest dispozitiv nu acceptă limba ta.';

  @override
  String get stt_error_unavailable =>
      'Nu a fost găsit niciun serviciu de recunoaștere vocală pe acest dispozitiv. Instalează o aplicație de introducere vocală (de exemplu, FUTO Voice Input) și seteaz-o ca recunoaștere vocală implicită.';

  @override
  String stt_error_generic(String code) {
    return 'Eroare de recunoaștere vocală: $code';
  }

  @override
  String get send_temperature_to_api => 'Trimite temperatura';

  @override
  String get send_top_p_to_api => 'Trimite Top P';

  @override
  String get send_sampling_params_desc =>
      'Dezactivează pentru furnizorii sau modelele care resping acest parametru (de exemplu, unele modele de raționament). Se aplică tuturor chat-urilor cu servere la distanță.';

  @override
  String get default_system_prompt => 'Prompt de sistem implicit';

  @override
  String get default_system_prompt_desc =>
      'Folosit pentru chat-urile fără persona sau prompt de sistem specific chat-ului.';

  @override
  String get default_system_prompt_hint => 'Ești un asistent util…';

  @override
  String background_generation_notice(String title) {
    return 'Se răspunde încă în „$title”. Poți trimite un mesaj aici după ce se termină. Atinge pentru a deschide.';
  }

  @override
  String get background_generation_notice_untitled =>
      'Un alt chat încă generează un răspuns. Poți trimite un mesaj aici după ce se termină. Atinge pentru a deschide.';

  @override
  String background_generation_notice_info(String title) {
    return 'Se generează un răspuns în „$title” în fundal. Atinge pentru a deschide.';
  }

  @override
  String get background_generation_notice_info_untitled =>
      'Se generează un răspuns în alt chat, în fundal. Atinge pentru a deschide.';

  @override
  String background_generation_notice_multiple(int count) {
    return 'Se generează răspunsuri în $count chat-uri, în fundal.';
  }

  @override
  String get background_generation_chat_untitled => 'Chat fără titlu';

  @override
  String get model_loaded_status => 'Încărcat';

  @override
  String get new_chat_title => 'Întreabă orice.';

  @override
  String get new_chat_on_device_headline => 'Rămâne pe acest telefon.';

  @override
  String get new_chat_on_device_detail =>
      'Răspunsurile sunt generate chiar aici — fără încărcare, fără cont, funcționează offline.';

  @override
  String new_chat_self_hosted_headline(String server) {
    return 'Răspuns de la $server.';
  }

  @override
  String get new_chat_self_hosted_detail =>
      'Mesajele ajung la propriul server, nu la o terță parte.';

  @override
  String new_chat_endpoint_detail(String server) {
    return 'Mesajele sunt trimise la $server, un endpoint compatibil cu OpenAI.';
  }

  @override
  String get new_chat_cloud_headline => 'Răspuns în cloud.';

  @override
  String new_chat_router_detail(String provider) {
    return 'Mesajele sunt trimise către $provider și către furnizorul modelului la care acesta le direcționează.';
  }

  @override
  String get new_chat_ollama_cloud_detail =>
      'Mesajele sunt trimise către serviciul cloud Ollama.';

  @override
  String get new_chat_no_server_headline => 'Alege un model pentru a începe.';

  @override
  String get new_chat_no_server_detail =>
      'Rulează un model pe acest telefon sau conectează un server.';

  @override
  String get new_chat_works_offline => 'Funcționează offline';

  @override
  String get new_chat_no_model => 'Niciun model selectat';

  @override
  String get new_chat_not_connected => 'Neconectat';

  @override
  String get attach_send_as_assistant => 'Trimite ca asistent';

  @override
  String get attach_send_as_assistant_desc =>
      'Adaugă mesajul tău ca răspuns; nu se generează nimic.';

  @override
  String get chat_input_hint_assistant => 'Scrie răspunsul asistentului';

  @override
  String get settings_section_general => 'General';

  @override
  String get settings_section_chat => 'Chat';

  @override
  String get settings_section_voice => 'Voce';

  @override
  String get settings_section_models => 'Modele';

  @override
  String get settings_section_data => 'Confidențialitate și date';

  @override
  String get settings_search_hint => 'Caută în setări';

  @override
  String get settings_more_chat_options => 'Mai multe opțiuni de chat';

  @override
  String get settings_group_replies => 'Răspunsuri';

  @override
  String get settings_group_prompt => 'Prompt de sistem și parametri';

  @override
  String get settings_group_composer => 'Editor de mesaje';

  @override
  String get sidebar_section_chats => 'Chaturi';

  @override
  String get sidebar_section_models => 'Modele';

  @override
  String get sidebar_section_app => 'Aplicație';

  @override
  String get add_models_button => 'Adaugă modele';

  @override
  String get curated_models_title => 'Modele recomandate';

  @override
  String curated_models_count(Object count) {
    return '$count modele';
  }

  @override
  String get your_models_title => 'Modelele tale';

  @override
  String your_models_count(Object count) {
    return '$count adăugate';
  }

  @override
  String get remove_model_from_list => 'Elimină din listă';

  @override
  String get delete_model_file_first => 'Șterge mai întâi fișierul modelului';

  @override
  String get add_model_title => 'Adaugă un model';

  @override
  String get add_model_gguf_tab => 'GGUF';

  @override
  String get add_model_litert_tab => 'LiteRT';

  @override
  String get add_model_gguf_url_label => 'URL GGUF Hugging Face';

  @override
  String get add_model_litert_url_label => 'URL LiteRT Hugging Face';

  @override
  String get add_model_add_from_url => 'Adaugă de la URL';

  @override
  String get add_model_pick_local_file => 'Alege un fișier local';

  @override
  String get add_model_search_gguf => 'Caută modele GGUF';

  @override
  String get add_model_search_litert => 'Caută modele LiteRT';

  @override
  String get add_model_searching => 'Se caută…';

  @override
  String get add_model_search => 'Caută';

  @override
  String get add_model_loading_files => 'Se încarcă fișierele…';

  @override
  String get add_model_cancel => 'Anulează';

  @override
  String add_model_files_in(Object repo) {
    return 'Fișiere în $repo';
  }

  @override
  String get add_model_no_gguf_files => 'Nu s-au găsit fișiere GGUF.';

  @override
  String get add_model_no_litert_files => 'Nu s-au găsit fișiere LiteRT.';

  @override
  String get add_model_added => 'Adăugat';

  @override
  String get add_model_add => 'Adaugă';

  @override
  String get add_model_gguf_added => 'Model GGUF adăugat';

  @override
  String get add_model_litert_added => 'Model LiteRT adăugat';

  @override
  String add_model_file_added(Object name) {
    return '$name a fost adăugat';
  }

  @override
  String get add_model_already_added => 'Modelul a fost deja adăugat';

  @override
  String get model_still_stopping =>
      'Modelul încă se oprește. Așteaptă înainte să încerci din nou.';

  @override
  String get localApiTitle => 'API local';

  @override
  String get localApiIntro =>
      'Folosește modelul încărcat în alte aplicații printr-un API compatibil cu OpenAI. Pornește serverul înainte să schimbi aplicația.';

  @override
  String get localApiRunning => 'API-ul local rulează';

  @override
  String get localApiStopped => 'Server oprit';

  @override
  String get localApiStarting => 'Se pornește serverul…';

  @override
  String get localApiStopping => 'Se oprește serverul…';

  @override
  String get localApiRotating => 'Se înlocuiește cheia API…';

  @override
  String get localApiModelRequired =>
      'Încarcă mai întâi un model LiteRT descărcat sau un model GGUF importat.';

  @override
  String get localApiInvalidPort => 'Introdu un port între 1024 și 65535.';

  @override
  String get localApiStartFailed =>
      'Android nu a putut porni serverul. Încearcă din nou cât timp LocalMind este deschis.';

  @override
  String get localApiPortUnavailable =>
      'Nu s-a putut asculta pe acest port. Încearcă alt port.';

  @override
  String get localApiKeyFailed => 'Nu s-a putut accesa cheia API.';

  @override
  String get localApiModelId => 'ID model';

  @override
  String get localApiTextAndTools => 'Text și apeluri de instrumente';

  @override
  String get localApiTextOnly => 'Doar text';

  @override
  String get localApiPort => 'Port';

  @override
  String get localApiLan =>
      'Permite accesul altor dispozitive din rețeaua locală';

  @override
  String get localApiLanHint =>
      'Folosește această opțiune doar într-o rețea de încredere. HTTP nu criptează prompturile sau cheia API.';

  @override
  String get localApiStart => 'Pornește serverul';

  @override
  String get localApiStop => 'Oprește serverul';

  @override
  String get localApiUrl => 'URL de bază pentru același dispozitiv';

  @override
  String get localApiLanUrl => 'URL de bază pentru rețeaua locală';

  @override
  String get localApiNoLan =>
      'Nu este disponibilă nicio adresă de rețea locală.';

  @override
  String get localApiKey => 'Cheie API';

  @override
  String get localApiShowKey => 'Afișează cheia API';

  @override
  String get localApiHideKey => 'Ascunde cheia API';

  @override
  String get localApiRotateKey => 'Înlocuiește cheia API';

  @override
  String get localApiRotateHint =>
      'Cheia actuală nu va mai funcționa. Actualizează cheia în aplicațiile conectate.';

  @override
  String localApiCopy(String label) {
    return 'Copiază $label';
  }

  @override
  String get localApiCopied => 'Copiat în clipboard';

  @override
  String get image_generation => 'Generare de imagini';

  @override
  String get image_model_ids => 'ID-uri de modele de imagini';

  @override
  String get image_model_ids_hint =>
      'Introdu ID-uri personalizate separate prin virgule sau rânduri noi.';

  @override
  String get image_generation_prompt =>
      'Descrie imaginea pe care vrei să o creezi';

  @override
  String get image_generation_temporary =>
      'Generarea de imagini este disponibilă în chaturile salvate. Începe un chat salvat pentru a crea o imagine.';

  @override
  String get image_generation_remove_attachments =>
      'Elimină atașamentele înainte de a genera o imagine.';

  @override
  String get image_generation_unavailable =>
      'Acest server sau model nu oferă un API Images compatibil. Verifică URL-ul serverului și ID-ul modelului.';

  @override
  String get image_generation_auth =>
      'Verifică cheia API și dacă aceasta poate accesa modelul de imagini.';

  @override
  String get image_generation_quota =>
      'Furnizorul a atins limita de frecvență sau cota. Verifică-ți contul înainte să încerci din nou.';

  @override
  String get image_generation_rejected =>
      'Furnizorul a respins solicitarea de imagine. Verifică promptul și încearcă din nou.';

  @override
  String get image_generation_timeout =>
      'Generarea imaginii a expirat. Încearcă din nou când furnizorul este disponibil.';

  @override
  String get image_generation_invalid =>
      'Furnizorul a returnat o imagine nevalidă sau incompatibilă.';

  @override
  String get image_generation_failed =>
      'Nu s-a putut genera imaginea. Verifică conexiunea și încearcă din nou.';

  @override
  String get image_generation_save_failed =>
      'Nu s-a putut salva imaginea generată. Verifică spațiul de stocare disponibil și încearcă din nou.';

  @override
  String get image_generation_share => 'Partajează imaginea';

  @override
  String get onDeviceSearchModels => 'Caută modele';

  @override
  String get onDeviceSearching => 'Se caută…';

  @override
  String get onDeviceSearch => 'Caută';

  @override
  String get onDeviceModelTypeBoth => 'Ambele';

  @override
  String get onDeviceModelTypeLitert => 'LiteRT';

  @override
  String get onDeviceModelTypeGguf => 'Llama.cpp (GGUF)';

  @override
  String get onDeviceModelTypeNone => 'Niciunul';

  @override
  String get onDeviceModalityAll => 'Toate';

  @override
  String get onDeviceModalityText => 'Text';

  @override
  String get onDeviceModalityVision => 'Viziune';

  @override
  String get onDeviceModalityAudio => 'Audio';

  @override
  String get onDeviceModalityEmbedding => 'Vectorizare';

  @override
  String get onDeviceModalityOmni => 'Omni';

  @override
  String get onDeviceModalityUnknown => 'Necunoscută';

  @override
  String get downloadBackgroundActive => 'În fundal';

  @override
  String get downloadBackgroundDescription =>
      'Această descărcare este gestionată de Android și poate continua când LocalMind este închis. Android o poate întrerupe sau amâna în funcție de condițiile sistemului.';

  @override
  String get downloadQueued => 'În coadă';

  @override
  String get downloadWaitingToRetry => 'Se așteaptă reîncercarea';

  @override
  String get onDeviceEnterSearchTerm => 'Introdu un termen de căutare';

  @override
  String get onDeviceFilters => 'Filtre';

  @override
  String get onDeviceFramework => 'Framework';

  @override
  String get onDeviceModality => 'Modalitate';

  @override
  String get onDeviceParameterSize => 'Dimensiunea parametrilor';

  @override
  String get onDeviceMinParam => 'Min. B';

  @override
  String get onDeviceMaxParam => 'Max. B';

  @override
  String get onDeviceIncludeUnknownSizes => 'Include dimensiunile necunoscute';

  @override
  String get onDeviceSplitModels => 'Modele împărțite';

  @override
  String get onDeviceImportFromUrl => 'Importă de la URL';

  @override
  String get onDeviceImportFromDevice => 'Importă de pe dispozitiv';

  @override
  String get onDeviceAddModelFromUrl => 'Adaugă model de la URL';

  @override
  String get onDeviceHuggingFaceUrl => 'URL Hugging Face';

  @override
  String get onDeviceUpdateAvailable => 'Actualizare disponibilă';

  @override
  String get onDeviceCheckForUpdates => 'Verifică dacă există actualizări';

  @override
  String get onDeviceAdded => 'Adăugat';

  @override
  String get onDeviceSplitModel => 'Împarte modelul';

  @override
  String get onDevicePickGguf => 'Alege GGUF';

  @override
  String get onDevicePickLitert => 'Alege LiteRT';

  @override
  String onDeviceUnknownSizeHidden(int count) {
    return '$count modele cu dimensiune necunoscută ascunse';
  }

  @override
  String get conversation_tags => 'Etichete';

  @override
  String get conversation_tags_desc =>
      'Grupează conversațiile după subiect. O conversație poate avea mai multe etichete, pe lângă un dosar.';

  @override
  String get conversation_tags_add_hint =>
      'Adaugă o etichetă, apoi apasă Enter';

  @override
  String get conversation_tags_existing => 'Etichetele tale';

  @override
  String get conversation_tags_add => 'Adaugă etichete';

  @override
  String get conversation_tags_edit => 'Editează etichetele';

  @override
  String get turn_instruction_title => 'Instrucțiune pentru următorul răspuns';

  @override
  String get turn_instruction_desc =>
      'Se aplică doar următorului tău mesaj, pe lângă promptul conversației.';

  @override
  String get turn_instruction_hint => 'de ex. Răspunde în trei puncte';

  @override
  String get turn_instruction_remove => 'Elimină instrucțiunea';

  @override
  String get turn_instruction_chip_label => 'Următorul răspuns:';
}
