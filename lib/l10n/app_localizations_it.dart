// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'La tua IA. Il tuo dispositivo. Le tue regole.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'Annulla';

  @override
  String get confirm => 'Conferma';

  @override
  String get delete => 'Elimina';

  @override
  String get save => 'Salva';

  @override
  String get retry => 'Riprova';

  @override
  String get close => 'Chiudi';

  @override
  String get done => 'Done';

  @override
  String get continue_action => 'Continua';

  @override
  String get skip => 'Salta';

  @override
  String get install => 'Installa';

  @override
  String get download => 'Download';

  @override
  String get resume => 'Riprendi';

  @override
  String get pause => 'Pausa';

  @override
  String get stop => 'Stop';

  @override
  String get edit => 'Modificare';

  @override
  String get preview => 'Anteprima';

  @override
  String get unload => 'Scarico';

  @override
  String get load => 'Carico';

  @override
  String get rename => 'Rinomina';

  @override
  String get pin => 'Pin';

  @override
  String get unpin => 'Sblocca';

  @override
  String get share => 'Condividi';

  @override
  String get copy => 'Copia';

  @override
  String get copied => 'Copiato!';

  @override
  String get copied_to_clipboard => 'Copiato negli appunti';

  @override
  String get select => 'Seleziona';

  @override
  String get active => 'Attivo';

  @override
  String get all => 'Tutto';

  @override
  String get none => 'Nessuna';

  @override
  String get none_selected => 'Nessuna selezione';

  @override
  String get online => 'Online';

  @override
  String get connected => 'Connesso';

  @override
  String get checking => 'Verifica in corso';

  @override
  String get offline => 'Offline';

  @override
  String get error => 'Errore';

  @override
  String get unknown_error => 'Errore sconosciuto';

  @override
  String get not_now => 'Non ora';

  @override
  String get enable => 'Abilita';

  @override
  String get proceed_anyway => 'Procedi Comunque';

  @override
  String get test_connection => 'Connessione di prova';

  @override
  String get testing => 'Collaudo';

  @override
  String get connection_successful => 'Connessione effettuata con successo!';

  @override
  String get connection_failed =>
      'Connessione non riuscita. Controlla le impostazioni.';

  @override
  String get save_continue => 'Salva e continua';

  @override
  String get save_changes => 'Salva modifiche';

  @override
  String get finish_setup => 'Fine impostazioni';

  @override
  String get start_new_chat => 'Avvia una nuova sessione di chat';

  @override
  String get cannot_undo => 'Non sarà possibile annullare questa operazione.';

  @override
  String get ram_warning => 'Avviso RAM';

  @override
  String get recommended => 'CONSIGLIATO';

  @override
  String get may_be_large =>
      'Potrebbe essere troppo grande per questo dispositivo';

  @override
  String get calculating => 'Calcolo in corso...';

  @override
  String get download_failed => 'Download non riuscito';

  @override
  String get downloaded => 'Scaricato';

  @override
  String get not_downloaded => 'Non scaricato';

  @override
  String get installed => 'Presente';

  @override
  String get not_installed => 'Non installata';

  @override
  String get loading => 'Caricamento in corso...';

  @override
  String get thinking => 'Pensiero';

  @override
  String get processing => 'Elaborazione in corso';

  @override
  String get initializing => 'Inizializzazione in corso...';

  @override
  String get ready => 'Pronto';

  @override
  String get preparing_app => 'Preparazione dell\'app in corso...';

  @override
  String get initializing_services => 'Inizializzazione servizi in corso...';

  @override
  String get configuring_server => 'Configurazione del server in corso ...';

  @override
  String get startup_failed => 'Avvio non riuscito';

  @override
  String get something_went_wrong => 'Qualcosa non ha funzionato';

  @override
  String get delete_model_title => 'ELIMINARE UN MODELLO.';

  @override
  String delete_model_body(String name) {
    return 'Eliminare';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'Sei sicuro di voler eliminare $name? In questo modo libererai circa $size di spazio.\n\nÈ possibile scaricare nuovamente questo modello in seguito, se necessario.';
  }

  @override
  String get delete_voice_title => 'Elimina tag vocale';

  @override
  String delete_voice_body(String name, String size) {
    return 'Sei sicuro di voler eliminare $name? In questo modo libererai circa $size di spazio.\n\nPuoi scaricare di nuovo questa voce in un secondo momento, se necessario.';
  }

  @override
  String get delete_server_title => 'Elimina server';

  @override
  String delete_server_body(String name) {
    return 'Sei sicuro di voler eliminare \"$name\"? L\'operazione non può essere annullata.';
  }

  @override
  String get delete_conversation_title => 'Eliminare la conversazione?';

  @override
  String delete_conversation_body(String title) {
    return 'Sei sicuro di voler eliminare \"$title\"? L\'operazione non può essere annullata.';
  }

  @override
  String get delete_message_title => 'Eliminare il messaggio?';

  @override
  String delete_persona_title(String name) {
    return 'Eliminare \"$name\"?';
  }

  @override
  String get delete_persona_body => 'L\'operazione non può essere annullata.';

  @override
  String get delete_builtin_persona_body =>
      'Questo è un personaggio predefinito. Puoi ripristinarlo in seguito dalle Impostazioni.';

  @override
  String get restore_builtin_personas => 'Ripristina personaggi predefiniti';

  @override
  String get restore_builtin_personas_desc =>
      'Aggiungi di nuovo i personaggi predefiniti che hai eliminato';

  @override
  String get restore_builtin_personas_success =>
      'Personaggi predefiniti ripristinati';

  @override
  String get clear_personas => 'Cancella personaggi';

  @override
  String get enable_image_compression => 'Comprimi immagini prima di inviare';

  @override
  String get enable_image_compression_desc =>
      'Ridimensiona e comprimi le immagini allegate affinché i caricamenti rimangano entro i limiti del server';

  @override
  String get image_compression_level => 'Intensità di compressione';

  @override
  String get image_compression_level_desc =>
      'Un\'intensità maggiore produce file più piccoli con qualità inferiore';

  @override
  String get image_compression_level_low => 'Bassa';

  @override
  String get image_compression_level_medium => 'Media';

  @override
  String get image_compression_level_high => 'Alta';

  @override
  String get sort_models_tooltip => 'Ordina modelli';

  @override
  String get sort_by_favorites => 'Preferiti prima';

  @override
  String get sort_by_name => 'Nome (A-Z)';

  @override
  String get sort_by_size_smallest => 'Dimensione (più piccolo prima)';

  @override
  String get sort_by_size_largest => 'Dimensione (più grande prima)';

  @override
  String get sort_by_context_length => 'Lunghezza del contesto';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'Ridenominazione in corso $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '$count selezionati';
  }

  @override
  String get ai_rename_tooltip => 'Rinomina selezionati con l\'IA';

  @override
  String get new_chat_in_folder_tooltip => 'Nuova chat in questa cartella';

  @override
  String total_tokens_count(int count) {
    return '$count token';
  }

  @override
  String get smart_replies_use_persona =>
      'Usa personaggio nelle risposte intelligenti';

  @override
  String get smart_replies_use_persona_desc =>
      'Le risposte suggerite corrispondono al tono del personaggio attivo invece di un assistente generico';

  @override
  String get keep_persona_on_new_chat =>
      'Mantieni personaggio con una nuova chat';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Non cancellare la selezione del personaggio all\'inizio di una nuova chat';

  @override
  String get role_swap_button_enabled => 'Mostra pulsante cambio ruolo';

  @override
  String get role_swap_button_enabled_desc =>
      'Mostra un pulsante nell\'input di chat per inviare il tuo messaggio con il ruolo assistente invece di utente, senza generare risposte';

  @override
  String get send_as_user_tooltip => 'Invia come utente';

  @override
  String get send_as_assistant_tooltip =>
      'Invia come assistente (nessuna risposta)';

  @override
  String get insert_without_generating_tooltip => 'Inserisci senza generare';

  @override
  String get token_usage_title => 'Utilizzo dei Token';

  @override
  String get total_tokens_label => 'Token usati';

  @override
  String get usage_percent_label => 'Contesto usato';

  @override
  String get export_choice_title => 'Esporta';

  @override
  String get export_choice_body => 'Come desideri esportare?';

  @override
  String get copy_to_clipboard => 'Copia negli appunti';

  @override
  String bulk_export_conversations_success(int count) {
    return 'Esportate $count conversazioni';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'Rinominare con l\'IA?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'Questo chiederà all\'IA di generare un nuovo titolo per ciascuna delle $count conversazioni selezionate, sostituendo i titoli attuali. Questa operazione può richiedere del tempo e non può essere annullata.';
  }

  @override
  String get sort_by_modified_date => 'Ultima modifica';

  @override
  String get sort_by_created_date => 'Data di creazione';

  @override
  String get sort_title => 'Ordina';

  @override
  String get clear_conversation_title => 'Conversazioni chiare?';

  @override
  String get clear_conversation_body =>
      'Questo eliminerà tutti i messaggi in questa conversazione.';

  @override
  String get clear => 'Cancella';

  @override
  String label_completed(String label) {
    return '$label completato';
  }

  @override
  String error_with_message(String error) {
    return 'Errore: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Anteprima non riuscita: $error';
  }

  @override
  String loading_model(String modelId) {
    return 'Caricamento di $modelId...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Modello caricato: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'Nessun modello caricato. Tocca \"Gestisci modelli sul dispositivo\" per scaricare e caricare un modello.';

  @override
  String loading_model_error(String error) {
    return 'Errore: $error';
  }

  @override
  String get delete_conversation => 'Eliminare la conversazione?';

  @override
  String get nav_history => 'Storia';

  @override
  String get nav_servers => 'Server';

  @override
  String get nav_local_models => 'Modelli locali';

  @override
  String get nav_tts => 'Sintesi vocale';

  @override
  String get nav_personas => 'Personas';

  @override
  String get nav_settings => 'Impostazioni';

  @override
  String get nav_new_chat => 'Nuova chat';

  @override
  String get search_hint => 'Cerca conversazioni...';

  @override
  String get no_server_selected => 'Nessun server selezionato';

  @override
  String get switch_server => 'Cambia server';

  @override
  String get switch_server_subtitle => 'Scegli un server a cui connetterti';

  @override
  String get manage_servers => 'Gestisci server';

  @override
  String get open_source => 'Open Source';

  @override
  String get open_source_desc =>
      'LocalMind è open source. Segui i nostri progressi o contribuisci su GitHub.';

  @override
  String get star_on_github => 'Metti in evidenza su GitHub';

  @override
  String get add_more => 'Aggiungi altro';

  @override
  String get on_github => 'su GitHub';

  @override
  String get could_not_open_github => 'Impossibile aprire GitHub.';

  @override
  String get settings_title => 'Impostazioni';

  @override
  String get settings_appearance => 'Aspetto';

  @override
  String get settings_language => 'Lingua';

  @override
  String get language_system_default => 'Predefinito di sistema';

  @override
  String get settings_tts => 'Sintesi vocale';

  @override
  String get settings_behavior => 'Comportamento';

  @override
  String get settings_on_device => 'Inferenza sul dispositivo';

  @override
  String get settings_default_server => 'Server predefinito';

  @override
  String get settings_default_persona => 'Persona predefinita';

  @override
  String get settings_default_model => 'Modello predefinito';

  @override
  String get settings_default_model_desc =>
      'Selezionato automaticamente quando avvii una nuova chat.';

  @override
  String get settings_privacy => 'Privacy';

  @override
  String get settings_data_management => 'Gestione dei dati';

  @override
  String get settings_about => 'Informazioni su';

  @override
  String get theme => 'Tema';

  @override
  String get theme_system => 'Sistema';

  @override
  String get theme_light => 'Luce';

  @override
  String get theme_dark => 'Scuro';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'Dimensione carattere';

  @override
  String get font_size_desc => 'Regola le dimensioni del testo in chat.';

  @override
  String get font_preview => 'La veloce volpe marrone salta sul cane pigro.';

  @override
  String get code_theme_dark => 'Tema codice (scuro)';

  @override
  String get code_theme_light => 'Tema codice (chiaro)';

  @override
  String get code_theme_desc =>
      'Scegli il tema di evidenziazione della sintassi per i blocchi di codice.';

  @override
  String get tts_engine => 'Motore TTS';

  @override
  String get tts_engine_system => 'System TTS';

  @override
  String get tts_engine_kitten => 'Gattino TTS';

  @override
  String get voice => 'Voce';

  @override
  String get voice_female => 'Donna';

  @override
  String get voice_male => 'Uomo';

  @override
  String get voice_other => 'Altro';

  @override
  String get tts_speed => 'Velocità TTS';

  @override
  String get tts_speed_desc => 'Regola la velocità di riproduzione.';

  @override
  String get manage_tts_models => 'Gestisci modelli TTS';

  @override
  String get manage_on_device_models => 'Gestisci modelli sul dispositivo';

  @override
  String get enable_smart_reply => 'Risposte intelligenti sul dispositivo';

  @override
  String get ai_user_response_enabled =>
      'Messaggio utente IA (tieni premuto invia)';

  @override
  String get ai_user_response_enabled_desc =>
      'Tieni premuto il pulsante di invio per 3 secondi per consentire all\'IA di scrivere e inviare il tuo prossimo messaggio';

  @override
  String get ai_user_response_tooltip => 'Genera messaggio utente con l\'IA';

  @override
  String get streaming_responses => 'Risposte in streaming';

  @override
  String get auto_generate_titles => 'Genera automaticamente titoli';

  @override
  String get send_on_enter => 'Invia su Invio';

  @override
  String get show_system_messages => 'Mostra messaggi di sistema';

  @override
  String get show_system_messages_desc =>
      'Quando nessun personaggio è selezionato, invia un prompt di sistema dell\'assistente predefinito con ogni richiesta';

  @override
  String get show_system_messages_in_chat =>
      'Mostra messaggi di sistema in chat';

  @override
  String get show_system_messages_in_chat_desc =>
      'Visualizza i messaggi di sistema (es. da un backup importato) come bolle visibili nella conversazione';

  @override
  String get haptic_feedback => 'Feedback aptico';

  @override
  String get enable_mcp => 'Abilita MCP';

  @override
  String get new_chat_mcp_default => 'Nuova chat MCP predefinita';

  @override
  String get show_data_indicator => 'Mostra indicatore dati';

  @override
  String get privacy_info => '\"LocalMind non vede mai i tuoi dati\"';

  @override
  String get delete_all_conversations => 'Elimina tutte le conversazioni';

  @override
  String get reset_settings_defaults => 'Ripristina impostazioni predefinite';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Parametri della chat';

  @override
  String get change_persona => 'Cambia persona';

  @override
  String get set_persona => 'Imposta persona';

  @override
  String get remove_persona => 'Rimuovi Persona';

  @override
  String get clear_conversation => 'Cancella conversazione';

  @override
  String get connection_error =>
      'Errore di connessione. Controlla il tuo server.';

  @override
  String get disconnected => 'Disconnesso dal server.';

  @override
  String get configure => 'Configura';

  @override
  String get select_model => 'Seleziona modello';

  @override
  String get select_persona => 'Seleziona Persona';

  @override
  String get manage_personas => 'Gestisci personaggi';

  @override
  String get personas_combine_hint =>
      'I personaggi selezionati verranno combinati';

  @override
  String get start_conversation => 'Avvia una conversazione';

  @override
  String get recent_chats => 'Chat recenti';

  @override
  String get see_all => 'Vedi tutto';

  @override
  String get quick_write => 'Aiutami a scrivere una funzione';

  @override
  String get quick_explain => 'Spiega questo codice';

  @override
  String get quick_debug => 'Esegui il debug per me';

  @override
  String get quick_async => 'Come si usa async/await?';

  @override
  String get history_missing_title => 'Cronologia mancante';

  @override
  String get history_missing_desc =>
      'I messaggi in questa chat sono stati eliminati o il record della cronologia è danneggiato.';

  @override
  String get technical_details => 'Dati tecnici';

  @override
  String get last_error => 'Ultimo errore:';

  @override
  String get copy_info => 'Copia informazioni';

  @override
  String get conversation_id => 'ID conversazione';

  @override
  String get created_at => 'Creato il';

  @override
  String get expected_messages => 'Messaggi previsti';

  @override
  String get debug_dialog_desc =>
      'Informazioni diagnostiche per aiutare a identificare i problemi di sincronizzazione.';

  @override
  String get chat_input_hint => 'Chiedi qualsiasi cosa';

  @override
  String get send_message_tooltip => 'Invia messaggio';

  @override
  String get stop_generation_tooltip => 'Interrompi generazione';

  @override
  String get attach_images_tooltip => 'Allega immagini';

  @override
  String get start_listening_tooltip => 'Avvia ascolto';

  @override
  String get stop_listening_tooltip => 'Interrompi ascolto';

  @override
  String tool_label(String toolCallId) {
    return 'Strumento: $toolCallId';
  }

  @override
  String get tool_unknown => 'Strumento: sconosciuto';

  @override
  String get message_options => 'Opzioni messaggio';

  @override
  String get copy_markdown => 'Copia come sconto';

  @override
  String get copied_markdown => 'Copiato come Markdown';

  @override
  String get read_aloud => 'Leggi ad alta voce';

  @override
  String get stop_reading => 'Smetti di leggere';

  @override
  String get more => 'Altro';

  @override
  String character_count(int length) {
    return '$length caratteri';
  }

  @override
  String get edit_message => 'Modifica messaggio';

  @override
  String get edit_message_desc =>
      'Il salvataggio rimuoverà la risposta dell\'assistente sottostante e la rigenererà.';

  @override
  String get save_regenerate => 'Salva e rigenera';

  @override
  String get chat_settings_title => 'Impostazioni chat';

  @override
  String get reset_defaults => 'Ripristina predefiniti';

  @override
  String get parameters_tab => 'Parametri';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'Temperatura';

  @override
  String get temperature_desc =>
      'Controlla la casualità: Più alto = Creativo, Più basso = Concentrato';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'Soglia di campionamento del nucleo';

  @override
  String get max_tokens => 'Numero massimo di token';

  @override
  String get max_tokens_desc => 'Limite di risposta';

  @override
  String get context_length => 'Lunghezza del contesto';

  @override
  String get context_length_desc => 'Finestra Cronologia';

  @override
  String get mcp_disabled_warning =>
      'MCP è disabilitato a livello globale. Abilitalo nelle Impostazioni per utilizzare queste funzionalità.';

  @override
  String get mcp_enable_chat => 'Abilita MCP per questa chat';

  @override
  String get auto_execute_tools => 'Esecuzione automatica degli strumenti';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Sperimentale';

  @override
  String get add_ephemeral_mcp => 'Aggiungi server MCP effimero';

  @override
  String get mcp_label_placeholder => 'Etichetta';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => 'Integrazioni attive';

  @override
  String get import_mcp_json => 'Importa JSON';

  @override
  String get import_mcp_json_dialog_title => 'Importa JSON configurazione MCP';

  @override
  String get import_mcp_json_instructions =>
      'Copia il tuo JSON mcpServers direttamente da LM Studio (mcp.json) o incolla un array di plugin qui sotto:';

  @override
  String get import_mcp_json_placeholder =>
      'Incolla il JSON mcpServers o l\'elenco dei plugin qui...';

  @override
  String mcp_import_success(int count) {
    return '$count integrazione/i importata/e con successo';
  }

  @override
  String get mcp_import_failed =>
      'Nessuna integrazione MCP valida trovata nel JSON';

  @override
  String get enable_notifications => 'Abilita notifiche';

  @override
  String get enable_notifications_desc =>
      'Ricevi una notifica quando i modelli terminano il download.';

  @override
  String get chat_history_title => 'Cronologia chat';

  @override
  String get conversation_just_now => 'Proprio ora';

  @override
  String conversation_minutes_ago(int minutes) {
    return '${minutes}m fa';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '${hours}h fa';
  }

  @override
  String get conversation_yesterday => 'Ieri';

  @override
  String conversation_days_ago(int days) {
    return '${days}d fa';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => 'Opzioni';

  @override
  String get no_results_found => 'Nessun risultato trovato';

  @override
  String get no_conversations_yet => 'Ancora nessuna conversazione';

  @override
  String get try_different_search => 'Prova un altro termine di ricerca';

  @override
  String get start_new_conversation => 'Inizia una nuova conversazione';

  @override
  String get rename_conversation => 'Rinomina conversazione';

  @override
  String get enter_new_title => 'Inserisci un nuovo titolo';

  @override
  String get pinned_section => 'BLOCCATO';

  @override
  String get today_section => 'OGGI';

  @override
  String get yesterday_section => 'IERI';

  @override
  String get previous_7_days => '7 GIORNI PRECEDENTI';

  @override
  String get previous_30_days => '30 GIORNI PRECEDENTI';

  @override
  String get older_section => 'PRECEDENTE';

  @override
  String get onboarding_choose_language => 'Scegli la lingua';

  @override
  String get onboarding_choose_language_desc =>
      'Seleziona la tua lingua preferita. Puoi modificarlo in qualsiasi momento nelle impostazioni.';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'Collega il tuo\nServer';

  @override
  String get onboarding_connect_desc =>
      'Connettiti a LM Studio, Ollama o\nOpenRouter per avviare la tua IA privata\nesperienza.';

  @override
  String get openai_compatible_api => 'API compatibile con OpenAI';

  @override
  String get https_requires_ssl => 'HTTPS richiede SSL';

  @override
  String get most_local_setups_use_http =>
      'La maggior parte delle configurazioni locali usa http://';

  @override
  String get onboarding_welcome => 'Benvenuto in LocalMind';

  @override
  String get server_type_on_device => 'On-Device';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'CLOUD GESTITO';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Connettendo Ollama Cloud, i tuoi messaggi di chat e i tuoi input vengono inviati ai server gestiti di Ollama per l\'inferenza. LocalMind non traccia né memorizza le tue conversazioni. Puoi revocare questa chiave in qualsiasi momento su ollama.com/settings/keys.';

  @override
  String get api_key_required_ollama_cloud =>
      'Chiave API richiesta per Ollama Cloud';

  @override
  String get api_key_hint_ollama_cloud =>
      'Incolla la tua chiave API di Ollama Cloud';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Connettiti a Ollama Cloud con una chiave API da ollama.com/settings/keys per accedere ai modelli cloud gestiti.';

  @override
  String get add_server_openrouter_subtitle =>
      'Connettiti tramite OpenRouter con una chiave API valida e tieni pronto questo profilo per l\'instradamento dei modelli.';

  @override
  String get add_server_endpoint_subtitle =>
      'Configura un endpoint locale o self-hosted, quindi verifica la connessione prima di salvare.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => 'CLOUD UNIFICATO';

  @override
  String get ready_continue => 'PRONTO A CONTINUARE';

  @override
  String get waiting_selection => 'IN ATTESA DI SELEZIONE';

  @override
  String get setup_connection => 'Configura connessione';

  @override
  String setup_connection_desc(String server) {
    return 'Configura il tuo server $server per iniziare a chattare.';
  }

  @override
  String get server_name => 'Nome server';

  @override
  String get name_required => 'Nome obbligatorio';

  @override
  String get name_max_50 => 'Max 50 caratteri';

  @override
  String get host_label => 'Indirizzo host / IP';

  @override
  String get host_required => 'Host obbligatorio';

  @override
  String get port_label => 'Porta';

  @override
  String get port_required => 'Porta richiesta';

  @override
  String get port_invalid => 'Deve essere un numero';

  @override
  String get port_range => 'Inserisci una porta valida (1-65535)';

  @override
  String get api_key_required => 'Chiave API *';

  @override
  String get api_key_optional => 'Chiave API (opzionale)';

  @override
  String get api_key_required_openrouter =>
      'Chiave API richiesta per OpenRouter';

  @override
  String get api_key_format => 'Le chiavi API OpenRouter iniziano con sk-';

  @override
  String get my_server_hint => 'Il mio server';

  @override
  String get name_length_validation =>
      'Il nome deve contenere al massimo 50 caratteri';

  @override
  String get host_valid => 'Inserisci un nome host o un indirizzo IP valido';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => 'Per server autenticati';

  @override
  String get update_server => 'Aggiorna server';

  @override
  String get save_server => 'Salva server';

  @override
  String get server_updated => 'Server aggiornato';

  @override
  String get server_added => 'Server aggiunto';

  @override
  String get download_model_title => 'Scarica un modello';

  @override
  String get download_model_desc =>
      'Scegli un modello da scaricare.\nVerrà eseguito localmente sul tuo dispositivo.';

  @override
  String get on_device_android_only =>
      'L\'inferenza sul dispositivo è attualmente disponibile solo su Android.';

  @override
  String get total_ram => 'RAM totale';

  @override
  String get available => 'Disponibile';

  @override
  String ram_min_required(String fileSize) {
    return '$fileSize GB RAM min';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'ETA: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'In pausa - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Questo modello richiede almeno $ram GB di RAM, ma il suo dispositivo dispone di $totalMemory. Potrebbe non funzionare correttamente o causare l\'arresto anomalo dell\'app.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Il suo dispositivo ha $availableRAM RAM disponibile, ma questo modello consiglia almeno $ram GB. Il caricamento potrebbe non riuscire o causare instabilità.';
  }

  @override
  String get choose_theme => 'Scegli tema';

  @override
  String get choose_theme_desc =>
      'Personalizza l\'aspetto dell\'app. Puoi sempre modificarlo in seguito nelle impostazioni.';

  @override
  String get theme_card_system => 'Sistema';

  @override
  String get theme_card_system_sub =>
      'Corrisponde alle impostazioni del tuo dispositivo';

  @override
  String get theme_card_light => 'Luce';

  @override
  String get theme_card_light_sub => 'Pulito e luminoso';

  @override
  String get theme_card_dark => 'Scuro';

  @override
  String get theme_card_dark_sub => 'Occhi facili';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'Un tema caldo color\n pesca';

  @override
  String get stay_updated => 'Resta aggiornato';

  @override
  String get stay_updated_desc =>
      'Ricevi una notifica quando i tuoi modelli di intelligenza artificiale terminano il download o quando le attività di lunga durata vengono completate.';

  @override
  String get notification_benefit_downloads => 'Avanzamento download modello';

  @override
  String get notification_benefit_completions =>
      'Completamenti della generazione';

  @override
  String get notification_benefit_background =>
      'Stato delle attività in background';

  @override
  String get allow_notifications => 'Consenti notifiche';

  @override
  String get servers_title => 'Server';

  @override
  String get no_servers_yet => 'Ancora nessun server';

  @override
  String get no_servers_desc =>
      'Aggiungi il tuo primo server per iniziare a chattare con i modelli di intelligenza artificiale.';

  @override
  String get add_server => 'Aggiungi server';

  @override
  String switched_to_server(String name) {
    return 'Passato a $name';
  }

  @override
  String get edit_server => 'Modifica server';

  @override
  String get add_server_title => 'Aggiungi server';

  @override
  String get server_type_label => 'Tipo di server';

  @override
  String get server_icon_label => 'Icona del server';

  @override
  String get default_icon => 'Icona predefinita';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'Compatibile con OpenAI';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'On-Device';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'Inferenza locale';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Predefinito';

  @override
  String get set_as_default => 'Imposta come predefinito';

  @override
  String get select_icon => 'Seleziona icona';

  @override
  String get select_icon_desc => 'Scegli un\'icona per il tuo server';

  @override
  String get search_icons_hint => 'Cerca icone...';

  @override
  String get server_icon_stack => 'Stack di server';

  @override
  String get server_icon_stack2 => 'Server Stack 02';

  @override
  String get server_icon_stack3 => 'Server Stack 03';

  @override
  String get server_icon_cloud => 'Cloud';

  @override
  String get server_icon_cloud_server => 'Cloud Server';

  @override
  String get server_icon_mcp => 'Server MCP';

  @override
  String get server_icon_database => 'Database';

  @override
  String get server_icon_database1 => 'Database 01';

  @override
  String get server_icon_database2 => 'Database 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'Chip';

  @override
  String get server_icon_chip2 => 'Chip 02';

  @override
  String get server_icon_computer => 'Computer';

  @override
  String get server_icon_laptop => 'Laptop';

  @override
  String get server_icon_terminal => 'Terminale informatico';

  @override
  String get server_icon_code => 'Codice';

  @override
  String get server_icon_ai_brain => 'Cervello AI';

  @override
  String get server_icon_ai_brain2 => 'AI Brain 02';

  @override
  String get server_icon_ai_cloud => 'AI Cloud';

  @override
  String get server_icon_ai_network => 'Rete AI';

  @override
  String get server_icon_ai_chat => 'AI Chat';

  @override
  String get server_icon_cellular => 'Rete cellulare';

  @override
  String get server_icon_plug1 => 'Plug 01';

  @override
  String get server_icon_plug2 => 'Plug 02';

  @override
  String get server_icon_bot => 'Bot';

  @override
  String get server_icon_bot2 => 'Bot 02';

  @override
  String get server_icon_robotic => 'Robotica';

  @override
  String get server_icon_rocket => 'Razzo';

  @override
  String get server_icon_star => 'Stella';

  @override
  String get server_icon_settings1 => 'Impostazioni 01';

  @override
  String get server_icon_settings2 => 'Impostazioni 02';

  @override
  String get server_icon_home1 => 'Home 01';

  @override
  String get server_icon_home2 => 'Home 02';

  @override
  String get server_icon_folder1 => 'Cartella 01';

  @override
  String get server_icon_folder2 => 'Cartella 02';

  @override
  String get server_icon_file1 => 'File 01';

  @override
  String get server_icon_lock => 'Blocca';

  @override
  String get server_icon_key => 'Chiave 01';

  @override
  String get server_icon_link => 'Link 01';

  @override
  String get server_icon_globe => 'Globe';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Freccia destra 01';

  @override
  String get server_icon_check => 'Cerchio di controllo';

  @override
  String get server_icon_alert => 'Cerchio di allerta';

  @override
  String get server_icon_info => 'Info Circle';

  @override
  String get server_icon_zap => 'Zap';

  @override
  String get server_icon_cloud_upload => 'Caricamento cloud';

  @override
  String get server_icon_cloud_download => 'Cloud Download';

  @override
  String get server_icon_refresh => 'Aggiorna';

  @override
  String get server_icon_hard_drive => 'Disco rigido';

  @override
  String get server_icon_drive => 'Guida';

  @override
  String get personas_title => 'Personas';

  @override
  String get persona_category_general => 'Generale';

  @override
  String get persona_category_coding => 'Codifica';

  @override
  String get persona_category_education => 'Istruzione';

  @override
  String get persona_category_creative => 'Creativo';

  @override
  String get persona_builtin_section => 'INTEGRATO';

  @override
  String get persona_my_section => 'LE MIE PERSONAS';

  @override
  String get clone_edit => 'Clona e modifica';

  @override
  String get builtin_badge => 'Integrato';

  @override
  String get no_personas_found => 'Nessuna persona trovata';

  @override
  String get no_personas_desc =>
      'Crea la tua prima persona per personalizzare il comportamento dell\'IA.';

  @override
  String get edit_persona => 'Modifica Persona';

  @override
  String get create_persona => 'Crea persona';

  @override
  String get create_persona_button => 'Crea';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'Nome';

  @override
  String get my_persona_hint => 'La mia Persona';

  @override
  String get category_label => 'Categoria';

  @override
  String get description_optional => 'Descrizione (opzionale)';

  @override
  String get description_hint => 'Cosa fa questo personaggio...';

  @override
  String get system_prompt => 'Prompt di sistema';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Ancora nessun prompt...';

  @override
  String get prompt_hint => 'Sei un assistente utile...';

  @override
  String get prompt_required => 'Il prompt di sistema è obbligatorio';

  @override
  String get prompt_max_chars => 'Max 4000 caratteri';

  @override
  String get advanced_settings => 'Impostazioni avanzate';

  @override
  String get temperature_label => 'Temperatura (0,0-2,0)';

  @override
  String get top_p_label => 'Top P (0,0-1,0)';

  @override
  String get temp_hint => '0.7';

  @override
  String get top_p_hint => '0,9';

  @override
  String get range_0_2 => '0,0-2,0';

  @override
  String get range_0_1 => '0,0-1,0';

  @override
  String get persona_updated => 'Persona aggiornata';

  @override
  String get persona_created => 'Persona creata';

  @override
  String get tts_models_title => 'Modelli di sintesi vocale';

  @override
  String get always_available => 'Sempre disponibile';

  @override
  String get tts_system_desc =>
      'Utilizza il motore di sintesi vocale integrato nel dispositivo.\nNessun download richiesto. La selezione vocale utilizza le impostazioni di sistema del tuo dispositivo.';

  @override
  String get downloading_status => 'Download in corso...';

  @override
  String tts_kitten_desc(String size) {
    return 'TTS neurale fulmineo con 8 voci espressive.\nRichiede il download di $size.';
  }

  @override
  String tts_piper_desc(String size) {
    return 'Veloce voce Piper offline con 2 voci espressive.\nRichiede $size download per voce.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount voci';
  }

  @override
  String get on_device_models_title => 'Modelli sul dispositivo';

  @override
  String get settings_huggingface_token => 'Token Hugging Face (Opzionale)';

  @override
  String get settings_huggingface_token_desc =>
      'Richiesto solo per i modelli con accesso limitato (ad es. Gemma). Ottieni un token su huggingface.co/settings/tokens.';

  @override
  String get settings_huggingface_token_set => 'Token salvato';

  @override
  String get settings_huggingface_token_cleared => 'Token cancellato';

  @override
  String get model_requires_huggingface_token =>
      'Richiede un token Hugging Face';

  @override
  String get model_missing_huggingface_token =>
      'Questo modello ha accesso limitato su Hugging Face. Aggiungi un token in Impostazioni → Inferenza sul dispositivo per scaricarlo.';

  @override
  String get set_huggingface_token => 'Imposta token';

  @override
  String get clear_huggingface_token => 'Cancella';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Token di accesso Hugging Face';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc =>
      'Motore AI locale. Nessuna chiave API richiesta.';

  @override
  String get server_type_on_device_desc =>
      'Funziona sul tuo telefono. Alcuni modelli richiedono un token Hugging Face.';

  @override
  String get server_type_lm_studio_desc =>
      'Server API locale. Nessuna chiave API richiesta.';

  @override
  String get available_models => 'Modelli disponibili';

  @override
  String get device_memory => 'Memoria del dispositivo';

  @override
  String get ram_usage => 'Utilizzo della RAM';

  @override
  String get memory_healthy => 'Sano';

  @override
  String get memory_critical => 'Critico';

  @override
  String get memory_low => 'Basso';

  @override
  String ram_used(String percent) {
    return '$percent% utilizzato';
  }

  @override
  String get available_ram => 'RAM disponibile';

  @override
  String get total_capacity => 'Capacità totale';

  @override
  String get loaded_status => 'Caricato';

  @override
  String get inference_backend => 'Backend di inferenza';

  @override
  String get backend_ios_notice =>
      'Solo il back-end della CPU è disponibile su iOS.';

  @override
  String get backend_cpu_desc =>
      'Funziona su tutti i dispositivi. Più compatibile.';

  @override
  String get backend_gpu_desc =>
      'Accelerazione OpenCL. Più veloce sui dispositivi supportati.';

  @override
  String get backend_npu_desc =>
      'NPU del fornitore (Qualcomm/MediaTek). L\'inferenza più veloce.';

  @override
  String get select_model_title => 'Seleziona modello';

  @override
  String get refresh_models => 'Aggiorna modelli';

  @override
  String get search_models_hint => 'Cerca modelli...';

  @override
  String get no_server_connected => 'Nessun server connesso';

  @override
  String get add_server_first =>
      'Aggiungi prima un server per vedere i modelli disponibili.';

  @override
  String get failed_load_models => 'Impossibile caricare i modelli';

  @override
  String get no_models_available => 'Nessun modello disponibile';

  @override
  String no_models_match(String searchQuery) {
    return 'Nessun modello corrisponde a \"$searchQuery\"';
  }

  @override
  String model_load_failed(String error) {
    return 'Impossibile caricare il modello: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return '$name verrà scaricato una volta trascorso il tempo di mantenimento in vita';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name scaricato correttamente';
  }

  @override
  String model_unload_failed(String error) {
    return 'Impossibile scaricare il modello: $error';
  }

  @override
  String get unload_from_server => 'Scarica dal server';

  @override
  String context_chip(String ctx) {
    return '$ctx ctx';
  }

  @override
  String get unload_all_models => 'Scarica tutti i modelli';

  @override
  String loaded_models_count(int count) {
    return '$count modelli caricati';
  }

  @override
  String get all_models_unloaded => 'Tutti i modelli scaricati';

  @override
  String get branch_chat => 'Crea ramo chat';

  @override
  String get branch_chat_desc =>
      'Crea una nuova chat a partire da questo messaggio';

  @override
  String get edit_assistant_message_desc =>
      'Modifica il contenuto del messaggio dell\'assistente';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'Passa al modello $model';
  }

  @override
  String download_notification_title(String modelName) {
    return 'Download di $modelName in corso...';
  }

  @override
  String get download_complete_notification => 'Download completato!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName è stato scaricato correttamente.';
  }

  @override
  String download_failed_notification(String error) {
    return 'Download non riuscito: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Impossibile scaricare $modelName.';
  }

  @override
  String get engine_name_system => 'System TTS';

  @override
  String get engine_tagline_system => 'Motore del dispositivo integrato';

  @override
  String get engine_name_kitten => 'Gattino TTS';

  @override
  String get engine_tagline_kitten => 'TTS neurale ad alta velocità';

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
  String get voice_leo => 'Leone';

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
      'Il più piccolo modello di chat generico. Risposte rapide, basso utilizzo della memoria.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'Qualità e dimensioni equilibrate. Ottimo per una conversazione generale.';

  @override
  String get model_deepseek => 'Distillato DeepSeek R1 Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Modello di ragionamento e catena di pensiero. Ideale per attività logiche.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'Modello di punta di Google. Massima qualità, richiede più RAM.';

  @override
  String export_header(String date) {
    return '*Esportato da LocalMind — $date*';
  }

  @override
  String get export_role_user => '## 👤 Utente';

  @override
  String get export_role_assistant => '## 🤖 Assistente';

  @override
  String get export_role_system => '## ⚙️ Sistema';

  @override
  String get export_role_tool => '## 🔧 Strumento';

  @override
  String get export_text_user => '[USER]';

  @override
  String get export_text_assistant => '[ASSISTENTE]';

  @override
  String get export_text_system => '[SISTEMA]';

  @override
  String get export_text_tool => '[STRUMENTO]';

  @override
  String get export_label_user => 'UTENTE';

  @override
  String get export_label_assistant => 'ASSISTENTE';

  @override
  String get export_label_system => 'SISTEMA';

  @override
  String get export_label_tool => 'STRUMENTO';

  @override
  String get select_model_hint =>
      'Seleziona un modello per iniziare a chattare';

  @override
  String get test_notification_title => 'Notifica di prova';

  @override
  String get test_notification_body =>
      'Questa è una notifica di prova per l\'avanzamento del download del modello.';

  @override
  String get tts_supports_background =>
      'Supporta la riproduzione in background come audio nativo';

  @override
  String get tts_other_services_background_note =>
      'Nota: Gli altri servizi TTS supportano la riproduzione in background come audio nativo.';

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
  String get model_favorite_toggle => 'Attiva/disattiva preferito';

  @override
  String get model_set_default => 'Imposta come modello predefinito';

  @override
  String get model_clear_default => 'Rimuovi come modello predefinito';

  @override
  String get model_default_badge => 'Predefinito';

  @override
  String get model_note_label => 'Nota';

  @override
  String get model_note_hint =>
      'Aggiungi una nota privata per questo modello...';

  @override
  String get unload_models_before_load => 'Scarica modelli prima di caricare';

  @override
  String get temp_chat_keyboard_incognito =>
      'Tastiera in incognito per chat temporanee';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'Richiedi alla tastiera del sistema di non salvare la cronologia di digitazione durante le chat temporanee';

  @override
  String get resume_last_chat => 'Riprendi l\'ultima chat';

  @override
  String get resume_last_chat_desc =>
      'Apri automaticamente la tua ultima conversazione attiva all\'avvio';

  @override
  String get export_all_data => 'Esporta tutti i dati';

  @override
  String get import_all_data => 'Importa tutti i dati';

  @override
  String get export_data_success => 'Dati esportati con successo';

  @override
  String get import_data_success => 'Dati importati con successo';

  @override
  String import_data_failed(String error) {
    return 'Impossibile importare i dati';
  }

  @override
  String get import_data_confirm =>
      'Questo sostituirà tutti i dati attuali con i dati importati. Continuare?';

  @override
  String get import_settings_confirm =>
      'Questo sostituirà le tue impostazioni attuali con quelle importate. Continuare?';

  @override
  String get export_conversations => 'Esporta conversazioni';

  @override
  String get import_conversations => 'Importa conversazioni';

  @override
  String get export_personas => 'Esporta personaggi';

  @override
  String get import_personas => 'Importa personaggi';

  @override
  String get export_settings => 'Esporta impostazioni';

  @override
  String get import_settings => 'Importa impostazioni';

  @override
  String get export_all_zip => 'Esporta tutto (ZIP)';

  @override
  String get import_all_zip => 'Importa tutto (ZIP)';

  @override
  String get duplicate_chat => 'Duplica chat';

  @override
  String get duplicate_chat_success => 'Chat duplicata con successo';

  @override
  String get move_to_folder => 'Sposta nella cartella';

  @override
  String get remove_from_folder => 'Rimuovi dalla cartella';

  @override
  String get create_folder => 'Crea cartella';

  @override
  String get new_folder => 'Nuova cartella';

  @override
  String get folder_name_hint => 'Inserisci il nome della cartella...';

  @override
  String get all_chats => 'Tutte le chat';

  @override
  String get unfiled_chats => 'Chat non archiviate';

  @override
  String get create => 'Crea';

  @override
  String get server_path_prefix_label => 'Prefisso percorso server';

  @override
  String get server_path_prefix_hint =>
      'Prefisso opzionale per i percorsi dell\'API del server (es. /v1)';

  @override
  String get search_message_contents => 'Cerca contenuto dei messaggi...';

  @override
  String get message_search_results => 'Risultati ricerca messaggi';

  @override
  String get saved_messages_title => 'Messaggi Salvati';

  @override
  String get nav_saved_messages => 'Messaggi salvati';

  @override
  String get saved_messages_empty => 'Ancora nessun messaggio salvato';

  @override
  String get save_message => 'Salva messaggio';

  @override
  String get message_saved => 'Messaggio salvato';

  @override
  String token_count(int count) {
    return 'Token: $count';
  }

  @override
  String estimated_token_count(int count) {
    return 'Token stimati: $count';
  }

  @override
  String get test_tts_section_title => 'Test Sintesi Vocale';

  @override
  String get test_tts_hint => 'Digita qualcosa per testare la voce...';

  @override
  String get test_speak_button => 'Parla';

  @override
  String get scroll_to_bottom => 'Scorri fino in fondo';

  @override
  String get generate_ai_response => 'Genera risposta IA';

  @override
  String get no_response => 'Nessuna risposta';

  @override
  String get export => 'Esporta';

  @override
  String get import => 'Importa';

  @override
  String get conversations_label => 'Conversazioni';

  @override
  String get personas_label => 'Personaggi';

  @override
  String get settings_label => 'Impostazioni';

  @override
  String get export_conversation => 'Esporta conversazione';

  @override
  String get tts_process_markdown => 'Elabora Markdown';

  @override
  String get tts_process_markdown_desc =>
      'Rimuovi la formattazione come il **grassetto** prima della lettura ad alta voce';

  @override
  String get tts_skip_seconds => 'Secondi da saltare';

  @override
  String get tts_skip_seconds_desc =>
      'Tempo per saltare avanti/indietro nel lettore vocale';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}s';
  }

  @override
  String get preview_system_prompts => 'Anteprima prompt di sistema';

  @override
  String get welcome_message_1 => 'Ciao! Sono il tuo assistente IA locale.';

  @override
  String get welcome_message_2 =>
      'Chiedimi qualsiasi cosa — sono pronto quando lo sei tu.';

  @override
  String get welcome_message_3 =>
      'I tuoi dati vengono elaborati localmente e non lasciano mai il dispositivo.';

  @override
  String get welcome_message_4 =>
      'Per iniziare, seleziona un modello dalla barra superiore o aggiungine uno nella gestione modelli.';

  @override
  String get temporary_chat => 'Chat temporanea';

  @override
  String get temporary_chat_desc =>
      'I messaggi di questa chat non saranno salvati nella cronologia';

  @override
  String get temporary_chat_banner =>
      'Chat Temporanea Attiva — Non verrà salvata nella cronologia';

  @override
  String get temporary_chat_save_warning_title => 'Salvare la chat temporanea?';

  @override
  String get temporary_chat_save_warning_body =>
      'Questa chat non è salvata nella cronologia. Vuoi salvarla adesso?';

  @override
  String get save_to_history => 'Salva nella cronologia';

  @override
  String get share_conversation => 'Condividi conversazione';

  @override
  String get download_tts_audio => 'Scarica audio vocale';

  @override
  String get tts_download_unavailable => 'Download voce non disponibile';

  @override
  String get tts_download_no_audio => 'Nessun audio generato da scaricare';

  @override
  String get tts_download_success => 'Audio vocale salvato con successo';

  @override
  String get return_to_chat => 'Torna alla chat';

  @override
  String get return_to_temp_chat => 'Torna alla chat temporanea';

  @override
  String get insert_saved_message => 'Inserisci messaggio salvato';

  @override
  String get insert_saved_message_desc =>
      'Aggiungi un estratto dai tuoi messaggi salvati alla chat';

  @override
  String get model_info => 'Informazioni modello';

  @override
  String get model_name => 'Nome modello';

  @override
  String get model_identifier => 'Identificatore modello';

  @override
  String get model_capabilities => 'Capacità';

  @override
  String get model_api_pricing => 'Prezzi API (per 1M di token)';

  @override
  String get not_available => 'Non disponibile';

  @override
  String get save_message_folders => 'Salva nelle cartelle';

  @override
  String get remove_from_saved => 'Rimuovi dai salvati';

  @override
  String get message_already_saved => 'Il messaggio è già salvato';

  @override
  String get stream_ttft => 'Tempo al primo token';

  @override
  String get stream_tokens_per_sec => 'Token al secondo';

  @override
  String get stream_stop_reason => 'Motivo interruzione';

  @override
  String get stream_input_tokens => 'Token di input';

  @override
  String get stream_output_tokens => 'Token di output';

  @override
  String get stream_generation_time => 'Tempo di generazione';

  @override
  String get attach_image => 'Allega immagine';

  @override
  String get attach_text_document => 'Allega documento di testo';

  @override
  String get attach_shortcut_images => 'Foto';

  @override
  String get attach_shortcut_documents => 'File';

  @override
  String get attach_shortcut_saved => 'Salvati';

  @override
  String get add_attachment => 'Aggiungi allegato';

  @override
  String get add_to_chat => 'Aggiungi alla chat';

  @override
  String get choose_what_to_attach => 'Cosa vorresti aggiungere?';

  @override
  String get choose_attachment_subtitle =>
      'Scegli una sorgente da allegare al tuo messaggio';

  @override
  String get photo_permission_denied => 'Permesso foto negato';

  @override
  String get select_model_prompt => 'Seleziona modello';

  @override
  String get characters_label => 'Caratteri';

  @override
  String get exit_temporary_chat_title => 'Uscire dalla chat temporanea?';

  @override
  String get exit_temporary_chat_body =>
      'Questo eliminerà permanentemente la conversazione corrente. Continuare?';

  @override
  String get saved_message_temp_snap_unavailable =>
      'I salvataggi dei messaggi non sono disponibili nelle chat temporanee';

  @override
  String get filter_title => 'Filtra chat';

  @override
  String get filter_pinned => 'Fissate';

  @override
  String get filter_archived => 'Archiviate';

  @override
  String get filter_temp_chats => 'Chat temporanee';

  @override
  String get filter_user_messages => 'Messaggi utente';

  @override
  String get filter_assistant_messages => 'Messaggi assistente';

  @override
  String get archive_chat => 'Archivia chat';

  @override
  String get unarchive_chat => 'Ripristina chat';

  @override
  String conversation_message_count(int count) {
    return '$count messaggi';
  }

  @override
  String conversation_character_count(int count) {
    return '$count caratteri';
  }

  @override
  String get generate_title_with_ai => 'Genera titolo con IA';

  @override
  String get generating_title => 'Generazione titolo in corso...';

  @override
  String get generate_title_failed => 'Impossibile generare un titolo';

  @override
  String get lm_studio_model_browser_title => 'Esplora Modelli';

  @override
  String get lm_studio_model_search_hint => 'Cerca modelli...';

  @override
  String get lm_studio_staff_picks => 'Scelte dello staff';

  @override
  String get lm_studio_community_models => 'Modelli della community';

  @override
  String get lm_studio_no_models => 'Nessun modello trovato';

  @override
  String lm_studio_models_count(int count) {
    return '$count modelli';
  }

  @override
  String get lm_studio_browse_models => 'Esplora modelli su LM Studio';

  @override
  String get lm_studio_model_search => 'Ricerca modelli';

  @override
  String get lm_studio_downloads_title => 'Download';

  @override
  String get lm_studio_choose_quant => 'Scegli quantizzazione';

  @override
  String get lm_studio_use_default_quant => 'Usa quantizzazione predefinita';

  @override
  String get lm_studio_recommended => 'Consigliato';

  @override
  String get lm_studio_clear_downloads => 'Cancella download completati';

  @override
  String get lm_studio_no_downloads => 'Nessun download attivo';

  @override
  String get lm_studio_downloads_disclaimer =>
      'I download dei modelli vengono effettuati direttamente da Hugging Face.';

  @override
  String get lm_studio_staff_pick => 'Scelta in evidenza';

  @override
  String get lm_studio_params => 'Parametri';

  @override
  String get lm_studio_arch => 'Architettura';

  @override
  String get lm_studio_domain => 'Dominio';

  @override
  String get lm_studio_format => 'Formato';

  @override
  String get lm_studio_vision => 'Visione';

  @override
  String get lm_studio_tool_use => 'Uso strumenti';

  @override
  String get lm_studio_reasoning => 'Ragionamento';

  @override
  String get openrouter_pricing_free => 'Gratuito';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return 'Input $input / Output $output per 1M di token';
  }

  @override
  String get lm_studio_download_options => 'Opzioni di download';

  @override
  String get lm_studio_download => 'Scarica';

  @override
  String lm_studio_download_size(String size) {
    return 'Dimensione del download';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'Scaricamento in corso: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'README non disponibile per questo modello.';

  @override
  String get lm_studio_full_gpu_offload => 'Offload GPU completo possibile';

  @override
  String get lm_studio_partial_gpu_offload => 'Offload GPU parziale possibile';

  @override
  String get lm_studio_likely_too_large => 'Probabilmente troppo grande';

  @override
  String get lm_studio_available_ram_gb => 'RAM disponibile (GB, opzionale)';

  @override
  String get lm_studio_available_vram_gb => 'VRAM disponibile (GB, opzionale)';

  @override
  String get lm_studio_memory_settings_title => 'Memoria per raccomandazioni';

  @override
  String get lm_studio_memory_settings_desc =>
      'Usato per stimare se i modelli entrano nella memoria della tua macchina nell\'esploratore di modelli.';

  @override
  String get think_button_label => 'Pensa';

  @override
  String get thinking_mode_title => 'Modalità di pensiero';

  @override
  String get reasoning_effort_low => 'Basso';

  @override
  String get reasoning_effort_medium => 'Medio';

  @override
  String get reasoning_effort_high => 'Alto';

  @override
  String get reasoning_effort_minimal => 'Minimo';

  @override
  String get reasoning_effort_xhigh => 'Molto alto';

  @override
  String get reasoning_effort_max => 'Massimo';

  @override
  String get reasoning_effort_off => 'Disattivato';

  @override
  String get could_not_read_file => 'Impossibile leggere il file';

  @override
  String get server_offline => 'Server offline';

  @override
  String get could_not_establish_connection =>
      'Impossibile stabilire una connessione al server. Verifica se il server è attivo e se le impostazioni host/porta sono corrette.';

  @override
  String get retry_connection => 'Riprova connessione';

  @override
  String get tokens_label => 'Token';

  @override
  String get enter_context_length => 'Inserisci lunghezza del contesto...';

  @override
  String get openrouter_disclosure =>
      'Collegando questo provider, i tuoi messaggi di chat e input verranno inviati ai loro server. LocalMind non traccia né memorizza le tue conversazioni.';

  @override
  String get welcome_message_cloud =>
      'I tuoi messaggi vengono inviati al provider connesso.';

  @override
  String get privacy_policy => 'Informativa sulla privacy';

  @override
  String get cloud_sync => 'Sincronizzazione S3';

  @override
  String get cloud_sync_description =>
      'Sincronizzazione crittografata end-to-end con il tuo server compatibile S3';

  @override
  String get cloud_sync_endpoint => 'URL endpoint';

  @override
  String get cloud_sync_bucket => 'Bucket';

  @override
  String get cloud_sync_region => 'Regione';

  @override
  String get cloud_sync_prefix => 'Prefisso';

  @override
  String get cloud_sync_access_key => 'ID chiave di accesso';

  @override
  String get cloud_sync_secret_key => 'Chiave di accesso segreta';

  @override
  String get cloud_sync_session_token => 'Token di sessione (facoltativo)';

  @override
  String get cloud_sync_passphrase => 'Passphrase di crittografia';

  @override
  String get cloud_sync_confirm_passphrase => 'Conferma passphrase';

  @override
  String get cloud_sync_path_style => 'Usa indirizzamento path-style';

  @override
  String get cloud_sync_allow_http => 'Consenti HTTP non sicuro';

  @override
  String get cloud_sync_http_warning =>
      'HTTP espone metadati e credenziali alla rete. Usalo solo con un server S3 locale attendibile.';

  @override
  String get cloud_sync_test => 'Verifica connessione';

  @override
  String get cloud_sync_enable => 'Attiva sincronizzazione crittografata';

  @override
  String get cloud_sync_now => 'Sincronizza ora';

  @override
  String get cloud_sync_disconnect => 'Disconnetti questo dispositivo';

  @override
  String get cloud_sync_last_synced => 'Ultima sincronizzazione';

  @override
  String get cloud_sync_never => 'Mai';

  @override
  String get cloud_sync_conflicts => 'Conflitti conservati';

  @override
  String get cloud_sync_passphrase_mismatch =>
      'Le passphrase non corrispondono';

  @override
  String get crash_report_title => 'Qualcosa è andato storto';

  @override
  String get crash_report_stack_trace => 'Stack trace';

  @override
  String get crash_report_tap_to_expand => 'Tocca per espandere';

  @override
  String get crash_report_button => 'Segnala questo crash';

  @override
  String get crash_try_again => 'Riprova';

  @override
  String get crash_report_empty_stack => '<vuoto>';

  @override
  String get crash_report_disclaimer =>
      'Segnalare apre GitHub con le diagnostiche già compilate. Hai il controllo: non viene inviato nulla automaticamente. Rivedi e rimuovi eventuali contenuti sensibili prima di inviare.';

  @override
  String get crash_report_copied => 'Copiato negli appunti';

  @override
  String get report_a_problem => 'Segnala un problema';

  @override
  String get rename_folder => 'Rinomina cartella';

  @override
  String get delete_folder => 'Elimina cartella';

  @override
  String get delete_folder_title => 'Eliminare la cartella?';

  @override
  String delete_folder_body(String name) {
    return 'Sei sicuro di voler eliminare \"$name\"? Le conversazioni o i messaggi salvati al suo interno verranno spostati in \"Senza cartella\". Operazione irreversibile.';
  }

  @override
  String get folder_name_required => 'Inserisci un nome per la cartella';

  @override
  String get model_required_toast => 'Devi prima selezionare un modello';
}
