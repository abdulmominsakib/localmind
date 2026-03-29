import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:hugeicons/styles/stroke_rounded.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class HugeIconData {
  final String name;
  final List<List<dynamic>> iconData;

  const HugeIconData(this.name, this.iconData);
}

const List<HugeIconData> serverIcons = [
  HugeIconData('Server Stack', HugeIconsStrokeRounded.serverStack01),
  HugeIconData('Server Stack 02', HugeIconsStrokeRounded.serverStack02),
  HugeIconData('Server Stack 03', HugeIconsStrokeRounded.serverStack03),
  HugeIconData('Cloud', HugeIconsStrokeRounded.cloud),
  HugeIconData('Cloud Server', HugeIconsStrokeRounded.cloudServer),
  HugeIconData('MCP Server', HugeIconsStrokeRounded.mcpServer),
  HugeIconData('Database', HugeIconsStrokeRounded.database),
  HugeIconData('Database 01', HugeIconsStrokeRounded.database01),
  HugeIconData('Database 02', HugeIconsStrokeRounded.database02),
  HugeIconData('CPU', HugeIconsStrokeRounded.cpu),
  HugeIconData('Chip', HugeIconsStrokeRounded.chip),
  HugeIconData('Chip 02', HugeIconsStrokeRounded.chip02),
  HugeIconData('Computer', HugeIconsStrokeRounded.computer),
  HugeIconData('Laptop', HugeIconsStrokeRounded.laptop),
  HugeIconData('Computer Terminal', HugeIconsStrokeRounded.computerTerminal01),
  HugeIconData('Code', HugeIconsStrokeRounded.code),
  HugeIconData('AI Brain', HugeIconsStrokeRounded.aiBrain01),
  HugeIconData('AI Brain 02', HugeIconsStrokeRounded.aiBrain02),
  HugeIconData('AI Cloud', HugeIconsStrokeRounded.aiCloud),
  HugeIconData('AI Network', HugeIconsStrokeRounded.aiNetwork),
  HugeIconData('AI Chat', HugeIconsStrokeRounded.aiChat01),
  HugeIconData('Cellular Network', HugeIconsStrokeRounded.cellularNetwork),
  HugeIconData('Plug 01', HugeIconsStrokeRounded.plug01),
  HugeIconData('Plug 02', HugeIconsStrokeRounded.plug02),
  HugeIconData('Bot', HugeIconsStrokeRounded.robot01),
  HugeIconData('Bot 02', HugeIconsStrokeRounded.robot02),
  HugeIconData('Robotic', HugeIconsStrokeRounded.robotic),
  HugeIconData('Rocket', HugeIconsStrokeRounded.rocket),
  HugeIconData('Star', HugeIconsStrokeRounded.star),
  HugeIconData('Settings 01', HugeIconsStrokeRounded.settings01),
  HugeIconData('Settings 02', HugeIconsStrokeRounded.settings02),
  HugeIconData('Home', HugeIconsStrokeRounded.home01),
  HugeIconData('Home 02', HugeIconsStrokeRounded.home02),
  HugeIconData('Folder', HugeIconsStrokeRounded.folder01),
  HugeIconData('Folder 02', HugeIconsStrokeRounded.folder02),
  HugeIconData('File', HugeIconsStrokeRounded.file01),
  HugeIconData('Lock', HugeIconsStrokeRounded.lock),
  HugeIconData('Key', HugeIconsStrokeRounded.key01),
  HugeIconData('Link', HugeIconsStrokeRounded.link01),
  HugeIconData('Globe', HugeIconsStrokeRounded.globe),
  HugeIconData('API', HugeIconsStrokeRounded.api),
  HugeIconData('Arrow Right', HugeIconsStrokeRounded.arrowRight01),
  HugeIconData('Check Circle', HugeIconsStrokeRounded.checkmarkCircle01),
  HugeIconData('Alert Circle', HugeIconsStrokeRounded.alertCircle),
  HugeIconData('Info Circle', HugeIconsStrokeRounded.informationCircle),
  HugeIconData('Zap', HugeIconsStrokeRounded.zap),
  HugeIconData('Cloud Upload', HugeIconsStrokeRounded.cloudUpload),
  HugeIconData('Cloud Download', HugeIconsStrokeRounded.cloudDownload),
  HugeIconData('Refresh', HugeIconsStrokeRounded.refresh),
  HugeIconData('Hard Drive', HugeIconsStrokeRounded.hardDrive),
  HugeIconData('Drive', HugeIconsStrokeRounded.drive),
];

