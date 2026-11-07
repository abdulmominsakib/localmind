import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../data/huggingface_model_search_service.dart';
import '../../utils/model_modality_classifier.dart';
import '../../utils/model_param_size_parser.dart';
import '../../utils/model_quantization_parser.dart';

class ModelSearchResultRow extends StatelessWidget {
  const ModelSearchResultRow({
    super.key,
    required this.result,
    required this.onTap,
    this.alreadyAdded = false,
  });

  final HuggingFaceModelSearchResult result;
  final VoidCallback onTap;
  final bool alreadyAdded;

  @override
  Widget build(BuildContext context) {
    final quant = parseQuantization(result.repoId);
    final modality = classifyModality(
      pipelineTag: result.pipelineTag,
      tags: result.tags,
      name: result.name,
    );
    final size = parseParameterSizeBillions(result.repoId);

    return Card(
      child: ListTile(
        title: Text(
          result.repoId,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${result.downloads} downloads · ${result.likes} likes'
          '${size != null ? ' · ${formatParameterSize(size)}' : ''}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (quant != null)
              _Badge(label: quant, color: Colors.blueGrey),
            _ModalityIcon(modality: modality),
            if (alreadyAdded)
              const _Badge(label: 'Added', color: Colors.green),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              size: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }
}

class _ModalityIcon extends StatelessWidget {
  const _ModalityIcon({required this.modality});
  final ModelModality modality;
  @override
  Widget build(BuildContext context) {
    late final List<List<dynamic>> icon;
    late final Color color;
    switch (modality) {
      case ModelModality.text:
        icon = HugeIcons.strokeRoundedInputText;
        color = Colors.blue;
        break;
      case ModelModality.vision:
        icon = HugeIcons.strokeRoundedImage01;
        color = Colors.green;
        break;
      case ModelModality.audio:
        icon = HugeIcons.strokeRoundedAudioWave01;
        color = Colors.orange;
        break;
      case ModelModality.embedding:
        icon = HugeIcons.strokeRoundedDatabase;
        color = Colors.purple;
        break;
      case ModelModality.unknown:
        icon = HugeIcons.strokeRoundedHelpCircle;
        color = Colors.grey;
        break;
    }
    return HugeIcon(icon: icon, size: 16, color: color);
  }
}
