// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline =>
      'Sizin Yapay Zekanız. Sizin Cihazınız. Sizin Kurallarınız.';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'İptal';

  @override
  String get confirm => 'Onayla';

  @override
  String get delete => 'Sil';

  @override
  String get save => 'Kaydet';

  @override
  String get retry => 'Yeniden Dene';

  @override
  String get close => 'Kapat';

  @override
  String get done => 'Bitti';

  @override
  String get continue_action => 'Devam Et';

  @override
  String get skip => 'Atla';

  @override
  String get install => 'Yükle';

  @override
  String get download => 'İndir';

  @override
  String get resume => 'Devam Ettir';

  @override
  String get pause => 'Duraklat';

  @override
  String get stop => 'Durdur';

  @override
  String get edit => 'Düzenle';

  @override
  String get preview => 'Önizleme';

  @override
  String get unload => 'Bellekten Çıkar';

  @override
  String get load => 'Yükle';

  @override
  String get rename => 'Yeniden Adlandır';

  @override
  String get pin => 'Sabitle';

  @override
  String get unpin => 'Sabitlemeyi Kaldır';

  @override
  String get share => 'Paylaş';

  @override
  String get copy => 'Kopyala';

  @override
  String get copied => 'Kopyalandı!';

  @override
  String get copied_to_clipboard => 'Panoya kopyalandı';

  @override
  String get select => 'Seç';

  @override
  String get active => 'Aktif';

  @override
  String get all => 'Tümü';

  @override
  String get none => 'Hiçbiri';

  @override
  String get none_selected => 'Hiçbiri seçilmedi';

  @override
  String get online => 'Çevrimiçi';

  @override
  String get connected => 'Bağlandı';

  @override
  String get checking => 'Kontrol ediliyor';

  @override
  String get offline => 'Çevrimdışı';

  @override
  String get error => 'Hata';

  @override
  String get unknown_error => 'Bilinmeyen hata';

  @override
  String get not_now => 'Şimdi Değil';

  @override
  String get enable => 'Etkinleştir';

  @override
  String get proceed_anyway => 'Yine de Devam Et';

  @override
  String get test_connection => 'Bağlantıyı Test Et';

  @override
  String get testing => 'Test ediliyor...';

  @override
  String get connection_successful => 'Bağlantı başarılı!';

  @override
  String get connection_failed =>
      'Bağlantı başarısız. Ayarlarınızı kontrol edin.';

  @override
  String get save_continue => 'Kaydet ve Devam Et';

  @override
  String get save_changes => 'Değişiklikleri Kaydet';

  @override
  String get finish_setup => 'Kurulumu Tamamla';

  @override
  String get start_new_chat => 'Yeni Sohbet Başlat';

  @override
  String get cannot_undo => 'Bu işlem geri alınamaz.';

  @override
  String get ram_warning => 'RAM Uyarısı';

  @override
  String get recommended => 'ÖNERİLEN';

  @override
  String get may_be_large => 'Bu cihaz için çok büyük olabilir';

  @override
  String get calculating => 'Hesaplanıyor...';

  @override
  String get download_failed => 'İndirme Başarısız';

  @override
  String get downloaded => 'İndirildi';

  @override
  String get not_downloaded => 'İndirilmedi';

  @override
  String get installed => 'Yüklendi';

  @override
  String get not_installed => 'Yüklenmedi';

  @override
  String get loading => 'Yükleniyor...';

  @override
  String get thinking => 'Düşünüyor...';

  @override
  String get processing => 'İşleniyor...';

  @override
  String get initializing => 'Başlatılıyor...';

  @override
  String get ready => 'Hazır';

  @override
  String get preparing_app => 'Uygulama hazırlanıyor...';

  @override
  String get initializing_services => 'Servisler başlatılıyor...';

  @override
  String get configuring_server => 'Sunucu yapılandırılıyor...';

  @override
  String get startup_failed => 'Başlatma başarısız oldu';

  @override
  String get something_went_wrong => 'Bir şeyler yanlış gitti';

  @override
  String get delete_model_title => 'Modeli Sil';

  @override
  String delete_model_body(String name) {
    return '$name modelini silmek istediğinizden emin misiniz?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return '$name modelini silmek istediğinizden emin misiniz? Bu yaklaşık $size alan boşaltacaktır.\n\nGerekirse bu modeli daha sonra tekrar indirebilirsiniz.';
  }

  @override
  String get delete_voice_title => 'Sesi Sil';

  @override
  String delete_voice_body(String name, String size) {
    return '$name sesini silmek istediğinizden emin misiniz? Bu yaklaşık $size alan boşaltacaktır.\n\nGerekirse bu sesi daha sonra tekrar indirebilirsiniz.';
  }

  @override
  String get delete_server_title => 'Sunucuyu Sil';

  @override
  String delete_server_body(String name) {
    return '\"$name\" sunucusunu silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  }

  @override
  String get delete_conversation_title => 'Sohbet silinsin mi?';

  @override
  String delete_conversation_body(String title) {
    return '\"$title\" sohbetini silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.';
  }

  @override
  String get delete_message_title => 'Mesaj silinsin mi?';

  @override
  String delete_persona_title(String name) {
    return '\"$name\" silinsin mi?';
  }

  @override
  String get delete_persona_body => 'Bu işlem geri alınamaz.';

  @override
  String get delete_builtin_persona_body =>
      'Bu yerleşik bir personalardır. Daha sonra Ayarlar\'dan geri yükleyebilirsiniz.';

  @override
  String get restore_builtin_personas => 'Varsayılan personaları geri yükle';

  @override
  String get restore_builtin_personas_desc =>
      'Sildiğiniz yerleşik personaları tekrar ekleyin';

  @override
  String get restore_builtin_personas_success =>
      'Varsayılan personalar geri yüklendi';

  @override
  String get clear_personas => 'Personaları temizle';

  @override
  String get enable_image_compression => 'Göndermeden önce görselleri sıkıştır';

  @override
  String get enable_image_compression_desc =>
      'Eklenen görsellerin boyutunu değiştirip sıkıştırarak sunucu sınırları içinde kalın';

  @override
  String get image_compression_level => 'Sıkıştırma seviyesi';

  @override
  String get image_compression_level_desc =>
      'Yüksek seviye, daha düşük kalitede daha küçük boyutlu yüklemeler sağlar';

  @override
  String get image_compression_level_low => 'Düşük';

  @override
  String get image_compression_level_medium => 'Orta';

  @override
  String get image_compression_level_high => 'Yüksek';

  @override
  String get sort_models_tooltip => 'Modelleri sırala';

  @override
  String get sort_by_favorites => 'Önce favoriler';

  @override
  String get sort_by_name => 'İsim (A-Z)';

  @override
  String get sort_by_size_smallest => 'Boyut (önce en küçük)';

  @override
  String get sort_by_size_largest => 'Boyut (önce en büyük)';

  @override
  String get sort_by_context_length => 'Bağlam uzunluğu';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return '$done/$total yeniden adlandırılıyor...';
  }

  @override
  String selected_count(int count) {
    return '$count seçildi';
  }

  @override
  String get ai_rename_tooltip => 'Seçilenleri Yapay Zeka ile yeniden adlandır';

  @override
  String get new_chat_in_folder_tooltip => 'Bu klasörde yeni sohbet';

  @override
  String total_tokens_count(int count) {
    return '$count token';
  }

  @override
  String get smart_replies_use_persona => 'Akıllı yanıtlarda personayı kullan';

  @override
  String get smart_replies_use_persona_desc =>
      'Önerilen yanıtlar genel asistan yerine aktif personanın tonuna uyar';

  @override
  String get keep_persona_on_new_chat => 'Yeni sohbette personayı koru';

  @override
  String get keep_persona_on_new_chat_desc =>
      'Yeni sohbet başlatıldıktan sonra seçilen persona(lar)ı temizleme';

  @override
  String get role_swap_button_enabled => 'Rol değiştirme düğmesini göster';

  @override
  String get role_swap_button_enabled_desc =>
      'Yanıt üretmeden mesajınızı kullanıcı yerine asistan olarak göndermek için sohbet girişinde bir düğme gösterin';

  @override
  String get send_as_user_tooltip => 'Kullanıcı olarak gönder';

  @override
  String get send_as_assistant_tooltip => 'Asistan olarak gönder (yanıt yok)';

  @override
  String get insert_without_generating_tooltip => 'Üretmeden ekle';

  @override
  String get token_usage_title => 'Token Kullanımı';

  @override
  String get total_tokens_label => 'Kullanılan token\'lar';

  @override
  String get usage_percent_label => 'Kullanılan bağlam';

  @override
  String get export_choice_title => 'Dışa Aktar';

  @override
  String get export_choice_body => 'Bunu nasıl dışa aktarmak istersiniz?';

  @override
  String get copy_to_clipboard => 'Panoya Kopyala';

  @override
  String bulk_export_conversations_success(int count) {
    return '$count sohbet dışa aktarıldı';
  }

  @override
  String get bulk_ai_rename_confirm_title =>
      'Yapay Zeka ile Yeniden Adlandırılsın mı?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'Bu işlem Yapay Zekadan seçilen $count sohbetin her biri için yeni bir başlık oluşturmasını ve mevcut başlıkların yerini almasını isteyecektir. Bu biraz zaman alabilir ve geri alınamaz.';
  }

  @override
  String get sort_by_modified_date => 'Son değiştirilme';

  @override
  String get sort_by_created_date => 'Oluşturulma tarihi';

  @override
  String get sort_title => 'Sırala';

  @override
  String get clear_conversation_title => 'Sohbet temizlensin mi?';

  @override
  String get clear_conversation_body =>
      'Bu işlem sohbet içindeki tüm mesajları silecektir.';

  @override
  String get clear => 'Temizle';

  @override
  String label_completed(String label) {
    return '$label tamamlandı';
  }

  @override
  String error_with_message(String error) {
    return 'Hata: $error';
  }

  @override
  String preview_failed(String error) {
    return 'Önizleme başarısız: $error';
  }

  @override
  String loading_model(String modelId) {
    return '$modelId yükleniyor...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'Model başarıyla yüklendi';
  }

  @override
  String get no_model_loaded =>
      'No model loaded. Tap \"Manage On-Device Modeller\" to download and load a model.';

  @override
  String loading_model_error(String error) {
    return 'Hata: $error';
  }

  @override
  String get delete_conversation => 'Sohbeti Sil';

  @override
  String get nav_history => 'Geçmiş';

  @override
  String get nav_servers => 'Sunucular';

  @override
  String get nav_local_models => 'Local Modeller';

  @override
  String get nav_tts => 'Metin Okuma';

  @override
  String get nav_personas => 'Personalar';

  @override
  String get nav_settings => 'Ayarlar';

  @override
  String get nav_new_chat => 'Yeni Sohbet';

  @override
  String get search_hint => 'Sohbetleri ara...';

  @override
  String get no_server_selected => 'Sunucu seçilmedi';

  @override
  String get switch_server => 'Sunucu Değiştir';

  @override
  String get switch_server_subtitle => 'Bağlanmak için bir sunucu seçin';

  @override
  String get manage_servers => 'Manage Sunucular';

  @override
  String get open_source => 'Açık Kaynak';

  @override
  String get open_source_desc =>
      'LocalMind açık kaynaklıdır. İlerlememizi takip edin veya GitHub\'da katkıda bulunun.';

  @override
  String get star_on_github => 'GitHub\'da Yıldızla';

  @override
  String get add_more => 'Daha fazla ekle';

  @override
  String get on_github => 'GitHub üzerinde';

  @override
  String get could_not_open_github => 'GitHub açılamadı.';

  @override
  String get settings_title => 'Ayarlar';

  @override
  String get settings_appearance => 'Görünüm';

  @override
  String get settings_language => 'Dil';

  @override
  String get language_system_default => 'Sistem Varsayılanı';

  @override
  String get settings_tts => 'Metin Okuma';

  @override
  String get settings_android_assistant => 'Android Asistanı';

  @override
  String get assistant_default_title => 'Varsayılan Sesli Asistan';

  @override
  String get assistant_default_description =>
      'Localmind\'ı Android sisteminizdeki varsayılan sesli asistan olarak ayarlayın.';

  @override
  String get assistant_status_active =>
      'Localmind varsayılan asistanınız olarak ayarlandı';

  @override
  String get assistant_status_available =>
      'Localmind varsayılan asistanınız olarak ayarlanabilir';

  @override
  String get assistant_status_manual =>
      'Sistem ayarlarını açın ve Localmind\'ı manuel olarak seçin';

  @override
  String get assistant_status_unsupported =>
      'Varsayılan asistan ayarı yalnızca Android 7.0+ sürümünde mevcuttur';

  @override
  String get assistant_status_checking => 'Asistan durumu kontrol ediliyor…';

  @override
  String get assistant_set_default => 'Varsayılan Asistanı Ayarla';

  @override
  String get assistant_open_settings => 'Asistan Ayarlarını Aç';

  @override
  String assistant_error(Object error) {
    return 'Hata: $error';
  }

  @override
  String get settings_behavior => 'Davranış';

  @override
  String get settings_on_device => 'Cihaz Üstü Çıkarım';

  @override
  String get settings_default_server => 'Varsayılan Sunucu';

  @override
  String get settings_default_persona => 'Varsayılan Persona';

  @override
  String get settings_default_model => 'Varsayılan Model';

  @override
  String get settings_default_model_desc =>
      'Yeni bir sohbet başlattığınızda otomatik olarak seçilir.';

  @override
  String get settings_privacy => 'Gizlilik';

  @override
  String get settings_data_management => 'Veri Yönetimi';

  @override
  String get settings_about => 'Hakkında';

  @override
  String get theme => 'Tema';

  @override
  String get theme_system => 'Sistem';

  @override
  String get theme_light => 'Açık';

  @override
  String get theme_dark => 'Koyu';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'Yazı Tipi Boyutu';

  @override
  String get font_size_desc => 'Sohbet içindeki metin boyutunu ayarlayın.';

  @override
  String get font_preview =>
      'Hızlı kahverengi tilki tembel köpeğin üzerinden atlar.';

  @override
  String get code_theme_dark => 'Kod Teması (Koyu)';

  @override
  String get code_theme_light => 'Kod Teması (Açık)';

  @override
  String get code_theme_desc =>
      'Kod blokları için sözdizimi vurgulama temasını seçin.';

  @override
  String get tts_engine => 'TTS Motoru';

  @override
  String get tts_engine_system => 'Sistem TTS';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => 'Ses';

  @override
  String get voice_female => 'Kadın';

  @override
  String get voice_male => 'Erkek';

  @override
  String get voice_other => 'Diğer';

  @override
  String get tts_speed => 'Konuşma Hızı';

  @override
  String get tts_speed_desc => 'Oynatma hızını ayarlayın.';

  @override
  String get manage_tts_models => 'Manage TTS Modeller';

  @override
  String get manage_on_device_models => 'Manage On-Device Modeller';

  @override
  String get enable_smart_reply => 'Cihaz Üstü Akıllı Yanıtlar';

  @override
  String get ai_user_response_enabled =>
      'Yapay zeka kullanıcı mesajı (göndere basılı tutun)';

  @override
  String get ai_user_response_enabled_desc =>
      'Yapay zekanın sonraki mesajınızı yazıp göndermesini sağlamak için gönder düğmesini 3 saniye basılı tutun';

  @override
  String get ai_user_response_tooltip =>
      'Yapay zeka ile kullanıcı mesajı oluştur';

  @override
  String get streaming_responses => 'Akan Yanıtlar (Streaming)';

  @override
  String get auto_generate_titles => 'Başlıkları Otomatik Oluştur';

  @override
  String get send_on_enter => 'Enter ile Gönder';

  @override
  String get show_system_messages => 'Varsayılan Sistem Yönergesini Gönder';

  @override
  String get show_system_messages_desc =>
      'Persona seçilmediğinde, her istekle birlikte varsayılan asistan sistem yönergesini gönder';

  @override
  String get show_system_messages_in_chat =>
      'Sohbette Sistem Mesajlarını Göster';

  @override
  String get show_system_messages_in_chat_desc =>
      'Sistem mesajlarını (örn. içe aktarılan yedekten) konuşmada görünür baloncuklar olarak göster';

  @override
  String get haptic_feedback => 'Dokunsal Geri Bildirim';

  @override
  String get enable_mcp => 'MCP\'yi Etkinleştir';

  @override
  String get new_chat_mcp_default => 'Yeni Sohbet MCP Varsayılanı';

  @override
  String get show_data_indicator => 'Veri Göstergesini Göster';

  @override
  String get privacy_info => '\"LocalMind verilerinizi asla görmez\"';

  @override
  String get delete_all_conversations => 'Sil All Sohbetler';

  @override
  String get reset_settings_defaults => 'Reset Ayarlar to Defaults';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'Sohbet Parametreleri';

  @override
  String get change_persona => 'Personayı Değiştir';

  @override
  String get set_persona => 'Personayı Ayarla';

  @override
  String get remove_persona => 'Kaldır Persona';

  @override
  String get clear_conversation => 'Sohbeti Temizle';

  @override
  String get connection_error => 'Bağlantı hatası. Sunucunuzu kontrol edin.';

  @override
  String get disconnected => 'Bağlantı Kesildi from server.';

  @override
  String get configure => 'Yapılandır';

  @override
  String get select_model => 'Model Seçin';

  @override
  String get select_persona => 'Persona Seç';

  @override
  String get manage_personas => 'Personaları yönet';

  @override
  String get personas_combine_hint =>
      'Sistem yönergelerini birleştirmek için sohbette birden fazla persona seçin.';

  @override
  String get start_conversation => 'Bir sohbet başlatın';

  @override
  String get recent_chats => 'Son sohbetler';

  @override
  String get see_all => 'Tümünü gör';

  @override
  String get quick_write => 'Bir fonksiyon yazmama yardım et';

  @override
  String get quick_explain => 'Bu kodu açıkla';

  @override
  String get quick_debug => 'Bunu benim için ayıkla (debug)';

  @override
  String get quick_async => 'async/await nasıl kullanılır?';

  @override
  String get history_missing_title => 'Geçmiş Eksik';

  @override
  String get history_missing_desc =>
      'Bu sohbetteki mesajlar silinmiş veya geçmiş kaydı bozulmuş.';

  @override
  String get technical_details => 'Teknik Detaylar';

  @override
  String get last_error => 'Last Hata:';

  @override
  String get copy_info => 'Copy Bilgi';

  @override
  String get conversation_id => 'Sohbet Kimliği (ID)';

  @override
  String get created_at => 'Oluşturulma Tarihi';

  @override
  String get expected_messages => 'Beklenen Mesajlar';

  @override
  String get debug_dialog_desc =>
      'Eşitleme sorunlarını belirlemeye yardımcı olacak teşhis bilgileri.';

  @override
  String get chat_input_hint => 'İstediğinizi sorun';

  @override
  String get send_message_tooltip => 'Mesaj gönder';

  @override
  String get stop_generation_tooltip => 'Üretimi durdur';

  @override
  String get attach_images_tooltip => 'Görsel veya metin ekle';

  @override
  String get start_listening_tooltip => 'Dinlemeyi başlat';

  @override
  String get stop_listening_tooltip => 'Dinlemeyi durdur';

  @override
  String tool_label(String toolCallId) {
    return 'Araç: $toolCallId';
  }

  @override
  String get tool_unknown => 'Araç: Bilinmeyen';

  @override
  String get message_options => 'Mesaj seçenekleri';

  @override
  String get copy_markdown => 'Markdown olarak Kopyala';

  @override
  String get copied_markdown => 'Markdown olarak kopyalandı';

  @override
  String get read_aloud => 'Sesli Oku';

  @override
  String get stop_reading => 'Okumayı Durdur';

  @override
  String get more => 'Daha fazla';

  @override
  String character_count(int length) {
    return '$length karakter';
  }

  @override
  String get edit_message => 'Mesajı Düzenle';

  @override
  String get edit_message_desc =>
      'Kaydetmek, alttaki asistan yanıtını kaldıracak ve yeniden üretecektir.';

  @override
  String get save_regenerate => 'Kaydet ve yeniden üret';

  @override
  String get chat_settings_title => 'Chat Ayarlar';

  @override
  String get reset_defaults => 'Varsayılanlara Sıfırla';

  @override
  String get parameters_tab => 'Parametreler';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'Sıcaklık (Temperature)';

  @override
  String get temperature_desc =>
      'Rastgeleliği kontrol eder: Yüksek = Yaratıcı, Düşük = Odaklanmış';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'Çekirdek örnekleme eşiği';

  @override
  String get max_tokens => 'Maksimum Token';

  @override
  String get max_tokens_desc => 'Yanıt sınırı';

  @override
  String get context_length => 'Bağlam Uzunluğu';

  @override
  String get context_length_desc => 'Geçmiş penceresi';

  @override
  String get mcp_disabled_warning =>
      'MCP is disabled globally. Enable it in Ayarlar to use these features.';

  @override
  String get mcp_enable_chat => 'Bu sohbet için MCP\'yi etkinleştir';

  @override
  String get auto_execute_tools => 'Araçları otomatik çalıştır';

  @override
  String get beta_label => 'Beta';

  @override
  String get experimental_label => 'Deneysel';

  @override
  String get add_ephemeral_mcp => 'Geçici MCP Sunucusu Ekle';

  @override
  String get mcp_label_placeholder => 'Etiket';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => 'Aktif Entegrasyonlar';

  @override
  String get import_mcp_json => 'JSON İçe Aktar';

  @override
  String get import_mcp_json_dialog_title =>
      'MCP Yapılandırma JSON\'ını İçe Aktar';

  @override
  String get import_mcp_json_instructions =>
      'mcpServers JSON dosyanızı doğrudan LM Studio\'dan (mcp.json) kopyalayın veya aşağıya bir eklenti dizisi yapıştırın:';

  @override
  String get import_mcp_json_placeholder =>
      'mcpServers JSON veya eklenti listesini buraya yapıştırın...';

  @override
  String mcp_import_success(int count) {
    return '$count entegrasyon başarıyla içe aktarıldı';
  }

  @override
  String get mcp_import_failed =>
      'JSON içinde geçerli bir MCP entegrasyonu bulunamadı';

  @override
  String get enable_notifications => 'Bildirimleri Etkinleştir';

  @override
  String get enable_notifications_desc =>
      'Modellerin indirilmesi tamamlandığında bildirim alın.';

  @override
  String get chat_history_title => 'Sohbet Geçmişi';

  @override
  String get conversation_just_now => 'Az önce';

  @override
  String conversation_minutes_ago(int minutes) {
    return '${minutes}d önce';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '${hours}s önce';
  }

  @override
  String get conversation_yesterday => 'Dün';

  @override
  String conversation_days_ago(int days) {
    return '${days}g önce';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$day/$month/$year';
  }

  @override
  String get options_tooltip => 'Seçenekler';

  @override
  String get no_results_found => 'Sonuç bulunamadı';

  @override
  String get no_conversations_yet => 'Henüz sohbet yok';

  @override
  String get try_different_search => 'Farklı bir arama terimi deneyin';

  @override
  String get start_new_conversation => 'Yeni bir sohbet başlatın';

  @override
  String get rename_conversation => 'Sohbeti Yeniden Adlandır';

  @override
  String get enter_new_title => 'Yeni başlık girin';

  @override
  String get pinned_section => 'SABİTLENENLER';

  @override
  String get today_section => 'BUGÜN';

  @override
  String get yesterday_section => 'DÜN';

  @override
  String get previous_7_days => 'Son 7 Gün';

  @override
  String get previous_30_days => 'Son 30 Gün';

  @override
  String get older_section => 'DAHA ESKİ';

  @override
  String get onboarding_choose_language => 'LocalMind dillerini keşfedin';

  @override
  String get onboarding_choose_language_desc =>
      'Uygulama arayüzünüz için tercih ettiğiniz dili seçin.';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'Sunucunuzu\nBağlayın';

  @override
  String get onboarding_connect_desc =>
      'Özel yapay zeka deneyiminize başlamak için LM Studio, Ollama,\nOllama Cloud veya OpenRouter\'a bağlanın.';

  @override
  String get openai_compatible_api => 'OpenAI uyumlu API';

  @override
  String get https_requires_ssl => 'HTTPS, SSL gerektirir';

  @override
  String get most_local_setups_use_http =>
      'Çoğu yerel kurulum http:// kullanır';

  @override
  String get onboarding_welcome => 'LocalMind\'a Hoş Geldiniz';

  @override
  String get server_type_on_device => 'Cihaz Üstü';

  @override
  String get server_type_lm_studio => 'LM Studio';

  @override
  String get server_type_ollama => 'Ollama';

  @override
  String get server_type_ollama_cloud => 'Ollama Cloud';

  @override
  String get server_type_ollama_cloud_sub => 'BULUT YÖNETİMLİ';

  @override
  String get server_type_ollama_cloud_display => 'Ollama Cloud';

  @override
  String get server_address_ollama_cloud => 'ollama.com';

  @override
  String get ollama_cloud_disclosure =>
      'Ollama Cloud\'a bağlanarak sohbet mesajlarınız ve girdileriniz çıkarım için Ollama\'nın yönetilen sunucularına gönderilir. LocalMind sohbetlerinizi izlemez veya saklamaz. Bu anahtarı ollama.com/settings/keys adresinden istediğiniz zaman iptal edebilirsiniz.';

  @override
  String get api_key_required_ollama_cloud =>
      'Ollama Cloud için API Anahtarı gereklidir';

  @override
  String get api_key_hint_ollama_cloud =>
      'Ollama Cloud API anahtarınızı yapıştırın';

  @override
  String get add_server_ollama_cloud_subtitle =>
      'Yönetilen bulut modellerine erişmek için ollama.com/settings/keys adresinden alacağınız API anahtarıyla Ollama Cloud\'a bağlanın.';

  @override
  String get add_server_openrouter_subtitle =>
      'Geçerli bir API anahtarıyla OpenRouter üzerinden bağlanın ve model yönlendirmesi için bu profili hazır tutun.';

  @override
  String get add_server_endpoint_subtitle =>
      'Yerel veya kendi barındırdığınız bir uç noktayı yapılandırın ve kaydetmeden önce bağlantıyı doğrulayın.';

  @override
  String get server_type_openrouter => 'OpenRouter';

  @override
  String get server_type_openrouter_sub => 'BİRLEŞİK BULUT';

  @override
  String get ready_continue => 'DEVAM ETMEYE HAZIR';

  @override
  String get waiting_selection => 'SEÇİM BEKLENİYOR';

  @override
  String get setup_connection => 'Bağlantıyı Kur';

  @override
  String setup_connection_desc(String server) {
    return 'Sohbet etmeye başlamak için $server sunucunuzu yapılandırın.';
  }

  @override
  String get server_name => 'Sunucu Adı';

  @override
  String get name_required => 'İsim gereklidir';

  @override
  String get name_max_50 => 'En fazla 50 karakter';

  @override
  String get host_label => 'Ana Bilgisayar / IP Adresi';

  @override
  String get host_required => 'Ana bilgisayar gereklidir';

  @override
  String get port_label => 'Port';

  @override
  String get port_required => 'Port gereklidir';

  @override
  String get port_invalid => 'Bir sayı olmalıdır';

  @override
  String get port_range => 'Geçerli bir port girin (1-65535)';

  @override
  String get api_key_required => 'API Anahtarı *';

  @override
  String get api_key_optional => 'API Anahtarı (İsteğe Bağlı)';

  @override
  String get api_key_required_openrouter =>
      'OpenRouter için API Anahtarı gereklidir';

  @override
  String get api_key_format => 'OpenRouter API anahtarları sk- ile başlar';

  @override
  String get my_server_hint => 'Sunucum';

  @override
  String get name_length_validation =>
      'İsim 50 karakter veya daha az olmalıdır';

  @override
  String get host_valid =>
      'Geçerli bir ana bilgisayar adı veya IP adresi girin';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => 'Kimlik doğrulamalı sunucular için';

  @override
  String get update_server => 'Sunucuyu Güncelle';

  @override
  String get save_server => 'Sunucuyu Kaydet';

  @override
  String get server_updated => 'Sunucu güncellendi';

  @override
  String get server_added => 'Sunucu eklendi';

  @override
  String get download_model_title => 'Bir Model İndirin';

  @override
  String get download_model_desc =>
      'İndirmek için bir model seçin.\nCihazınızda yerel olarak çalışacaktır.';

  @override
  String get on_device_android_only =>
      'Cihaz üstü çıkarım şu anda yalnızca Android\'de kullanılabilir.';

  @override
  String get total_ram => 'Toplam RAM';

  @override
  String get available => 'Kullanılabilir';

  @override
  String ram_min_required(String fileSize) {
    return 'En az $fileSize GB RAM';
  }

  @override
  String download_progress(String percent, String speed) {
    return '%$percent • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'Kalan Süre: $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'Duraklatıldı - %$percent';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'Bu model en az $ram GB RAM gerektirir, ancak cihazınızda $totalMemory var. Düzgün çalışmayabilir veya uygulamanın çökmesine neden olabilir.';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'Cihazınızda $availableRAM kullanılabilir RAM var, ancak bu model en az $ram GB önerir. Yükleme başarısız olabilir veya kararsızlığa yol açabilir.';
  }

  @override
  String get choose_theme => 'Tema Seçin';

  @override
  String get choose_theme_desc =>
      'Uygulama görünümünü kişiselleştirin. Bunu daha sonra ayarlar içinden değiştirebilirsiniz.';

  @override
  String get theme_card_system => 'Sistem';

  @override
  String get theme_card_system_sub => 'Cihaz ayarlarınızla eşleşir';

  @override
  String get theme_card_light => 'Açık';

  @override
  String get theme_card_light_sub => 'Temiz ve parlak';

  @override
  String get theme_card_dark => 'Koyu';

  @override
  String get theme_card_dark_sub => 'Gözleri yormaz';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'Sıcak, şeftali tonlu bir tema';

  @override
  String get stay_updated => 'Güncel Kalın';

  @override
  String get stay_updated_desc =>
      'Yapay zeka modellerinizin indirilmesi tamamlandığında veya uzun süren görevler bittiğinde bildirim alın.';

  @override
  String get notification_benefit_downloads => 'Model indirme ilerlemesi';

  @override
  String get notification_benefit_completions => 'Üretim tamamlamaları';

  @override
  String get notification_benefit_background => 'Geriground tasks status';

  @override
  String get allow_notifications => 'Bildirimlere İzin Ver';

  @override
  String get servers_title => 'Sunucular';

  @override
  String get no_servers_yet => 'No Sunucular Yet';

  @override
  String get no_servers_desc =>
      'Yapay zeka modelleriyle sohbet etmeye başlamak için ilk sunucunuzu ekleyin.';

  @override
  String get add_server => 'Sunucu Ekle';

  @override
  String switched_to_server(String name) {
    return '$name sunucusuna geçildi';
  }

  @override
  String get edit_server => 'Sunucuyu Düzenle';

  @override
  String get add_server_title => 'Sunucu Ekle';

  @override
  String get server_type_label => 'Sunucu Türü';

  @override
  String get server_icon_label => 'Sunucu Simgesi';

  @override
  String get default_icon => 'Varsayılan simge';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'OpenAI Uyumlu';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'Cihaz Üstü';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'Yerel çıkarım';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'Varsayılan';

  @override
  String get set_as_default => 'Varsayılan Olarak Ayarla';

  @override
  String get select_icon => 'Simge Seç';

  @override
  String get select_icon_desc => 'Sunucunuz için bir simge seçin';

  @override
  String get search_icons_hint => 'Simgeleri ara...';

  @override
  String get server_icon_stack => 'Sunucu Yığını';

  @override
  String get server_icon_stack2 => 'Sunucu Yığını 02';

  @override
  String get server_icon_stack3 => 'Sunucu Yığını 03';

  @override
  String get server_icon_cloud => 'Bulut';

  @override
  String get server_icon_cloud_server => 'Bulut Sunucu';

  @override
  String get server_icon_mcp => 'MCP Sunucusu';

  @override
  String get server_icon_database => 'Veritabanı';

  @override
  String get server_icon_database1 => 'Veritabanı 01';

  @override
  String get server_icon_database2 => 'Veritabanı 02';

  @override
  String get server_icon_cpu => 'İşlemci (CPU)';

  @override
  String get server_icon_chip => 'Yonga (Chip)';

  @override
  String get server_icon_chip2 => 'Yonga 02';

  @override
  String get server_icon_computer => 'Bilgisayar';

  @override
  String get server_icon_laptop => 'Dizüstü Bilgisayar';

  @override
  String get server_icon_terminal => 'Bilgisayar Terminali';

  @override
  String get server_icon_code => 'Kod';

  @override
  String get server_icon_ai_brain => 'Yapay Zeka Beyin';

  @override
  String get server_icon_ai_brain2 => 'Yapay Zeka Beyin 02';

  @override
  String get server_icon_ai_cloud => 'Yapay Zeka Bulut';

  @override
  String get server_icon_ai_network => 'Yapay Zeka Ağı';

  @override
  String get server_icon_ai_chat => 'Yapay Zeka Sohbet';

  @override
  String get server_icon_cellular => 'Hücresel Ağ';

  @override
  String get server_icon_plug1 => 'Fiş 01';

  @override
  String get server_icon_plug2 => 'Fiş 02';

  @override
  String get server_icon_bot => 'Bot';

  @override
  String get server_icon_bot2 => 'Bot 02';

  @override
  String get server_icon_robotic => 'Robotik';

  @override
  String get server_icon_rocket => 'Roket';

  @override
  String get server_icon_star => 'Yıldız';

  @override
  String get server_icon_settings1 => 'Ayarlar 01';

  @override
  String get server_icon_settings2 => 'Ayarlar 02';

  @override
  String get server_icon_home1 => 'Ev 01';

  @override
  String get server_icon_home2 => 'Ev 02';

  @override
  String get server_icon_folder1 => 'Klasör 01';

  @override
  String get server_icon_folder2 => 'Klasör 02';

  @override
  String get server_icon_file1 => 'Dosya 01';

  @override
  String get server_icon_lock => 'Kilit';

  @override
  String get server_icon_key => 'Anahtar 01';

  @override
  String get server_icon_link => 'Bağlantı 01';

  @override
  String get server_icon_globe => 'Dünya';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'Sağ Ok 01';

  @override
  String get server_icon_check => 'Onay Dairesi';

  @override
  String get server_icon_alert => 'Uyarı Dairesi';

  @override
  String get server_icon_info => 'Bilgi Circle';

  @override
  String get server_icon_zap => 'Hızlı Yıldırım';

  @override
  String get server_icon_cloud_upload => 'Buluta Yükle';

  @override
  String get server_icon_cloud_download => 'Buluttan İndir';

  @override
  String get server_icon_refresh => 'Yenile';

  @override
  String get server_icon_hard_drive => 'Sabit Sürücü';

  @override
  String get server_icon_drive => 'Sürücü';

  @override
  String get personas_title => 'Personalar';

  @override
  String get persona_category_general => 'Genel';

  @override
  String get persona_category_coding => 'Kodlama';

  @override
  String get persona_category_education => 'Eğitim';

  @override
  String get persona_category_creative => 'Yaratıcı';

  @override
  String get persona_builtin_section => 'YERLEŞİK';

  @override
  String get persona_my_section => 'PERSONALARIM';

  @override
  String get clone_edit => 'Clone & Düzenle';

  @override
  String get builtin_badge => 'Yerleşik';

  @override
  String get no_personas_found => 'Persona bulunamadı';

  @override
  String get no_personas_desc =>
      'Yapay zeka davranışını özelleştirmek için ilk personanızı oluşturun.';

  @override
  String get edit_persona => 'Personayı Düzenle';

  @override
  String get create_persona => 'Persona Oluştur';

  @override
  String get create_persona_button => 'Oluştur';

  @override
  String get emoji_label => 'Emoji';

  @override
  String get name_label => 'İsim';

  @override
  String get my_persona_hint => 'Personam';

  @override
  String get category_label => 'Kategori';

  @override
  String get description_optional => 'Açıklama (isteğe bağlı)';

  @override
  String get description_hint => 'Bu persona ne yapar...';

  @override
  String get system_prompt => 'Sistem Yönergesi';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'Henüz yönerge yok...';

  @override
  String get prompt_hint => 'Sen yardımcı bir asistansın...';

  @override
  String get prompt_required => 'Sistem yönergesi gereklidir';

  @override
  String get prompt_max_chars => 'En fazla 4000 karakter';

  @override
  String get advanced_settings => 'Advanced Ayarlar';

  @override
  String get temperature_label => 'Sıcaklık (0.0-2.0)';

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
  String get persona_updated => 'Persona güncellendi';

  @override
  String get persona_created => 'Persona oluşturuldu';

  @override
  String get tts_models_title => 'Text To Speech Modeller';

  @override
  String get always_available => 'Her zaman kullanılabilir';

  @override
  String get tts_system_desc =>
      'Cihazınızın yerleşik metin okuma motorunu kullanır.\nİndirme gerekmez. Ses seçimi cihazınızın sistem ayarlarını kullanır.';

  @override
  String get downloading_status => 'İndiriliyor...';

  @override
  String tts_kitten_desc(String size) {
    return '8 ifade dolu ses içeren şimşek hızında nöral TTS.\n$size indirme gerektirir.';
  }

  @override
  String tts_piper_desc(String size) {
    return '2 ifade dolu ses içeren hızlı çevrimdışı Piper sesleri.\nSes başına $size indirme gerektirir.';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB RAM · $voiceCount ses';
  }

  @override
  String get on_device_models_title => 'On-Device Modeller';

  @override
  String get settings_huggingface_token => 'Hugging Face Jetonu (İsteğe Bağlı)';

  @override
  String get settings_huggingface_token_desc =>
      'Yalnızca kapalı modeller (örn. Gemma) için gereklidir. huggingface.co/settings/tokens adresinden edinin.';

  @override
  String get settings_huggingface_token_set => 'Jeton kaydedildi';

  @override
  String get settings_huggingface_token_cleared => 'Jeton temizlendi';

  @override
  String get model_requires_huggingface_token =>
      'Hugging Face jetonu gerektirir';

  @override
  String get model_missing_huggingface_token =>
      'This model is gated on Hugging Face. Add a token in Ayarlar → On-Device Inference to download it.';

  @override
  String get set_huggingface_token => 'Jetonu ayarla';

  @override
  String get clear_huggingface_token => 'Temizle';

  @override
  String get edit_huggingface_token_dialog_title =>
      'Hugging Face Erişim Jetonu';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc =>
      'Yerel yapay zeka motoru. API anahtarı gerekmez.';

  @override
  String get server_type_on_device_desc =>
      'Telefonunuzda çalışır. Bazı modeller Hugging Face jetonu gerektirir.';

  @override
  String get server_type_lm_studio_desc =>
      'Yerel API sunucusu. API anahtarı gerekmez.';

  @override
  String get available_models => 'Available Modeller';

  @override
  String get device_memory => 'Cihaz Belleği';

  @override
  String get ram_usage => 'RAM Kullanımı';

  @override
  String get memory_healthy => 'Sağlıklı';

  @override
  String get memory_critical => 'Kritik';

  @override
  String get memory_low => 'Düşük';

  @override
  String ram_used(String percent) {
    return '%$percent kullanılıyor';
  }

  @override
  String get available_ram => 'Kullanılabilir RAM';

  @override
  String get total_capacity => 'Toplam Kapasite';

  @override
  String get loaded_status => 'Yüklendi';

  @override
  String get inference_backend => 'Inference Geriend';

  @override
  String get backend_ios_notice =>
      'iOS\'ta yalnızca CPU arka ucu kullanılabilir.';

  @override
  String get backend_cpu_desc => 'Tüm cihazlarda çalışır. En uyumlusu.';

  @override
  String get backend_gpu_desc =>
      'OpenCL hızlandırma. Desteklenen cihazlarda daha hızlı.';

  @override
  String get backend_npu_desc =>
      'Üretici NPU\'su (Qualcomm/MediaTek). En hızlı çıkarım.';

  @override
  String get select_model_title => 'Model Seç';

  @override
  String get refresh_models => 'Modelleri yenile';

  @override
  String get search_models_hint => 'Modelleri ara...';

  @override
  String get no_server_connected => 'Bağlı sunucu yok';

  @override
  String get add_server_first =>
      'Mevcut modelleri görmek için önce bir sunucu ekleyin.';

  @override
  String get failed_load_models => 'Başarısız to load models';

  @override
  String get no_models_available => 'Mevcut model yok';

  @override
  String no_models_match(String searchQuery) {
    return '\"$searchQuery\" ile eşleşen model yok';
  }

  @override
  String model_load_failed(String error) {
    return 'Başarısız to load model: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return '$name için bellekten çıkarma istendi. Ollama ulaşılabilirse model hemen serbest bırakılır.';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name başarıyla bellekten çıkarıldı';
  }

  @override
  String model_unload_failed(String error) {
    return 'Başarısız to unload model: $error';
  }

  @override
  String get unload_from_server => 'Sunucudan bellekten çıkar';

  @override
  String context_chip(String ctx) {
    return '$ctx bağlam';
  }

  @override
  String get unload_all_models => 'Tümünü bellekten çıkar';

  @override
  String loaded_models_count(int count) {
    return '$count yüklendi';
  }

  @override
  String get all_models_unloaded => 'Tüm modeller bellekten çıkarıldı';

  @override
  String get branch_chat => 'Sohbeti Dallandır';

  @override
  String get branch_chat_desc => 'Bu mesajdan yeni bir sohbet dalı oluşturun';

  @override
  String get edit_assistant_message_desc =>
      'Düzenle the assistant response text.';

  @override
  String switch_to_model(String modelName, Object model) {
    return '$modelName modeline geç';
  }

  @override
  String download_notification_title(String modelName) {
    return '$modelName indiriliyor...';
  }

  @override
  String get download_complete_notification => 'İndirme tamamlandı!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName başarıyla indirildi.';
  }

  @override
  String download_failed_notification(String error) {
    return 'İndirme başarısız: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return 'Başarısız to download $modelName.';
  }

  @override
  String get engine_name_system => 'Sistem TTS';

  @override
  String get engine_tagline_system => 'Cihazın yerleşik motoru';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => 'Yüksek hızlı nöral TTS';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'Çevrimdışı Piper sesleri';

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
  String get voice_lessac => 'Lessac (ABD)';

  @override
  String get voice_ryan => 'Ryan (ABD)';

  @override
  String get model_qwen_3 => 'Qwen 3 0.6B';

  @override
  String get model_qwen_3_desc =>
      'En küçük genel amaçlı sohbet modeli. Hızlı yanıtlar, düşük bellek kullanımı.';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'Dengeli kalite ve boyut. Genel konuşmalar için iyidir.';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'Mantık yürütme ve düşünce zinciri modeli. Mantıksal görevler için en iyisidir.';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'Google amiral gemisi modeli. En yüksek kalite, daha fazla RAM gerektirir.';

  @override
  String export_header(String date) {
    return '*LocalMind üzerinden dışa aktarıldı — $date*';
  }

  @override
  String get export_role_user => '## 👤 Kullanıcı';

  @override
  String get export_role_assistant => '## 🤖 Asistan';

  @override
  String get export_role_system => '## ⚙️ Sistem';

  @override
  String get export_role_tool => '## 🔧 Araç';

  @override
  String get export_text_user => '[KULLANICI]';

  @override
  String get export_text_assistant => '[ASİSTAN]';

  @override
  String get export_text_system => '[SİSTEM]';

  @override
  String get export_text_tool => '[ARAÇ]';

  @override
  String get export_label_user => 'KULLANICI';

  @override
  String get export_label_assistant => 'ASİSTAN';

  @override
  String get export_label_system => 'SİSTEM';

  @override
  String get export_label_tool => 'ARAÇ';

  @override
  String get select_model_hint => 'Sohbete başlamak için bir model seçin';

  @override
  String get test_notification_title => 'Test bildirimi';

  @override
  String get test_notification_body =>
      'Bu, model indirme ilerlemesi için bir test bildirimidir.';

  @override
  String get tts_supports_background =>
      'Yerel ses olarak arka planda oynatmayı destekler';

  @override
  String get tts_other_services_background_note =>
      'Not: Diğer TTS servisleri yerel ses olarak arka planda oynatmayı destekler.';

  @override
  String get gguf_imported_models_title => 'İçe aktarılan GGUF modelleri';

  @override
  String get gguf_imported_models_empty_subtitle =>
      'Cihazınızdan bir GGUF aktarın veya Hugging Face\'ten ekleyin. İçe aktarılan modeller llama.cpp ile yerel çalışır.';

  @override
  String get gguf_imported_models_ready =>
      'yerel çıkarım için hazır içe aktarılan modeller.';

  @override
  String get gguf_curated_models_subtitle =>
      'LocalMind içinde indirebileceğiniz ve yönetebileceğiniz özel cihaz üstü modeller.';

  @override
  String get gguf_only_supported =>
      'Bu içe aktarma için yalnızca GGUF modelleri desteklenir.';

  @override
  String get gguf_imported_from_local_file => 'yerel dosyadan içe aktarıldı.';

  @override
  String get gguf_import_failed => 'Başarısız to import GGUF model';

  @override
  String get gguf_imported_from_huggingface =>
      'Hugging Face\'ten içe aktarıldı.';

  @override
  String get gguf_import_canceled => 'GGUF içe aktarma iptal edildi.';

  @override
  String get gguf_enter_huggingface_url =>
      'Bir Hugging Face GGUF URL\'si girin.';

  @override
  String get gguf_only_official_huggingface_urls =>
      'Yalnızca resmi Hugging Face GGUF URL\'leri desteklenir.';

  @override
  String get gguf_use_https_url =>
      'GGUF içe aktarımı için HTTPS Hugging Face URL\'si kullanın.';

  @override
  String get gguf_url_must_point_to_file =>
      'Hugging Face URL\'si doğrudan bir .gguf dosyasına işaret etmelidir.';

  @override
  String get gguf_unable_to_detect_file_name => 'GGUF dosya adı belirlenemedi.';

  @override
  String get gguf_download_empty => 'İndirilen GGUF dosyası boş veya eksik.';

  @override
  String get gguf_selected_file_missing =>
      'Seçilen model dosyası mevcut değil.';

  @override
  String get gguf_import_action => 'GGUF İçe Aktar';

  @override
  String get gguf_overview_title => 'Kendi GGUF modellerinizi getirin';

  @override
  String get gguf_overview_subtitle =>
      'Yerel depolamadan bir .gguf dosyası aktarın veya doğrudan Hugging Face\'ten indirin. İçe aktarılan modeller bu cihazda kalır ve llama.cpp ile yüklenir.';

  @override
  String get gguf_imported_count_label => 'içe aktarıldı';

  @override
  String get gguf_local_files_label => 'yerel dosyalar';

  @override
  String get gguf_huggingface_label => 'Hugging Face';

  @override
  String get gguf_import_local_title => 'Yerel GGUF İçe Aktar';

  @override
  String get gguf_import_local_subtitle =>
      'Bu cihazdan bir .gguf dosyası kopyalayın';

  @override
  String get gguf_import_huggingface_title => 'Hugging Face\'ten İçe Aktar';

  @override
  String get gguf_import_huggingface_subtitle =>
      'Bir GGUF URL\'si veya depo yolu yapıştırın';

  @override
  String get gguf_no_imported_title => 'Henüz içe aktarılan GGUF modeli yok';

  @override
  String get gguf_no_imported_subtitle =>
      'Cihaz depolamanızdan kendi GGUF dosyanızı getirebilir veya bir .gguf dosyasına işaret eden bir Hugging Face URL\'si veya depo yolu yapıştırabilirsiniz.';

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
      'Requires a Hugging Face token. Add one in Ayarlar if this GGUF is gated or private.';

  @override
  String get gguf_downloading => 'Downloading GGUF';

  @override
  String get gguf_preparing => 'Preparing';

  @override
  String get gguf_preparing_download => 'Preparing download...';

  @override
  String get gguf_cancel_import => 'İptal import';

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
  String get mcp_tools_title => 'MCP Araçları';

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
  String get tool_status_failed => 'Başarısız';

  @override
  String get model_favorite_toggle => 'Toggle favorite';

  @override
  String get model_set_default => 'Varsayılan model olarak ayarla';

  @override
  String get model_clear_default => 'Varsayılan modelden kaldır';

  @override
  String get model_default_badge => 'Varsayılan';

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
  String get export_data_success => 'Geriup exported successfully';

  @override
  String get import_data_success => 'Geriup imported successfully';

  @override
  String import_data_failed(String error) {
    return 'Başarısız to import backup: $error';
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
  String get export_settings => 'Ayarları dışa aktar';

  @override
  String get import_settings => 'Ayarları içe aktar';

  @override
  String get export_all_zip => 'Tümünü dışa aktar (ZIP)';

  @override
  String get import_all_zip => 'Tümünü içe aktar (ZIP)';

  @override
  String get duplicate_chat => 'Sohbeti çoğalt';

  @override
  String get duplicate_chat_success => 'Sohbet çoğaltıldı';

  @override
  String get move_to_folder => 'Klasöre taşı';

  @override
  String get remove_from_folder => 'Kaldır from folder';

  @override
  String get create_folder => 'Klasör oluştur';

  @override
  String get new_folder => 'Yeni klasör';

  @override
  String get folder_name_hint => 'Örn. İş, Kişisel, Araştırma';

  @override
  String get all_chats => 'Tümü';

  @override
  String get unfiled_chats => 'Kategorisiz';

  @override
  String get create => 'Oluştur';

  @override
  String get server_path_prefix_label => 'API yol öneki';

  @override
  String get server_path_prefix_hint => '/gizli-jetonunuz';

  @override
  String get search_message_contents => 'Mesaj içeriklerini ara';

  @override
  String get message_search_results => 'Mesaj eşleşmeleri';

  @override
  String get saved_messages_title => 'Kaydedilen Mesajlar';

  @override
  String get nav_saved_messages => 'Kaydedilenler';

  @override
  String get saved_messages_empty =>
      'Henüz kaydedilen mesaj yok. Seçenekler menüsünden bir mesajı yer imlerine ekleyin.';

  @override
  String get save_message => 'Mesajı kaydet';

  @override
  String get message_saved => 'Mesaj kaydedildi';

  @override
  String token_count(int count) {
    return '$count token';
  }

  @override
  String estimated_token_count(int count) {
    return '~$count token (tahmini)';
  }

  @override
  String get test_tts_section_title => 'Sesi test et';

  @override
  String get test_tts_hint => 'Mevcut TTS motorunu duymak için metin girin…';

  @override
  String get test_speak_button => 'Konuş';

  @override
  String get scroll_to_bottom => 'En aşağı kaydır';

  @override
  String get generate_ai_response => 'Yapay zeka yanıtı üret';

  @override
  String get no_response => 'Yanıt yok';

  @override
  String get export => 'Dışa Aktar';

  @override
  String get import => 'İçe Aktar';

  @override
  String get conversations_label => 'Sohbetler';

  @override
  String get personas_label => 'Personalar';

  @override
  String get settings_label => 'Ayarlar';

  @override
  String get export_conversation => 'Sohbeti Dışa Aktar';

  @override
  String get tts_process_markdown => 'Konuşma için markdown\'ı işle';

  @override
  String get tts_process_markdown_desc =>
      'Sesli okunmadan önce **koyu** gibi biçimlendirmeleri temizle';

  @override
  String get tts_skip_seconds => 'Atlama aralığı';

  @override
  String get tts_skip_seconds_desc =>
      'Oynatma sırasında ileri ve geri sarma adımı boyutu';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}sn';
  }

  @override
  String get preview_system_prompts => 'Sistem yönergelerini önizle';

  @override
  String get welcome_message_1 => 'Bugün size nasıl yardımcı olabilirim?';

  @override
  String get welcome_message_2 =>
      'İstediğinizi sorun — hazır olduğunuzda buradayım.';

  @override
  String get welcome_message_3 =>
      'Verileriniz yerel olarak işlenir ve cihazınızdan asla ayrılmaz.';

  @override
  String get welcome_message_4 =>
      'Fikre mi ihtiyacınız var? Hızlı yönergelerden birini deneyin.';

  @override
  String get temporary_chat => 'Geçici sohbet';

  @override
  String get temporary_chat_desc => 'Sohbetler geçmişe kaydedilmez.';

  @override
  String get temporary_chat_banner => 'Geçici sohbet — geçmişe kaydedilmez';

  @override
  String get temporary_chat_save_warning_title =>
      'Mesaj geçici sohbete kaydedilsin mi?';

  @override
  String get temporary_chat_save_warning_body =>
      'Bu sohbet geçicidir ve geçmişten gizlenir. Kaydedilen mesaj yine de Kaydedilen Mesajlar bölümünde görünecektir.';

  @override
  String get save_to_history => 'Geçmişe kaydet';

  @override
  String get share_conversation => 'Sohbeti paylaş';

  @override
  String get download_tts_audio => 'Sesi indir';

  @override
  String get tts_download_unavailable =>
      'İndirme yalnızca Piper ve Kitten TTS için mevcuttur';

  @override
  String get tts_download_no_audio => 'Henüz indirilecek ses yok';

  @override
  String get tts_download_success => 'Ses kaydedildi';

  @override
  String get return_to_chat => 'Sohbete dön';

  @override
  String get return_to_temp_chat => 'Geçici sohbete dön';

  @override
  String get insert_saved_message => 'Kaydedilen mesajı ekle';

  @override
  String get insert_saved_message_desc =>
      'Girdinize eklemek için kaydedilmiş bir mesaj seçin';

  @override
  String get model_info => 'Model bilgisi';

  @override
  String get model_name => 'Model adı';

  @override
  String get model_identifier => 'Kimlik (Identifier)';

  @override
  String get model_capabilities => 'Yetenekler';

  @override
  String get model_api_pricing => 'API fiyatlandırması (1M jeton başına)';

  @override
  String get not_available => 'Mevcut değil';

  @override
  String get save_message_folders => 'Mesajı kaydet';

  @override
  String get remove_from_saved => 'Kaldır from saved';

  @override
  String get message_already_saved => 'Kaydedildi';

  @override
  String get stream_ttft => 'İlk tokene kadar geçen süre (TTFT)';

  @override
  String get stream_tokens_per_sec => 'Saniyedeki token';

  @override
  String get stream_stop_reason => 'Durdurma nedeni';

  @override
  String get stream_input_tokens => 'Girdi token\'ları';

  @override
  String get stream_output_tokens => 'Çıktı token\'ları';

  @override
  String get stream_generation_time => 'Üretim süresi';

  @override
  String get attach_image => 'Fotoğraflar';

  @override
  String get attach_text_document => 'Belgeler';

  @override
  String get attach_shortcut_images => 'Fotoğraflar';

  @override
  String get attach_shortcut_documents => 'Dosyalar';

  @override
  String get attach_shortcut_saved => 'Kaydedilenler';

  @override
  String get add_attachment => 'Ek ekle';

  @override
  String get add_to_chat => 'Sohbete ekle';

  @override
  String get choose_what_to_attach => 'Ne eklemek istersiniz?';

  @override
  String get choose_attachment_subtitle =>
      'Mesajınıza eklemek için bir kaynak seçin';

  @override
  String get photo_permission_denied =>
      'Görsel eklemek için fotoğraf erişim izni gereklidir';

  @override
  String get select_model_prompt => 'Model seçin';

  @override
  String get characters_label => 'Karakter';

  @override
  String get exit_temporary_chat_title => 'Geçici sohbetten çıkılsın mı?';

  @override
  String get exit_temporary_chat_body =>
      'Bu işlem mevcut geçici sohbeti atacak ve yeni sohbet ekranına dönecektir.';

  @override
  String get saved_message_temp_snap_unavailable =>
      'Bu mesaj geçici bir sohbetten kaydedildi ve orijinal konuşmasında açılamaz.';

  @override
  String get filter_title => 'Filtrele';

  @override
  String get filter_pinned => 'Sabitlenenler';

  @override
  String get filter_archived => 'Arşivlenenler';

  @override
  String get filter_temp_chats => 'Geçici sohbetler';

  @override
  String get filter_user_messages => 'Kullanıcı mesajları';

  @override
  String get filter_assistant_messages => 'Asistan mesajları';

  @override
  String get archive_chat => 'Arşivle';

  @override
  String get unarchive_chat => 'Arşivden Çıkar';

  @override
  String conversation_message_count(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mesaj',
      one: '1 mesaj',
    );
    return '$_temp0';
  }

  @override
  String conversation_character_count(int count) {
    return '$count krk';
  }

  @override
  String get generate_title_with_ai => 'Yapay Zeka ile oluştur';

  @override
  String get generating_title => 'Oluşturuluyor...';

  @override
  String get generate_title_failed => 'Başlık oluşturulamadı';

  @override
  String get lm_studio_model_browser_title => 'Modelleri gözden geçir';

  @override
  String get lm_studio_model_search_hint =>
      'Modelleri ad veya yazara göre ara…';

  @override
  String get lm_studio_staff_picks => 'Öne çıkanlar';

  @override
  String get lm_studio_community_models => 'Topluluk modelleri';

  @override
  String get lm_studio_no_models => 'Model bulunamadı';

  @override
  String lm_studio_models_count(int count) {
    return '$count model';
  }

  @override
  String get lm_studio_browse_models => 'Gözden geçir ve indir';

  @override
  String get lm_studio_model_search => 'LMS Model Arama';

  @override
  String get lm_studio_downloads_title => 'İndirmeler';

  @override
  String get lm_studio_choose_quant => 'Bir indirme seçeneği belirleyin';

  @override
  String get lm_studio_use_default_quant => 'Varsayılanı kullan';

  @override
  String get lm_studio_recommended => 'Önerilen';

  @override
  String get lm_studio_clear_downloads => 'Tamamlananları temizle';

  @override
  String get lm_studio_no_downloads => 'Henüz indirme yok';

  @override
  String get lm_studio_downloads_disclaimer =>
      'İndirmeler LM Studio ana bilgisayarında çalışır. Duraklatma, durdurma ve model silme işlemleri bu uygulama üzerinden değil, o bilgisayarda yapılmalıdır.';

  @override
  String get lm_studio_staff_pick => 'Öne çıkan';

  @override
  String get lm_studio_params => 'PARAMETRE';

  @override
  String get lm_studio_arch => 'MİMARİ';

  @override
  String get lm_studio_domain => 'ALAN';

  @override
  String get lm_studio_format => 'FORMAT';

  @override
  String get lm_studio_vision => 'Görüş';

  @override
  String get lm_studio_tool_use => 'Araç kullanımı';

  @override
  String get lm_studio_reasoning => 'Mantık yürütme';

  @override
  String get openrouter_pricing_free => 'Ücretsiz';

  @override
  String openrouter_pricing_tooltip(String input, String output) {
    return '1M jeton başına Girdi $input / Çıktı $output';
  }

  @override
  String get lm_studio_download_options => 'İndirme seçenekleri';

  @override
  String get lm_studio_download => 'İndir';

  @override
  String lm_studio_download_size(String size) {
    return '$size İndir';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'İndiriliyor %$percent';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'Bu model için README mevcut değil.';

  @override
  String get lm_studio_full_gpu_offload => 'Tam GPU yük devretmesi mümkün';

  @override
  String get lm_studio_partial_gpu_offload => 'Kısmi GPU yük devretmesi mümkün';

  @override
  String get lm_studio_likely_too_large => 'Muhtemelen çok büyük';

  @override
  String get lm_studio_available_ram_gb =>
      'Kullanılabilir RAM (GB, isteğe bağlı)';

  @override
  String get lm_studio_available_vram_gb =>
      'Kullanılabilir VRAM (GB, isteğe bağlı)';

  @override
  String get lm_studio_memory_settings_title => 'Öneriler için bellek';

  @override
  String get lm_studio_memory_settings_desc =>
      'Model tarayıcısında modellerin makinenize sığıp sığmadığını tahmin etmek için kullanılır.';

  @override
  String get think_button_label => 'Düşün';

  @override
  String get thinking_mode_title => 'Düşünme modu';

  @override
  String get reasoning_effort_low => 'Düşük';

  @override
  String get reasoning_effort_medium => 'Orta';

  @override
  String get reasoning_effort_high => 'Yüksek';

  @override
  String get reasoning_effort_minimal => 'Minimum';

  @override
  String get reasoning_effort_xhigh => 'Çok Yüksek';

  @override
  String get reasoning_effort_max => 'Maksimum';

  @override
  String get reasoning_effort_off => 'Kapalı';

  @override
  String get could_not_read_file => 'Dosya okunamadı';

  @override
  String get server_offline => 'Sunucu Çevrimdışı';

  @override
  String get could_not_establish_connection =>
      'Sunucuya bağlantı kurulamadı. Lütfen sunucunuzun çalışıp çalışmadığını ve ana bilgisayar/port ayarlarının doğru olup olmadığını kontrol edin.';

  @override
  String get retry_connection => 'Bağlantıyı Yeniden Dene';

  @override
  String get tokens_label => 'Token\'lar';

  @override
  String get enter_context_length => 'Bağlam uzunluğunu girin...';

  @override
  String get openrouter_disclosure =>
      'Bu sağlayıcıya bağlanarak sohbet mesajlarınız ve girdileriniz onların sunucularına gönderilir. LocalMind sohbetlerinizi izlemez veya saklamaz.';

  @override
  String get welcome_message_cloud =>
      'Mesajlarınız bağlı olan sağlayıcınıza gönderilir.';

  @override
  String get privacy_policy => 'Gizlilik Politikası';

  @override
  String get cloud_sync => 'S3 Bulut Eşitleme';

  @override
  String get cloud_sync_description =>
      'Kendi S3 uyumlu sunucunuza uçtan uca şifreli eşitleme';

  @override
  String get cloud_sync_endpoint => 'Uç Nokta URL\'si (Endpoint)';

  @override
  String get cloud_sync_bucket => 'Kova (Bucket)';

  @override
  String get cloud_sync_region => 'Bölge (Region)';

  @override
  String get cloud_sync_prefix => 'Önek (Prefix)';

  @override
  String get cloud_sync_access_key => 'Erişim Anahtarı Kimliği';

  @override
  String get cloud_sync_secret_key => 'Gizli Erişim Anahtarı';

  @override
  String get cloud_sync_session_token => 'Oturum Jetonu (İsteğe Bağlı)';

  @override
  String get cloud_sync_passphrase => 'Şifreleme Parolası';

  @override
  String get cloud_sync_confirm_passphrase => 'Parolayı Onayla';

  @override
  String get cloud_sync_path_style => 'Yol stili adresleme kullan';

  @override
  String get cloud_sync_allow_http => 'Güvensiz HTTP\'ye izin ver';

  @override
  String get cloud_sync_http_warning =>
      'HTTP istek meta verilerini ve kimlik bilgilerini ağa açık hale getirir. Yalnızca güvenilir bir yerel S3 sunucusu için kullanın.';

  @override
  String get cloud_sync_test => 'Bağlantıyı test et';

  @override
  String get cloud_sync_enable => 'Şifreli eşitlemeyi etkinleştir';

  @override
  String get cloud_sync_now => 'Şimdi eşitle';

  @override
  String get cloud_sync_disconnect => 'Bu cihazın bağlantısını kes';

  @override
  String get cloud_sync_last_synced => 'Son eşitleme';

  @override
  String get cloud_sync_never => 'Hiçbir zaman';

  @override
  String get cloud_sync_conflicts => 'Çakışmalar korundu';

  @override
  String get cloud_sync_passphrase_mismatch => 'Parolalar eşleşmiyor';

  @override
  String get crash_report_title => 'Bir şeyler yanlış gitti';

  @override
  String get crash_report_stack_trace => 'Yığın izleme (Stack trace)';

  @override
  String get crash_report_tap_to_expand => 'Genişletmek için dokunun';

  @override
  String get crash_report_button => 'Bu çökmeyi bildir';

  @override
  String get crash_try_again => 'Tekrar dene';

  @override
  String get crash_report_empty_stack => '<boş>';

  @override
  String get crash_report_disclaimer =>
      'Bildirme işlemi, teşhis bilgileri önceden doldurulmuş olarak GitHub\'ı açar. Kontrol sizdedir — hiçbir şey otomatik olarak gönderilmez. Lütfen göndermeden önce hassas içerikleri gözden geçirin ve kaldırın.';

  @override
  String get crash_report_copied => 'Panoya kopyalandı';

  @override
  String get report_a_problem => 'Sorun bildir';

  @override
  String get rename_folder => 'Klasörü yeniden adlandır';

  @override
  String get delete_folder => 'Sil folder';

  @override
  String get delete_folder_title => 'Sil folder?';

  @override
  String delete_folder_body(String name) {
    return 'Silmek istediğinizden emin misiniz \"$name\"? Sohbetler or saved messages inside will be moved back to \"Unfiled\". Bu işlem geri alınamaz.';
  }

  @override
  String get folder_name_required => 'Lütfen bir klasör adı girin';

  @override
  String get model_required_toast => 'Önce bir model seçmeniz gerekiyor';

  @override
  String get settings_concise_voice_responses => 'Özet Sesli Mod Yanıtları';

  @override
  String get settings_concise_voice_responses_desc =>
      'Sesli modda LLM yanıtlarını kısa tutun (1 kısa paragraf) ve takip soruları sorun.';

  @override
  String get s3_connection_succeeded => 'S3 bağlantısı başarılı.';

  @override
  String failed_to_open_url(String error) {
    return 'URL açılamadı: $error';
  }

  @override
  String failed_to_copy(String error) {
    return 'Kopyalanamadı: $error';
  }

  @override
  String get file_explorer_not_found =>
      'No file explorer found. Please make sure a file manager app is installed and enabled on your device.';

  @override
  String export_data_failed(String error) {
    return 'Failed to export backup: $error';
  }

  @override
  String file_pick_failed(String error) {
    return 'Failed to select file: $error';
  }

  @override
  String image_pick_failed(String error) {
    return 'Failed to select image: $error';
  }
}
