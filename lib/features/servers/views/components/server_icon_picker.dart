import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HugeIconData {
  final String name;
  final List<List<dynamic>> icon;

  const HugeIconData(this.name, this.icon);
}

const List<HugeIconData> serverIcons = [
  HugeIconData('Server Stack', HugeIcons.strokeRoundedServerStack01),
  HugeIconData('Server Stack 02', HugeIcons.strokeRoundedServerStack02),
  HugeIconData('Server Stack 03', HugeIcons.strokeRoundedServerStack03),
  HugeIconData('Cloud', HugeIcons.strokeRoundedCloud),
  HugeIconData('Cloud Server', HugeIcons.strokeRoundedCloudServer),
  HugeIconData('MCP Server', HugeIcons.strokeRoundedMcpServer),
  HugeIconData('Database', HugeIcons.strokeRoundedDatabase),
  HugeIconData('Database 01', HugeIcons.strokeRoundedDatabase01),
  HugeIconData('Database 02', HugeIcons.strokeRoundedDatabase02),
  HugeIconData('CPU', HugeIcons.strokeRoundedCpu),
  HugeIconData('Chip', HugeIcons.strokeRoundedChip),
  HugeIconData('Chip 02', HugeIcons.strokeRoundedChip02),
  HugeIconData('Computer', HugeIcons.strokeRoundedComputer),
  HugeIconData('Laptop', HugeIcons.strokeRoundedLaptop),
  HugeIconData('Computer Terminal', HugeIcons.strokeRoundedComputerTerminal01),
  HugeIconData('Code', HugeIcons.strokeRoundedCode),
  HugeIconData('AI Brain', HugeIcons.strokeRoundedAiBrain01),
  HugeIconData('AI Brain 02', HugeIcons.strokeRoundedAiBrain02),
  HugeIconData('AI Cloud', HugeIcons.strokeRoundedAiCloud),
  HugeIconData('AI Network', HugeIcons.strokeRoundedAiNetwork),
  HugeIconData('AI Chat', HugeIcons.strokeRoundedAiChat01),
  HugeIconData('Cellular Network', HugeIcons.strokeRoundedCellularNetwork),
  HugeIconData('Plug 01', HugeIcons.strokeRoundedPlug01),
  HugeIconData('Plug 02', HugeIcons.strokeRoundedPlug02),
  HugeIconData('Bot', HugeIcons.strokeRoundedRobot01),
  HugeIconData('Bot 02', HugeIcons.strokeRoundedRobot02),
  HugeIconData('Robotic', HugeIcons.strokeRoundedRobotic),
  HugeIconData('Rocket', HugeIcons.strokeRoundedRocket),
  HugeIconData('Star', HugeIcons.strokeRoundedStar),
  HugeIconData('Settings 01', HugeIcons.strokeRoundedSettings01),
  HugeIconData('Settings 02', HugeIcons.strokeRoundedSettings02),
  HugeIconData('Home', HugeIcons.strokeRoundedHome01),
  HugeIconData('Home 02', HugeIcons.strokeRoundedHome02),
  HugeIconData('Folder', HugeIcons.strokeRoundedFolder01),
  HugeIconData('Folder 02', HugeIcons.strokeRoundedFolder02),
  HugeIconData('File', HugeIcons.strokeRoundedFile01),
  HugeIconData('Lock', HugeIcons.strokeRoundedLock),
  HugeIconData('Key', HugeIcons.strokeRoundedKey01),
  HugeIconData('Link', HugeIcons.strokeRoundedLink01),
  HugeIconData('Globe', HugeIcons.strokeRoundedGlobe),
  HugeIconData('API', HugeIcons.strokeRoundedApi),
  HugeIconData('Arrow Right', HugeIcons.strokeRoundedArrowRight01),
  HugeIconData('Check Circle', HugeIcons.strokeRoundedCheckmarkCircle01),
  HugeIconData('Alert Circle', HugeIcons.strokeRoundedAlertCircle),
  HugeIconData('Info Circle', HugeIcons.strokeRoundedInformationCircle),
  HugeIconData('Zap', HugeIcons.strokeRoundedZap),
  HugeIconData('Cloud Upload', HugeIcons.strokeRoundedCloudUpload),
  HugeIconData('Cloud Download', HugeIcons.strokeRoundedCloudDownload),
  HugeIconData('Refresh', HugeIcons.strokeRoundedRefresh),
  HugeIconData('Hard Drive', HugeIcons.strokeRoundedHardDrive),
  HugeIconData('Drive', HugeIcons.strokeRoundedDrive),
];

class ServerIconPicker extends StatefulWidget {
  final String? selectedIconName;
  final ValueChanged<String> onIconSelected;

  const ServerIconPicker({
    super.key,
    this.selectedIconName,
    required this.onIconSelected,
  });

  @override
  State<ServerIconPicker> createState() => _ServerIconPickerState();
}

class _ServerIconPickerState extends State<ServerIconPicker> {
  late String? _selected;
  final TextEditingController _searchController = TextEditingController();
  List<HugeIconData> _filteredIcons = serverIcons;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedIconName;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterIcons(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredIcons = serverIcons;
      } else {
        _filteredIcons = serverIcons
            .where(
              (icon) => icon.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ShadSheet(
      title: const Text('Select Icon'),
      description: const Text('Choose an icon for your server'),
      child: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ShadInput(
                controller: _searchController,
                placeholder: const Text('Search icons...'),
                leading: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.search, size: 18),
                ),
                onChanged: _filterIcons,
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: _filteredIcons.length,
                itemBuilder: (context, index) {
                  final icon = _filteredIcons[index];
                  final isSelected = _selected == icon.name;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selected = icon.name;
                      });
                      widget.onIconSelected(icon.name);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? theme.colorScheme.primary.withValues(alpha: 0.2)
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          HugeIcon(
                            icon: icon.icon,
                            size: 24,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            icon.name,
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 8,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: ShadButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

HugeIconData? getHugeIconByName(String? name) {
  if (name == null) return null;
  try {
    return serverIcons.firstWhere((icon) => icon.name == name);
  } catch (_) {
    return null;
  }
}

HugeIconData? getDefaultServerIcon(String? serverType) {
  switch (serverType) {
    case 'lmStudio':
      return serverIcons.firstWhere(
        (icon) => icon.name == 'Computer Terminal',
        orElse: () => serverIcons.first,
      );
    case 'ollama':
      return serverIcons.firstWhere(
        (icon) => icon.name == 'Bot',
        orElse: () => serverIcons.first,
      );
    case 'openRouter':
      return serverIcons.firstWhere(
        (icon) => icon.name == 'Cloud',
        orElse: () => serverIcons.first,
      );
    default:
      return serverIcons.firstWhere(
        (icon) => icon.name == 'Server Stack',
        orElse: () => serverIcons.first,
      );
  }
}
