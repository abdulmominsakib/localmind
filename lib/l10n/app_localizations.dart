import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_it.dart';
import 'app_localizations_ja.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('bn'),
    Locale('en'),
    Locale('es'),
    Locale('hi'),
    Locale('it'),
    Locale('ja'),
    Locale('ru'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// Application display name
  ///
  /// In en, this message translates to:
  /// **'LocalMind'**
  String get app_name;

  /// Application tagline shown in settings and splash
  ///
  /// In en, this message translates to:
  /// **'Your AI. Your Device. Your Rules.'**
  String get app_tagline;

  /// Application version number
  ///
  /// In en, this message translates to:
  /// **'1.0.0'**
  String get app_version;

  /// Generic cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Generic confirm button label
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// Generic delete button label
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// Generic save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Generic retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// Generic close button label
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Generic done button label
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Generic continue button label
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continue_action;

  /// Generic skip button label
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// Install action button
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get install;

  /// Download action button
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get download;

  /// Resume download button
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// Pause download button
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// Stop action button
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get stop;

  /// Edit action label
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// Preview action label
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// Unload model action
  ///
  /// In en, this message translates to:
  /// **'Unload'**
  String get unload;

  /// Load model action
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// Rename action label
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// Pin conversation action
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pin;

  /// Unpin conversation action
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpin;

  /// Share action label
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// Copy action label
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;

  /// Copied confirmation text
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get copied;

  /// Snackbar message after copy
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copied_to_clipboard;

  /// Select action button
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get select;

  /// Active status badge
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// All filter label
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No selection label
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get none;

  /// Dropdown placeholder when nothing selected
  ///
  /// In en, this message translates to:
  /// **'None selected'**
  String get none_selected;

  /// Connection status online
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get online;

  /// Connection status offline
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// Error status text
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// Fallback unknown error message
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknown_error;

  /// Dismiss action for notifications
  ///
  /// In en, this message translates to:
  /// **'Not Now'**
  String get not_now;

  /// Enable action button
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enable;

  /// Proceed despite warning
  ///
  /// In en, this message translates to:
  /// **'Proceed Anyway'**
  String get proceed_anyway;

  /// Button to test server connection
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get test_connection;

  /// Button label while testing connection
  ///
  /// In en, this message translates to:
  /// **'Testing...'**
  String get testing;

  /// Connection test success message
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get connection_successful;

  /// Connection test failure message
  ///
  /// In en, this message translates to:
  /// **'Connection failed. Check your settings.'**
  String get connection_failed;

  /// Save and proceed button
  ///
  /// In en, this message translates to:
  /// **'Save & Continue'**
  String get save_continue;

  /// Save changes button
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get save_changes;

  /// Complete onboarding button
  ///
  /// In en, this message translates to:
  /// **'Finish Setup'**
  String get finish_setup;

  /// Button to start a new chat
  ///
  /// In en, this message translates to:
  /// **'Start New Chat'**
  String get start_new_chat;

  /// Warning for destructive actions
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get cannot_undo;

  /// RAM warning dialog title
  ///
  /// In en, this message translates to:
  /// **'RAM Warning'**
  String get ram_warning;

  /// Recommended badge on model cards
  ///
  /// In en, this message translates to:
  /// **'RECOMMENDED'**
  String get recommended;

  /// Warning when model may exceed device RAM
  ///
  /// In en, this message translates to:
  /// **'May be too large for this device'**
  String get may_be_large;

  /// ETA placeholder during download
  ///
  /// In en, this message translates to:
  /// **'Calculating...'**
  String get calculating;

  /// Download failure status
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get download_failed;

  /// Download completed status
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get downloaded;

  /// Model not yet downloaded
  ///
  /// In en, this message translates to:
  /// **'Not downloaded'**
  String get not_downloaded;

  /// Installed status
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get installed;

  /// Not installed status
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get not_installed;

  /// Generic loading indicator text
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loading;

  /// Model thinking indicator
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get thinking;

  /// Processing indicator text
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// Initializing status
  ///
  /// In en, this message translates to:
  /// **'Initializing...'**
  String get initializing;

  /// Ready status text
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get ready;

  /// Bootstrap stage message
  ///
  /// In en, this message translates to:
  /// **'Preparing app...'**
  String get preparing_app;

  /// Bootstrap stage message
  ///
  /// In en, this message translates to:
  /// **'Initializing services...'**
  String get initializing_services;

  /// Bootstrap stage message
  ///
  /// In en, this message translates to:
  /// **'Configuring server...'**
  String get configuring_server;

  /// Bootstrap error message
  ///
  /// In en, this message translates to:
  /// **'Startup failed'**
  String get startup_failed;

  /// Generic error heading on bootstrap screen
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get something_went_wrong;

  /// Delete model dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Model'**
  String get delete_model_title;

  /// Delete model confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}?'**
  String delete_model_body(String name);

  /// Delete model dialog body with size info
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}? This will free up approximately {size} of space.\n\nYou can download this model again later if needed.'**
  String delete_model_body_with_size(String name, String size);

  /// Delete voice confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Voice'**
  String get delete_voice_title;

  /// Delete voice confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete {name}? This will free up approximately {size} of space.\n\nYou can download this voice again later if needed.'**
  String delete_voice_body(String name, String size);

  /// Delete server confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete Server'**
  String get delete_server_title;

  /// Delete server confirmation body
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"? This cannot be undone.'**
  String delete_server_body(String name);

  /// Delete conversation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get delete_conversation_title;

  /// Delete conversation dialog body
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{title}\"? This cannot be undone.'**
  String delete_conversation_body(String title);

  /// Delete message dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete message?'**
  String get delete_message_title;

  /// Delete persona dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String delete_persona_title(String name);

  /// Delete persona dialog body
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone.'**
  String get delete_persona_body;

  /// Delete built-in persona dialog body
  ///
  /// In en, this message translates to:
  /// **'This is a built-in persona. You can restore it later from Settings.'**
  String get delete_builtin_persona_body;

  /// Settings action to re-add any deleted built-in personas
  ///
  /// In en, this message translates to:
  /// **'Restore default personas'**
  String get restore_builtin_personas;

  /// Settings description for restore built-in personas
  ///
  /// In en, this message translates to:
  /// **'Re-add any built-in personas you\'ve deleted'**
  String get restore_builtin_personas_desc;

  /// Snackbar after restoring built-in personas
  ///
  /// In en, this message translates to:
  /// **'Default personas restored'**
  String get restore_builtin_personas_success;

  /// Button to clear all selected personas in the picker
  ///
  /// In en, this message translates to:
  /// **'Clear personas'**
  String get clear_personas;

  /// Settings toggle to enable/disable automatic image compression
  ///
  /// In en, this message translates to:
  /// **'Compress images before sending'**
  String get enable_image_compression;

  /// Description for the image compression toggle
  ///
  /// In en, this message translates to:
  /// **'Resize and compress attached images so uploads stay within server limits'**
  String get enable_image_compression_desc;

  /// Label for the image compression level selector
  ///
  /// In en, this message translates to:
  /// **'Compression aggressiveness'**
  String get image_compression_level;

  /// Description for the image compression level selector
  ///
  /// In en, this message translates to:
  /// **'Higher aggressiveness produces smaller uploads at lower quality'**
  String get image_compression_level_desc;

  /// Low image compression aggressiveness
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get image_compression_level_low;

  /// Medium image compression aggressiveness
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get image_compression_level_medium;

  /// High image compression aggressiveness
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get image_compression_level_high;

  /// Tooltip for the model list sort button
  ///
  /// In en, this message translates to:
  /// **'Sort models'**
  String get sort_models_tooltip;

  /// Sort models with favorites first, then alphabetically
  ///
  /// In en, this message translates to:
  /// **'Favorites first'**
  String get sort_by_favorites;

  /// Sort models alphabetically by name
  ///
  /// In en, this message translates to:
  /// **'Name (A-Z)'**
  String get sort_by_name;

  /// Sort models by file size, smallest first
  ///
  /// In en, this message translates to:
  /// **'Size (smallest first)'**
  String get sort_by_size_smallest;

  /// Sort models by file size, largest first
  ///
  /// In en, this message translates to:
  /// **'Size (largest first)'**
  String get sort_by_size_largest;

  /// Sort models by max context length, largest first
  ///
  /// In en, this message translates to:
  /// **'Context length'**
  String get sort_by_context_length;

  /// Progress text while AI-renaming multiple conversations
  ///
  /// In en, this message translates to:
  /// **'Renaming {done}/{total}...'**
  String bulk_ai_rename_progress(int done, int total);

  /// Header shown in selection mode
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selected_count(int count);

  /// Tooltip for bulk AI rename button
  ///
  /// In en, this message translates to:
  /// **'Rename selected with AI'**
  String get ai_rename_tooltip;

  /// Tooltip for the history screen new-chat FAB
  ///
  /// In en, this message translates to:
  /// **'New chat in this folder'**
  String get new_chat_in_folder_tooltip;

  /// Total token count shown under the chat text field
  ///
  /// In en, this message translates to:
  /// **'{count} tokens'**
  String total_tokens_count(int count);

  /// Settings toggle to include persona system prompt when generating smart reply suggestions
  ///
  /// In en, this message translates to:
  /// **'Use persona in smart replies'**
  String get smart_replies_use_persona;

  /// Description for the smart-replies-use-persona toggle
  ///
  /// In en, this message translates to:
  /// **'Suggested replies match the tone of the active persona instead of a generic assistant'**
  String get smart_replies_use_persona_desc;

  /// Settings toggle to not clear persona selection when starting a new chat
  ///
  /// In en, this message translates to:
  /// **'Keep persona on new chat'**
  String get keep_persona_on_new_chat;

  /// Description for the keep-persona-on-new-chat toggle
  ///
  /// In en, this message translates to:
  /// **'Don\'t clear the selected persona(s) after starting a new chat'**
  String get keep_persona_on_new_chat_desc;

  /// Settings toggle to show a button that lets the user send a message as the assistant role
  ///
  /// In en, this message translates to:
  /// **'Show role-swap button'**
  String get role_swap_button_enabled;

  /// Description for the role-swap-button-enabled toggle
  ///
  /// In en, this message translates to:
  /// **'Show a button in the chat input to send your message as the assistant instead of the user, without generating a response'**
  String get role_swap_button_enabled_desc;

  /// Tooltip for the role-swap button when it will send as the user role
  ///
  /// In en, this message translates to:
  /// **'Send as user'**
  String get send_as_user_tooltip;

  /// Tooltip for the role-swap button when it will send as the assistant role
  ///
  /// In en, this message translates to:
  /// **'Send as assistant (no response)'**
  String get send_as_assistant_tooltip;

  /// Tooltip shown for long-pressing the send button to insert a message without generating a response
  ///
  /// In en, this message translates to:
  /// **'Insert without generating'**
  String get insert_without_generating_tooltip;

  /// Title of the sheet shown when tapping the token usage indicator
  ///
  /// In en, this message translates to:
  /// **'Token Usage'**
  String get token_usage_title;

  /// Label for the total token count row in the token usage sheet
  ///
  /// In en, this message translates to:
  /// **'Tokens used'**
  String get total_tokens_label;

  /// Label for the percentage-of-context-length row in the token usage sheet
  ///
  /// In en, this message translates to:
  /// **'Context used'**
  String get usage_percent_label;

  /// Title for the copy-vs-share export choice dialog
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export_choice_title;

  /// Body text for the copy-vs-share export choice dialog
  ///
  /// In en, this message translates to:
  /// **'How would you like to export this?'**
  String get export_choice_body;

  /// Button to copy export content to the clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy to Clipboard'**
  String get copy_to_clipboard;

  /// Success message after bulk-exporting conversations
  ///
  /// In en, this message translates to:
  /// **'Exported {count} conversations'**
  String bulk_export_conversations_success(int count);

  /// Title for the bulk AI rename confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Rename with AI?'**
  String get bulk_ai_rename_confirm_title;

  /// Body text for the bulk AI rename confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'This will ask the AI to generate a new title for each of the {count} selected conversations, replacing their current titles. This can take a while and cannot be undone.'**
  String bulk_ai_rename_confirm_body(int count);

  /// Sort history by last modified date
  ///
  /// In en, this message translates to:
  /// **'Last modified'**
  String get sort_by_modified_date;

  /// Sort history by creation date
  ///
  /// In en, this message translates to:
  /// **'Date created'**
  String get sort_by_created_date;

  /// Tooltip for the history sort button
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort_title;

  /// Clear conversation dialog title
  ///
  /// In en, this message translates to:
  /// **'Clear conversation?'**
  String get clear_conversation_title;

  /// Clear conversation confirmation body
  ///
  /// In en, this message translates to:
  /// **'This will delete all messages in this conversation.'**
  String get clear_conversation_body;

  /// Clear action button
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// Completion status message
  ///
  /// In en, this message translates to:
  /// **'{label} completed'**
  String label_completed(String label);

  /// Error display with message
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error_with_message(String error);

  /// Audio preview failed message
  ///
  /// In en, this message translates to:
  /// **'Preview failed: {error}'**
  String preview_failed(String error);

  /// Model loading status
  ///
  /// In en, this message translates to:
  /// **'Loading {modelId}...'**
  String loading_model(String modelId);

  /// Model loaded status in settings
  ///
  /// In en, this message translates to:
  /// **'Model loaded: {modelId} ({backend})'**
  String model_loaded(String modelId, String backend);

  /// Status when no on-device model is loaded
  ///
  /// In en, this message translates to:
  /// **'No model loaded. Tap \"Manage On-Device Models\" to download and load a model.'**
  String get no_model_loaded;

  /// Model loading error status
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String loading_model_error(String error);

  /// Delete conversation dialog title
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get delete_conversation;

  /// Navigation item for chat history
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get nav_history;

  /// Navigation item for servers
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get nav_servers;

  /// Navigation item for local on-device models
  ///
  /// In en, this message translates to:
  /// **'Local Models'**
  String get nav_local_models;

  /// Navigation item for TTS models
  ///
  /// In en, this message translates to:
  /// **'Text To Speech'**
  String get nav_tts;

  /// Navigation item for personas
  ///
  /// In en, this message translates to:
  /// **'Personas'**
  String get nav_personas;

  /// Navigation item for settings
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get nav_settings;

  /// Button to start a new chat
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get nav_new_chat;

  /// Search field placeholder for conversations
  ///
  /// In en, this message translates to:
  /// **'Search conversations...'**
  String get search_hint;

  /// Placeholder when no server is selected
  ///
  /// In en, this message translates to:
  /// **'No server selected'**
  String get no_server_selected;

  /// Switch server sheet title
  ///
  /// In en, this message translates to:
  /// **'Switch Server'**
  String get switch_server;

  /// Switch server sheet subtitle
  ///
  /// In en, this message translates to:
  /// **'Choose a server to connect to'**
  String get switch_server_subtitle;

  /// Button to manage servers list
  ///
  /// In en, this message translates to:
  /// **'Manage Servers'**
  String get manage_servers;

  /// GitHub repo card title
  ///
  /// In en, this message translates to:
  /// **'Open Source'**
  String get open_source;

  /// GitHub repo card description
  ///
  /// In en, this message translates to:
  /// **'LocalMind is open source. Follow our progress or contribute on GitHub.'**
  String get open_source_desc;

  /// Button to star repo on GitHub
  ///
  /// In en, this message translates to:
  /// **'Star on GitHub'**
  String get star_on_github;

  /// Label for the decorative GitHub tile on onboarding
  ///
  /// In en, this message translates to:
  /// **'Add more'**
  String get add_more;

  /// Secondary label for the decorative GitHub tile on onboarding
  ///
  /// In en, this message translates to:
  /// **'on GitHub'**
  String get on_github;

  /// Snackbar text shown when opening the GitHub repo fails
  ///
  /// In en, this message translates to:
  /// **'Could not open GitHub.'**
  String get could_not_open_github;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_title;

  /// Settings section header for appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settings_appearance;

  /// Settings section label for language selection
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_language;

  /// Option to use the device's system language
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get language_system_default;

  /// Settings section header for TTS
  ///
  /// In en, this message translates to:
  /// **'Text-to-Speech'**
  String get settings_tts;

  /// Settings section header for behavior
  ///
  /// In en, this message translates to:
  /// **'Behavior'**
  String get settings_behavior;

  /// Settings section header for on-device
  ///
  /// In en, this message translates to:
  /// **'On-Device Inference'**
  String get settings_on_device;

  /// Settings section header for default server
  ///
  /// In en, this message translates to:
  /// **'Default Server'**
  String get settings_default_server;

  /// Settings section header for default persona
  ///
  /// In en, this message translates to:
  /// **'Default Persona'**
  String get settings_default_persona;

  /// Settings section header for privacy
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get settings_privacy;

  /// Settings section header for data management
  ///
  /// In en, this message translates to:
  /// **'Data Management'**
  String get settings_data_management;

  /// Settings section header for about
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settings_about;

  /// Theme selection label
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// System theme option
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get theme_system;

  /// Light theme option
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get theme_light;

  /// Dark theme option
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get theme_dark;

  /// Claude theme option
  ///
  /// In en, this message translates to:
  /// **'Claude'**
  String get theme_claude;

  /// Font size slider label
  ///
  /// In en, this message translates to:
  /// **'Font Size'**
  String get font_size;

  /// Font size setting description
  ///
  /// In en, this message translates to:
  /// **'Adjust text size in chat.'**
  String get font_size_desc;

  /// Font preview sample text
  ///
  /// In en, this message translates to:
  /// **'The quick brown fox jumps over the lazy dog.'**
  String get font_preview;

  /// Dark code theme dropdown label
  ///
  /// In en, this message translates to:
  /// **'Code Theme (Dark)'**
  String get code_theme_dark;

  /// Light code theme dropdown label
  ///
  /// In en, this message translates to:
  /// **'Code Theme (Light)'**
  String get code_theme_light;

  /// Code theme setting description
  ///
  /// In en, this message translates to:
  /// **'Choose syntax highlighting theme for code blocks.'**
  String get code_theme_desc;

  /// TTS engine dropdown label
  ///
  /// In en, this message translates to:
  /// **'TTS Engine'**
  String get tts_engine;

  /// System TTS engine option
  ///
  /// In en, this message translates to:
  /// **'System TTS'**
  String get tts_engine_system;

  /// Kitten TTS engine option
  ///
  /// In en, this message translates to:
  /// **'Kitten TTS'**
  String get tts_engine_kitten;

  /// Voice selection label
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get voice;

  /// Female voice gender label
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get voice_female;

  /// Male voice gender label
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get voice_male;

  /// Other voice gender label
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get voice_other;

  /// TTS speed slider label
  ///
  /// In en, this message translates to:
  /// **'TTS Speed'**
  String get tts_speed;

  /// TTS speed setting description
  ///
  /// In en, this message translates to:
  /// **'Adjust the playback rate.'**
  String get tts_speed_desc;

  /// Button to manage TTS models
  ///
  /// In en, this message translates to:
  /// **'Manage TTS Models'**
  String get manage_tts_models;

  /// Button to manage on-device models
  ///
  /// In en, this message translates to:
  /// **'Manage On-Device Models'**
  String get manage_on_device_models;

  /// Toggle for on-device smart reply suggestions
  ///
  /// In en, this message translates to:
  /// **'On-Device Smart Replies'**
  String get enable_smart_reply;

  /// Settings toggle for AI-generated user message triggered by holding the send button
  ///
  /// In en, this message translates to:
  /// **'AI user message (hold send)'**
  String get ai_user_response_enabled;

  /// Description for the hold-to-generate-AI-user-message toggle
  ///
  /// In en, this message translates to:
  /// **'Hold the send button for 3 seconds to have the AI write and send your next message'**
  String get ai_user_response_enabled_desc;

  /// Tooltip for the AI user message button next to send
  ///
  /// In en, this message translates to:
  /// **'Generate user message with AI'**
  String get ai_user_response_tooltip;

  /// Toggle for streaming responses
  ///
  /// In en, this message translates to:
  /// **'Streaming Responses'**
  String get streaming_responses;

  /// Toggle for auto-generating conversation titles
  ///
  /// In en, this message translates to:
  /// **'Auto-generate Titles'**
  String get auto_generate_titles;

  /// Toggle for send on enter behavior
  ///
  /// In en, this message translates to:
  /// **'Send on Enter'**
  String get send_on_enter;

  /// Toggle for sending a default 'You are LocalMind' system prompt to the model when no persona is selected
  ///
  /// In en, this message translates to:
  /// **'Send Default System Prompt'**
  String get show_system_messages;

  /// Description for the send-default-system-prompt toggle
  ///
  /// In en, this message translates to:
  /// **'When no persona is selected, send a default assistant system prompt with each request'**
  String get show_system_messages_desc;

  /// Toggle for whether system-role messages are displayed as bubbles in the chat transcript
  ///
  /// In en, this message translates to:
  /// **'Show System Messages in Chat'**
  String get show_system_messages_in_chat;

  /// Description for the show-system-messages-in-chat toggle
  ///
  /// In en, this message translates to:
  /// **'Display system messages (e.g. from an imported backup) as visible bubbles in the conversation'**
  String get show_system_messages_in_chat_desc;

  /// Toggle for haptic feedback
  ///
  /// In en, this message translates to:
  /// **'Haptic Feedback'**
  String get haptic_feedback;

  /// Toggle for MCP feature
  ///
  /// In en, this message translates to:
  /// **'Enable MCP'**
  String get enable_mcp;

  /// Toggle for MCP default in new chats
  ///
  /// In en, this message translates to:
  /// **'New Chat MCP Default'**
  String get new_chat_mcp_default;

  /// Toggle for data indicator visibility
  ///
  /// In en, this message translates to:
  /// **'Show Data Indicator'**
  String get show_data_indicator;

  /// Privacy information text
  ///
  /// In en, this message translates to:
  /// **'\"LocalMind never sees your data\"'**
  String get privacy_info;

  /// Dangerous action button to clear all conversations
  ///
  /// In en, this message translates to:
  /// **'Delete All Conversations'**
  String get delete_all_conversations;

  /// Button to reset all settings
  ///
  /// In en, this message translates to:
  /// **'Reset Settings to Defaults'**
  String get reset_settings_defaults;

  /// Fallback chat screen title
  ///
  /// In en, this message translates to:
  /// **'LocalMind'**
  String get chat_title;

  /// Tooltip for chat parameters button
  ///
  /// In en, this message translates to:
  /// **'Chat Parameters'**
  String get chat_parameters_tooltip;

  /// Menu item to change persona
  ///
  /// In en, this message translates to:
  /// **'Change Persona'**
  String get change_persona;

  /// Menu item to set persona
  ///
  /// In en, this message translates to:
  /// **'Set Persona'**
  String get set_persona;

  /// Menu item to remove persona
  ///
  /// In en, this message translates to:
  /// **'Remove Persona'**
  String get remove_persona;

  /// Menu item to clear conversation
  ///
  /// In en, this message translates to:
  /// **'Clear Conversation'**
  String get clear_conversation;

  /// Connection error banner text
  ///
  /// In en, this message translates to:
  /// **'Connection error. Check your server.'**
  String get connection_error;

  /// Disconnected banner text
  ///
  /// In en, this message translates to:
  /// **'Disconnected from server.'**
  String get disconnected;

  /// Configure action button
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// Model selection placeholder
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get select_model;

  /// Persona selection sheet title
  ///
  /// In en, this message translates to:
  /// **'Select Persona'**
  String get select_persona;

  /// No description provided for @manage_personas.
  ///
  /// In en, this message translates to:
  /// **'Manage personas'**
  String get manage_personas;

  /// Hint in persona manager about combining personas
  ///
  /// In en, this message translates to:
  /// **'Select multiple personas in chat to stack their system prompts.'**
  String get personas_combine_hint;

  /// Empty state heading
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get start_conversation;

  /// Recent chats section label
  ///
  /// In en, this message translates to:
  /// **'Recent chats'**
  String get recent_chats;

  /// See all link text
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get see_all;

  /// Quick prompt chip text
  ///
  /// In en, this message translates to:
  /// **'Help me write a function'**
  String get quick_write;

  /// Quick prompt chip text
  ///
  /// In en, this message translates to:
  /// **'Explain this code'**
  String get quick_explain;

  /// Quick prompt chip text
  ///
  /// In en, this message translates to:
  /// **'Debug this for me'**
  String get quick_debug;

  /// Quick prompt chip text
  ///
  /// In en, this message translates to:
  /// **'How do I use async/await?'**
  String get quick_async;

  /// Corrupted chat error title
  ///
  /// In en, this message translates to:
  /// **'History Missing'**
  String get history_missing_title;

  /// Corrupted chat error description
  ///
  /// In en, this message translates to:
  /// **'Either the messages in this chat were deleted or the history record is corrupted.'**
  String get history_missing_desc;

  /// Button for debug details
  ///
  /// In en, this message translates to:
  /// **'Technical Details'**
  String get technical_details;

  /// Diagnostic label
  ///
  /// In en, this message translates to:
  /// **'Last Error:'**
  String get last_error;

  /// Button to copy debug info
  ///
  /// In en, this message translates to:
  /// **'Copy Info'**
  String get copy_info;

  /// Debug row label
  ///
  /// In en, this message translates to:
  /// **'Conversation ID'**
  String get conversation_id;

  /// Debug row label
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get created_at;

  /// Debug row label
  ///
  /// In en, this message translates to:
  /// **'Expected Messages'**
  String get expected_messages;

  /// Debug dialog description
  ///
  /// In en, this message translates to:
  /// **'Diagnostic information to help identify synchronization issues.'**
  String get debug_dialog_desc;

  /// Chat input field hint
  ///
  /// In en, this message translates to:
  /// **'Ask anything'**
  String get chat_input_hint;

  /// Tooltip for send button
  ///
  /// In en, this message translates to:
  /// **'Send message'**
  String get send_message_tooltip;

  /// Tooltip for stop button
  ///
  /// In en, this message translates to:
  /// **'Stop generation'**
  String get stop_generation_tooltip;

  /// Tooltip for attach button
  ///
  /// In en, this message translates to:
  /// **'Attach images or text'**
  String get attach_images_tooltip;

  /// Tooltip for start listening button
  ///
  /// In en, this message translates to:
  /// **'Start listening'**
  String get start_listening_tooltip;

  /// Tooltip for stop listening button
  ///
  /// In en, this message translates to:
  /// **'Stop listening'**
  String get stop_listening_tooltip;

  /// Tool call label in chat bubble
  ///
  /// In en, this message translates to:
  /// **'Tool: {toolCallId}'**
  String tool_label(String toolCallId);

  /// Unknown tool call fallback
  ///
  /// In en, this message translates to:
  /// **'Tool: Unknown'**
  String get tool_unknown;

  /// Message actions sheet title
  ///
  /// In en, this message translates to:
  /// **'Message options'**
  String get message_options;

  /// Copy as markdown option
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get copy_markdown;

  /// Copied as markdown snackbar
  ///
  /// In en, this message translates to:
  /// **'Copied as Markdown'**
  String get copied_markdown;

  /// Read aloud action
  ///
  /// In en, this message translates to:
  /// **'Read Aloud'**
  String get read_aloud;

  /// Stop reading action
  ///
  /// In en, this message translates to:
  /// **'Stop Reading'**
  String get stop_reading;

  /// More actions label
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// Character count display
  ///
  /// In en, this message translates to:
  /// **'{length} characters'**
  String character_count(int length);

  /// Edit message dialog title
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get edit_message;

  /// Edit message dialog description
  ///
  /// In en, this message translates to:
  /// **'Saving will remove the assistant response below and regenerate.'**
  String get edit_message_desc;

  /// Save and regenerate button
  ///
  /// In en, this message translates to:
  /// **'Save & regenerate'**
  String get save_regenerate;

  /// Chat settings sheet title
  ///
  /// In en, this message translates to:
  /// **'Chat Settings'**
  String get chat_settings_title;

  /// Reset to defaults button
  ///
  /// In en, this message translates to:
  /// **'Reset Defaults'**
  String get reset_defaults;

  /// Chat settings parameters tab
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get parameters_tab;

  /// Chat settings MCP tab
  ///
  /// In en, this message translates to:
  /// **'MCP'**
  String get mcp_tab;

  /// Temperature slider label
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get temperature;

  /// Temperature description
  ///
  /// In en, this message translates to:
  /// **'Controls randomness: Higher = Creative, Lower = Focused'**
  String get temperature_desc;

  /// Top P slider label
  ///
  /// In en, this message translates to:
  /// **'Top P'**
  String get top_p;

  /// Top P description
  ///
  /// In en, this message translates to:
  /// **'Nucleus sampling threshold'**
  String get top_p_desc;

  /// Max tokens input label
  ///
  /// In en, this message translates to:
  /// **'Max Tokens'**
  String get max_tokens;

  /// Max tokens description
  ///
  /// In en, this message translates to:
  /// **'Response limit'**
  String get max_tokens_desc;

  /// Context length input label
  ///
  /// In en, this message translates to:
  /// **'Context Length'**
  String get context_length;

  /// Context length description
  ///
  /// In en, this message translates to:
  /// **'History window'**
  String get context_length_desc;

  /// Warning when MCP is disabled
  ///
  /// In en, this message translates to:
  /// **'MCP is disabled globally. Enable it in Settings to use these features.'**
  String get mcp_disabled_warning;

  /// Toggle to enable MCP for current chat
  ///
  /// In en, this message translates to:
  /// **'Enable MCP for this chat'**
  String get mcp_enable_chat;

  /// Toggle for auto-executing tools
  ///
  /// In en, this message translates to:
  /// **'Auto-execute tools'**
  String get auto_execute_tools;

  /// Badge label for beta features
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get beta_label;

  /// Badge label for experimental features
  ///
  /// In en, this message translates to:
  /// **'Experimental'**
  String get experimental_label;

  /// Section label for adding temp MCP server
  ///
  /// In en, this message translates to:
  /// **'Add Ephemeral MCP Server'**
  String get add_ephemeral_mcp;

  /// MCP label field placeholder
  ///
  /// In en, this message translates to:
  /// **'Label'**
  String get mcp_label_placeholder;

  /// MCP URL field placeholder
  ///
  /// In en, this message translates to:
  /// **'URL (https://...)'**
  String get mcp_url_placeholder;

  /// Active MCP integrations section
  ///
  /// In en, this message translates to:
  /// **'Active Integrations'**
  String get active_integrations;

  /// Notification banner title
  ///
  /// In en, this message translates to:
  /// **'Enable Notifications'**
  String get enable_notifications;

  /// Notification banner subtitle
  ///
  /// In en, this message translates to:
  /// **'Get notified when models finish downloading.'**
  String get enable_notifications_desc;

  /// Chat history screen title
  ///
  /// In en, this message translates to:
  /// **'Chat History'**
  String get chat_history_title;

  /// Recent conversation timestamp
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get conversation_just_now;

  /// Minutes ago timestamp
  ///
  /// In en, this message translates to:
  /// **'{minutes}m ago'**
  String conversation_minutes_ago(int minutes);

  /// Hours ago timestamp
  ///
  /// In en, this message translates to:
  /// **'{hours}h ago'**
  String conversation_hours_ago(int hours);

  /// Yesterday timestamp
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get conversation_yesterday;

  /// Days ago timestamp
  ///
  /// In en, this message translates to:
  /// **'{days}d ago'**
  String conversation_days_ago(int days);

  /// Full date timestamp
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}/{year}'**
  String conversation_date(int month, int day, int year);

  /// Options menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options_tooltip;

  /// Search empty state
  ///
  /// In en, this message translates to:
  /// **'No results found'**
  String get no_results_found;

  /// Empty conversations state
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get no_conversations_yet;

  /// Search empty state subtitle
  ///
  /// In en, this message translates to:
  /// **'Try a different search term'**
  String get try_different_search;

  /// Empty state subtitle when no conversations
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation'**
  String get start_new_conversation;

  /// Rename dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename conversation'**
  String get rename_conversation;

  /// Rename text field hint
  ///
  /// In en, this message translates to:
  /// **'Enter new title'**
  String get enter_new_title;

  /// Pinned conversations section header
  ///
  /// In en, this message translates to:
  /// **'PINNED'**
  String get pinned_section;

  /// Today section header
  ///
  /// In en, this message translates to:
  /// **'TODAY'**
  String get today_section;

  /// Yesterday section header
  ///
  /// In en, this message translates to:
  /// **'YESTERDAY'**
  String get yesterday_section;

  /// Previous 7 days section header
  ///
  /// In en, this message translates to:
  /// **'PREVIOUS 7 DAYS'**
  String get previous_7_days;

  /// Previous 30 days section header
  ///
  /// In en, this message translates to:
  /// **'PREVIOUS 30 DAYS'**
  String get previous_30_days;

  /// Older conversations section header
  ///
  /// In en, this message translates to:
  /// **'OLDER'**
  String get older_section;

  /// Onboarding title to select application language
  ///
  /// In en, this message translates to:
  /// **'Choose Language'**
  String get onboarding_choose_language;

  /// Onboarding description for language selection
  ///
  /// In en, this message translates to:
  /// **'Select your preferred language. You can change this anytime in settings.'**
  String get onboarding_choose_language_desc;

  /// Onboarding screen branding text
  ///
  /// In en, this message translates to:
  /// **'LOCALMIND'**
  String get onboarding_localmind;

  /// Onboarding heading for server connection
  ///
  /// In en, this message translates to:
  /// **'Connect Your\nServer'**
  String get onboarding_connect_server;

  /// Onboarding server connection description
  ///
  /// In en, this message translates to:
  /// **'Connect to LM Studio, Ollama, or\nOpenRouter to start your private AI\nexperience.'**
  String get onboarding_connect_desc;

  /// Subtitle for the OpenAI compatible server card in onboarding
  ///
  /// In en, this message translates to:
  /// **'OpenAI-compatible API'**
  String get openai_compatible_api;

  /// Hint shown when a user enters an https URL for a local server
  ///
  /// In en, this message translates to:
  /// **'HTTPS requires SSL'**
  String get https_requires_ssl;

  /// Hint shown with the HTTPS warning chip
  ///
  /// In en, this message translates to:
  /// **'Most local setups use http://'**
  String get most_local_setups_use_http;

  /// Onboarding welcome message
  ///
  /// In en, this message translates to:
  /// **'Welcome to LocalMind'**
  String get onboarding_welcome;

  /// On-device server type card title
  ///
  /// In en, this message translates to:
  /// **'On-Device'**
  String get server_type_on_device;

  /// LM Studio server type card title
  ///
  /// In en, this message translates to:
  /// **'LM Studio'**
  String get server_type_lm_studio;

  /// Ollama server type card title
  ///
  /// In en, this message translates to:
  /// **'Ollama'**
  String get server_type_ollama;

  /// OpenRouter server type card title
  ///
  /// In en, this message translates to:
  /// **'OpenRouter'**
  String get server_type_openrouter;

  /// OpenRouter server type card subtitle
  ///
  /// In en, this message translates to:
  /// **'UNIFIED CLOUD'**
  String get server_type_openrouter_sub;

  /// Onboarding ready status
  ///
  /// In en, this message translates to:
  /// **'READY TO CONTINUE'**
  String get ready_continue;

  /// Onboarding waiting status
  ///
  /// In en, this message translates to:
  /// **'WAITING FOR SELECTION'**
  String get waiting_selection;

  /// Onboarding setup screen title
  ///
  /// In en, this message translates to:
  /// **'Setup Connection'**
  String get setup_connection;

  /// Onboarding setup description
  ///
  /// In en, this message translates to:
  /// **'Configure your {server} server to start chatting.'**
  String setup_connection_desc(String server);

  /// Server name field label
  ///
  /// In en, this message translates to:
  /// **'Server Name'**
  String get server_name;

  /// Validation: name required
  ///
  /// In en, this message translates to:
  /// **'Name required'**
  String get name_required;

  /// Validation: max 50 chars
  ///
  /// In en, this message translates to:
  /// **'Max 50 characters'**
  String get name_max_50;

  /// Host field label
  ///
  /// In en, this message translates to:
  /// **'Host / IP Address'**
  String get host_label;

  /// Validation: host required
  ///
  /// In en, this message translates to:
  /// **'Host required'**
  String get host_required;

  /// Port field label
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get port_label;

  /// Validation: port required
  ///
  /// In en, this message translates to:
  /// **'Port required'**
  String get port_required;

  /// Validation: invalid port number
  ///
  /// In en, this message translates to:
  /// **'Must be a number'**
  String get port_invalid;

  /// Validation: port range
  ///
  /// In en, this message translates to:
  /// **'Enter a valid port (1-65535)'**
  String get port_range;

  /// Required API key label
  ///
  /// In en, this message translates to:
  /// **'API Key *'**
  String get api_key_required;

  /// Optional API key label
  ///
  /// In en, this message translates to:
  /// **'API Key (Optional)'**
  String get api_key_optional;

  /// Validation: API key for OpenRouter
  ///
  /// In en, this message translates to:
  /// **'API Key required for OpenRouter'**
  String get api_key_required_openrouter;

  /// Validation: API key format
  ///
  /// In en, this message translates to:
  /// **'OpenRouter API keys start with sk-'**
  String get api_key_format;

  /// Server name field hint
  ///
  /// In en, this message translates to:
  /// **'My Server'**
  String get my_server_hint;

  /// Validation: name too long
  ///
  /// In en, this message translates to:
  /// **'Name must be 50 characters or less'**
  String get name_length_validation;

  /// Validation: invalid host
  ///
  /// In en, this message translates to:
  /// **'Enter a valid hostname or IP address'**
  String get host_valid;

  /// OpenRouter API key hint
  ///
  /// In en, this message translates to:
  /// **'sk-...'**
  String get api_key_hint_openrouter;

  /// Generic API key hint
  ///
  /// In en, this message translates to:
  /// **'For authenticated servers'**
  String get api_key_hint_generic;

  /// Update server button
  ///
  /// In en, this message translates to:
  /// **'Update Server'**
  String get update_server;

  /// Save server button
  ///
  /// In en, this message translates to:
  /// **'Save Server'**
  String get save_server;

  /// Server update snackbar
  ///
  /// In en, this message translates to:
  /// **'Server updated'**
  String get server_updated;

  /// Server added snackbar
  ///
  /// In en, this message translates to:
  /// **'Server added'**
  String get server_added;

  /// Onboarding download model screen title
  ///
  /// In en, this message translates to:
  /// **'Download a Model'**
  String get download_model_title;

  /// Onboarding download model description
  ///
  /// In en, this message translates to:
  /// **'Choose a model to download.\nIt will run locally on your device.'**
  String get download_model_desc;

  /// Platform limitation notice
  ///
  /// In en, this message translates to:
  /// **'On-device inference is currently available on Android only.'**
  String get on_device_android_only;

  /// Total RAM label
  ///
  /// In en, this message translates to:
  /// **'Total RAM'**
  String get total_ram;

  /// Available label
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// Minimum RAM requirement label
  ///
  /// In en, this message translates to:
  /// **'{fileSize} GB RAM min'**
  String ram_min_required(String fileSize);

  /// Download progress display
  ///
  /// In en, this message translates to:
  /// **'{percent}% • {speed}'**
  String download_progress(String percent, String speed);

  /// Estimated time remaining label
  ///
  /// In en, this message translates to:
  /// **'ETA: {eta}'**
  String eta_label(String eta);

  /// Paused download status with progress
  ///
  /// In en, this message translates to:
  /// **'Paused - {percent}%'**
  String paused_progress(String percent);

  /// RAM warning during download
  ///
  /// In en, this message translates to:
  /// **'This model requires at least {ram} GB RAM, but your device has {totalMemory}. It may not run correctly or could cause the app to crash.'**
  String ram_warning_body_download(String ram, String totalMemory);

  /// RAM warning during model load
  ///
  /// In en, this message translates to:
  /// **'Your device has {availableRAM} available RAM, but this model recommends at least {ram} GB. Loading it might fail or cause instability.'**
  String ram_warning_body_load(String availableRAM, String ram);

  /// Onboarding theme selection title
  ///
  /// In en, this message translates to:
  /// **'Choose Theme'**
  String get choose_theme;

  /// Onboarding theme selection description
  ///
  /// In en, this message translates to:
  /// **'Personalize the app appearance. You can always change this later in settings.'**
  String get choose_theme_desc;

  /// System theme card title
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get theme_card_system;

  /// System theme card subtitle
  ///
  /// In en, this message translates to:
  /// **'Matches your device settings'**
  String get theme_card_system_sub;

  /// Light theme card title
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get theme_card_light;

  /// Light theme card subtitle
  ///
  /// In en, this message translates to:
  /// **'Clean and bright'**
  String get theme_card_light_sub;

  /// Dark theme card title
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get theme_card_dark;

  /// Dark theme card subtitle
  ///
  /// In en, this message translates to:
  /// **'Easy on the eyes'**
  String get theme_card_dark_sub;

  /// Claude theme card title
  ///
  /// In en, this message translates to:
  /// **'Claude'**
  String get theme_card_claude;

  /// Claude theme card subtitle
  ///
  /// In en, this message translates to:
  /// **'A warm, peach-tinted theme'**
  String get theme_card_claude_sub;

  /// Onboarding notification screen heading
  ///
  /// In en, this message translates to:
  /// **'Stay Updated'**
  String get stay_updated;

  /// Onboarding notification screen description
  ///
  /// In en, this message translates to:
  /// **'Get notified when your AI models finish downloading or when long-running tasks complete.'**
  String get stay_updated_desc;

  /// Notification benefit list item
  ///
  /// In en, this message translates to:
  /// **'Model download progress'**
  String get notification_benefit_downloads;

  /// Notification benefit list item
  ///
  /// In en, this message translates to:
  /// **'Generation completions'**
  String get notification_benefit_completions;

  /// Notification benefit list item
  ///
  /// In en, this message translates to:
  /// **'Background tasks status'**
  String get notification_benefit_background;

  /// Allow notifications button
  ///
  /// In en, this message translates to:
  /// **'Allow Notifications'**
  String get allow_notifications;

  /// Server list screen title
  ///
  /// In en, this message translates to:
  /// **'Servers'**
  String get servers_title;

  /// Empty server list title
  ///
  /// In en, this message translates to:
  /// **'No Servers Yet'**
  String get no_servers_yet;

  /// Empty server list description
  ///
  /// In en, this message translates to:
  /// **'Add your first server to start chatting with AI models.'**
  String get no_servers_desc;

  /// Add server button
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get add_server;

  /// Server switch snackbar
  ///
  /// In en, this message translates to:
  /// **'Switched to {name}'**
  String switched_to_server(String name);

  /// Edit server screen title
  ///
  /// In en, this message translates to:
  /// **'Edit Server'**
  String get edit_server;

  /// Add server screen title
  ///
  /// In en, this message translates to:
  /// **'Add Server'**
  String get add_server_title;

  /// Server type section label
  ///
  /// In en, this message translates to:
  /// **'Server Type'**
  String get server_type_label;

  /// Server icon section label
  ///
  /// In en, this message translates to:
  /// **'Server Icon'**
  String get server_icon_label;

  /// Default icon fallback text
  ///
  /// In en, this message translates to:
  /// **'Default icon'**
  String get default_icon;

  /// LM Studio server type display
  ///
  /// In en, this message translates to:
  /// **'LM Studio'**
  String get server_type_lm_studio_display;

  /// OpenAI compatible server type display
  ///
  /// In en, this message translates to:
  /// **'OpenAI Compatible'**
  String get server_type_openai_display;

  /// Ollama server type display
  ///
  /// In en, this message translates to:
  /// **'Ollama'**
  String get server_type_ollama_display;

  /// OpenRouter server type display
  ///
  /// In en, this message translates to:
  /// **'OpenRouter'**
  String get server_type_openrouter_display;

  /// On-device server type display
  ///
  /// In en, this message translates to:
  /// **'On-Device'**
  String get server_type_on_device_display;

  /// OpenRouter default address
  ///
  /// In en, this message translates to:
  /// **'openrouter.ai'**
  String get server_address_openrouter;

  /// On-device server address
  ///
  /// In en, this message translates to:
  /// **'Local inference'**
  String get server_address_on_device;

  /// Server address display format
  ///
  /// In en, this message translates to:
  /// **'{host}:{port}'**
  String server_address_format(String host, String port);

  /// Default server badge
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get default_badge;

  /// Set as default menu item
  ///
  /// In en, this message translates to:
  /// **'Set as Default'**
  String get set_as_default;

  /// Icon picker sheet title
  ///
  /// In en, this message translates to:
  /// **'Select Icon'**
  String get select_icon;

  /// Icon picker sheet description
  ///
  /// In en, this message translates to:
  /// **'Choose an icon for your server'**
  String get select_icon_desc;

  /// Icon search field placeholder
  ///
  /// In en, this message translates to:
  /// **'Search icons...'**
  String get search_icons_hint;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Server Stack'**
  String get server_icon_stack;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Server Stack 02'**
  String get server_icon_stack2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Server Stack 03'**
  String get server_icon_stack3;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Cloud'**
  String get server_icon_cloud;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Cloud Server'**
  String get server_icon_cloud_server;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'MCP Server'**
  String get server_icon_mcp;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get server_icon_database;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Database 01'**
  String get server_icon_database1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Database 02'**
  String get server_icon_database2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get server_icon_cpu;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Chip'**
  String get server_icon_chip;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Chip 02'**
  String get server_icon_chip2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Computer'**
  String get server_icon_computer;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Laptop'**
  String get server_icon_laptop;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Computer Terminal'**
  String get server_icon_terminal;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get server_icon_code;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'AI Brain'**
  String get server_icon_ai_brain;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'AI Brain 02'**
  String get server_icon_ai_brain2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'AI Cloud'**
  String get server_icon_ai_cloud;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'AI Network'**
  String get server_icon_ai_network;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'AI Chat'**
  String get server_icon_ai_chat;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Cellular Network'**
  String get server_icon_cellular;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Plug 01'**
  String get server_icon_plug1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Plug 02'**
  String get server_icon_plug2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Bot'**
  String get server_icon_bot;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Bot 02'**
  String get server_icon_bot2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Robotic'**
  String get server_icon_robotic;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Rocket'**
  String get server_icon_rocket;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Star'**
  String get server_icon_star;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Settings 01'**
  String get server_icon_settings1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Settings 02'**
  String get server_icon_settings2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Home 01'**
  String get server_icon_home1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Home 02'**
  String get server_icon_home2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Folder 01'**
  String get server_icon_folder1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Folder 02'**
  String get server_icon_folder2;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'File 01'**
  String get server_icon_file1;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Lock'**
  String get server_icon_lock;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Key 01'**
  String get server_icon_key;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Link 01'**
  String get server_icon_link;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Globe'**
  String get server_icon_globe;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'API'**
  String get server_icon_api;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Arrow Right 01'**
  String get server_icon_arrow_right;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Check Circle'**
  String get server_icon_check;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Alert Circle'**
  String get server_icon_alert;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Info Circle'**
  String get server_icon_info;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Zap'**
  String get server_icon_zap;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Cloud Upload'**
  String get server_icon_cloud_upload;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Cloud Download'**
  String get server_icon_cloud_download;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get server_icon_refresh;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Hard Drive'**
  String get server_icon_hard_drive;

  /// Server icon name
  ///
  /// In en, this message translates to:
  /// **'Drive'**
  String get server_icon_drive;

  /// Persona list screen title
  ///
  /// In en, this message translates to:
  /// **'Personas'**
  String get personas_title;

  /// General persona category
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get persona_category_general;

  /// Coding persona category
  ///
  /// In en, this message translates to:
  /// **'Coding'**
  String get persona_category_coding;

  /// Education persona category
  ///
  /// In en, this message translates to:
  /// **'Education'**
  String get persona_category_education;

  /// Creative persona category
  ///
  /// In en, this message translates to:
  /// **'Creative'**
  String get persona_category_creative;

  /// Built-in personas section label
  ///
  /// In en, this message translates to:
  /// **'BUILT-IN'**
  String get persona_builtin_section;

  /// My personas section label
  ///
  /// In en, this message translates to:
  /// **'MY PERSONAS'**
  String get persona_my_section;

  /// Clone and edit persona action
  ///
  /// In en, this message translates to:
  /// **'Clone & Edit'**
  String get clone_edit;

  /// Built-in persona badge
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get builtin_badge;

  /// Empty persona list title
  ///
  /// In en, this message translates to:
  /// **'No personas found'**
  String get no_personas_found;

  /// Empty persona list subtitle
  ///
  /// In en, this message translates to:
  /// **'Create your first persona to customize AI behavior.'**
  String get no_personas_desc;

  /// Edit persona screen title
  ///
  /// In en, this message translates to:
  /// **'Edit Persona'**
  String get edit_persona;

  /// Create persona screen title
  ///
  /// In en, this message translates to:
  /// **'Create Persona'**
  String get create_persona;

  /// Create persona action button
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create_persona_button;

  /// Emoji selection label
  ///
  /// In en, this message translates to:
  /// **'Emoji'**
  String get emoji_label;

  /// Name field label
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name_label;

  /// Persona name hint
  ///
  /// In en, this message translates to:
  /// **'My Persona'**
  String get my_persona_hint;

  /// Category field label
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category_label;

  /// Optional description label
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get description_optional;

  /// Description field hint
  ///
  /// In en, this message translates to:
  /// **'What this persona does...'**
  String get description_hint;

  /// System prompt section label
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get system_prompt;

  /// Character counter for system prompt
  ///
  /// In en, this message translates to:
  /// **'{currentLen}/4000'**
  String character_count_max(int currentLen);

  /// Preview placeholder when no prompt
  ///
  /// In en, this message translates to:
  /// **'No prompt yet...'**
  String get no_prompt_placeholder;

  /// System prompt text field hint
  ///
  /// In en, this message translates to:
  /// **'You are a helpful assistant...'**
  String get prompt_hint;

  /// Validation: prompt required
  ///
  /// In en, this message translates to:
  /// **'System prompt is required'**
  String get prompt_required;

  /// Validation: prompt max chars
  ///
  /// In en, this message translates to:
  /// **'Max 4000 characters'**
  String get prompt_max_chars;

  /// Expandable advanced settings section
  ///
  /// In en, this message translates to:
  /// **'Advanced Settings'**
  String get advanced_settings;

  /// Temperature field label in personas
  ///
  /// In en, this message translates to:
  /// **'Temperature (0.0-2.0)'**
  String get temperature_label;

  /// Top P field label in personas
  ///
  /// In en, this message translates to:
  /// **'Top P (0.0-1.0)'**
  String get top_p_label;

  /// Temperature field hint
  ///
  /// In en, this message translates to:
  /// **'0.7'**
  String get temp_hint;

  /// Top P field hint
  ///
  /// In en, this message translates to:
  /// **'0.9'**
  String get top_p_hint;

  /// Range validation error (temperature)
  ///
  /// In en, this message translates to:
  /// **'0.0-2.0'**
  String get range_0_2;

  /// Range validation error (top P)
  ///
  /// In en, this message translates to:
  /// **'0.0-1.0'**
  String get range_0_1;

  /// Persona update snackbar
  ///
  /// In en, this message translates to:
  /// **'Persona updated'**
  String get persona_updated;

  /// Persona creation snackbar
  ///
  /// In en, this message translates to:
  /// **'Persona created'**
  String get persona_created;

  /// TTS model manager screen title
  ///
  /// In en, this message translates to:
  /// **'Text To Speech Models'**
  String get tts_models_title;

  /// Always available status
  ///
  /// In en, this message translates to:
  /// **'Always available'**
  String get always_available;

  /// System TTS engine description
  ///
  /// In en, this message translates to:
  /// **'Uses your device\'s built-in text-to-speech engine.\nNo downloads required. Voice selection uses your device\'s system settings.'**
  String get tts_system_desc;

  /// Downloading status text
  ///
  /// In en, this message translates to:
  /// **'Downloading...'**
  String get downloading_status;

  /// Kitten TTS engine description
  ///
  /// In en, this message translates to:
  /// **'Lightning-fast neural TTS with 8 expressive voices.\nRequires {size} download.'**
  String tts_kitten_desc(String size);

  /// Piper TTS engine description
  ///
  /// In en, this message translates to:
  /// **'Fast offline Piper voices with 2 expressive voices.\nRequires {size} download per voice.'**
  String tts_piper_desc(String size);

  /// Engine specification display
  ///
  /// In en, this message translates to:
  /// **'{sizeMb} MB · {ramMb} MB RAM · {voiceCount} voices'**
  String engine_spec(String sizeMb, String ramMb, int voiceCount);

  /// On-device model manager screen title
  ///
  /// In en, this message translates to:
  /// **'On-Device Models'**
  String get on_device_models_title;

  /// Settings field label for an optional Hugging Face access token
  ///
  /// In en, this message translates to:
  /// **'Hugging Face Token (Optional)'**
  String get settings_huggingface_token;

  /// Description for the Hugging Face token setting
  ///
  /// In en, this message translates to:
  /// **'Required only for gated models (e.g. Gemma). Get a token at huggingface.co/settings/tokens.'**
  String get settings_huggingface_token_desc;

  /// Toast text after a Hugging Face token is saved
  ///
  /// In en, this message translates to:
  /// **'Token saved'**
  String get settings_huggingface_token_set;

  /// Toast text after a Hugging Face token is cleared
  ///
  /// In en, this message translates to:
  /// **'Token cleared'**
  String get settings_huggingface_token_cleared;

  /// Badge on a model that is gated on Hugging Face
  ///
  /// In en, this message translates to:
  /// **'Requires a Hugging Face token'**
  String get model_requires_huggingface_token;

  /// Inline warning shown when a gated model download is attempted without a token
  ///
  /// In en, this message translates to:
  /// **'This model is gated on Hugging Face. Add a token in Settings → On-Device Inference to download it.'**
  String get model_missing_huggingface_token;

  /// Button label to set/edit a Hugging Face token
  ///
  /// In en, this message translates to:
  /// **'Set token'**
  String get set_huggingface_token;

  /// Button label to clear a saved Hugging Face token
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear_huggingface_token;

  /// Title of the dialog for entering a Hugging Face token
  ///
  /// In en, this message translates to:
  /// **'Hugging Face Access Token'**
  String get edit_huggingface_token_dialog_title;

  /// Placeholder for the Hugging Face token input field
  ///
  /// In en, this message translates to:
  /// **'hf_…'**
  String get huggingface_token_dialog_hint;

  /// Short description for the Ollama server type
  ///
  /// In en, this message translates to:
  /// **'Local AI engine. No API key required.'**
  String get server_type_ollama_desc;

  /// Short description for the On-Device server type
  ///
  /// In en, this message translates to:
  /// **'Runs on your phone. Some models need a Hugging Face token.'**
  String get server_type_on_device_desc;

  /// Short description for the LM Studio server type
  ///
  /// In en, this message translates to:
  /// **'Local API server. No API key required.'**
  String get server_type_lm_studio_desc;

  /// Available models section title
  ///
  /// In en, this message translates to:
  /// **'Available Models'**
  String get available_models;

  /// Device memory card title
  ///
  /// In en, this message translates to:
  /// **'Device Memory'**
  String get device_memory;

  /// RAM usage label
  ///
  /// In en, this message translates to:
  /// **'RAM Usage'**
  String get ram_usage;

  /// Memory status healthy
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get memory_healthy;

  /// Memory status critical
  ///
  /// In en, this message translates to:
  /// **'Critical'**
  String get memory_critical;

  /// Memory status low
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get memory_low;

  /// RAM usage percentage
  ///
  /// In en, this message translates to:
  /// **'{percent}% used'**
  String ram_used(String percent);

  /// Available RAM stat label
  ///
  /// In en, this message translates to:
  /// **'Available RAM'**
  String get available_ram;

  /// Total capacity stat label
  ///
  /// In en, this message translates to:
  /// **'Total Capacity'**
  String get total_capacity;

  /// Model loaded status
  ///
  /// In en, this message translates to:
  /// **'Loaded'**
  String get loaded_status;

  /// Backend selector section title
  ///
  /// In en, this message translates to:
  /// **'Inference Backend'**
  String get inference_backend;

  /// iOS backend limitation notice
  ///
  /// In en, this message translates to:
  /// **'Only CPU backend is available on iOS.'**
  String get backend_ios_notice;

  /// CPU backend description
  ///
  /// In en, this message translates to:
  /// **'Works on all devices. Most compatible.'**
  String get backend_cpu_desc;

  /// GPU backend description
  ///
  /// In en, this message translates to:
  /// **'OpenCL acceleration. Faster on supported devices.'**
  String get backend_gpu_desc;

  /// NPU backend description
  ///
  /// In en, this message translates to:
  /// **'Vendor NPU (Qualcomm/MediaTek). Fastest inference.'**
  String get backend_npu_desc;

  /// Model picker sheet title
  ///
  /// In en, this message translates to:
  /// **'Select Model'**
  String get select_model_title;

  /// Refresh models tooltip
  ///
  /// In en, this message translates to:
  /// **'Refresh models'**
  String get refresh_models;

  /// Model search field hint
  ///
  /// In en, this message translates to:
  /// **'Search models...'**
  String get search_models_hint;

  /// Model picker empty state title
  ///
  /// In en, this message translates to:
  /// **'No server connected'**
  String get no_server_connected;

  /// Model picker empty state subtitle
  ///
  /// In en, this message translates to:
  /// **'Add a server first to see available models.'**
  String get add_server_first;

  /// Model load error title
  ///
  /// In en, this message translates to:
  /// **'Failed to load models'**
  String get failed_load_models;

  /// Empty models state
  ///
  /// In en, this message translates to:
  /// **'No models available'**
  String get no_models_available;

  /// No search results for models
  ///
  /// In en, this message translates to:
  /// **'No models match \"{searchQuery}\"'**
  String no_models_match(String searchQuery);

  /// Model load failure snackbar
  ///
  /// In en, this message translates to:
  /// **'Failed to load model: {error}'**
  String model_load_failed(String error);

  /// Ollama model unloaded status
  ///
  /// In en, this message translates to:
  /// **'Unload requested for {name}. If Ollama is reachable, the model is released immediately.'**
  String model_unloaded_ollama(String name);

  /// Model unloaded success snackbar
  ///
  /// In en, this message translates to:
  /// **'{name} unloaded successfully'**
  String model_unloaded_success(String name);

  /// Model unload failure snackbar
  ///
  /// In en, this message translates to:
  /// **'Failed to unload model: {error}'**
  String model_unload_failed(String error);

  /// Unload model tooltip
  ///
  /// In en, this message translates to:
  /// **'Unload from server'**
  String get unload_from_server;

  /// Context length chip
  ///
  /// In en, this message translates to:
  /// **'{ctx} ctx'**
  String context_chip(String ctx);

  /// Button to unload all loaded models
  ///
  /// In en, this message translates to:
  /// **'Unload all'**
  String get unload_all_models;

  /// Count of currently loaded models
  ///
  /// In en, this message translates to:
  /// **'{count} loaded'**
  String loaded_models_count(int count);

  /// Snackbar after unloading all models
  ///
  /// In en, this message translates to:
  /// **'All models unloaded'**
  String get all_models_unloaded;

  /// Branch conversation from a message
  ///
  /// In en, this message translates to:
  /// **'Branch chat'**
  String get branch_chat;

  /// Branch chat option description
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation from this message'**
  String get branch_chat_desc;

  /// Description shown when editing an assistant message
  ///
  /// In en, this message translates to:
  /// **'Edit the assistant response text.'**
  String get edit_assistant_message_desc;

  /// Tooltip for switching to the model used in a message
  ///
  /// In en, this message translates to:
  /// **'Switch to {modelName}'**
  String switch_to_model(String modelName);

  /// Download notification title
  ///
  /// In en, this message translates to:
  /// **'Downloading {modelName}...'**
  String download_notification_title(String modelName);

  /// Download complete notification title
  ///
  /// In en, this message translates to:
  /// **'Download complete!'**
  String get download_complete_notification;

  /// Download complete notification body
  ///
  /// In en, this message translates to:
  /// **'{modelName} has been downloaded successfully.'**
  String download_complete_body(String modelName);

  /// Download failed notification title
  ///
  /// In en, this message translates to:
  /// **'Download failed: {error}'**
  String download_failed_notification(String error);

  /// Download failed notification body
  ///
  /// In en, this message translates to:
  /// **'Failed to download {modelName}.'**
  String download_failed_body(String modelName);

  /// System TTS engine display name
  ///
  /// In en, this message translates to:
  /// **'System TTS'**
  String get engine_name_system;

  /// System TTS engine tagline
  ///
  /// In en, this message translates to:
  /// **'Built-in device engine'**
  String get engine_tagline_system;

  /// Kitten TTS engine display name
  ///
  /// In en, this message translates to:
  /// **'Kitten TTS'**
  String get engine_name_kitten;

  /// Kitten TTS engine tagline
  ///
  /// In en, this message translates to:
  /// **'High-speed neural TTS'**
  String get engine_tagline_kitten;

  /// Sherpa ONNX engine display name
  ///
  /// In en, this message translates to:
  /// **'Sherpa ONNX VITS'**
  String get engine_name_sherpa;

  /// Sherpa ONNX engine tagline
  ///
  /// In en, this message translates to:
  /// **'Offline Piper voices'**
  String get engine_tagline_sherpa;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Jasper'**
  String get voice_jasper;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Bella'**
  String get voice_bella;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Bruno'**
  String get voice_bruno;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Luna'**
  String get voice_luna;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Hugo'**
  String get voice_hugo;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Rosie'**
  String get voice_rosie;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Leo'**
  String get voice_leo;

  /// Kitten TTS voice name
  ///
  /// In en, this message translates to:
  /// **'Kiki'**
  String get voice_kiki;

  /// Piper voice name
  ///
  /// In en, this message translates to:
  /// **'Lessac (US)'**
  String get voice_lessac;

  /// Piper voice name
  ///
  /// In en, this message translates to:
  /// **'Ryan (US)'**
  String get voice_ryan;

  /// On-device model name
  ///
  /// In en, this message translates to:
  /// **'Qwen 3 0.6B'**
  String get model_qwen_3;

  /// Qwen 3 model description
  ///
  /// In en, this message translates to:
  /// **'Smallest general-purpose chat model. Fast responses, low memory usage.'**
  String get model_qwen_3_desc;

  /// Apache license label
  ///
  /// In en, this message translates to:
  /// **'Apache-2.0'**
  String get model_license_apache;

  /// On-device model name
  ///
  /// In en, this message translates to:
  /// **'Qwen 2.5 1.5B Instruct'**
  String get model_qwen_25;

  /// Qwen 2.5 model description
  ///
  /// In en, this message translates to:
  /// **'Balanced quality and size. Good for general conversation.'**
  String get model_qwen_25_desc;

  /// On-device model name
  ///
  /// In en, this message translates to:
  /// **'DeepSeek R1 Distill Qwen 1.5B'**
  String get model_deepseek;

  /// DeepSeek model description
  ///
  /// In en, this message translates to:
  /// **'Reasoning and chain-of-thought model. Best for logical tasks.'**
  String get model_deepseek_desc;

  /// MIT license label
  ///
  /// In en, this message translates to:
  /// **'MIT'**
  String get model_license_mit;

  /// On-device model name
  ///
  /// In en, this message translates to:
  /// **'Gemma 4 E2B Instruct'**
  String get model_gemma;

  /// Gemma model description
  ///
  /// In en, this message translates to:
  /// **'Google flagship model. Highest quality, requires more RAM.'**
  String get model_gemma_desc;

  /// Markdown export header
  ///
  /// In en, this message translates to:
  /// **'*Exported from LocalMind — {date}*'**
  String export_header(String date);

  /// Markdown export user role label
  ///
  /// In en, this message translates to:
  /// **'## 👤 User'**
  String get export_role_user;

  /// Markdown export assistant role label
  ///
  /// In en, this message translates to:
  /// **'## 🤖 Assistant'**
  String get export_role_assistant;

  /// Markdown export system role label
  ///
  /// In en, this message translates to:
  /// **'## ⚙️ System'**
  String get export_role_system;

  /// Markdown export tool role label
  ///
  /// In en, this message translates to:
  /// **'## 🔧 Tool'**
  String get export_role_tool;

  /// Text export user role prefix
  ///
  /// In en, this message translates to:
  /// **'[USER]'**
  String get export_text_user;

  /// Text export assistant role prefix
  ///
  /// In en, this message translates to:
  /// **'[ASSISTANT]'**
  String get export_text_assistant;

  /// Text export system role prefix
  ///
  /// In en, this message translates to:
  /// **'[SYSTEM]'**
  String get export_text_system;

  /// Text export tool role prefix
  ///
  /// In en, this message translates to:
  /// **'[TOOL]'**
  String get export_text_tool;

  /// Export user role label
  ///
  /// In en, this message translates to:
  /// **'USER'**
  String get export_label_user;

  /// Export assistant role label
  ///
  /// In en, this message translates to:
  /// **'ASSISTANT'**
  String get export_label_assistant;

  /// Export system role label
  ///
  /// In en, this message translates to:
  /// **'SYSTEM'**
  String get export_label_system;

  /// Export tool role label
  ///
  /// In en, this message translates to:
  /// **'TOOL'**
  String get export_label_tool;

  /// Fallback text when no model is selected
  ///
  /// In en, this message translates to:
  /// **'Select a model to start chatting'**
  String get select_model_hint;

  /// Test notification title
  ///
  /// In en, this message translates to:
  /// **'Test notification'**
  String get test_notification_title;

  /// Test notification body
  ///
  /// In en, this message translates to:
  /// **'This is a test notification for model download progress.'**
  String get test_notification_body;

  /// TTS background playback support status
  ///
  /// In en, this message translates to:
  /// **'Supports background playback as native audio'**
  String get tts_supports_background;

  /// TTS background playback support status
  ///
  /// In en, this message translates to:
  /// **'Note: The other TTS services support background playback as native audio.'**
  String get tts_other_services_background_note;

  /// No description provided for @gguf_imported_models_title.
  ///
  /// In en, this message translates to:
  /// **'Imported GGUF models'**
  String get gguf_imported_models_title;

  /// No description provided for @gguf_imported_models_empty_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Import a GGUF from your device or add one from Hugging Face. Imported models run locally with llama.cpp.'**
  String get gguf_imported_models_empty_subtitle;

  /// No description provided for @gguf_imported_models_ready.
  ///
  /// In en, this message translates to:
  /// **'imported models ready for local inference.'**
  String get gguf_imported_models_ready;

  /// No description provided for @gguf_curated_models_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Curated on-device models you can download and manage inside LocalMind.'**
  String get gguf_curated_models_subtitle;

  /// No description provided for @gguf_only_supported.
  ///
  /// In en, this message translates to:
  /// **'Only GGUF models are supported for this import.'**
  String get gguf_only_supported;

  /// No description provided for @gguf_imported_from_local_file.
  ///
  /// In en, this message translates to:
  /// **'imported from local file.'**
  String get gguf_imported_from_local_file;

  /// No description provided for @gguf_import_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed to import GGUF model'**
  String get gguf_import_failed;

  /// No description provided for @gguf_imported_from_huggingface.
  ///
  /// In en, this message translates to:
  /// **'imported from Hugging Face.'**
  String get gguf_imported_from_huggingface;

  /// No description provided for @gguf_import_canceled.
  ///
  /// In en, this message translates to:
  /// **'GGUF import canceled.'**
  String get gguf_import_canceled;

  /// No description provided for @gguf_enter_huggingface_url.
  ///
  /// In en, this message translates to:
  /// **'Enter a Hugging Face GGUF URL.'**
  String get gguf_enter_huggingface_url;

  /// No description provided for @gguf_only_official_huggingface_urls.
  ///
  /// In en, this message translates to:
  /// **'Only official Hugging Face GGUF URLs are supported.'**
  String get gguf_only_official_huggingface_urls;

  /// No description provided for @gguf_use_https_url.
  ///
  /// In en, this message translates to:
  /// **'Use an HTTPS Hugging Face URL for GGUF import.'**
  String get gguf_use_https_url;

  /// No description provided for @gguf_url_must_point_to_file.
  ///
  /// In en, this message translates to:
  /// **'The Hugging Face URL must point directly to a .gguf file.'**
  String get gguf_url_must_point_to_file;

  /// No description provided for @gguf_unable_to_detect_file_name.
  ///
  /// In en, this message translates to:
  /// **'Unable to determine the GGUF file name.'**
  String get gguf_unable_to_detect_file_name;

  /// No description provided for @gguf_download_empty.
  ///
  /// In en, this message translates to:
  /// **'The downloaded GGUF file was empty or missing.'**
  String get gguf_download_empty;

  /// No description provided for @gguf_selected_file_missing.
  ///
  /// In en, this message translates to:
  /// **'Selected model file does not exist.'**
  String get gguf_selected_file_missing;

  /// No description provided for @gguf_import_action.
  ///
  /// In en, this message translates to:
  /// **'Import GGUF'**
  String get gguf_import_action;

  /// No description provided for @gguf_overview_title.
  ///
  /// In en, this message translates to:
  /// **'Bring your own GGUF models'**
  String get gguf_overview_title;

  /// No description provided for @gguf_overview_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Import a .gguf from local storage or download one straight from Hugging Face. Imported models stay on this device and load with llama.cpp.'**
  String get gguf_overview_subtitle;

  /// No description provided for @gguf_imported_count_label.
  ///
  /// In en, this message translates to:
  /// **'imported'**
  String get gguf_imported_count_label;

  /// No description provided for @gguf_local_files_label.
  ///
  /// In en, this message translates to:
  /// **'local files'**
  String get gguf_local_files_label;

  /// No description provided for @gguf_huggingface_label.
  ///
  /// In en, this message translates to:
  /// **'Hugging Face'**
  String get gguf_huggingface_label;

  /// No description provided for @gguf_import_local_title.
  ///
  /// In en, this message translates to:
  /// **'Import local GGUF'**
  String get gguf_import_local_title;

  /// No description provided for @gguf_import_local_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Copy a .gguf file from this device'**
  String get gguf_import_local_subtitle;

  /// No description provided for @gguf_import_huggingface_title.
  ///
  /// In en, this message translates to:
  /// **'Import from Hugging Face'**
  String get gguf_import_huggingface_title;

  /// No description provided for @gguf_import_huggingface_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a GGUF URL or repo path'**
  String get gguf_import_huggingface_subtitle;

  /// No description provided for @gguf_no_imported_title.
  ///
  /// In en, this message translates to:
  /// **'No imported GGUF models yet'**
  String get gguf_no_imported_title;

  /// No description provided for @gguf_no_imported_subtitle.
  ///
  /// In en, this message translates to:
  /// **'You can bring your own GGUF file from device storage or paste a Hugging Face URL or repo path that points to a .gguf file.'**
  String get gguf_no_imported_subtitle;

  /// No description provided for @gguf_import_huggingface_dialog_title.
  ///
  /// In en, this message translates to:
  /// **'Import GGUF from Hugging Face'**
  String get gguf_import_huggingface_dialog_title;

  /// No description provided for @gguf_import_huggingface_dialog_subtitle.
  ///
  /// In en, this message translates to:
  /// **'Paste a direct GGUF URL or a Hugging Face repo path like `owner/repo/blob/main/model.gguf`. Blob links are converted automatically.'**
  String get gguf_import_huggingface_dialog_subtitle;

  /// No description provided for @gguf_url_or_repo_path.
  ///
  /// In en, this message translates to:
  /// **'GGUF URL or repo path'**
  String get gguf_url_or_repo_path;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @gguf_browse.
  ///
  /// In en, this message translates to:
  /// **'Browse GGUFs'**
  String get gguf_browse;

  /// No description provided for @gguf_huggingface_token_ready.
  ///
  /// In en, this message translates to:
  /// **'Hugging Face token ready'**
  String get gguf_huggingface_token_ready;

  /// No description provided for @gguf_huggingface_token_optional.
  ///
  /// In en, this message translates to:
  /// **'Token optional but recommended'**
  String get gguf_huggingface_token_optional;

  /// No description provided for @gguf_huggingface_token_ready_desc.
  ///
  /// In en, this message translates to:
  /// **'Your saved token will be used automatically for gated or private repositories.'**
  String get gguf_huggingface_token_ready_desc;

  /// No description provided for @gguf_huggingface_token_optional_desc.
  ///
  /// In en, this message translates to:
  /// **'Requires a Hugging Face token. Add one in Settings if this GGUF is gated or private.'**
  String get gguf_huggingface_token_optional_desc;

  /// No description provided for @gguf_downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading GGUF'**
  String get gguf_downloading;

  /// No description provided for @gguf_preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get gguf_preparing;

  /// No description provided for @gguf_preparing_download.
  ///
  /// In en, this message translates to:
  /// **'Preparing download...'**
  String get gguf_preparing_download;

  /// No description provided for @gguf_cancel_import.
  ///
  /// In en, this message translates to:
  /// **'Cancel import'**
  String get gguf_cancel_import;

  /// No description provided for @clipboard_empty.
  ///
  /// In en, this message translates to:
  /// **'Clipboard is empty.'**
  String get clipboard_empty;

  /// No description provided for @could_not_open_huggingface.
  ///
  /// In en, this message translates to:
  /// **'Could not open Hugging Face.'**
  String get could_not_open_huggingface;

  /// No description provided for @gguf_paste_url_error.
  ///
  /// In en, this message translates to:
  /// **'Paste a Hugging Face GGUF URL or repo path.'**
  String get gguf_paste_url_error;

  /// No description provided for @gguf_blob_link.
  ///
  /// In en, this message translates to:
  /// **'Blob link'**
  String get gguf_blob_link;

  /// No description provided for @gguf_repository_label.
  ///
  /// In en, this message translates to:
  /// **'Repository'**
  String get gguf_repository_label;

  /// No description provided for @gguf_detected_path_label.
  ///
  /// In en, this message translates to:
  /// **'Detected path'**
  String get gguf_detected_path_label;

  /// No description provided for @gguf_imported_section_label.
  ///
  /// In en, this message translates to:
  /// **'Imported GGUF'**
  String get gguf_imported_section_label;

  /// No description provided for @gguf_already_available.
  ///
  /// In en, this message translates to:
  /// **'Already available on this device'**
  String get gguf_already_available;

  /// No description provided for @gguf_curated_models_short.
  ///
  /// In en, this message translates to:
  /// **'Curated on-device models'**
  String get gguf_curated_models_short;

  /// No description provided for @execute_tool_title.
  ///
  /// In en, this message translates to:
  /// **'Execute Tool'**
  String get execute_tool_title;

  /// No description provided for @execute_tool_request_desc.
  ///
  /// In en, this message translates to:
  /// **'The model is requesting to execute the following tool:'**
  String get execute_tool_request_desc;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @server_type_help.
  ///
  /// In en, this message translates to:
  /// **'Pick the provider before filling connection details.'**
  String get server_type_help;

  /// No description provided for @server_identity_title.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get server_identity_title;

  /// No description provided for @server_identity_desc.
  ///
  /// In en, this message translates to:
  /// **'Name this server and choose how it appears in the list.'**
  String get server_identity_desc;

  /// No description provided for @server_connection_title.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get server_connection_title;

  /// No description provided for @server_connection_desc.
  ///
  /// In en, this message translates to:
  /// **'Use the address and port exposed by your server.'**
  String get server_connection_desc;

  /// No description provided for @server_authentication_title.
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get server_authentication_title;

  /// No description provided for @server_authentication_required_desc.
  ///
  /// In en, this message translates to:
  /// **'OpenRouter requires an API key before testing.'**
  String get server_authentication_required_desc;

  /// No description provided for @server_authentication_optional_desc.
  ///
  /// In en, this message translates to:
  /// **'Leave the API key empty if this server does not require one.'**
  String get server_authentication_optional_desc;

  /// No description provided for @mcp_tools_title.
  ///
  /// In en, this message translates to:
  /// **'MCP Tools'**
  String get mcp_tools_title;

  /// No description provided for @available_tools.
  ///
  /// In en, this message translates to:
  /// **'Available tools'**
  String get available_tools;

  /// No description provided for @unable_load_tools.
  ///
  /// In en, this message translates to:
  /// **'Unable to load tools'**
  String get unable_load_tools;

  /// No description provided for @no_tools_registered.
  ///
  /// In en, this message translates to:
  /// **'No tools registered'**
  String get no_tools_registered;

  /// No description provided for @no_tools_registered_desc.
  ///
  /// In en, this message translates to:
  /// **'Enable the example MCP server or add MCP integrations from chat settings.'**
  String get no_tools_registered_desc;

  /// No description provided for @example_mcp_server_title.
  ///
  /// In en, this message translates to:
  /// **'Example MCP server'**
  String get example_mcp_server_title;

  /// No description provided for @example_mcp_server_desc.
  ///
  /// In en, this message translates to:
  /// **'Registers example.echo and example.word_count through the same MCP tool provider used by external servers.'**
  String get example_mcp_server_desc;

  /// No description provided for @disable_example_server.
  ///
  /// In en, this message translates to:
  /// **'Disable example server'**
  String get disable_example_server;

  /// No description provided for @enable_example_server.
  ///
  /// In en, this message translates to:
  /// **'Enable example server'**
  String get enable_example_server;

  /// No description provided for @built_in_label.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get built_in_label;

  /// No description provided for @highlights_label.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlights_label;

  /// No description provided for @built_with_label.
  ///
  /// In en, this message translates to:
  /// **'Built with'**
  String get built_with_label;

  /// No description provided for @local_label.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get local_label;

  /// No description provided for @gguf_format_label.
  ///
  /// In en, this message translates to:
  /// **'GGUF'**
  String get gguf_format_label;

  /// No description provided for @tool_status_requested.
  ///
  /// In en, this message translates to:
  /// **'Requested'**
  String get tool_status_requested;

  /// No description provided for @tool_status_approved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get tool_status_approved;

  /// No description provided for @tool_status_rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get tool_status_rejected;

  /// No description provided for @tool_status_running.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get tool_status_running;

  /// No description provided for @tool_status_done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get tool_status_done;

  /// No description provided for @tool_status_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get tool_status_failed;

  /// Long-press menu option to favorite a model
  ///
  /// In en, this message translates to:
  /// **'Toggle favorite'**
  String get model_favorite_toggle;

  /// Label for model note text field
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get model_note_label;

  /// Hint for model note text field
  ///
  /// In en, this message translates to:
  /// **'Add a note about this model…'**
  String get model_note_hint;

  /// Setting to unload every loaded model instance before loading another
  ///
  /// In en, this message translates to:
  /// **'Unload all models before loading a new one'**
  String get unload_models_before_load;

  /// Use private/incognito keyboard mode while in a temporary chat
  ///
  /// In en, this message translates to:
  /// **'Incognito keyboard in temporary chat'**
  String get temp_chat_keyboard_incognito;

  /// Description for temporary chat incognito keyboard setting
  ///
  /// In en, this message translates to:
  /// **'Disables keyboard learning and suggestions in temporary chats (e.g. SwiftKey incognito).'**
  String get temp_chat_keyboard_incognito_desc;

  /// Reopen the most recently active conversation when the app starts
  ///
  /// In en, this message translates to:
  /// **'Resume last chat on launch'**
  String get resume_last_chat;

  /// Description for resume last chat setting
  ///
  /// In en, this message translates to:
  /// **'Restore your last open conversation when reopening the app.'**
  String get resume_last_chat_desc;

  /// Export conversations and personas to a JSON file
  ///
  /// In en, this message translates to:
  /// **'Export all data'**
  String get export_all_data;

  /// Import conversations and personas from a JSON backup
  ///
  /// In en, this message translates to:
  /// **'Import all data'**
  String get import_all_data;

  /// Snackbar after exporting backup
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully'**
  String get export_data_success;

  /// Snackbar after importing backup
  ///
  /// In en, this message translates to:
  /// **'Backup imported successfully'**
  String get import_data_success;

  /// Snackbar when import fails
  ///
  /// In en, this message translates to:
  /// **'Failed to import backup: {error}'**
  String import_data_failed(String error);

  /// No description provided for @import_data_confirm.
  ///
  /// In en, this message translates to:
  /// **'Import conversations and custom personas from this backup? Existing items with the same IDs will be updated.'**
  String get import_data_confirm;

  /// No description provided for @import_settings_confirm.
  ///
  /// In en, this message translates to:
  /// **'Replace current settings with the imported backup?'**
  String get import_settings_confirm;

  /// No description provided for @export_conversations.
  ///
  /// In en, this message translates to:
  /// **'Export conversations'**
  String get export_conversations;

  /// No description provided for @import_conversations.
  ///
  /// In en, this message translates to:
  /// **'Import conversations'**
  String get import_conversations;

  /// No description provided for @export_personas.
  ///
  /// In en, this message translates to:
  /// **'Export personas'**
  String get export_personas;

  /// No description provided for @import_personas.
  ///
  /// In en, this message translates to:
  /// **'Import personas'**
  String get import_personas;

  /// No description provided for @export_settings.
  ///
  /// In en, this message translates to:
  /// **'Export settings'**
  String get export_settings;

  /// No description provided for @import_settings.
  ///
  /// In en, this message translates to:
  /// **'Import settings'**
  String get import_settings;

  /// No description provided for @export_all_zip.
  ///
  /// In en, this message translates to:
  /// **'Export all (ZIP)'**
  String get export_all_zip;

  /// No description provided for @import_all_zip.
  ///
  /// In en, this message translates to:
  /// **'Import all (ZIP)'**
  String get import_all_zip;

  /// No description provided for @duplicate_chat.
  ///
  /// In en, this message translates to:
  /// **'Duplicate chat'**
  String get duplicate_chat;

  /// No description provided for @duplicate_chat_success.
  ///
  /// In en, this message translates to:
  /// **'Chat duplicated'**
  String get duplicate_chat_success;

  /// No description provided for @move_to_folder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get move_to_folder;

  /// No description provided for @remove_from_folder.
  ///
  /// In en, this message translates to:
  /// **'Remove from folder'**
  String get remove_from_folder;

  /// No description provided for @create_folder.
  ///
  /// In en, this message translates to:
  /// **'Create folder'**
  String get create_folder;

  /// No description provided for @new_folder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get new_folder;

  /// No description provided for @folder_name_hint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get folder_name_hint;

  /// No description provided for @all_chats.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all_chats;

  /// No description provided for @unfiled_chats.
  ///
  /// In en, this message translates to:
  /// **'Unfiled'**
  String get unfiled_chats;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @server_path_prefix_label.
  ///
  /// In en, this message translates to:
  /// **'API path prefix'**
  String get server_path_prefix_label;

  /// No description provided for @server_path_prefix_hint.
  ///
  /// In en, this message translates to:
  /// **'/your-secret-token'**
  String get server_path_prefix_hint;

  /// No description provided for @search_message_contents.
  ///
  /// In en, this message translates to:
  /// **'Search message contents'**
  String get search_message_contents;

  /// No description provided for @message_search_results.
  ///
  /// In en, this message translates to:
  /// **'Message matches'**
  String get message_search_results;

  /// No description provided for @saved_messages_title.
  ///
  /// In en, this message translates to:
  /// **'Saved Messages'**
  String get saved_messages_title;

  /// No description provided for @nav_saved_messages.
  ///
  /// In en, this message translates to:
  /// **'Saved Messages'**
  String get nav_saved_messages;

  /// No description provided for @saved_messages_empty.
  ///
  /// In en, this message translates to:
  /// **'No saved messages yet. Bookmark a message from its options menu.'**
  String get saved_messages_empty;

  /// No description provided for @save_message.
  ///
  /// In en, this message translates to:
  /// **'Save message'**
  String get save_message;

  /// No description provided for @message_saved.
  ///
  /// In en, this message translates to:
  /// **'Message saved'**
  String get message_saved;

  /// No description provided for @token_count.
  ///
  /// In en, this message translates to:
  /// **'{count} tokens'**
  String token_count(int count);

  /// No description provided for @estimated_token_count.
  ///
  /// In en, this message translates to:
  /// **'~{count} tokens (estimated)'**
  String estimated_token_count(int count);

  /// No description provided for @test_tts_section_title.
  ///
  /// In en, this message translates to:
  /// **'Test voice'**
  String get test_tts_section_title;

  /// No description provided for @test_tts_hint.
  ///
  /// In en, this message translates to:
  /// **'Enter text to hear the current TTS engine…'**
  String get test_tts_hint;

  /// No description provided for @test_speak_button.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get test_speak_button;

  /// No description provided for @scroll_to_bottom.
  ///
  /// In en, this message translates to:
  /// **'Scroll to bottom'**
  String get scroll_to_bottom;

  /// No description provided for @generate_ai_response.
  ///
  /// In en, this message translates to:
  /// **'Generate AI response'**
  String get generate_ai_response;

  /// No description provided for @no_response.
  ///
  /// In en, this message translates to:
  /// **'No response'**
  String get no_response;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @import.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get import;

  /// No description provided for @conversations_label.
  ///
  /// In en, this message translates to:
  /// **'Conversations'**
  String get conversations_label;

  /// No description provided for @personas_label.
  ///
  /// In en, this message translates to:
  /// **'Personas'**
  String get personas_label;

  /// No description provided for @settings_label.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings_label;

  /// No description provided for @export_conversation.
  ///
  /// In en, this message translates to:
  /// **'Export conversation'**
  String get export_conversation;

  /// No description provided for @tts_process_markdown.
  ///
  /// In en, this message translates to:
  /// **'Process markdown for speech'**
  String get tts_process_markdown;

  /// No description provided for @tts_process_markdown_desc.
  ///
  /// In en, this message translates to:
  /// **'Strip formatting like **bold** before reading aloud'**
  String get tts_process_markdown_desc;

  /// No description provided for @tts_skip_seconds.
  ///
  /// In en, this message translates to:
  /// **'Skip interval'**
  String get tts_skip_seconds;

  /// No description provided for @tts_skip_seconds_desc.
  ///
  /// In en, this message translates to:
  /// **'Forward and rewind jump size during playback'**
  String get tts_skip_seconds_desc;

  /// No description provided for @tts_skip_seconds_value.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String tts_skip_seconds_value(int seconds);

  /// No description provided for @preview_system_prompts.
  ///
  /// In en, this message translates to:
  /// **'Preview system prompts'**
  String get preview_system_prompts;

  /// No description provided for @welcome_message_1.
  ///
  /// In en, this message translates to:
  /// **'What can I help you with today?'**
  String get welcome_message_1;

  /// No description provided for @welcome_message_2.
  ///
  /// In en, this message translates to:
  /// **'Ask me anything — I\'m ready when you are.'**
  String get welcome_message_2;

  /// No description provided for @welcome_message_3.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation below.'**
  String get welcome_message_3;

  /// No description provided for @welcome_message_4.
  ///
  /// In en, this message translates to:
  /// **'Need ideas? Try one of the quick prompts.'**
  String get welcome_message_4;

  /// No description provided for @temporary_chat.
  ///
  /// In en, this message translates to:
  /// **'Temporary chat'**
  String get temporary_chat;

  /// No description provided for @temporary_chat_desc.
  ///
  /// In en, this message translates to:
  /// **'Chats aren\'t saved to history.'**
  String get temporary_chat_desc;

  /// No description provided for @temporary_chat_banner.
  ///
  /// In en, this message translates to:
  /// **'Temporary chat — not saved to history'**
  String get temporary_chat_banner;

  /// No description provided for @temporary_chat_save_warning_title.
  ///
  /// In en, this message translates to:
  /// **'Save message in temporary chat?'**
  String get temporary_chat_save_warning_title;

  /// No description provided for @temporary_chat_save_warning_body.
  ///
  /// In en, this message translates to:
  /// **'This chat is temporary and hidden from history. The saved message will still appear in Saved Messages.'**
  String get temporary_chat_save_warning_body;

  /// No description provided for @save_to_history.
  ///
  /// In en, this message translates to:
  /// **'Save to history'**
  String get save_to_history;

  /// No description provided for @share_conversation.
  ///
  /// In en, this message translates to:
  /// **'Share conversation'**
  String get share_conversation;

  /// No description provided for @download_tts_audio.
  ///
  /// In en, this message translates to:
  /// **'Download audio'**
  String get download_tts_audio;

  /// No description provided for @tts_download_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Download is only available for Piper and Kitten TTS'**
  String get tts_download_unavailable;

  /// No description provided for @tts_download_no_audio.
  ///
  /// In en, this message translates to:
  /// **'No audio available to download yet'**
  String get tts_download_no_audio;

  /// No description provided for @tts_download_success.
  ///
  /// In en, this message translates to:
  /// **'Audio saved'**
  String get tts_download_success;

  /// No description provided for @return_to_chat.
  ///
  /// In en, this message translates to:
  /// **'Return to chat'**
  String get return_to_chat;

  /// No description provided for @return_to_temp_chat.
  ///
  /// In en, this message translates to:
  /// **'Return to temporary chat'**
  String get return_to_temp_chat;

  /// No description provided for @insert_saved_message.
  ///
  /// In en, this message translates to:
  /// **'Insert saved message'**
  String get insert_saved_message;

  /// No description provided for @insert_saved_message_desc.
  ///
  /// In en, this message translates to:
  /// **'Choose a saved message to add to your input'**
  String get insert_saved_message_desc;

  /// No description provided for @model_info.
  ///
  /// In en, this message translates to:
  /// **'Model info'**
  String get model_info;

  /// No description provided for @model_name.
  ///
  /// In en, this message translates to:
  /// **'Model name'**
  String get model_name;

  /// No description provided for @model_identifier.
  ///
  /// In en, this message translates to:
  /// **'Identifier'**
  String get model_identifier;

  /// No description provided for @not_available.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get not_available;

  /// No description provided for @save_message_folders.
  ///
  /// In en, this message translates to:
  /// **'Save message'**
  String get save_message_folders;

  /// No description provided for @remove_from_saved.
  ///
  /// In en, this message translates to:
  /// **'Remove from saved'**
  String get remove_from_saved;

  /// No description provided for @message_already_saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get message_already_saved;

  /// No description provided for @stream_ttft.
  ///
  /// In en, this message translates to:
  /// **'Time to first token'**
  String get stream_ttft;

  /// No description provided for @stream_tokens_per_sec.
  ///
  /// In en, this message translates to:
  /// **'Tokens per second'**
  String get stream_tokens_per_sec;

  /// No description provided for @stream_stop_reason.
  ///
  /// In en, this message translates to:
  /// **'Stop reason'**
  String get stream_stop_reason;

  /// No description provided for @stream_input_tokens.
  ///
  /// In en, this message translates to:
  /// **'Input tokens'**
  String get stream_input_tokens;

  /// No description provided for @stream_output_tokens.
  ///
  /// In en, this message translates to:
  /// **'Output tokens'**
  String get stream_output_tokens;

  /// No description provided for @stream_generation_time.
  ///
  /// In en, this message translates to:
  /// **'Generation time'**
  String get stream_generation_time;

  /// No description provided for @attach_image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get attach_image;

  /// No description provided for @attach_text_document.
  ///
  /// In en, this message translates to:
  /// **'Text document'**
  String get attach_text_document;

  /// No description provided for @add_attachment.
  ///
  /// In en, this message translates to:
  /// **'Add attachment'**
  String get add_attachment;

  /// No description provided for @photo_permission_denied.
  ///
  /// In en, this message translates to:
  /// **'Photo access is required to attach images'**
  String get photo_permission_denied;

  /// No description provided for @characters_label.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get characters_label;

  /// No description provided for @exit_temporary_chat_title.
  ///
  /// In en, this message translates to:
  /// **'Exit temporary chat?'**
  String get exit_temporary_chat_title;

  /// No description provided for @exit_temporary_chat_body.
  ///
  /// In en, this message translates to:
  /// **'This will discard the current temporary chat and return to a new chat.'**
  String get exit_temporary_chat_body;

  /// No description provided for @saved_message_temp_snap_unavailable.
  ///
  /// In en, this message translates to:
  /// **'This message was saved from a temporary chat and can\'t be opened in its original conversation.'**
  String get saved_message_temp_snap_unavailable;

  /// No description provided for @filter_title.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get filter_title;

  /// No description provided for @filter_pinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get filter_pinned;

  /// No description provided for @filter_archived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get filter_archived;

  /// No description provided for @filter_temp_chats.
  ///
  /// In en, this message translates to:
  /// **'Temporary chats'**
  String get filter_temp_chats;

  /// No description provided for @filter_user_messages.
  ///
  /// In en, this message translates to:
  /// **'User messages'**
  String get filter_user_messages;

  /// No description provided for @filter_assistant_messages.
  ///
  /// In en, this message translates to:
  /// **'Assistant messages'**
  String get filter_assistant_messages;

  /// No description provided for @archive_chat.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get archive_chat;

  /// No description provided for @unarchive_chat.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get unarchive_chat;

  /// No description provided for @conversation_message_count.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 message} other{{count} messages}}'**
  String conversation_message_count(int count);

  /// No description provided for @conversation_character_count.
  ///
  /// In en, this message translates to:
  /// **'{count} chars'**
  String conversation_character_count(int count);

  /// No description provided for @generate_title_with_ai.
  ///
  /// In en, this message translates to:
  /// **'Generate with AI'**
  String get generate_title_with_ai;

  /// No description provided for @generating_title.
  ///
  /// In en, this message translates to:
  /// **'Generating...'**
  String get generating_title;

  /// No description provided for @generate_title_failed.
  ///
  /// In en, this message translates to:
  /// **'Could not generate a title'**
  String get generate_title_failed;

  /// No description provided for @lm_studio_model_browser_title.
  ///
  /// In en, this message translates to:
  /// **'Browse models'**
  String get lm_studio_model_browser_title;

  /// No description provided for @lm_studio_model_search_hint.
  ///
  /// In en, this message translates to:
  /// **'Search models by name or author…'**
  String get lm_studio_model_search_hint;

  /// No description provided for @lm_studio_staff_picks.
  ///
  /// In en, this message translates to:
  /// **'Staff picks'**
  String get lm_studio_staff_picks;

  /// No description provided for @lm_studio_community_models.
  ///
  /// In en, this message translates to:
  /// **'Community models'**
  String get lm_studio_community_models;

  /// No description provided for @lm_studio_no_models.
  ///
  /// In en, this message translates to:
  /// **'No models found'**
  String get lm_studio_no_models;

  /// No description provided for @lm_studio_models_count.
  ///
  /// In en, this message translates to:
  /// **'{count} models'**
  String lm_studio_models_count(int count);

  /// No description provided for @lm_studio_browse_models.
  ///
  /// In en, this message translates to:
  /// **'Browse & download'**
  String get lm_studio_browse_models;

  /// No description provided for @lm_studio_model_search.
  ///
  /// In en, this message translates to:
  /// **'LMS Model Search'**
  String get lm_studio_model_search;

  /// No description provided for @lm_studio_downloads_title.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get lm_studio_downloads_title;

  /// No description provided for @lm_studio_choose_quant.
  ///
  /// In en, this message translates to:
  /// **'Choose a download option'**
  String get lm_studio_choose_quant;

  /// No description provided for @lm_studio_use_default_quant.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get lm_studio_use_default_quant;

  /// No description provided for @lm_studio_recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get lm_studio_recommended;

  /// No description provided for @lm_studio_clear_downloads.
  ///
  /// In en, this message translates to:
  /// **'Clear finished'**
  String get lm_studio_clear_downloads;

  /// No description provided for @lm_studio_no_downloads.
  ///
  /// In en, this message translates to:
  /// **'No downloads yet'**
  String get lm_studio_no_downloads;

  /// No description provided for @lm_studio_downloads_disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Downloads run on the LM Studio host. Pausing, stopping, and deleting models must be done on that computer — not from this app.'**
  String get lm_studio_downloads_disclaimer;

  /// No description provided for @lm_studio_staff_pick.
  ///
  /// In en, this message translates to:
  /// **'Staff pick'**
  String get lm_studio_staff_pick;

  /// No description provided for @lm_studio_params.
  ///
  /// In en, this message translates to:
  /// **'PARAMS'**
  String get lm_studio_params;

  /// No description provided for @lm_studio_arch.
  ///
  /// In en, this message translates to:
  /// **'ARCH'**
  String get lm_studio_arch;

  /// No description provided for @lm_studio_domain.
  ///
  /// In en, this message translates to:
  /// **'DOMAIN'**
  String get lm_studio_domain;

  /// No description provided for @lm_studio_format.
  ///
  /// In en, this message translates to:
  /// **'FORMAT'**
  String get lm_studio_format;

  /// No description provided for @lm_studio_vision.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get lm_studio_vision;

  /// No description provided for @lm_studio_tool_use.
  ///
  /// In en, this message translates to:
  /// **'Tool use'**
  String get lm_studio_tool_use;

  /// No description provided for @lm_studio_reasoning.
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get lm_studio_reasoning;

  /// No description provided for @lm_studio_download_options.
  ///
  /// In en, this message translates to:
  /// **'Download options'**
  String get lm_studio_download_options;

  /// No description provided for @lm_studio_download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get lm_studio_download;

  /// No description provided for @lm_studio_download_size.
  ///
  /// In en, this message translates to:
  /// **'Download {size}'**
  String lm_studio_download_size(String size);

  /// No description provided for @lm_studio_downloading_percent.
  ///
  /// In en, this message translates to:
  /// **'Downloading {percent}%'**
  String lm_studio_downloading_percent(int percent);

  /// No description provided for @lm_studio_readme_unavailable.
  ///
  /// In en, this message translates to:
  /// **'README not available for this model.'**
  String get lm_studio_readme_unavailable;

  /// No description provided for @lm_studio_full_gpu_offload.
  ///
  /// In en, this message translates to:
  /// **'Full GPU offload possible'**
  String get lm_studio_full_gpu_offload;

  /// No description provided for @lm_studio_partial_gpu_offload.
  ///
  /// In en, this message translates to:
  /// **'Partial GPU offload possible'**
  String get lm_studio_partial_gpu_offload;

  /// No description provided for @lm_studio_likely_too_large.
  ///
  /// In en, this message translates to:
  /// **'Likely too large'**
  String get lm_studio_likely_too_large;

  /// No description provided for @lm_studio_available_ram_gb.
  ///
  /// In en, this message translates to:
  /// **'Available RAM (GB, optional)'**
  String get lm_studio_available_ram_gb;

  /// No description provided for @lm_studio_available_vram_gb.
  ///
  /// In en, this message translates to:
  /// **'Available VRAM (GB, optional)'**
  String get lm_studio_available_vram_gb;

  /// No description provided for @lm_studio_memory_settings_title.
  ///
  /// In en, this message translates to:
  /// **'Memory for recommendations'**
  String get lm_studio_memory_settings_title;

  /// No description provided for @lm_studio_memory_settings_desc.
  ///
  /// In en, this message translates to:
  /// **'Used to estimate whether models fit on your machine in the model browser.'**
  String get lm_studio_memory_settings_desc;

  /// Label for the reasoning-toggle button shown for reasoning-capable models
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get think_button_label;

  /// Low reasoning effort level
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get reasoning_effort_low;

  /// Medium reasoning effort level
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get reasoning_effort_medium;

  /// High reasoning effort level
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get reasoning_effort_high;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'bn',
    'en',
    'es',
    'hi',
    'it',
    'ja',
    'ru',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'hi':
      return AppLocalizationsHi();
    case 'it':
      return AppLocalizationsIt();
    case 'ja':
      return AppLocalizationsJa();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
