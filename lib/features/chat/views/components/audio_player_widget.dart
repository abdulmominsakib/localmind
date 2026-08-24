import 'package:hugeicons/hugeicons.dart';
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:localmind/core/theme/colors.dart';

class AudioPlayerWidget extends StatefulWidget {
  final String source;
  final double? height;

  const AudioPlayerWidget({super.key, required this.source, this.height});

  bool get isUrl =>
      source.startsWith('http://') || source.startsWith('https://');

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  final AudioPlayer _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (mounted) setState(() => _state = s);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_state == PlayerState.playing) {
      await _player.pause();
    } else {
      if (_position == _duration || _position == Duration.zero) {
        if (widget.isUrl) {
          await _player.play(UrlSource(widget.source));
        } else {
          await _player.play(DeviceFileSource(widget.source));
        }
      } else {
        await _player.resume();
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fileName = widget.source.split('/').last;

    return Container(
      height: widget.height ?? 56,
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurfaceCard : AppColors.lightSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: HugeIcon(
              icon: _state == PlayerState.playing
                  ? HugeIcons.strokeRoundedPauseCircle
                  : HugeIcons.strokeRoundedPlayCircle,
              size: 28,
              color: isDark ? Colors.white : Colors.black87,
            ),
            onPressed: _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatDuration(_position),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: _duration.inMilliseconds > 0
                                ? _position.inMilliseconds /
                                      _duration.inMilliseconds
                                : 0,
                            backgroundColor: isDark
                                ? Colors.white12
                                : Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? Colors.white60 : Colors.black54,
                            ),
                            minHeight: 3,
                          ),
                        ),
                      ),
                    ),
                    Text(
                      _formatDuration(_duration),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
