// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get app_name => 'LocalMind';

  @override
  String get app_tagline => 'आपका AI. आपका डिवाइस. आपके नियम।';

  @override
  String get app_version => '1.0.0';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get confirm => 'पुष्टि करें';

  @override
  String get delete => 'हटाएं';

  @override
  String get save => 'सहेजें';

  @override
  String get retry => 'पुनः प्रयास करें';

  @override
  String get close => 'बंद करें';

  @override
  String get done => 'पूर्ण';

  @override
  String get continue_action => 'जारी रखें';

  @override
  String get skip => 'छोड़ें';

  @override
  String get install => 'इंस्टॉल करें';

  @override
  String get download => 'डाउनलोड करें';

  @override
  String get resume => 'फिर से शुरू करें';

  @override
  String get pause => 'विराम दें';

  @override
  String get stop => 'रोकें';

  @override
  String get edit => 'संपादित करें';

  @override
  String get preview => 'पूर्वावलोकन';

  @override
  String get unload => 'अनलोड करें';

  @override
  String get load => 'लोड करें';

  @override
  String get rename => 'नाम बदलें';

  @override
  String get pin => 'पिन करें';

  @override
  String get unpin => 'अनपिन करें';

  @override
  String get share => 'साझा करें';

  @override
  String get copy => 'कॉपी करें';

  @override
  String get copied => 'कॉपी किया गया!';

  @override
  String get copied_to_clipboard => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get select => 'चुनें';

  @override
  String get active => 'सक्रिय';

  @override
  String get all => 'सभी';

  @override
  String get none => 'कोई नहीं';

  @override
  String get none_selected => 'कोई चयनित नहीं है';

  @override
  String get online => 'ऑनलाइन';

  @override
  String get connected => 'कनेक्टेड';

  @override
  String get checking => 'जाँच की जा रही है';

  @override
  String get offline => 'ऑफ़लाइन';

  @override
  String get error => 'त्रुटि';

  @override
  String get unknown_error => 'अज्ञात त्रुटि';

  @override
  String get not_now => 'अभी नहीं';

  @override
  String get enable => 'सक्षम करें';

  @override
  String get proceed_anyway => 'वैसे भी आगे बढ़ें';

  @override
  String get test_connection => 'कनेक्शन का परीक्षण करें';

  @override
  String get testing => 'परीक्षण किया जा रहा है...';

  @override
  String get connection_successful => 'कनेक्शन सफल रहा!';

  @override
  String get connection_failed =>
      'कनेक्शन विफल रहा। अपनी सेटिंग्स की जांच करें।';

  @override
  String get save_continue => 'सहेजें और जारी रखें';

  @override
  String get save_changes => 'बदलाव सहेजें';

  @override
  String get finish_setup => 'सेटअप पूर्ण करें';

  @override
  String get start_new_chat => 'नई चैट शुरू करें';

  @override
  String get cannot_undo => 'इस क्रिया को पूर्ववत नहीं किया जा सकता।';

  @override
  String get ram_warning => 'रैम चेतावनी';

  @override
  String get recommended => 'अनुशंसित';

  @override
  String get may_be_large => 'इस डिवाइस के लिए बहुत बड़ा हो सकता है';

  @override
  String get calculating => 'गणना की जा रही है...';

  @override
  String get download_failed => 'डाउनलोड विफल';

  @override
  String get downloaded => 'डाउनलोड किया गया';

  @override
  String get not_downloaded => 'डाउनलोड नहीं किया गया';

  @override
  String get installed => 'इंस्टॉल किया गया';

  @override
  String get not_installed => 'इंस्टॉल नहीं किया गया';

  @override
  String get loading => 'लोड हो रहा है...';

  @override
  String get thinking => 'सोच रहा है';

  @override
  String get processing => 'प्रसंस्करण किया जा रहा है...';

  @override
  String get initializing => 'प्रारंभ किया जा रहा है...';

  @override
  String get ready => 'तैयार';

  @override
  String get preparing_app => 'ऐप तैयार किया जा रहा है...';

  @override
  String get initializing_services => 'सेवाएं प्रारंभ की जा रही हैं...';

  @override
  String get configuring_server => 'सर्वर कॉन्फ़िगर किया जा रहा है...';

  @override
  String get startup_failed => 'स्टार्टअप विफल रहा';

  @override
  String get something_went_wrong => 'कुछ गलत हो गया';

  @override
  String get delete_model_title => 'मॉडल हटाएं';

  @override
  String delete_model_body(String name) {
    return 'क्या आप निश्चित रूप से $name को हटाना चाहते हैं?';
  }

  @override
  String delete_model_body_with_size(String name, String size) {
    return 'क्या आप निश्चित रूप से $name को हटाना चाहते हैं? इससे लगभग $size स्थान खाली हो जाएगा।\n\nयदि आवश्यकता हो तो आप बाद में इस मॉडल को फिर से डाउनलोड कर सकते हैं।';
  }

  @override
  String get delete_voice_title => 'आवाज हटाएं';

  @override
  String delete_voice_body(String name, String size) {
    return 'क्या आप निश्चित रूप से $name को हटाना चाहते हैं? इससे लगभग $size स्थान खाली हो जाएगा।\n\nयदि आवश्यकता हो तो आप बाद में इस आवाज को फिर से डाउनलोड कर सकते हैं।';
  }

  @override
  String get delete_server_title => 'सर्वर हटाएं';

  @override
  String delete_server_body(String name) {
    return 'क्या आप निश्चित रूप से \"$name\" को हटाना चाहते हैं? इसे पूर्ववत नहीं किया जा सकता।';
  }

  @override
  String get delete_conversation_title => 'बातचीत हटाएं?';

  @override
  String delete_conversation_body(String title) {
    return 'क्या आप निश्चित रूप से \"$title\" को हटाना चाहते हैं? इसे पूर्ववत नहीं किया जा सकता।';
  }

  @override
  String get delete_message_title => 'संदेश हटाएं?';

  @override
  String delete_persona_title(String name) {
    return '\"$name\" हटाएं?';
  }

  @override
  String get delete_persona_body => 'इसे पूर्ववत नहीं किया जा सकता।';

  @override
  String get delete_builtin_persona_body =>
      'यह एक अंतर्निहित व्यक्तित्व (Persona) है। आप इसे बाद में सेटिंग्स से पुनर्स्थापित कर सकते हैं।';

  @override
  String get restore_builtin_personas =>
      'डिफ़ॉल्ट व्यक्तित्व पुनर्स्थापित करें';

  @override
  String get restore_builtin_personas_desc =>
      'आपके द्वारा हटाए गए किसी भी अंतर्निहित व्यक्तित्व को फिर से जोड़ें';

  @override
  String get restore_builtin_personas_success =>
      'डिफ़ॉल्ट व्यक्तित्व पुनर्स्थापित कर दिए गए हैं';

  @override
  String get clear_personas => 'व्यक्तित्व साफ़ करें';

  @override
  String get enable_image_compression => 'भेजने से पहले छवियों को कंप्रेस करें';

  @override
  String get enable_image_compression_desc =>
      'संलग्न छवियों का आकार बदलें और कंप्रेस करें ताकि अपलोड सर्वर सीमाओं के भीतर रहें';

  @override
  String get image_compression_level => 'कंप्रेशन की आक्रामकता';

  @override
  String get image_compression_level_desc =>
      'अधिक आक्रामकता कम गुणवत्ता पर छोटे आकार के अपलोड बनाती है';

  @override
  String get image_compression_level_low => 'कम';

  @override
  String get image_compression_level_medium => 'मध्यम';

  @override
  String get image_compression_level_high => 'उच्च';

  @override
  String get sort_models_tooltip => 'मॉडलों को सॉर्ट करें';

  @override
  String get sort_by_favorites => 'पसंदीदा पहले';

  @override
  String get sort_by_name => 'नाम (A-Z)';

  @override
  String get sort_by_size_smallest => 'आकार (सबसे छोटा पहले)';

  @override
  String get sort_by_size_largest => 'आकार (सबसे बड़ा पहले)';

  @override
  String get sort_by_context_length => 'संदर्भ की लंबाई';

  @override
  String bulk_ai_rename_progress(int done, int total) {
    return 'नाम बदला जा रहा है $done/$total...';
  }

  @override
  String selected_count(int count) {
    return '$count चयनित';
  }

  @override
  String get ai_rename_tooltip => 'एआई के साथ चयनित का नाम बदलें';

  @override
  String get new_chat_in_folder_tooltip => 'इस फ़ोल्डर में नई चैट';

  @override
  String total_tokens_count(int count) {
    return '$count टोकन';
  }

  @override
  String get smart_replies_use_persona =>
      'स्मार्ट उत्तरों में व्यक्तित्व का उपयोग करें';

  @override
  String get smart_replies_use_persona_desc =>
      'सुझाए गए उत्तर सामान्य सहायक के बजाय सक्रिय व्यक्तित्व के लहजे से मेल खाते हैं';

  @override
  String get keep_persona_on_new_chat => 'नई चैट पर व्यक्तित्व बनाए रखें';

  @override
  String get keep_persona_on_new_chat_desc =>
      'नई चैट शुरू करने के बाद चयनित व्यक्तित्व को साफ़ न करें';

  @override
  String get role_swap_button_enabled => 'भूमिका-बदल बटन दिखाएं';

  @override
  String get role_swap_button_enabled_desc =>
      'बिना कोई प्रतिक्रिया उत्पन्न किए, अपने संदेश को उपयोगकर्ता के बजाय सहायक भूमिका के रूप में भेजने के लिए चैट इनपुट में एक बटन दिखाएं';

  @override
  String get send_as_user_tooltip => 'उपयोगकर्ता के रूप में भेजें';

  @override
  String get send_as_assistant_tooltip =>
      'सहायक के रूप में भेजें (कोई प्रतिक्रिया नहीं)';

  @override
  String get insert_without_generating_tooltip => 'बिना जनरेट किए डालें';

  @override
  String get token_usage_title => 'टोकन उपयोग';

  @override
  String get total_tokens_label => 'उपयोग किए गए टोकन';

  @override
  String get usage_percent_label => 'उपयोग किया गया संदर्भ';

  @override
  String get export_choice_title => 'निर्यात (Export) करें';

  @override
  String get export_choice_body => 'आप इसे कैसे निर्यात करना चाहेंगे?';

  @override
  String get copy_to_clipboard => 'क्लिपबोर्ड पर कॉपी करें';

  @override
  String bulk_export_conversations_success(int count) {
    return '$count वार्तालाप निर्यात किए गए';
  }

  @override
  String get bulk_ai_rename_confirm_title => 'एआई के साथ नाम बदलें?';

  @override
  String bulk_ai_rename_confirm_body(int count) {
    return 'यह एआई को वर्तमान शीर्षकों को प्रतिस्थापित करते हुए, प्रत्येक $count चयनित वार्तालापों के लिए एक नया शीर्षक उत्पन्न करने के लिए कहेगा। इसमें कुछ समय लग सकता है और इसे पूर्ववत नहीं किया जा सकता है।';
  }

  @override
  String get sort_by_modified_date => 'पिछला संशोधन';

  @override
  String get sort_by_created_date => 'निर्माण तिथि';

  @override
  String get sort_title => 'सॉर्ट करें';

  @override
  String get clear_conversation_title => 'बातचीत साफ़ करें?';

  @override
  String get clear_conversation_body =>
      'यह इस बातचीत के सभी संदेशों को हटा देगा।';

  @override
  String get clear => 'साफ़ करें';

  @override
  String label_completed(String label) {
    return '$label पूर्ण';
  }

  @override
  String error_with_message(String error) {
    return 'त्रुटि: $error';
  }

  @override
  String preview_failed(String error) {
    return 'पूर्वावलोकन विफल: $error';
  }

  @override
  String loading_model(String modelId) {
    return '$modelId लोड किया जा रहा है...';
  }

  @override
  String model_loaded(String modelId, String backend) {
    return 'मॉडल लोड किया गया: $modelId ($backend)';
  }

  @override
  String get no_model_loaded =>
      'कोई मॉडल लोड नहीं है। मॉडल डाउनलोड और लोड करने के लिए \"ऑन-डिवाइस मॉडल प्रबंधित करें\" पर टैप करें।';

  @override
  String loading_model_error(String error) {
    return 'त्रुटि: $error';
  }

  @override
  String get delete_conversation => 'बातचीत हटाएं?';

  @override
  String get nav_history => 'इतिहास';

  @override
  String get nav_servers => 'सर्वर';

  @override
  String get nav_local_models => 'स्थानीय मॉडल';

  @override
  String get nav_tts => 'टेक्स्ट टू स्पीच';

  @override
  String get nav_personas => 'चरित्र (Personas)';

  @override
  String get nav_settings => 'सेटिंग्स';

  @override
  String get nav_new_chat => 'नई चैट';

  @override
  String get search_hint => 'बातचीत खोजें...';

  @override
  String get no_server_selected => 'कोई सर्वर चयनित नहीं है';

  @override
  String get switch_server => 'सर्वर बदलें';

  @override
  String get switch_server_subtitle => 'कनेक्ट करने के लिए एक सर्वर चुनें';

  @override
  String get manage_servers => 'सर्वर प्रबंधित करें';

  @override
  String get open_source => 'ओपन सोर्स';

  @override
  String get open_source_desc =>
      'LocalMind ओपन सोर्स है। गिटहब (GitHub) पर हमारी प्रगति का अनुसरण करें या योगदान दें।';

  @override
  String get star_on_github => 'GitHub पर स्टार दें';

  @override
  String get add_more => 'और जोड़ें';

  @override
  String get on_github => 'GitHub पर';

  @override
  String get could_not_open_github => 'GitHub नहीं खोल सका।';

  @override
  String get settings_title => 'सेटिंग्स';

  @override
  String get settings_appearance => 'दिखावट';

  @override
  String get settings_language => 'भाषा';

  @override
  String get language_system_default => 'सिस्टम डिफ़ॉल्ट';

  @override
  String get settings_tts => 'टेक्स्ट-टू-स्पीच';

  @override
  String get settings_behavior => 'व्यवहार';

  @override
  String get settings_on_device => 'ऑन-डिवाइस अनुमान (On-Device Inference)';

  @override
  String get settings_default_server => 'डिफ़ॉल्ट सर्वर';

  @override
  String get settings_default_persona => 'डिफ़ॉल्ट चरित्र';

  @override
  String get settings_default_model => 'Default Model';

  @override
  String get settings_default_model_desc =>
      'Automatically selected when you start a new chat.';

  @override
  String get settings_privacy => 'गोपनीयता';

  @override
  String get settings_data_management => 'डेटा प्रबंधन';

  @override
  String get settings_about => 'परिचय';

  @override
  String get theme => 'थीम';

  @override
  String get theme_system => 'सिस्टम';

  @override
  String get theme_light => 'लाइट';

  @override
  String get theme_dark => 'डार्क';

  @override
  String get theme_claude => 'Claude';

  @override
  String get font_size => 'फ़ॉन्ट का आकार';

  @override
  String get font_size_desc => 'चैट में टेक्स्ट का आकार समायोजित करें।';

  @override
  String get font_preview =>
      'त्वरित भूरी लोमड़ी आलसी कुत्ते के ऊपर से कूदती है।';

  @override
  String get code_theme_dark => 'कोड थीम (डार्क)';

  @override
  String get code_theme_light => 'कोड थीम (लाइट)';

  @override
  String get code_theme_desc =>
      'कोड ब्लॉक के लिए सिंटैक्स हाइलाइटिंग थीम चुनें।';

  @override
  String get tts_engine => 'TTS इंजन';

  @override
  String get tts_engine_system => 'सिस्टम TTS';

  @override
  String get tts_engine_kitten => 'Kitten TTS';

  @override
  String get voice => 'आवाज';

  @override
  String get voice_female => 'महिला';

  @override
  String get voice_male => 'पुरुष';

  @override
  String get voice_other => 'अन्य';

  @override
  String get tts_speed => 'TTS गति';

  @override
  String get tts_speed_desc => 'प्लेबैक की गति समायोजित करें।';

  @override
  String get manage_tts_models => 'TTS मॉडल प्रबंधित करें';

  @override
  String get manage_on_device_models => 'ऑन-डिवाइस मॉडल प्रबंधित करें';

  @override
  String get enable_smart_reply => 'ऑन-डिवाइस स्मार्ट रिप्लाइ';

  @override
  String get ai_user_response_enabled =>
      'एआई उपयोगकर्ता संदेश (भेजें बटन दबाकर रखें)';

  @override
  String get ai_user_response_enabled_desc =>
      'एआई से अपना अगला संदेश लिखवाने और भेजने के लिए भेजें बटन को 3 सेकंड के लिए दबाकर रखें';

  @override
  String get ai_user_response_tooltip =>
      'एआई के साथ उपयोगकर्ता संदेश जनरेट करें';

  @override
  String get streaming_responses => 'प्रतिक्रियाएं स्ट्रीम करें';

  @override
  String get auto_generate_titles => 'स्वचालित रूप से शीर्षक उत्पन्न करें';

  @override
  String get send_on_enter => 'एंटर (Enter) दबाने पर भेजें';

  @override
  String get show_system_messages => 'सिस्टम संदेश दिखाएं';

  @override
  String get show_system_messages_desc =>
      'जब कोई व्यक्तित्व चयनित न हो, तो प्रत्येक अनुरोध के साथ एक डिफ़ॉल्ट सहायक सिस्टम प्रॉम्प्ट भेजें';

  @override
  String get show_system_messages_in_chat => 'चैट में सिस्टम संदेश दिखाएं';

  @override
  String get show_system_messages_in_chat_desc =>
      'चैट ट्रांसक्रिप्ट में दृश्यमान बुलबुले के रूप में सिस्टम संदेश (जैसे आयातित बैकअप से) प्रदर्शित करें';

  @override
  String get haptic_feedback => 'हैप्टिक फीडबैक';

  @override
  String get enable_mcp => 'MCP सक्षम करें';

  @override
  String get new_chat_mcp_default => 'नई चैट MCP डिफ़ॉल्ट';

  @override
  String get show_data_indicator => 'डेटा सूचक दिखाएं';

  @override
  String get privacy_info => '\"LocalMind आपके डेटा को कभी नहीं देखता है\"';

  @override
  String get delete_all_conversations => 'सभी बातचीत हटाएं';

  @override
  String get reset_settings_defaults => 'सेटिंग्स को डिफ़ॉल्ट पर रीसेट करें';

  @override
  String get chat_title => 'LocalMind';

  @override
  String get chat_parameters_tooltip => 'चैट पैरामीटर';

  @override
  String get change_persona => 'चरित्र बदलें';

  @override
  String get set_persona => 'चरित्र सेट करें';

  @override
  String get remove_persona => 'चरित्र हटाएं';

  @override
  String get clear_conversation => 'बातचीत साफ़ करें';

  @override
  String get connection_error => 'कनेक्शन त्रुटि। अपने सर्वर की जांच करें।';

  @override
  String get disconnected => 'सर्वर से कनेक्शन टूट गया।';

  @override
  String get configure => 'कॉन्फ़िगर करें';

  @override
  String get select_model => 'मॉडल चुनें';

  @override
  String get select_persona => 'चरित्र चुनें';

  @override
  String get manage_personas => 'व्यक्तित्व प्रबंधित करें';

  @override
  String get personas_combine_hint => 'चयनित व्यक्तित्वों को मिला दिया जाएगा';

  @override
  String get start_conversation => 'बातचीत शुरू करें';

  @override
  String get recent_chats => 'हालिया चैट';

  @override
  String get see_all => 'सभी देखें';

  @override
  String get quick_write => 'मुझे एक फ़ंक्शन लिखने में मदद करें';

  @override
  String get quick_explain => 'इस कोड को समझाएं';

  @override
  String get quick_debug => 'इसे मेरे लिए डीबग करें';

  @override
  String get quick_async => 'मैं async/await का उपयोग कैसे करूं?';

  @override
  String get history_missing_title => 'इतिहास गायब है';

  @override
  String get history_missing_desc =>
      'या तो इस चैट के संदेश हटा दिए गए थे या इतिहास रिकॉर्ड दूषित हो गया है।';

  @override
  String get technical_details => 'तकनीकी विवरण';

  @override
  String get last_error => 'अंतिम त्रुटि:';

  @override
  String get copy_info => 'जानकारी कॉपी करें';

  @override
  String get conversation_id => 'बातचीत आईडी';

  @override
  String get created_at => 'निर्माण का समय';

  @override
  String get expected_messages => 'अपेक्षित संदेश';

  @override
  String get debug_dialog_desc =>
      'सिंक्रनाइज़ेशन समस्याओं की पहचान करने में सहायता के लिए नैदानिक जानकारी।';

  @override
  String get chat_input_hint => 'कुछ भी पूछें';

  @override
  String get send_message_tooltip => 'संदेश भेजें';

  @override
  String get stop_generation_tooltip => 'उत्पादन रोकें';

  @override
  String get attach_images_tooltip => 'छवियाँ संलग्न करें';

  @override
  String get start_listening_tooltip => 'सुनना शुरू करें';

  @override
  String get stop_listening_tooltip => 'सुनना बंद करें';

  @override
  String tool_label(String toolCallId) {
    return 'उपकरण: $toolCallId';
  }

  @override
  String get tool_unknown => 'उपकरण: अज्ञात';

  @override
  String get message_options => 'संदेश विकल्प';

  @override
  String get copy_markdown => 'Markdown के रूप में कॉपी करें';

  @override
  String get copied_markdown => 'Markdown के रूप में कॉपी किया गया';

  @override
  String get read_aloud => 'ज़ोर से पढ़ें';

  @override
  String get stop_reading => 'पढ़ना बंद करें';

  @override
  String get more => 'अधिक';

  @override
  String character_count(int length) {
    return '$length वर्ण';
  }

  @override
  String get edit_message => 'संदेश संपादित करें';

  @override
  String get edit_message_desc =>
      'सहेजने से नीचे सहायक की प्रतिक्रिया हट जाएगी और पुनः उत्पन्न होगी।';

  @override
  String get save_regenerate => 'सहेजें और पुनः उत्पन्न करें';

  @override
  String get chat_settings_title => 'चैट सेटिंग्स';

  @override
  String get reset_defaults => 'डिफ़ॉल्ट पर रीसेट करें';

  @override
  String get parameters_tab => 'पैरामीटर';

  @override
  String get mcp_tab => 'MCP';

  @override
  String get temperature => 'तापमान';

  @override
  String get temperature_desc =>
      'यादृच्छिकता को नियंत्रित करता है: उच्च = रचनात्मक, निम्न = केंद्रित';

  @override
  String get top_p => 'Top P';

  @override
  String get top_p_desc => 'न्यूक्लियस सैंपलिंग थ्रेशोल्ड';

  @override
  String get max_tokens => 'अधिकतम टोकन';

  @override
  String get max_tokens_desc => 'प्रतिक्रिया सीमा';

  @override
  String get context_length => 'संदर्भ लंबाई (Context Length)';

  @override
  String get context_length_desc => 'इतिहास विंडो';

  @override
  String get mcp_disabled_warning =>
      'MCP वैश्विक रूप से अक्षम है। इन सुविधाओं का उपयोग करने के लिए सेटिंग्स में इसे सक्षम करें।';

  @override
  String get mcp_enable_chat => 'इस चैट के लिए MCP सक्षम करें';

  @override
  String get auto_execute_tools => 'स्वचालित रूप से उपकरण निष्पादित करें';

  @override
  String get beta_label => 'बीटा';

  @override
  String get experimental_label => 'प्रायोगिक';

  @override
  String get add_ephemeral_mcp => 'अस्थायी MCP सर्वर जोड़ें';

  @override
  String get mcp_label_placeholder => 'लेबल';

  @override
  String get mcp_url_placeholder => 'URL (https://...)';

  @override
  String get active_integrations => 'सक्रिय एकीकरण';

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
  String get enable_notifications => 'सूचनाएं सक्षम करें';

  @override
  String get enable_notifications_desc =>
      'मॉडल डाउनलोड पूरा होने पर सूचित किया जाए।';

  @override
  String get chat_history_title => 'चैट इतिहास';

  @override
  String get conversation_just_now => 'अभी-अभी';

  @override
  String conversation_minutes_ago(int minutes) {
    return '$minutes मिनट पहले';
  }

  @override
  String conversation_hours_ago(int hours) {
    return '$hours घंटे पहले';
  }

  @override
  String get conversation_yesterday => 'कल';

  @override
  String conversation_days_ago(int days) {
    return '$days दिन पहले';
  }

  @override
  String conversation_date(int month, int day, int year) {
    return '$month/$day/$year';
  }

  @override
  String get options_tooltip => 'विकल्प';

  @override
  String get no_results_found => 'कोई परिणाम नहीं मिला';

  @override
  String get no_conversations_yet => 'अभी तक कोई बातचीत नहीं';

  @override
  String get try_different_search => 'कोई अन्य खोज शब्द आज़माएं';

  @override
  String get start_new_conversation => 'नई बातचीत शुरू करें';

  @override
  String get rename_conversation => 'बातचीत का नाम बदलें';

  @override
  String get enter_new_title => 'नया शीर्षक दर्ज करें';

  @override
  String get pinned_section => 'पिन किया गया';

  @override
  String get today_section => 'आज';

  @override
  String get yesterday_section => 'कल';

  @override
  String get previous_7_days => 'पिछले 7 दिन';

  @override
  String get previous_30_days => 'पिछले 30 दिन';

  @override
  String get older_section => 'पुराने';

  @override
  String get onboarding_choose_language => 'भाषा चुनें';

  @override
  String get onboarding_choose_language_desc =>
      'अपनी पसंदीदा भाषा चुनें। आप इसे सेटिंग्स में कभी भी बदल सकते हैं।';

  @override
  String get onboarding_localmind => 'LOCALMIND';

  @override
  String get onboarding_connect_server => 'अपना सर्वर\nकनेक्ट करें';

  @override
  String get onboarding_connect_desc =>
      'अपना निजी AI अनुभव शुरू करने के लिए\nLM Studio, Ollama, या OpenRouter से\nकनेक्ट करें।';

  @override
  String get openai_compatible_api => 'OpenAI-संगत API';

  @override
  String get https_requires_ssl => 'HTTPS के लिए SSL आवश्यक है';

  @override
  String get most_local_setups_use_http =>
      'ज़्यादातर स्थानीय सेटअप में http:// इस्तेमाल होता है';

  @override
  String get onboarding_welcome => 'LocalMind में आपका स्वागत है';

  @override
  String get server_type_on_device => 'ऑन-डिवाइस';

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
  String get server_type_openrouter_sub => 'एकीकृत क्लाउड';

  @override
  String get ready_continue => 'जारी रखने के लिए तैयार';

  @override
  String get waiting_selection => 'चयन की प्रतीक्षा की जा रही है';

  @override
  String get setup_connection => 'कनेक्शन सेटअप करें';

  @override
  String setup_connection_desc(String server) {
    return 'चैटिंग शुरू करने के लिए अपने $server सर्वर को कॉन्फ़िगर करें।';
  }

  @override
  String get server_name => 'सर्वर का नाम';

  @override
  String get name_required => 'नाम आवश्यक है';

  @override
  String get name_max_50 => 'अधिकतम 50 वर्ण';

  @override
  String get host_label => 'होस्ट / IP पता';

  @override
  String get host_required => 'होस्ट आवश्यक है';

  @override
  String get port_label => 'पोर्ट';

  @override
  String get port_required => 'पोर्ट आवश्यक है';

  @override
  String get port_invalid => 'एक संख्या होनी चाहिए';

  @override
  String get port_range => 'एक वैध पोर्ट दर्ज करें (1-65535)';

  @override
  String get api_key_required => 'API कुंजी *';

  @override
  String get api_key_optional => 'API कुंजी (वैकल्पिक)';

  @override
  String get api_key_required_openrouter =>
      'OpenRouter के लिए API कुंजी आवश्यक है';

  @override
  String get api_key_format => 'OpenRouter API कुंजियाँ sk- से शुरू होती हैं';

  @override
  String get my_server_hint => 'मेरा सर्वर';

  @override
  String get name_length_validation => 'नाम 50 वर्ण या उससे कम होना चाहिए';

  @override
  String get host_valid => 'एक वैध होस्टनाम या IP पता दर्ज करें';

  @override
  String get api_key_hint_openrouter => 'sk-...';

  @override
  String get api_key_hint_generic => 'प्रमाणित सर्वर के लिए';

  @override
  String get update_server => 'सर्वर अपडेट करें';

  @override
  String get save_server => 'सर्वर सहेजें';

  @override
  String get server_updated => 'सर्वर अपडेट किया गया';

  @override
  String get server_added => 'सर्वर जोड़ा गया';

  @override
  String get download_model_title => 'मॉडल डाउनलोड करें';

  @override
  String get download_model_desc =>
      'डाउनलोड करने के लिए एक मॉडल चुनें।\nयह आपके डिवाइस पर स्थानीय रूप से चलेगा।';

  @override
  String get on_device_android_only =>
      'ऑन-डिवाइस अनुमान वर्तमान में केवल Android पर उपलब्ध है।';

  @override
  String get total_ram => 'कुल रैम';

  @override
  String get available => 'उपलब्ध';

  @override
  String ram_min_required(String fileSize) {
    return 'न्यूनतम $fileSize GB रैम (RAM) आवश्यक';
  }

  @override
  String download_progress(String percent, String speed) {
    return '$percent% • $speed';
  }

  @override
  String eta_label(String eta) {
    return 'शेष समय (ETA): $eta';
  }

  @override
  String paused_progress(String percent) {
    return 'रोका गया - $percent%';
  }

  @override
  String ram_warning_body_download(String ram, String totalMemory) {
    return 'इस मॉडल के लिए कम से कम $ram GB रैम की आवश्यकता है, लेकिन आपके डिवाइस में $totalMemory है। यह सही ढंग से काम नहीं कर सकता है या ऐप क्रैश हो सकता है।';
  }

  @override
  String ram_warning_body_load(String availableRAM, String ram) {
    return 'आपके डिवाइस में $availableRAM उपलब्ध रैम है, लेकिन यह मॉडल कम से कम $ram GB की सिफारिश करता है। इसे लोड करना विफल हो सकता है या अस्थिरता पैदा कर सकता है।';
  }

  @override
  String get choose_theme => 'थीम चुनें';

  @override
  String get choose_theme_desc =>
      'ऐप के रूप को निजीकृत करें। आप इसे बाद में सेटिंग्स में कभी भी बदल सकते हैं।';

  @override
  String get theme_card_system => 'सिस्टम';

  @override
  String get theme_card_system_sub => 'आपके डिवाइस की सेटिंग्स से मेल खाता है';

  @override
  String get theme_card_light => 'लाइट';

  @override
  String get theme_card_light_sub => 'साफ़ और उज्ज्वल';

  @override
  String get theme_card_dark => 'डार्क';

  @override
  String get theme_card_dark_sub => 'आँखों के लिए आरामदायक';

  @override
  String get theme_card_claude => 'Claude';

  @override
  String get theme_card_claude_sub => 'एक हल्का नारंगी-पीला (peach) थीम';

  @override
  String get stay_updated => 'अपडेट रहें';

  @override
  String get stay_updated_desc =>
      'जब आपके AI मॉडल डाउनलोड हो जाएं या लंबे समय तक चलने वाले कार्य पूरे हो जाएं तो सूचित किया जाए।';

  @override
  String get notification_benefit_downloads => 'मॉडल डाउनलोड प्रगति';

  @override
  String get notification_benefit_completions => 'उत्पादन पूर्णता';

  @override
  String get notification_benefit_background => 'पृष्ठभूमि कार्यों की स्थिति';

  @override
  String get allow_notifications => 'सूचनाओं की अनुमति दें';

  @override
  String get servers_title => 'सर्वर';

  @override
  String get no_servers_yet => 'अभी तक कोई सर्वर नहीं है';

  @override
  String get no_servers_desc =>
      'AI मॉडल के साथ चैट करना शुरू करने के लिए अपना पहला सर्वर जोड़ें।';

  @override
  String get add_server => 'सर्वर जोड़ें';

  @override
  String switched_to_server(String name) {
    return '$name पर स्विच किया गया';
  }

  @override
  String get edit_server => 'सर्वर संपादित करें';

  @override
  String get add_server_title => 'सर्वर जोड़ें';

  @override
  String get server_type_label => 'सर्वर का प्रकार';

  @override
  String get server_icon_label => 'सर्वर आइकन';

  @override
  String get default_icon => 'डिफ़ॉल्ट आइकन';

  @override
  String get server_type_lm_studio_display => 'LM Studio';

  @override
  String get server_type_openai_display => 'OpenAI संगत';

  @override
  String get server_type_ollama_display => 'Ollama';

  @override
  String get server_type_openrouter_display => 'OpenRouter';

  @override
  String get server_type_on_device_display => 'ऑन-डिवाइस';

  @override
  String get server_address_openrouter => 'openrouter.ai';

  @override
  String get server_address_on_device => 'स्थानीय अनुमान (Local Inference)';

  @override
  String server_address_format(String host, String port) {
    return '$host:$port';
  }

  @override
  String get default_badge => 'डिफ़ॉल्ट';

  @override
  String get set_as_default => 'डिफ़ॉल्ट रूप में सेट करें';

  @override
  String get select_icon => 'आइकन चुनें';

  @override
  String get select_icon_desc => 'अपने सर्वर के लिए एक आइकन चुनें';

  @override
  String get search_icons_hint => 'आइकन खोजें...';

  @override
  String get server_icon_stack => 'सर्वर स्टैक';

  @override
  String get server_icon_stack2 => 'सर्वर स्टैक 02';

  @override
  String get server_icon_stack3 => 'सर्वर स्टैक 03';

  @override
  String get server_icon_cloud => 'क्लाउड';

  @override
  String get server_icon_cloud_server => 'क्लाउड सर्वर';

  @override
  String get server_icon_mcp => 'MCP सर्वर';

  @override
  String get server_icon_database => 'डेटाबेस';

  @override
  String get server_icon_database1 => 'डेटाबेस 01';

  @override
  String get server_icon_database2 => 'डेटाबेस 02';

  @override
  String get server_icon_cpu => 'CPU';

  @override
  String get server_icon_chip => 'चिप';

  @override
  String get server_icon_chip2 => 'चिप 02';

  @override
  String get server_icon_computer => 'कंप्यूटर';

  @override
  String get server_icon_laptop => 'लैपटॉप';

  @override
  String get server_icon_terminal => 'कंप्यूटर टर्मिनल';

  @override
  String get server_icon_code => 'कोड';

  @override
  String get server_icon_ai_brain => 'AI ब्रेन';

  @override
  String get server_icon_ai_brain2 => 'AI ब्रेन 02';

  @override
  String get server_icon_ai_cloud => 'AI क्लाउड';

  @override
  String get server_icon_ai_network => 'AI नेटवर्क';

  @override
  String get server_icon_ai_chat => 'AI चैट';

  @override
  String get server_icon_cellular => 'सेलुलर नेटवर्क';

  @override
  String get server_icon_plug1 => 'प्लग 01';

  @override
  String get server_icon_plug2 => 'प्लग 02';

  @override
  String get server_icon_bot => 'बॉट';

  @override
  String get server_icon_bot2 => 'बॉट 02';

  @override
  String get server_icon_robotic => 'रोबोटिक';

  @override
  String get server_icon_rocket => 'रॉकेट';

  @override
  String get server_icon_star => 'स्टार';

  @override
  String get server_icon_settings1 => 'सेटिंग्स 01';

  @override
  String get server_icon_settings2 => 'सेटिंग्स 02';

  @override
  String get server_icon_home1 => 'होम 01';

  @override
  String get server_icon_home2 => 'होम 02';

  @override
  String get server_icon_folder1 => 'फ़ोल्डर 01';

  @override
  String get server_icon_folder2 => 'फ़ोल्डर 02';

  @override
  String get server_icon_file1 => 'फ़ाइल 01';

  @override
  String get server_icon_lock => 'लॉक';

  @override
  String get server_icon_key => 'कुंजी 01';

  @override
  String get server_icon_link => 'लिंक 01';

  @override
  String get server_icon_globe => 'ग्लोब';

  @override
  String get server_icon_api => 'API';

  @override
  String get server_icon_arrow_right => 'दायाँ तीर 01';

  @override
  String get server_icon_check => 'सत्यापन वृत्त';

  @override
  String get server_icon_alert => 'चेतावनी वृत्त';

  @override
  String get server_icon_info => 'सूचना वृत्त';

  @override
  String get server_icon_zap => 'जैप';

  @override
  String get server_icon_cloud_upload => 'क्लाउड अपलोड';

  @override
  String get server_icon_cloud_download => 'क्लाउड डाउनलोड';

  @override
  String get server_icon_refresh => 'रीफ्रेश करें';

  @override
  String get server_icon_hard_drive => 'हार्ड ड्राइव';

  @override
  String get server_icon_drive => 'ड्राइव';

  @override
  String get personas_title => 'चरित्र (Personas)';

  @override
  String get persona_category_general => 'सामान्य';

  @override
  String get persona_category_coding => 'कोडिंग';

  @override
  String get persona_category_education => 'शिक्षा';

  @override
  String get persona_category_creative => 'रचनात्मक';

  @override
  String get persona_builtin_section => 'इन-बिल्ट';

  @override
  String get persona_my_section => 'मेरे चरित्र (Personas)';

  @override
  String get clone_edit => 'क्लोन और संपादित करें';

  @override
  String get builtin_badge => 'इन-बिल्ट';

  @override
  String get no_personas_found => 'कोई चरित्र नहीं मिला';

  @override
  String get no_personas_desc =>
      'AI के व्यवहार को अनुकूलित करने के लिए अपना पहला चरित्र बनाएं।';

  @override
  String get edit_persona => 'चरित्र संपादित करें';

  @override
  String get create_persona => 'चरित्र बनाएं';

  @override
  String get create_persona_button => 'बनाएं';

  @override
  String get emoji_label => 'इमोजी';

  @override
  String get name_label => 'नाम';

  @override
  String get my_persona_hint => 'मेरा चरित्र';

  @override
  String get category_label => 'श्रेणी';

  @override
  String get description_optional => 'विवरण (वैकल्पिक)';

  @override
  String get description_hint => 'यह चरित्र क्या करता है...';

  @override
  String get system_prompt => 'सिस्टम प्रॉम्ट';

  @override
  String character_count_max(int currentLen) {
    return '$currentLen/4000';
  }

  @override
  String get no_prompt_placeholder => 'अभी तक कोई प्रॉम्ट नहीं...';

  @override
  String get prompt_hint => 'आप एक सहायक हैं...';

  @override
  String get prompt_required => 'सिस्टम प्रॉम्ट आवश्यक है';

  @override
  String get prompt_max_chars => 'अधिकतम 4000 वर्ण';

  @override
  String get advanced_settings => 'उन्नत सेटिंग्स';

  @override
  String get temperature_label => 'तापमान (0.0-2.0)';

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
  String get persona_updated => 'चरित्र अद्यतित (updated)';

  @override
  String get persona_created => 'चरित्र निर्मित';

  @override
  String get tts_models_title => 'टेक्स्ट टू स्पीच मॉडल';

  @override
  String get always_available => 'हमेशा उपलब्ध';

  @override
  String get tts_system_desc =>
      'आपके डिवाइस के इन-बिल्ट टेक्स्ट-टू-स्पीच इंजन का उपयोग करता है।\nकिसी डाउनलोड की आवश्यकता नहीं है। आवाज चयन आपके डिवाइस की सिस्टम सेटिंग्स का उपयोग करता है।';

  @override
  String get downloading_status => 'डाउनलोड किया जा रहा है...';

  @override
  String tts_kitten_desc(String size) {
    return '8 अभिव्यंजक आवाज़ों के साथ बिजली की तरह तेज़ न्यूरल TTS।\n$size डाउनलोड की आवश्यकता है।';
  }

  @override
  String tts_piper_desc(String size) {
    return '2 अभिव्यंजक आवाज़ों के साथ तेज़ ऑफ़लाइन पाइपर (Piper) आवाज़ें।\nप्रति आवाज़ $size डाउनलोड की आवश्यकता है।';
  }

  @override
  String engine_spec(String sizeMb, String ramMb, int voiceCount) {
    return '$sizeMb MB · $ramMb MB रैम · $voiceCount आवाजें';
  }

  @override
  String get on_device_models_title => 'ऑन-डिवाइस मॉडल';

  @override
  String get settings_huggingface_token => 'Hugging Face टोकन (वैकल्पिक)';

  @override
  String get settings_huggingface_token_desc =>
      'केवल gated मॉडलों के लिए आवश्यक (जैसे Gemma)। huggingface.co/settings/tokens पर टोकन प्राप्त करें।';

  @override
  String get settings_huggingface_token_set => 'टोकन सहेजा गया';

  @override
  String get settings_huggingface_token_cleared => 'टोकन साफ़ किया गया';

  @override
  String get model_requires_huggingface_token => 'Hugging Face टोकन आवश्यक है';

  @override
  String get model_missing_huggingface_token =>
      'यह मॉडल Hugging Face पर gated है। इसे डाउनलोड करने के लिए Settings → On-Device Inference में एक टोकन जोड़ें।';

  @override
  String get set_huggingface_token => 'टोकन सेट करें';

  @override
  String get clear_huggingface_token => 'साफ़ करें';

  @override
  String get edit_huggingface_token_dialog_title => 'Hugging Face एक्सेस टोकन';

  @override
  String get huggingface_token_dialog_hint => 'hf_…';

  @override
  String get server_type_ollama_desc =>
      'लोकल AI इंजन। API key की आवश्यकता नहीं है।';

  @override
  String get server_type_on_device_desc =>
      'आपके फ़ोन पर चलता है। कुछ मॉडलों के लिए Hugging Face टोकन चाहिए।';

  @override
  String get server_type_lm_studio_desc =>
      'लोकल API सर्वर। API key की आवश्यकता नहीं है।';

  @override
  String get available_models => 'उपलब्ध मॉडल';

  @override
  String get device_memory => 'डिवाइस मेमोरी';

  @override
  String get ram_usage => 'रैम का उपयोग';

  @override
  String get memory_healthy => 'स्वस्थ';

  @override
  String get memory_critical => 'महत्वपूर्ण';

  @override
  String get memory_low => 'कम';

  @override
  String ram_used(String percent) {
    return '$percent% प्रयुक्त';
  }

  @override
  String get available_ram => 'उपलब्ध रैम (RAM)';

  @override
  String get total_capacity => 'कुल क्षमता';

  @override
  String get loaded_status => 'लोड किया गया';

  @override
  String get inference_backend => 'अनुमान बैकएंड (Inference Backend)';

  @override
  String get backend_ios_notice => 'iOS पर केवल CPU बैकएंड उपलब्ध है।';

  @override
  String get backend_cpu_desc => 'सभी उपकरणों पर काम करता है। सबसे अनुकूल।';

  @override
  String get backend_gpu_desc => 'OpenCL त्वरण। समर्थित उपकरणों पर तेज़।';

  @override
  String get backend_npu_desc =>
      'विक्रेता NPU (Qualcomm/MediaTek)। सबसे तेज़ अनुमान।';

  @override
  String get select_model_title => 'मॉडल चुनें';

  @override
  String get refresh_models => 'मॉडल रीफ्रेश करें';

  @override
  String get search_models_hint => 'मॉडल खोजें...';

  @override
  String get no_server_connected => 'कोई सर्वर कनेक्ट नहीं है';

  @override
  String get add_server_first =>
      'उपलब्ध मॉडल देखने के लिए पहले एक सर्वर जोड़ें।';

  @override
  String get failed_load_models => 'मॉडल लोड करने में विफल';

  @override
  String get no_models_available => 'कोई मॉडल उपलब्ध नहीं है';

  @override
  String no_models_match(String searchQuery) {
    return '\"$searchQuery\" से मेल खाने वाला कोई मॉडल नहीं मिला';
  }

  @override
  String model_load_failed(String error) {
    return 'मॉडल लोड करने में विफल: $error';
  }

  @override
  String model_unloaded_ollama(String name) {
    return 'कीप-अलाइव (keep-alive) समय बीतने के बाद $name को अनलोड कर दिया जाएगा';
  }

  @override
  String model_unloaded_success(String name) {
    return '$name सफलतापूर्वक अनलोड हो गया';
  }

  @override
  String model_unload_failed(String error) {
    return 'मॉडल अनलोड करने में विफल: $error';
  }

  @override
  String get unload_from_server => 'सर्वर से अनलोड करें';

  @override
  String context_chip(String ctx) {
    return '$ctx संदर्भ (ctx)';
  }

  @override
  String get unload_all_models => 'सभी मॉडल अनलोड करें';

  @override
  String loaded_models_count(int count) {
    return '$count मॉडल लोड किए गए';
  }

  @override
  String get all_models_unloaded => 'सभी मॉडल अनलोड कर दिए गए';

  @override
  String get branch_chat => 'ब्रांच चैट';

  @override
  String get branch_chat_desc => 'इस संदेश से शुरू होने वाली एक नई चैट बनाएं';

  @override
  String get edit_assistant_message_desc =>
      'सहायक संदेश की सामग्री को संपादित करें';

  @override
  String switch_to_model(String modelName, Object model) {
    return 'मॉडल $model पर स्विच करें';
  }

  @override
  String download_notification_title(String modelName) {
    return '$modelName डाउनलोड किया जा रहा है...';
  }

  @override
  String get download_complete_notification => 'डाउनलोड पूर्ण!';

  @override
  String download_complete_body(String modelName) {
    return '$modelName सफलतापूर्वक डाउनलोड हो गया है।';
  }

  @override
  String download_failed_notification(String error) {
    return 'डाउनलोड विफल: $error';
  }

  @override
  String download_failed_body(String modelName) {
    return '$modelName डाउनलोड करने में विफल।';
  }

  @override
  String get engine_name_system => 'सिस्टम TTS';

  @override
  String get engine_tagline_system => 'इन-बिल्ट डिवाइस इंजन';

  @override
  String get engine_name_kitten => 'Kitten TTS';

  @override
  String get engine_tagline_kitten => 'उच्च गति न्यूरल TTS';

  @override
  String get engine_name_sherpa => 'Sherpa ONNX VITS';

  @override
  String get engine_tagline_sherpa => 'ऑफ़लाइन पाइपर (Piper) आवाज़ें';

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
      'सबसे छोटा सामान्य प्रयोजन चैट मॉडल। त्वरित प्रतिक्रियाएं, कम मेमोरी उपयोग।';

  @override
  String get model_license_apache => 'Apache-2.0';

  @override
  String get model_qwen_25 => 'Qwen 2.5 1.5B Instruct';

  @override
  String get model_qwen_25_desc =>
      'संतुलित गुणवत्ता और आकार। सामान्य बातचीत के लिए अच्छा है।';

  @override
  String get model_deepseek => 'DeepSeek R1 Distill Qwen 1.5B';

  @override
  String get model_deepseek_desc =>
      'तर्क और विचार-श्रृंखला मॉडल। तार्किक कार्यों के लिए सर्वोत्तम।';

  @override
  String get model_license_mit => 'MIT';

  @override
  String get model_gemma => 'Gemma 4 E2B Instruct';

  @override
  String get model_gemma_desc =>
      'गूगल का फ्लैगशिप मॉडल। उच्चतम गुणवत्ता, अधिक रैम की आवश्यकता है।';

  @override
  String export_header(String date) {
    return '*LocalMind से निर्यात किया गया — $date*';
  }

  @override
  String get export_role_user => '## 👤 उपयोगकर्ता';

  @override
  String get export_role_assistant => '## 🤖 सहायक';

  @override
  String get export_role_system => '## ⚙️ सिस्टम';

  @override
  String get export_role_tool => '## 🔧 उपकरण';

  @override
  String get export_text_user => '[उपयोगकर्ता]';

  @override
  String get export_text_assistant => '[सहायक]';

  @override
  String get export_text_system => '[सिस्टम]';

  @override
  String get export_text_tool => '[उपकरण]';

  @override
  String get export_label_user => 'उपयोगकर्ता';

  @override
  String get export_label_assistant => 'सहायक';

  @override
  String get export_label_system => 'सिस्टम';

  @override
  String get export_label_tool => 'उपकरण';

  @override
  String get select_model_hint => 'चैटिंग शुरू करने के लिए एक मॉडल चुनें';

  @override
  String get test_notification_title => 'परीक्षण सूचना';

  @override
  String get test_notification_body =>
      'यह मॉडल डाउनलोड प्रगति के लिए एक परीक्षण सूचना है।';

  @override
  String get tts_supports_background =>
      'मूल ऑडियो के रूप में पृष्ठभूमि प्लेबैक का समर्थन करता है';

  @override
  String get tts_other_services_background_note =>
      'नोट: अन्य टीटीएस सेवाएं मूल ऑडियो के रूप में पृष्ठभूमि प्लेबैक का समर्थन करती हैं।';

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
  String get model_favorite_toggle => 'पसंदीदा टॉगल करें';

  @override
  String get model_set_default => 'Set as default model';

  @override
  String get model_clear_default => 'Remove as default model';

  @override
  String get model_default_badge => 'Default';

  @override
  String get model_note_label => 'टिप्पणी (Note)';

  @override
  String get model_note_hint => 'इस मॉडल के लिए एक निजी टिप्पणी जोड़ें...';

  @override
  String get unload_models_before_load => 'लोड करने से पहले मॉडल अनलोड करें';

  @override
  String get temp_chat_keyboard_incognito =>
      'अस्थायी चैट में गुप्त (Incognito) कीबोर्ड';

  @override
  String get temp_chat_keyboard_incognito_desc =>
      'अस्थायी चैट के दौरान टाइपिंग इतिहास को सहेजने के लिए सिस्टम कीबोर्ड से अनुरोध न करें';

  @override
  String get resume_last_chat => 'पिछली चैट फिर से शुरू करें';

  @override
  String get resume_last_chat_desc =>
      'स्टार्टअप पर स्वचालित रूप से अपना अंतिम सक्रिय वार्तालाप खोलें';

  @override
  String get export_all_data => 'सभी डेटा निर्यात करें';

  @override
  String get import_all_data => 'सभी डेटा आयात करें';

  @override
  String get export_data_success => 'डेटा सफलतापूर्वक निर्यात किया गया';

  @override
  String get import_data_success => 'डेटा सफलतापूर्वक आयात किया गया';

  @override
  String import_data_failed(String error) {
    return 'डेटा आयात करने में विफल';
  }

  @override
  String get import_data_confirm =>
      'यह आपके सभी वर्तमान डेटा को आयातित डेटा से बदल देगा। क्या आप जारी रखना चाहते हैं?';

  @override
  String get import_settings_confirm =>
      'यह आपकी वर्तमान सेटिंग्स को आयातित सेटिंग्स से बदल देगा। क्या आप जारी रखना चाहते हैं?';

  @override
  String get export_conversations => 'वार्तालाप निर्यात करें';

  @override
  String get import_conversations => 'वार्तालाप आयात करें';

  @override
  String get export_personas => 'व्यक्तित्व निर्यात करें';

  @override
  String get import_personas => 'व्यक्तित्व आयात करें';

  @override
  String get export_settings => 'सेटिंग्स निर्यात करें';

  @override
  String get import_settings => 'सेटिंग्स आयात करें';

  @override
  String get export_all_zip => 'सभी निर्यात करें (ZIP)';

  @override
  String get import_all_zip => 'सभी आयात करें (ZIP)';

  @override
  String get duplicate_chat => 'चैट की प्रतिलिपि बनाएँ';

  @override
  String get duplicate_chat_success => 'चैट की प्रतिलिपि सफलतापूर्वक बनाई गई';

  @override
  String get move_to_folder => 'फ़ोल्डर में ले जाएं';

  @override
  String get remove_from_folder => 'फ़ोल्डर से निकालें';

  @override
  String get create_folder => 'फ़ोल्डर बनाएं';

  @override
  String get new_folder => 'नया फ़ोल्डर';

  @override
  String get folder_name_hint => 'फ़ोल्डर का नाम दर्ज करें...';

  @override
  String get all_chats => 'सभी चैट';

  @override
  String get unfiled_chats => 'बिना श्रेणीबद्ध चैट';

  @override
  String get create => 'बनाएं';

  @override
  String get server_path_prefix_label => 'सर्वर पथ उपसर्ग (Path Prefix)';

  @override
  String get server_path_prefix_hint =>
      'सर्वर एपीआई पथों के लिए वैकल्पिक उपसर्ग (जैसे /v1)';

  @override
  String get search_message_contents => 'संदेश सामग्री खोजें...';

  @override
  String get message_search_results => 'संदेश खोज परिणाम';

  @override
  String get saved_messages_title => 'सहेजे गए संदेश';

  @override
  String get nav_saved_messages => 'सहेजे गए संदेश';

  @override
  String get saved_messages_empty => 'अभी तक कोई सहेजा गया संदेश नहीं है';

  @override
  String get save_message => 'संदेश सहेजें';

  @override
  String get message_saved => 'संदेश सहेजा गया';

  @override
  String token_count(int count) {
    return 'टोकन: $count';
  }

  @override
  String estimated_token_count(int count) {
    return 'अनुमानित टोकन: $count';
  }

  @override
  String get test_tts_section_title => 'टेक्स्ट-टू-स्पीच परीक्षण';

  @override
  String get test_tts_hint => 'आवाज का परीक्षण करने के लिए कुछ टाइप करें...';

  @override
  String get test_speak_button => 'बोलें';

  @override
  String get scroll_to_bottom => 'नीचे स्क्रॉल करें';

  @override
  String get generate_ai_response => 'एआई प्रतिक्रिया जनरेट करें';

  @override
  String get no_response => 'कोई प्रतिक्रिया नहीं';

  @override
  String get export => 'निर्यात';

  @override
  String get import => 'आयात';

  @override
  String get conversations_label => 'वार्तालाप';

  @override
  String get personas_label => 'व्यक्तित्व';

  @override
  String get settings_label => 'सेटिंग्स';

  @override
  String get export_conversation => 'वार्तालाप निर्यात करें';

  @override
  String get tts_process_markdown => 'मार्कडाउन संसाधित करें';

  @override
  String get tts_process_markdown_desc =>
      'तेज़ आवाज में पढ़ने से पहले **बोल्ड** जैसी फ़ॉर्मेटिंग हटा दें';

  @override
  String get tts_skip_seconds => 'स्किप करने के लिए सेकंड';

  @override
  String get tts_skip_seconds_desc => 'वॉयस प्लेयर में आगे/पीछे जाने का समय';

  @override
  String tts_skip_seconds_value(int seconds) {
    return '${seconds}s';
  }

  @override
  String get preview_system_prompts => 'सिस्टम प्रॉम्प्ट का पूर्वावलोकन करें';

  @override
  String get welcome_message_1 => 'नमस्ते! मैं आपका स्थानीय एआई सहायक हूँ।';

  @override
  String get welcome_message_2 =>
      'मुझसे कुछ भी पूछें — जब आप तैयार हों मैं तैयार हूँ।';

  @override
  String get welcome_message_3 =>
      'आपका डेटा स्थानीय रूप से संसाधित होता है और आपके डिवाइस से कभी बाहर नहीं जाता है।';

  @override
  String get welcome_message_4 =>
      'शुरू करने के लिए, शीर्ष बार से एक मॉडल चुनें या मॉडल प्रबंधन अनुभाग में एक नया मॉडल जोड़ें।';

  @override
  String get temporary_chat => 'अस्थायी चैट';

  @override
  String get temporary_chat_desc =>
      'इस चैट के संदेश इतिहास में सहेजे नहीं जाएंगे';

  @override
  String get temporary_chat_banner =>
      'अस्थायी चैट सक्रिय — इतिहास सहेजा नहीं जाएगा';

  @override
  String get temporary_chat_save_warning_title => 'अस्थायी चैट सहेजें?';

  @override
  String get temporary_chat_save_warning_body =>
      'यह चैट आपके इतिहास में सहेजी नहीं गई है। क्या आप इसे अभी सहेजना चाहते हैं?';

  @override
  String get save_to_history => 'इतिहास में सहेजें';

  @override
  String get share_conversation => 'वार्तालाप साझा करें';

  @override
  String get download_tts_audio => 'वॉयस ऑडियो डाउनलोड करें';

  @override
  String get tts_download_unavailable => 'वॉयस डाउनलोड अनुपलब्ध';

  @override
  String get tts_download_no_audio =>
      'डाउनलोड करने के लिए कोई जनरेटेड ऑडियो नहीं है';

  @override
  String get tts_download_success => 'वॉयस ऑडियो सफलतापूर्वक सहेजा गया';

  @override
  String get return_to_chat => 'चैट पर लौटें';

  @override
  String get return_to_temp_chat => 'अस्थायी चैट पर लौटें';

  @override
  String get insert_saved_message => 'सहेजा गया संदेश डालें';

  @override
  String get insert_saved_message_desc =>
      'अपने सहेजे गए संदेशों का एक अंश चैट में जोड़ें';

  @override
  String get model_info => 'मॉडल की जानकारी';

  @override
  String get model_name => 'मॉडल का नाम';

  @override
  String get model_identifier => 'मॉडल पहचानकर्ता';

  @override
  String get not_available => 'अनुपलब्ध';

  @override
  String get save_message_folders => 'फ़ोल्डरों में सहेजें';

  @override
  String get remove_from_saved => 'सहेजे गए से निकालें';

  @override
  String get message_already_saved => 'संदेश पहले से ही सहेजा गया है';

  @override
  String get stream_ttft => 'पहले टोकन तक का समय';

  @override
  String get stream_tokens_per_sec => 'टोकन प्रति सेकंड';

  @override
  String get stream_stop_reason => 'रुकने का कारण';

  @override
  String get stream_input_tokens => 'इनपुट टोकन';

  @override
  String get stream_output_tokens => 'आउटपुट टोकन';

  @override
  String get stream_generation_time => 'जेनरेशन का समय';

  @override
  String get attach_image => 'छवि संलग्न करें';

  @override
  String get attach_text_document => 'पाठ दस्तावेज़ संलग्न करें';

  @override
  String get attach_shortcut_images => 'फ़ोटो';

  @override
  String get attach_shortcut_documents => 'फ़ाइलें';

  @override
  String get attach_shortcut_saved => 'सहेजे गए';

  @override
  String get add_attachment => 'संलग्नक जोड़ें';

  @override
  String get add_to_chat => 'चैट में जोड़ें';

  @override
  String get choose_what_to_attach => 'आप क्या जोड़ना चाहते हैं?';

  @override
  String get choose_attachment_subtitle =>
      'अपने संदेश में संलग्न करने के लिए एक स्रोत चुनें';

  @override
  String get photo_permission_denied => 'फ़ोटो अनुमति अस्वीकृत';

  @override
  String get select_model_prompt => 'मॉडल चुनें';

  @override
  String get characters_label => 'वर्ण (Characters)';

  @override
  String get exit_temporary_chat_title => 'अस्थायी चैट से बाहर निकलें?';

  @override
  String get exit_temporary_chat_body =>
      'यह वर्तमान वार्तालाप को स्थायी रूप से हटा देगा। क्या आप जारी रखना चाहते हैं?';

  @override
  String get saved_message_temp_snap_unavailable =>
      'अस्थायी चैट में संदेश स्नैपशॉट उपलब्ध नहीं हैं';

  @override
  String get filter_title => 'चैट फ़िल्टर करें';

  @override
  String get filter_pinned => 'पिन किया गया';

  @override
  String get filter_archived => 'अभिलेखागार (Archived)';

  @override
  String get filter_temp_chats => 'अस्थायी चैट';

  @override
  String get filter_user_messages => 'उपयोगकर्ता संदेश';

  @override
  String get filter_assistant_messages => 'सहायक संदेश';

  @override
  String get archive_chat => 'चैट को आर्काइव करें';

  @override
  String get unarchive_chat => 'चैट को अनआर्काइव करें';

  @override
  String conversation_message_count(int count) {
    return '$count संदेश';
  }

  @override
  String conversation_character_count(int count) {
    return '$count वर्ण';
  }

  @override
  String get generate_title_with_ai => 'एआई के साथ शीर्षक जनरेट करें';

  @override
  String get generating_title => 'शीर्षक जनरेट किया जा रहा है...';

  @override
  String get generate_title_failed => 'शीर्षक जनरेट नहीं किया जा सका';

  @override
  String get lm_studio_model_browser_title => 'मॉडल ब्राउज़र';

  @override
  String get lm_studio_model_search_hint => 'मॉडल खोजें...';

  @override
  String get lm_studio_staff_picks => 'स्टाफ की पसंद';

  @override
  String get lm_studio_community_models => 'सामुदायिक मॉडल';

  @override
  String get lm_studio_no_models => 'कोई मॉडल नहीं मिला';

  @override
  String lm_studio_models_count(int count) {
    return '$count मॉडल';
  }

  @override
  String get lm_studio_browse_models => 'LM Studio पर मॉडल ब्राउज़ करें';

  @override
  String get lm_studio_model_search => 'मॉडल खोज';

  @override
  String get lm_studio_downloads_title => 'डाउनलोड';

  @override
  String get lm_studio_choose_quant => 'क्वांटाइजेशन चुनें';

  @override
  String get lm_studio_use_default_quant =>
      'डिफ़ॉल्ट क्वांटाइजेशन का उपयोग करें';

  @override
  String get lm_studio_recommended => 'अनुशंसित';

  @override
  String get lm_studio_clear_downloads => 'पूर्ण डाउनलोड साफ़ करें';

  @override
  String get lm_studio_no_downloads => 'कोई सक्रिय डाउनलोड नहीं';

  @override
  String get lm_studio_downloads_disclaimer =>
      'मॉडल डाउनलोड सीधे Hugging Face से किए जाते हैं।';

  @override
  String get lm_studio_staff_pick => 'स्टाफ की विशेष पसंद';

  @override
  String get lm_studio_params => 'पैरामीटर';

  @override
  String get lm_studio_arch => 'आर्किटेक्चर';

  @override
  String get lm_studio_domain => 'डोमेन';

  @override
  String get lm_studio_format => 'प्रारूप (Format)';

  @override
  String get lm_studio_vision => 'विज़न (Vision)';

  @override
  String get lm_studio_tool_use => 'टूल का उपयोग';

  @override
  String get lm_studio_reasoning => 'तर्क (Reasoning)';

  @override
  String get lm_studio_download_options => 'डाउनलोड विकल्प';

  @override
  String get lm_studio_download => 'डाउनलोड करें';

  @override
  String lm_studio_download_size(String size) {
    return 'डाउनलोड का आकार';
  }

  @override
  String lm_studio_downloading_percent(int percent) {
    return 'डाउनलोड हो रहा है: $percent%';
  }

  @override
  String get lm_studio_readme_unavailable =>
      'इस मॉडल के लिए README अनुपलब्ध है।';

  @override
  String get lm_studio_full_gpu_offload => 'पूर्ण GPU ऑफलोड संभव';

  @override
  String get lm_studio_partial_gpu_offload => 'आंशिक GPU ऑफलोड संभव';

  @override
  String get lm_studio_likely_too_large => 'संभवतः बहुत बड़ा है';

  @override
  String get lm_studio_available_ram_gb => 'उपलब्ध रैम (GB, वैकल्पिक)';

  @override
  String get lm_studio_available_vram_gb => 'उपलब्ध वीराम (GB, वैकल्पिक)';

  @override
  String get lm_studio_memory_settings_title => 'सिफारिशों के लिए मेमोरी';

  @override
  String get lm_studio_memory_settings_desc =>
      'मॉडल ब्राउज़र में यह अनुमान लगाने के लिए उपयोग किया जाता है कि क्या मॉडल आपकी मशीन में फिट होंगे।';

  @override
  String get think_button_label => 'सोचें';

  @override
  String get thinking_mode_title => 'सोच का तरीका';

  @override
  String get reasoning_effort_low => 'कम';

  @override
  String get reasoning_effort_medium => 'मध्यम';

  @override
  String get reasoning_effort_high => 'उच्च';

  @override
  String get could_not_read_file => 'फ़ाइल पढ़ी नहीं जा सकी';

  @override
  String get server_offline => 'सर्वर ऑफ़लाइन';

  @override
  String get could_not_establish_connection =>
      'सर्वर से कनेक्शन स्थापित नहीं किया जा सका। कृपया जांचें कि क्या आपका सर्वर चल रहा है और होस्ट/पोर्ट सेटिंग्स सही हैं।';

  @override
  String get retry_connection => 'कनेक्शन का पुनः प्रयास करें';

  @override
  String get tokens_label => 'टोकन';

  @override
  String get enter_context_length => 'संदर्भ की लंबाई दर्ज करें...';

  @override
  String get openrouter_disclosure =>
      'इस प्रदाता को कनेक्ट करके, आपके चैट संदेश और इनपुट उनके सर्वर पर भेजे जाएंगे। LocalMind आपकी बातचीत को ट्रैक या संग्रहीत नहीं करता है।';

  @override
  String get welcome_message_cloud =>
      'आपके संदेश आपके कनेक्टेड प्रदाता को भेजे जाते हैं।';

  @override
  String get privacy_policy => 'गोपनीयता नीति';

  @override
  String get cloud_sync => 'S3 क्लाउड सिंक';

  @override
  String get cloud_sync_description =>
      'अपने S3-संगत सर्वर पर एंड-टू-एंड एन्क्रिप्टेड सिंक';

  @override
  String get cloud_sync_endpoint => 'एंडपॉइंट URL';

  @override
  String get cloud_sync_bucket => 'बकेट';

  @override
  String get cloud_sync_region => 'क्षेत्र';

  @override
  String get cloud_sync_prefix => 'प्रीफ़िक्स';

  @override
  String get cloud_sync_access_key => 'एक्सेस कुंजी ID';

  @override
  String get cloud_sync_secret_key => 'गुप्त एक्सेस कुंजी';

  @override
  String get cloud_sync_session_token => 'सत्र टोकन (वैकल्पिक)';

  @override
  String get cloud_sync_passphrase => 'एन्क्रिप्शन पासफ़्रेज़';

  @override
  String get cloud_sync_confirm_passphrase => 'पासफ़्रेज़ की पुष्टि करें';

  @override
  String get cloud_sync_path_style => 'पाथ-स्टाइल एड्रेसिंग का उपयोग करें';

  @override
  String get cloud_sync_allow_http => 'असुरक्षित HTTP की अनुमति दें';

  @override
  String get cloud_sync_http_warning =>
      'HTTP नेटवर्क पर अनुरोध की जानकारी और क्रेडेंशियल उजागर करता है। इसे केवल विश्वसनीय स्थानीय S3 सर्वर के लिए उपयोग करें।';

  @override
  String get cloud_sync_test => 'कनेक्शन जाँचें';

  @override
  String get cloud_sync_enable => 'एन्क्रिप्टेड सिंक चालू करें';

  @override
  String get cloud_sync_now => 'अभी सिंक करें';

  @override
  String get cloud_sync_disconnect => 'इस डिवाइस को डिस्कनेक्ट करें';

  @override
  String get cloud_sync_last_synced => 'अंतिम सिंक';

  @override
  String get cloud_sync_never => 'कभी नहीं';

  @override
  String get cloud_sync_conflicts => 'सहेजे गए विरोध';

  @override
  String get cloud_sync_passphrase_mismatch => 'पासफ़्रेज़ मेल नहीं खाते';

  @override
  String get crash_report_title => 'कुछ गलत हो गया';

  @override
  String get crash_report_stack_trace => 'स्टैक ट्रेस';

  @override
  String get crash_report_tap_to_expand => 'विस्तार करने के लिए टैप करें';

  @override
  String get crash_report_button => 'इस क्रैश की रिपोर्ट करें';

  @override
  String get crash_try_again => 'फिर से प्रयास करें';

  @override
  String get crash_report_empty_stack => '<खाली>';

  @override
  String get crash_report_disclaimer =>
      'रिपोर्टिंग GitHub खोलेगी जिसमें निदान पहले से भरा होगा। नियंत्रण आपके पास है — कुछ भी स्वचालित रूप से सबमिट नहीं किया जाता। कृपया सबमिट करने से पहले संवेदनशील सामग्री की समीक्षा करें और हटा दें।';

  @override
  String get crash_report_copied => 'क्लिपबोर्ड पर कॉपी किया गया';

  @override
  String get report_a_problem => 'समस्या की रिपोर्ट करें';

  @override
  String get rename_folder => 'फ़ोल्डर का नाम बदलें';

  @override
  String get delete_folder => 'फ़ोल्डर हटाएँ';

  @override
  String get delete_folder_title => 'फ़ोल्डर हटाएँ?';

  @override
  String delete_folder_body(String name) {
    return 'क्या आप वाकई \"$name\" हटाना चाहते हैं? अंदर की बातचीत या सहेजे गए संदेश \"अवर्गीकृत\" में वापस चले जाएंगे। इसे पूर्ववत नहीं किया जा सकता।';
  }

  @override
  String get folder_name_required => 'कृपया फ़ोल्डर का नाम दर्ज करें';

  @override
  String get model_required_toast => 'आपको पहले एक मॉडल चुनना होगा';
}
