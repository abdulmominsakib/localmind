import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/providers/service_providers.dart';
import '../../providers/on_device_providers.dart';
import 'package:localmind/core/utils/hugging_face_url.dart';
import '../../utils/gguf_file_classifier.dart';
import 'package:localmind/l10n/app_localizations.dart';

class AddModelFromUrlDialog extends ConsumerStatefulWidget {
  const AddModelFromUrlDialog({super.key});

  @override
  ConsumerState<AddModelFromUrlDialog> createState() =>
      _AddModelFromUrlDialogState();
}

class _AddModelFromUrlDialogState
    extends ConsumerState<AddModelFromUrlDialog> {
  final TextEditingController _urlController = TextEditingController();
  bool _isImporting = false;
  String? _error;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  String? _validate(String url) {
    if (url.isEmpty) return 'Enter a Hugging Face model URL.';
    final lower = url.toLowerCase();
    if (!(lower.endsWith('.gguf') || lower.endsWith('.litertlm'))) {
      return 'URL must point to a .gguf or .litertlm file.';
    }
    final fileName = url.split('/').last;
    if (isSplitModelFile(fileName)) {
      return 'Split/multi-part models are not supported.';
    }
    if (isProjectorFile(fileName)) {
      return 'Projector (mmproj) files cannot be added as a model.';
    }
    // Validate host before any network request.
    try {
      canonicalizeHuggingFaceUrl(url);
    } catch (_) {
      return 'Only official Hugging Face URLs are supported.';
    }
    return null;
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    final validationError = _validate(url);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }

    setState(() {
      _isImporting = true;
      _error = null;
    });

    final token = ref.read(settingsProvider).huggingFaceToken;
    final dio = ref.read(dioProvider);

    // Canonicalize (host validation) before any network request.
    Uri canonical;
    try {
      canonical = canonicalizeHuggingFaceUrl(url);
    } catch (_) {
      setState(() {
        _isImporting = false;
        _error = 'Only official Hugging Face URLs are supported.';
      });
      return;
    }
    final canonicalUrl = canonical.toString();

    // Best-effort HEAD to confirm existence.
    try {
      await dio.head(
        canonicalUrl,
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        setState(() {
          _isImporting = false;
          _error = 'Access denied. Provide a Hugging Face token for gated models.';
        });
        return;
      }
      if (status == 404) {
        setState(() {
          _isImporting = false;
          _error = 'File not found (404).';
        });
        return;
      }
      // Network/other errors: proceed anyway (best-effort).
    } catch (_) {
      // ignore
    }

    final lower = canonicalUrl.toLowerCase();
    try {
      if (lower.endsWith('.litertlm')) {
        await ref.read(importedLitertModelsProvider.notifier).addFromUrl(
              canonicalUrl,
              token: token,
            );
      } else {
        await ref.read(importedGgufModelsProvider.notifier).addFromUrl(
              canonicalUrl,
              huggingFaceToken: token,
            );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImporting = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: const Text('Add model from URL'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlController,
            enabled: !_isImporting,
            decoration: const InputDecoration(
              labelText: 'Hugging Face URL',
              hintText: 'https://huggingface.co/.../model.gguf',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_isImporting) ...[
            const SizedBox(height: 12),
            const CircularProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _isImporting ? null : _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }
}
