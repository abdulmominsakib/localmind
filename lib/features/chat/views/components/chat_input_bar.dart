import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:localmind/features/chat/views/components/token_usage_indicator.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/models/enums.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/colors.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../saved_messages/views/components/saved_message_picker_sheet.dart';
import '../../../servers/providers/server_providers.dart';
import '../../../stt/providers/stt_providers.dart';
import '../../../tts/providers/tts_providers.dart';
import '../../../voice_mode/providers/voice_mode_provider.dart';
import '../../providers/chat_providers.dart';
import '../../utils/attachment_helpers.dart';
import '../../utils/image_upload_utils.dart';
import '../../../models/views/model_picker_sheet.dart';
import 'attach_sheet.dart';
import 'image_preview_dialog.dart';
import 'model_chip.dart';
import '../../../on_device/providers/on_device_providers.dart';
import '../../../voice_mode/views/voice_mode_overlay.dart';

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

    this.totalTokenCount = 0,
  });

  final void Function(String message, {List<File>? attachments}) onSend;

  final VoidCallback onStop;

  final void Function(List<File> attachments)? onAttach;

  final bool enabled;

  final bool isStreaming;

  final FocusNode? focusNode;

  final bool keyboardIncognito;

  final int totalTokenCount;

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
  bool _holdTriggered = false;

  late AnimationController _sendButtonAnimController;

  late Animation<double> _sendButtonScale;

  late AnimationController _micAnimController;

  /// Drives the clockwise ring drawn around the send button while it's held
  /// down. Reaching the end (3s) triggers AI-generated-user-message instead
  /// of the normal tap/short-hold actions.
  late AnimationController _holdProgressController;

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

    _holdProgressController =
        AnimationController(duration: _holdDuration, vsync: this)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) {
              _holdTriggered = true;
              _holdProgressController.value = 0;
              _handleGenerateAiUser();
            }
          });
  }

  @override
  void didUpdateWidget(ChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyboardIncognito == widget.keyboardIncognito) return;

    final text = _normalController.text;
    final selection = _normalController.selection;

    if (widget.keyboardIncognito) {
      _incognitoController.value = TextEditingValue(
        text: text,
        selection: selection,
      );
      if (_focusNode.hasFocus) {
        _incognitoFocus.requestFocus();
      }
    } else {
      _normalController.value = TextEditingValue(
        text: text,
        selection: selection,
      );
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

    _holdProgressController.dispose();

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

  void _showAttachMenu() async {
    final result = await showAttachSheet(context);
    if (!mounted || result == null) return;
    switch (result) {
      case AttachAction.documents:
        _pickTextDocument();
      case AttachAction.images:
        _pickImages();
      case AttachAction.savedMessage:
        _handleInsertSavedMessage();
    }
  }

  Future<void> _handleMicToggle() async {
    final stt = ref.read(sttProvider.notifier);

    final isListening = ref.read(sttProvider).isListening;

    Haptics.vibrate(HapticsType.light);

    if (isListening) {
      await stt.stopListening();
    } else {
      _preSpeechText = _controller.text;

      await stt.startListening(onResult: _onSpeechResult);
    }
  }

  void _onSpeechResult(String words) {
    if (words.isEmpty || !mounted) return;
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

              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedMic01,
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

  Widget _buildVoiceModeButton(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final onDeviceLoaded = ref.watch(
      onDeviceEngineProvider.select(
        (s) => s.status == OnDeviceEngineStatus.loaded,
      ),
    );
    final connectionStatus = ref.watch(connectionStatusProvider);
    final isConnected = connectionStatus == ConnectionStatus.connected;
    final hasRemoteModel =
        isConnected && ref.watch(selectedModelProvider) != null;
    final modelReady = onDeviceLoaded || hasRemoteModel;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF6366F1).withValues(alpha: 0.15)
            : const Color(0xFF4F46E5).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedAudioWave01,
          size: 20,
          color: isDark ? const Color(0xFF6366F1) : const Color(0xFF4F46E5),
        ),
        onPressed: !modelReady
            ? () {
                Haptics.vibrate(HapticsType.light);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.model_required_toast)),
                );
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  builder: (_) => const ModelPickerSheet(),
                );
              }
            : () {
                Haptics.vibrate(HapticsType.light);
                VoiceModeOverlay.show(context);
              },
        tooltip: modelReady ? 'Voice mode' : l10n.model_required_toast,
      ),
    );
  }

  Widget _buildAddButton(bool isConnected, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.05),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedAdd01,
          size: 22,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
        onPressed: isConnected ? _showAttachMenu : null,
        tooltip: l10n.add_attachment,
      ),
    );
  }

  void _handleSubmit() {
    final text = _controller.text.trim();

    if (text.isEmpty && _attachedFiles.isEmpty) return;

    if (!_ensureModelSelected()) return;

    Haptics.vibrate(HapticsType.medium);

    if (_sendAsAssistant) {
      ref
          .read(chatProvider.notifier)
          .insertMessageWithoutGenerating(
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

    if (!_ensureModelSelected()) return;

    Haptics.vibrate(HapticsType.medium);
    ref
        .read(chatProvider.notifier)
        .insertMessageWithoutGenerating(
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

  /// Returns true if a model is currently selected. When no model is selected,
  /// shows a SnackBar prompting the user to pick one and opens the model
  /// picker sheet, then returns false so the caller can bail out.
  bool _ensureModelSelected() {
    if (ref.read(selectedModelProvider) != null) return true;
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.model_required_toast)));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ModelPickerSheet(),
    );
    return false;
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

  Widget _buildRoleSwapButton(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;

    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: _sendAsAssistant
            ? l10n.send_as_assistant_tooltip
            : l10n.send_as_user_tooltip,
        onPressed: widget.enabled
            ? () {
                Haptics.vibrate(HapticsType.light);
                setState(() => _sendAsAssistant = !_sendAsAssistant);
              }
            : null,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedExchange01,
          size: 20,
          color: _sendAsAssistant
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  String _effortLabel(ReasoningEffort effort) {
    final l10n = AppLocalizations.of(context)!;
    return switch (effort) {
      ReasoningEffort.low => l10n.reasoning_effort_low,
      ReasoningEffort.medium => l10n.reasoning_effort_medium,
      ReasoningEffort.high => l10n.reasoning_effort_high,
    };
  }

  Widget _buildThinkButton(ThemeData theme) {
    final selectedModel = ref.watch(selectedModelProvider);
    if (selectedModel?.supportsReasoning != true) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context)!;
    final reasoningConfig = ref.watch(chatReasoningConfigProvider);
    final enabled = reasoningConfig.enabled;
    final activeColor = theme.colorScheme.primary;
    final fgColor = enabled
        ? activeColor
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? activeColor.withValues(alpha: 0.15)
              : theme.colorScheme.onSurface.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Haptics.vibrate(HapticsType.light);
                ref
                    .read(chatReasoningConfigProvider.notifier)
                    .setEnabled(!enabled);
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  start: 10,
                  end: 4,
                  top: 6,
                  bottom: 6,
                ),
                child: HugeIcon(
                  icon: enabled
                      ? HugeIcons.strokeRoundedTick01
                      : HugeIcons.strokeRoundedSquare01,
                  size: 18,
                  color: fgColor,
                ),
              ),
            ),
            PopupMenuButton<ReasoningEffort>(
              tooltip: '',
              padding: EdgeInsets.zero,
              onSelected: (effort) {
                Haptics.vibrate(HapticsType.light);
                ref
                    .read(chatReasoningConfigProvider.notifier)
                    .setEffort(effort);
              },
              itemBuilder: (context) => ReasoningEffort.values
                  .map(
                    (effort) => PopupMenuItem(
                      value: effort,
                      child: Text(_effortLabel(effort)),
                    ),
                  )
                  .toList(),
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: 12,
                  top: 6,
                  bottom: 6,
                ),
                child: Text(
                  '${l10n.think_button_label} (${_effortLabel(reasoningConfig.effort)})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fgColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _holdDuration = Duration(milliseconds: 3000);
  static const _insertHoldThreshold = 500 / 3000;

  /// Reserve space on the right edge of the text field so long
  /// messages never slide underneath the overlaid token-usage
  /// indicator. Sized to comfortably fit a 6-digit token count.
  static const double _tokenUsageReservedWidth = 70;

  Widget _buildActionButton(bool canSend, ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;

    final backgroundColor = widget.isStreaming
        ? Colors.red
        : theme.colorScheme.primary;

    final iconColor = widget.isStreaming
        ? Colors.white
        : theme.colorScheme.onPrimary;

    final connectionStatus = ref.watch(connectionStatusProvider);
    final isConnected = connectionStatus == ConnectionStatus.connected;
    final aiUserHoldEnabled =
        ref.watch(settingsProvider.select((s) => s.aiUserResponseEnabled)) &&
        isConnected &&
        widget.enabled;

    void handleTapDown() {
      _holdTriggered = false;
      if (canSend) _sendButtonAnimController.forward();
      if (!widget.isStreaming && !_isGeneratingAiUser && aiUserHoldEnabled) {
        _holdProgressController.forward(from: 0);
      }
    }

    void resetHold() {
      _holdProgressController.stop();
      _holdProgressController.value = 0;
    }

    void handleTapUp() {
      if (canSend) _sendButtonAnimController.reverse();
      final holdFraction = _holdProgressController.value;
      final wasTriggered = _holdTriggered;
      resetHold();
      _holdTriggered = false;

      if (wasTriggered || _isGeneratingAiUser) return;

      if (widget.isStreaming) {
        _handleStop();
        return;
      }

      if (holdFraction >= _insertHoldThreshold) {
        _handleInsertWithoutGenerating();
      } else if (canSend) {
        _handleSubmit();
      }
    }

    void handleTapCancel() {
      if (canSend) _sendButtonAnimController.reverse();
      resetHold();
      _holdTriggered = false;
    }

    // Uses raw pointer callbacks instead of GestureDetector's onTapDown/
    // onTapUp: those depend on winning the gesture arena, but a nested
    // interactive descendant (the button's own tap target) can win instead,
    // silently swallowing onTapUp and breaking the hold-timing logic below.
    // Listener always fires regardless of who else claims the gesture.
    return Listener(
      onPointerDown: (_) => handleTapDown(),

      onPointerUp: (_) => handleTapUp(),

      onPointerCancel: (_) => handleTapCancel(),

      child: Tooltip(
        message: widget.isStreaming
            ? l10n.stop_generation_tooltip
            : l10n.send_message_tooltip,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _holdProgressController,
              builder: (context, child) {
                if (_holdProgressController.value <= 0) {
                  return const SizedBox(width: 44, height: 44);
                }
                return SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: _holdProgressController.value,
                    strokeWidth: 2.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),
            ScaleTransition(
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
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(scale: animation, child: child);
                    },
                    child: _isGeneratingAiUser
                        ? SizedBox(
                            key: const ValueKey('ai-user-generating'),
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: iconColor,
                            ),
                          )
                        : widget.isStreaming
                        ? HugeIcon(
                            icon: HugeIcons.strokeRoundedStop,
                            key: const ValueKey('stop'),
                            color: iconColor,
                            size: 18,
                          )
                        : canSend
                        ? HugeIcon(
                            icon: HugeIcons.strokeRoundedArrowRight01,
                            key: ValueKey(canSend),
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
                ),
              ),
            ),
          ],
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
          final cleanName = error
              .replaceFirst('error_', '')
              .replaceAll('_', ' ');

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
    final showRoleSwapButton = ref
        .watch(settingsProvider)
        .roleSwapButtonEnabled;

    final selectedModel = ref.watch(selectedModelProvider);

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

    ref.listen<String?>(sttProvider.select((s) => s.error), (previous, next) {
      if (next != null) {
        final voiceState = ref.read(voiceModeProvider);
        final voiceActive =
            voiceState.isActive || voiceState.phase != VoiceModePhase.idle;
        if (voiceActive) return;

        final message = _mapSttError(next);

        if (message != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    });

    // Voice-to-voice: when the LLM stops producing output and any auto-TTS
    // playback has finished (or was never scheduled), restart the mic so the
    // user can speak again without pressing the mic button.
    ref.listen<bool>(isStreamingProvider, (previous, next) async {
      if (previous == true && next == false && mounted) {
        if (!ref.read(settingsProvider).autoSpeakEnabled) return;
        final voiceState = ref.read(voiceModeProvider);
        final voiceActive =
            voiceState.isActive || voiceState.phase != VoiceModePhase.idle;
        if (voiceActive) return;
        final ttsSpeaking = ref.read(ttsProvider).isSpeaking;
        final sttActive = ref.read(sttProvider).isListening;
        if (ttsSpeaking || sttActive) return;

        // Small delay so the OS finishes releasing the audio session before
        // we ask for the microphone again.
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) return;
        if (ref.read(sttProvider).isListening) return;
        if (ref.read(isStreamingProvider)) return;

        _preSpeechText = _controller.text;
        await ref.read(sttProvider.notifier).startListening(
              onResult: _onSpeechResult,
            );
      }
    });

    final canSend =
        widget.enabled &&
        isConnected &&
        (_controller.text.trim().isNotEmpty || _attachedFiles.isNotEmpty) &&
        !widget.isStreaming;

    return SafeArea(
      top: false,

      child: Container(
        margin: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8),

        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),

        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurfaceInput : AppColors.lightSurface,

          borderRadius: BorderRadius.circular(26),

          border: Border.all(
            color: isDark
                ? AppColors.darkBorder.withValues(alpha: 0.6)
                : AppColors.lightBorder,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),

        child: Column(
          mainAxisSize: MainAxisSize.min,

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [
            if (_attachedFiles.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                child: SizedBox(
                  height: 68,

                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,

                    itemCount: _attachedFiles.length,

                    separatorBuilder: (_, _) => const SizedBox(width: 8),

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
                                          .colorScheme
                                          .surfaceContainerHighest,

                                      child: HugeIcon(
                                        icon: HugeIcons.strokeRoundedFile01,

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
                              onTap: () => setState(
                                () => _attachedFiles.removeAt(index),
                              ),

                              child: Container(
                                width: 18,

                                height: 18,

                                decoration: const BoxDecoration(
                                  color: Colors.black,

                                  shape: BoxShape.circle,
                                ),

                                child: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedCancel01,

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
              ),
              const SizedBox(height: 8),
            ],

            // Text input row. Sits on top of the action row so the action
            // controls stay visually grouped below. The token usage
            // indicator is overlaid on the right edge of the input so
            // the bottom row stays focused on composer actions.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Stack(
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
                          fontSize: 16,
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.38,
                            ),
                            fontSize: 16,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(
                            4,
                            8,
                            // Leave room on the right for the token-usage
                            // indicator so long messages don't slide
                            // underneath it.
                            _tokenUsageReservedWidth,
                            8,
                          ),
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
                          fontSize: 16,
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
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.38,
                            ),
                            fontSize: 16,
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(
                            4,
                            8,
                            _tokenUsageReservedWidth,
                            8,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_controller.text.isEmpty)
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: TokenUsageIndicator(
                          totalTokenCount: widget.totalTokenCount,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Bottom action row: attach button, model picker chip, optional
            // reasoning/role controls, mic, send. Mirrors the modern
            // composer layout where composer actions sit in a single
            // horizontal row directly below the text input.
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildAddButton(isConnected, theme),

                const SizedBox(width: 8),

                ModelChip(
                  model: selectedModel,
                  enabled: isConnected && widget.enabled,
                  onTap: () {
                    Haptics.vibrate(HapticsType.light);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => const ModelPickerSheet(),
                    );
                  },
                ),

                if (selectedModel?.supportsReasoning == true) ...[
                  const SizedBox(width: 6),
                  _buildThinkButton(theme),
                ],
                if (showRoleSwapButton) ...[
                  const SizedBox(width: 4),
                  _buildRoleSwapButton(theme),
                ],

                const Spacer(),

                _buildMicButton(isListening, theme),

                const SizedBox(width: 4),

                _buildVoiceModeButton(theme),

                const SizedBox(width: 8),

                _buildActionButton(canSend, theme),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
