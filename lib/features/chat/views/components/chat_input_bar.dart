import 'dart:io';



import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:haptic_feedback/haptic_feedback.dart';

import 'package:hugeicons/hugeicons.dart';

import 'package:image_picker/image_picker.dart';

import 'package:localmind/l10n/app_localizations.dart';

import 'package:localmind/core/theme/colors.dart';

import 'package:permission_handler/permission_handler.dart';



import '../../../../core/models/enums.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../servers/providers/server_providers.dart';

import '../../../stt/providers/stt_providers.dart';
import '../../providers/chat_providers.dart';
import '../../utils/attachment_helpers.dart';
import '../../utils/image_upload_utils.dart';
import 'image_preview_dialog.dart';
import '../../../saved_messages/views/components/saved_message_picker_sheet.dart';



class ChatInputBar extends ConsumerStatefulWidget {

  const ChatInputBar({

    super.key,

    required this.onSend,

    required this.onStop,

    this.onAttach,

    this.enabled = true,

    this.isStreaming = false,

    this.focusNode,

    this.keyboardIncognito = false,

  });



  final void Function(String message, {List<File>? attachments}) onSend;

  final VoidCallback onStop;

  final void Function(List<File> attachments)? onAttach;

  final bool enabled;

  final bool isStreaming;

  final FocusNode? focusNode;

  final bool keyboardIncognito;



  @override

  ConsumerState<ChatInputBar> createState() => ChatInputBarState();

}



