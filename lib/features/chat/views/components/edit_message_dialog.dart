import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:localmind/l10n/app_localizations.dart';
import 'edit_message_result.dart';

class EditMessageDialog extends StatefulWidget {
  const EditMessageDialog({
    super.key,
    required this.initialContent,
    this.description,
    this.saveLabel,
    this.showSaveOnly = false,
  });

  final String initialContent;
  final String? description;
  final String? saveLabel;
  final bool showSaveOnly;

  static Future<String?> show(
    BuildContext context, {
    required String initialContent,
    String? description,
    String? saveLabel,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => EditMessageDialog(
        initialContent: initialContent,
        description: description,
        saveLabel: saveLabel,
      ),
    );
  }

  static Future<EditMessageResult?> showUserEdit(
    BuildContext context, {
    required String initialContent,
  }) {
    return showModalBottomSheet<EditMessageResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          EditMessageDialog(initialContent: initialContent, showSaveOnly: true),
    );
  }

  @override
  State<EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<EditMessageDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String? _validatedText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return null;
    return text;
  }

  void _popResult({required bool regenerate}) {
    final text = _validatedText();
    if (text == null) return;
    if (widget.showSaveOnly) {
      Navigator.of(
        context,
      ).pop(EditMessageResult(content: text, regenerate: regenerate));
    } else {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark
        ? const Color(0xFF888888)
        : const Color(0xFF666666);

    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF121212) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFFE5E5E5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.edit_message,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: 8,
                  minLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(12),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.description ?? l10n.edit_message_desc,
                  style: TextStyle(fontSize: 12, color: hintColor),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ShadButton.outline(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.cancel),
                    ),
                    const SizedBox(width: 8),
                    if (widget.showSaveOnly) ...[
                      ShadButton.outline(
                        onPressed: () => _popResult(regenerate: false),
                        child: Text(l10n.save),
                      ),
                      const SizedBox(width: 8),
                      ShadButton(
                        onPressed: () => _popResult(regenerate: true),
                        child: Text(l10n.save_regenerate),
                      ),
                    ] else
                      ShadButton(
                        onPressed: () => _popResult(regenerate: true),
                        child: Text(widget.saveLabel ?? l10n.save_regenerate),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
