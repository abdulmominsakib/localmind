import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../l10n/app_localizations.dart';
import '../../data/local_api_configuration.dart';

class LocalApiConfigurationForm extends StatefulWidget {
  const LocalApiConfigurationForm({
    super.key,
    required this.config,
    required this.enabled,
    required this.canStart,
    required this.onStart,
  });
  final LocalApiConfiguration config;
  final bool enabled;
  final bool canStart;
  final void Function(String port, bool lan) onStart;

  @override
  State<LocalApiConfigurationForm> createState() =>
      _LocalApiConfigurationFormState();
}

class _LocalApiConfigurationFormState extends State<LocalApiConfigurationForm> {
  late final TextEditingController _port;
  late bool _lan;

  @override
  void initState() {
    super.initState();
    _port = TextEditingController(text: widget.config.port.toString());
    _lan = widget.config.lan;
  }

  @override
  void dispose() {
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _port,
          enabled: widget.enabled,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(5),
          ],
          decoration: InputDecoration(labelText: l10n.localApiPort),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.localApiLan),
          value: _lan,
          onChanged: widget.enabled
              ? (value) => setState(() => _lan = value)
              : null,
        ),
        if (_lan) Text(l10n.localApiLanHint),
        if (widget.enabled)
          FilledButton(
            onPressed: widget.canStart
                ? () => widget.onStart(_port.text, _lan)
                : null,
            child: Text(l10n.localApiStart),
          ),
      ],
    );
  }
}