class HugeIcon extends StatelessWidget {
  final List<List<dynamic>> iconData;
  final double size;
  final Color? color;

  const HugeIcon(this.iconData, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _HugeIconPainter(
        iconData: iconData,
        color: color ?? Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _HugeIconPainter extends CustomPainter {
  final List<List<dynamic>> iconData;
  final Color color;

  _HugeIconPainter({required this.iconData, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final pathData in iconData) {
      if (pathData[0] == 'path') {
        final pathMap = pathData[1] as Map<dynamic, dynamic>;
        final d = pathMap['d'] as String;
        final strokeWidth = pathMap['strokeWidth'];
        final strokeLinecap = pathMap['strokeLinecap'];
        final strokeLinejoin = pathMap['strokeLinejoin'];

        if (strokeWidth != null) {
          paint.strokeWidth = double.parse(strokeWidth.toString());
        }
        if (strokeLinecap == 'round') {
          paint.strokeCap = StrokeCap.round;
        }
        if (strokeLinejoin == 'round') {
          paint.strokeJoin = StrokeJoin.round;
        }

        final path = _parseSvgPath(d);
        canvas.drawPath(path, paint);
      }
    }
  }

  Path _parseSvgPath(String d) {
    final path = Path();
    final commands = RegExp(
      r'([MmLlHhVvCcSsQqTtAaZz])([^MmLlHhVvCcSsQqTtAaZz]*)',
    ).allMatches(d);

    for (final match in commands) {
      final command = match.group(1)!;
      final argsStr = match.group(2)?.trim() ?? '';
      final args = argsStr.isEmpty
          ? <double>[]
          : argsStr
                .split(RegExp(r'[\s,]+'))
                .where((s) => s.isNotEmpty)
                .map(double.parse)
                .toList();

      switch (command) {
        case 'M':
          if (args.isNotEmpty) {
            path.moveTo(args[0], args[1]);
            for (int i = 2; i < args.length; i += 2) {
              path.lineTo(args[i], args[i + 1]);
            }
          }
          break;
        case 'm':
          if (args.isNotEmpty) {
            path.moveTo(args[0], args[1]);
            for (int i = 2; i < args.length; i += 2) {
              path.relativeLineTo(args[i], args[i + 1]);
            }
          }
          break;
        case 'L':
          for (int i = 0; i < args.length; i += 2) {
            path.lineTo(args[i], args[i + 1]);
          }
          break;
        case 'l':
          for (int i = 0; i < args.length; i += 2) {
            path.relativeLineTo(args[i], args[i + 1]);
          }
          break;
        case 'H':
          for (final x in args) {
            path.lineTo(x, path.getBounds().bottom);
          }
          break;
        case 'h':
          for (final dx in args) {
            path.relativeLineTo(dx, 0);
          }
          break;
        case 'V':
          for (final y in args) {
            path.lineTo(path.getBounds().right, y);
          }
          break;
        case 'v':
          for (final dy in args) {
            path.relativeLineTo(0, dy);
          }
          break;
        case 'C':
          for (int i = 0; i < args.length; i += 6) {
            path.cubicTo(
              args[i],
              args[i + 1],
              args[i + 2],
              args[i + 3],
              args[i + 4],
              args[i + 5],
            );
          }
          break;
        case 'c':
          for (int i = 0; i < args.length; i += 6) {
            path.relativeCubicTo(
              args[i],
              args[i + 1],
              args[i + 2],
              args[i + 3],
              args[i + 4],
              args[i + 5],
            );
          }
          break;
        case 'Q':
          for (int i = 0; i < args.length; i += 4) {
            path.quadraticBezierTo(
              args[i],
              args[i + 1],
              args[i + 2],
              args[i + 3],
            );
          }
          break;
        case 'q':
          for (int i = 0; i < args.length; i += 4) {
            path.relativeQuadraticBezierTo(
              args[i],
              args[i + 1],
              args[i + 2],
              args[i + 3],
            );
          }
          break;
        case 'Z':
        case 'z':
          path.close();
          break;
      }
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _HugeIconPainter oldDelegate) {
    return oldDelegate.iconData != iconData || oldDelegate.color != color;
  }
}

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
                            icon.iconData,
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