class ChatInputBarState extends ConsumerState<ChatInputBar>

    with TickerProviderStateMixin {

  final _normalController = TextEditingController();
  final _incognitoController = TextEditingController();
  late final FocusNode _focusNode;
  late final FocusNode _incognitoFocus;

  TextEditingController get _controller =>
      widget.keyboardIncognito ? _incognitoController : _normalController;

  FocusNode get _activeFocus =>
      widget.keyboardIncognito ? _incognitoFocus : _focusNode;

  final List<File> _attachedFiles = [];

  bool _isGeneratingAiUser = false;
  bool _sendAsAssistant = false;

  late AnimationController _sendButtonAnimController;

  late Animation<double> _sendButtonScale;

  late AnimationController _micAnimController;

  String _preSpeechText = '';



  @override
  void initState() {
    super.initState();

    _focusNode = widget.focusNode ?? FocusNode();
    _incognitoFocus = FocusNode();

    _sendButtonAnimController = AnimationController(

      duration: const Duration(milliseconds: 200),

      vsync: this,

    );

    _sendButtonScale = Tween<double>(begin: 1.0, end: 1.1).animate(

      CurvedAnimation(parent: _sendButtonAnimController, curve: Curves.easeOut),

    );

    _micAnimController = AnimationController(

      duration: const Duration(milliseconds: 800),

      vsync: this,

    );

  }



  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyboardIncognito == widget.keyboardIncognito) return;

    final text = _normalController.text;
    final selection = _normalController.selection;

    if (widget.keyboardIncognito) {
      _incognitoController.value = TextEditingValue(text: text, selection: selection);
      if (_focusNode.hasFocus) {
        _incognitoFocus.requestFocus();
      }
    } else {
      _normalController.value = TextEditingValue(text: text, selection: selection);
      if (_incognitoFocus.hasFocus) {
        _focusNode.requestFocus();
      }
    }
  }



  @override

  void dispose() {

    _normalController.dispose();
    _incognitoController.dispose();

    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _incognitoFocus.dispose();

    _sendButtonAnimController.dispose();

    _micAnimController.dispose();

    super.dispose();

  }



  void insertText(String text) {

    final insert = text.trim();

    if (insert.isEmpty) return;

    final current = _controller.text;

    if (current.isEmpty) {

      _controller.text = insert;

    } else {

      _controller.text = '$current\n\n$insert';

    }

    setState(() {});

    _activeFocus.requestFocus();

    _controller.selection = TextSelection.fromPosition(

      TextPosition(offset: _controller.text.length),

    );

  }



  Future<bool> _ensurePhotoPermission() async {

    if (!Platform.isAndroid && !Platform.isIOS) return true;



    var status = await Permission.photos.status;

    if (status.isGranted || status.isLimited) return true;



    status = await Permission.photos.request();

    if (status.isGranted || status.isLimited) return true;



    if (Platform.isAndroid) {

      final storage = await Permission.storage.request();

      return storage.isGranted;

    }

    return false;

  }



  Future<void> _pickImages() async {

    final granted = await _ensurePhotoPermission();

    if (!granted) {

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(

        SnackBar(

          content: Text(AppLocalizations.of(context)!.photo_permission_denied),

        ),

      );

      return;

    }



    final picker = ImagePicker();

    final images = await picker.pickMultiImage(imageQuality: 85);

    if (images.isEmpty) return;

    final settings = ref.read(settingsProvider);
    final compressed = <File>[];
    for (final image in images) {
      compressed.add(
        await ImageUploadUtils.prepareImageFile(
          File(image.path),
          enabled: settings.imageCompressionEnabled,
          level: settings.imageCompressionLevel,
        ),
      );
    }

    setState(() {
      _attachedFiles.addAll(compressed);
    });

    widget.onAttach?.call(_attachedFiles);

  }



  Future<void> _pickTextDocument() async {

    final result = await FilePicker.pickFiles(

      type: FileType.custom,

      allowedExtensions: const ['txt', 'md'],

      allowMultiple: true,

    );

    if (result == null || result.files.isEmpty) return;



    setState(() {

      _attachedFiles.addAll(

        result.files.where((f) => f.path != null).map((f) => File(f.path!)),

      );

    });

    widget.onAttach?.call(_attachedFiles);

  }



  Future<void> _handleInsertSavedMessage() async {

    final content = await showSavedMessagePickerSheet(context);

    if (content != null && content.isNotEmpty) {

      insertText(content);

    }

  }



  void _showAttachMenu() {

    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet(

      context: context,

      builder: (ctx) => SafeArea(

        child: Column(

          mainAxisSize: MainAxisSize.min,

          children: [

            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l10n.attach_text_document),
              onTap: () {
                Navigator.pop(ctx);
                _pickTextDocument();
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.attach_image),
              onTap: () {
                Navigator.pop(ctx);
                _pickImages();
              },
            ),

            ListTile(

              leading: const Icon(Icons.bookmark_outline),

              title: Text(l10n.insert_saved_message),

              onTap: () {

                Navigator.pop(ctx);

                _handleInsertSavedMessage();

              },

            ),

            const SizedBox(height: 8),

          ],

        ),

      ),

    );

  }



  Future<void> _handleMicToggle() async {

    final stt = ref.read(sttProvider.notifier);

    final isListening = ref.read(sttProvider).isListening;



    Haptics.vibrate(HapticsType.light);



    if (isListening) {

      await stt.stopListening();

    } else {

      _preSpeechText = _controller.text;

      await stt.startListening(

        onResult: (words) {

          if (words.isNotEmpty) {

            setState(() {

              if (_preSpeechText.isEmpty) {

                _controller.text = words;

              } else {

                _controller.text = '$_preSpeechText $words';

              }

              _controller.selection = TextSelection.fromPosition(

                TextPosition(offset: _controller.text.length),

              );

            });

          }

        },

      );

    }

  }



  Widget _buildMicButton(bool isListening, ThemeData theme) {

    final l10n = AppLocalizations.of(context)!;

    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(

      animation: _micAnimController,

      builder: (context, child) {

        final pulseValue = isListening ? _micAnimController.value : 0.0;

        return Container(

          decoration: BoxDecoration(

            shape: BoxShape.circle,

            boxShadow: [

              if (isListening)

                BoxShadow(

                  color: Colors.red.withValues(alpha: 0.4 * pulseValue),

                  blurRadius: 8 + (8 * pulseValue),

                  spreadRadius: 1 + (3 * pulseValue),

                ),

            ],

          ),

          child: Container(

            width: 36,

            height: 36,

            decoration: BoxDecoration(

              color: isListening

                  ? Colors.red

                  : theme.colorScheme.onSurface.withValues(alpha: 0.05),

              shape: BoxShape.circle,

            ),

            child: IconButton(

              padding: EdgeInsets.zero,

              icon: Icon(

                Icons.mic_none_rounded,

                size: 20,

                color: isListening

                    ? (isDark ? Colors.white : Colors.black)

                    : theme.colorScheme.onSurface.withValues(alpha: 0.7),

              ),

              onPressed: _handleMicToggle,

              tooltip: isListening

                  ? l10n.stop_listening_tooltip

                  : l10n.start_listening_tooltip,

            ),

          ),

        );

      },

    );

  }



  void _handleSubmit() {

    final text = _controller.text.trim();

    if (text.isEmpty && _attachedFiles.isEmpty) return;



    Haptics.vibrate(HapticsType.medium);

    if (_sendAsAssistant) {
      ref.read(chatProvider.notifier).insertMessageWithoutGenerating(
            text,
            role: MessageRole.assistant,
            attachments: List.from(_attachedFiles),
          );
    } else {
      widget.onSend(text, attachments: List.from(_attachedFiles));
    }

    _controller.clear();

    setState(() {

      _attachedFiles.clear();
      _sendAsAssistant = false;

    });

  }

  void _handleInsertWithoutGenerating() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachedFiles.isEmpty) return;

    Haptics.vibrate(HapticsType.medium);
    ref.read(chatProvider.notifier).insertMessageWithoutGenerating(
          text,
          role: _sendAsAssistant ? MessageRole.assistant : MessageRole.user,
          attachments: List.from(_attachedFiles),
        );

    _controller.clear();
    setState(() {
      _attachedFiles.clear();
      _sendAsAssistant = false;
    });
  }



  void _handleStop() {

    Haptics.vibrate(HapticsType.light);

    widget.onStop();

  }



  Future<void> _handleGenerateAiUser() async {
    if (_isGeneratingAiUser || widget.isStreaming || !widget.enabled) return;
    setState(() => _isGeneratingAiUser = true);
    try {
      await ref.read(chatProvider.notifier).generateAiUserMessage();
    } finally {
      if (mounted) setState(() => _isGeneratingAiUser = false);
    }
  }

  Widget _buildAiUserButton(bool isConnected, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final enabled = isConnected && widget.enabled && !widget.isStreaming;

    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: l10n.ai_user_response_tooltip,
      onPressed: enabled && !_isGeneratingAiUser ? _handleGenerateAiUser : null,
      icon: _isGeneratingAiUser
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            )
          : Icon(
              Icons.person_outline,
              size: 22,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
    );
  }

  Widget _buildRoleSwapButton(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;

    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: _sendAsAssistant
          ? l10n.send_as_assistant_tooltip
          : l10n.send_as_user_tooltip,
      onPressed: widget.enabled
          ? () {
              Haptics.vibrate(HapticsType.light);
              setState(() => _sendAsAssistant = !_sendAsAssistant);
            }
          : null,
      icon: Icon(
        Icons.swap_horiz_rounded,
        size: 22,
        color: _sendAsAssistant
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurface.withValues(alpha: 0.7),
      ),
    );
  }

  Widget _buildActionButton(bool canSend, ThemeData theme) {

    final l10n = AppLocalizations.of(context)!;

    final backgroundColor = widget.isStreaming

        ? Colors.red

        : theme.colorScheme.primary;

    final iconColor = widget.isStreaming

        ? Colors.white

        : theme.colorScheme.onPrimary;



    return GestureDetector(

      onTapDown: canSend ? (_) => _sendButtonAnimController.forward() : null,

      onTapUp: canSend ? (_) => _sendButtonAnimController.reverse() : null,

      onTapCancel: canSend ? () => _sendButtonAnimController.reverse() : null,

      onLongPress: (canSend && !widget.isStreaming)
          ? _handleInsertWithoutGenerating
          : null,

      child: ScaleTransition(

        scale: _sendButtonScale,

        child: AnimatedContainer(

          duration: const Duration(milliseconds: 200),

          curve: Curves.easeOut,

          width: 36,

          height: 36,

          decoration: BoxDecoration(

            color: backgroundColor.withValues(

              alpha: (canSend || widget.isStreaming) ? 1.0 : 0.2,

            ),

            shape: BoxShape.circle,

          ),

          child: IconButton(

            padding: EdgeInsets.zero,

            icon: AnimatedSwitcher(

              duration: const Duration(milliseconds: 150),

              transitionBuilder: (child, animation) {

                return ScaleTransition(scale: animation, child: child);

              },

              child: widget.isStreaming

                  ? HugeIcon(

                      icon: HugeIcons.strokeRoundedStop,

                      key: const ValueKey('stop'),

                      color: iconColor,

                      size: 18,

                    )

                  : HugeIcon(

                      icon: HugeIcons.strokeRoundedArrowUp01,

                      key: ValueKey(canSend),

                      color: iconColor,

                      size: 18,

                    ),

            ),

            onPressed: widget.isStreaming

                ? _handleStop

                : (canSend ? _handleSubmit : null),

            tooltip: widget.isStreaming

                ? l10n.stop_generation_tooltip

                : l10n.send_message_tooltip,

          ),

        ),

      ),

    );

  }



  String? _mapSttError(String error) {

    switch (error) {

      case 'error_no_match':

        return 'No speech recognized. Please try speaking again and check your microphone.';

      case 'error_speech_timeout':

        return 'No speech detected. Timed out.';

      case 'error_permission':

        return 'Microphone permission denied.';

      case 'error_busy':

        return 'Speech recognition is busy. Please try again.';

      case 'error_network':

      case 'error_network_timeout':

        return 'Network error. Please check your connection and try again.';

      case 'error_audio':

        return 'Audio recording error. Please check your microphone.';

      default:

        if (error.startsWith('error_')) {

          final cleanName =

              error.replaceFirst('error_', '').replaceAll('_', ' ');

          return 'Speech recognition error: $cleanName';

        }

        return error;

    }

  }



  @override

  Widget build(BuildContext context) {

    final l10n = AppLocalizations.of(context)!;

    final theme = Theme.of(context);

    final isDark = theme.brightness == Brightness.dark;

    final connectionStatus = ref.watch(connectionStatusProvider);

    final isConnected = connectionStatus == ConnectionStatus.connected;
    final showAiUserButton = ref.watch(settingsProvider).aiUserResponseEnabled;
    final showRoleSwapButton =
        ref.watch(settingsProvider).roleSwapButtonEnabled;



    final sttState = ref.watch(sttProvider);

    final isListening = sttState.isListening;



    if (isListening) {

      if (!_micAnimController.isAnimating) {

        _micAnimController.repeat(reverse: true);

      }

    } else {

      if (_micAnimController.isAnimating) {

        _micAnimController.stop();

        _micAnimController.reset();

      }

    }



    ref.listen<String?>(

      sttProvider.select((s) => s.error),

      (previous, next) {

        if (next != null) {

          final message = _mapSttError(next);

          if (message != null) {

            ScaffoldMessenger.of(context).showSnackBar(

              SnackBar(content: Text(message)),

            );

          }

        }

      },

    );



    final canSend = widget.enabled &&

        isConnected &&

        (_controller.text.trim().isNotEmpty || _attachedFiles.isNotEmpty) &&

        !widget.isStreaming;



    return SafeArea(

      top: false,

      child: Container(

        margin: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 12),

        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),

        decoration: BoxDecoration(

          color: isDark ? AppColors.darkSurfaceInput : AppColors.lightSurface,

          borderRadius: BorderRadius.circular(16),

          border: Border.all(

            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,

          ),

        ),

        child: Column(

          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            if (_attachedFiles.isNotEmpty)

              SizedBox(

                height: 68,

                child: ListView.separated(

                  scrollDirection: Axis.horizontal,

                  itemCount: _attachedFiles.length,

                  separatorBuilder: (_, __) => const SizedBox(width: 8),

                  itemBuilder: (context, index) {

                    final file = _attachedFiles[index];
                    final isImage = AttachmentHelpers.isImagePath(file.path);

                    return Stack(

                      clipBehavior: Clip.none,

                      children: [

                        Container(

                          decoration: BoxDecoration(

                            borderRadius: BorderRadius.circular(10),

                            border: Border.all(

                              color: isDark

                                  ? AppColors.darkBorder

                                  : AppColors.lightBorder,

                            ),

                          ),

                          child: ClipRRect(

                            borderRadius: BorderRadius.circular(9),

                            child: isImage
                                ? GestureDetector(
                                    onTap: () =>
                                        showImagePreview(context, file.path),
                                    child: Image.file(
                                      file,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                    ),
                                  )

                                : Container(

                                    width: 48,

                                    height: 48,

                                    color: theme

                                        .colorScheme.surfaceContainerHighest,

                                    child: Icon(

                                      Icons.description_outlined,

                                      size: 22,

                                      color: theme.colorScheme.primary,

                                    ),

                                  ),

                          ),

                        ),

                        PositionedDirectional(

                          top: -4,

                          end: -4,

                          child: GestureDetector(

                            onTap: () =>

                                setState(() => _attachedFiles.removeAt(index)),

                            child: Container(

                              width: 18,

                              height: 18,

                              decoration: const BoxDecoration(

                                color: Colors.black,

                                shape: BoxShape.circle,

                              ),

                              child: const Icon(

                                Icons.close,

                                size: 10,

                                color: Colors.white,

                              ),

                            ),

                          ),

                        ),

                      ],

                    );

                  },

                ),

              ),

            Stack(
              children: [
                IgnorePointer(
                  ignoring: widget.keyboardIncognito,
                  child: Opacity(
                    opacity: widget.keyboardIncognito ? 0 : 1,
                    child: TextField(
                      controller: _normalController,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      maxLines: 6,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      enableSuggestions: true,
                      autocorrect: true,
                      enableIMEPersonalizedLearning: true,
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        hintText: l10n.chat_input_hint,
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.38),
                          fontSize: 15,
                        ),
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  ignoring: !widget.keyboardIncognito,
                  child: Opacity(
                    opacity: widget.keyboardIncognito ? 1 : 0,
                    child: TextField(
                      controller: _incognitoController,
                      focusNode: _incognitoFocus,
                      enabled: widget.enabled,
                      maxLines: 6,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      enableSuggestions: false,
                      autocorrect: false,
                      enableIMEPersonalizedLearning: false,
                      spellCheckConfiguration:
                          const SpellCheckConfiguration.disabled(),
                      smartDashesType: SmartDashesType.disabled,
                      smartQuotesType: SmartQuotesType.disabled,
                      onChanged: (_) => setState(() {}),
                    style: TextStyle(
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      hintText: l10n.chat_input_hint,
                      hintStyle: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.38),
                        fontSize: 15,
                      ),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 4),
                    ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(

              children: [

                IconButton(

                  visualDensity: VisualDensity.compact,

                  padding: const EdgeInsets.all(8),

                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),

                  icon: Icon(

                    Icons.add,

                    size: 22,

                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),

                  ),

                  onPressed: isConnected ? _showAttachMenu : null,

                  tooltip: l10n.add_attachment,

                ),

                const Spacer(),

                if (showAiUserButton) ...[
                  _buildAiUserButton(isConnected, theme),
                  const SizedBox(width: 6),
                ],

                if (showRoleSwapButton) ...[
                  _buildRoleSwapButton(theme),
                  const SizedBox(width: 6),
                ],

                _buildMicButton(isListening, theme),

                const SizedBox(width: 6),

                _buildActionButton(canSend, theme),

              ],

            ),

          ],

        ),

      ),

    );

  }

}


