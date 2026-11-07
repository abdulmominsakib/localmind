import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../../l10n/app_localizations.dart';

class LocalApiBackButton extends StatelessWidget {
  const LocalApiBackButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
    onPressed: () => Navigator.maybePop(context),
    icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01),
  );
}

class LocalApiCopyRow extends StatelessWidget {
  const LocalApiCopyRow({
    super.key,
    required this.label,
    required this.value,
    this.hidden = false,
    this.trailing,
  });
  final String label;
  final String value;
  final bool hidden;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: SelectableText(hidden ? '••••••••••••' : value),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?trailing,
          IconButton(
            tooltip: l10n.localApiCopy(label),
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCopy01),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: value));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(l10n.localApiCopied)));
            },
          ),
        ],
      ),
    );
  }
}

class LocalApiKeyCard extends StatefulWidget {
  const LocalApiKeyCard({
    super.key,
    required this.apiKey,
    required this.onRotate,
  });
  final String apiKey;
  final VoidCallback? onRotate;

  @override
  State<LocalApiKeyCard> createState() => _LocalApiKeyCardState();
}

class _LocalApiKeyCardState extends State<LocalApiKeyCard> {
  bool _visible = false;

  @override
  void didUpdateWidget(LocalApiKeyCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.apiKey != widget.apiKey) _visible = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LocalApiCopyRow(
          label: l10n.localApiKey,
          value: widget.apiKey,
          hidden: !_visible,
          trailing: IconButton(
            tooltip: _visible ? l10n.localApiHideKey : l10n.localApiShowKey,
            icon: HugeIcon(
              icon: _visible
                  ? HugeIcons.strokeRoundedViewOff
                  : HugeIcons.strokeRoundedView,
            ),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
        TextButton(
          onPressed: widget.onRotate == null
              ? null
              : () async {
                  final rotate = await showDialog<bool>(
                    context: context,
                    builder: (context) => const LocalApiRotateKeyDialog(),
                  );
                  if (mounted && rotate == true) widget.onRotate?.call();
                },
          child: Text(l10n.localApiRotateKey),
        ),
      ],
    );
  }
}

class LocalApiRotateKeyDialog extends StatelessWidget {
  const LocalApiRotateKeyDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.localApiRotateKey),
      content: Text(l10n.localApiRotateHint),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.localApiRotateKey),
        ),
      ],
    );
  }
}
