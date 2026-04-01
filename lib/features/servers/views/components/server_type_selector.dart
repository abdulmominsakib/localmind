import 'package:flutter/material.dart';
import '../../../../core/models/enums.dart';

class ServerTypeSelector extends StatelessWidget {
  final ServerType selectedType;
  final ValueChanged<ServerType> onChanged;

  const ServerTypeSelector({
    super.key,
    required this.selectedType,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ServerType>(
      segments: const [
        ButtonSegment<ServerType>(
          value: ServerType.lmStudio,
          label: Text('LM Studio'),
          icon: Icon(Icons.terminal, size: 18),
        ),
        ButtonSegment<ServerType>(
          value: ServerType.openAICompatible,
          label: Text('OpenAI'),
          icon: Icon(Icons.api, size: 18),
        ),
        ButtonSegment<ServerType>(
          value: ServerType.ollama,
          label: Text('Ollama'),
          icon: Icon(Icons.pets, size: 18),
        ),
        ButtonSegment<ServerType>(
          value: ServerType.openRouter,
          label: Text('OpenRouter'),
          icon: Icon(Icons.cloud, size: 18),
        ),
      ],
      selected: {selectedType},
      onSelectionChanged: (Set<ServerType> selected) {
        if (selected.isNotEmpty) {
          onChanged(selected.first);
        }
      },
      showSelectedIcon: false,
    );
  }
}
