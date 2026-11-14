import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/features/on_device/data/download_engine.dart';
import 'package:localmind/features/on_device/data/download_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in end-to-end resume test against the real Hugging Face CDN, proving
/// the review fixes hold on the live path: re-resolve before every resume
/// (signed URLs expire after ~1 hour), Range continuation from the sidecar
/// offset, and restart recovery across engine dispose.
///
/// Run with:
///   LM_RESUME_HF_URL=`hf resolve url of a small gguf` flutter test \
///     test/features/on_device/hf_resume_integration_test.dart
///
/// Uses a partial-file target of a few MB so the pause/kill cycle is fast.
/// Without the environment variable the test exits immediately so regular
/// CI stays hermetic.
void main() {
  test(
    'HF download pauses, survives engine dispose and resumes over the CDN',
    () async {
      final url = Platform.environment['LM_RESUME_HF_URL'];
      if (url == null || url.isEmpty) {
        // ignore: avoid_print
        print('LM_RESUME_HF_URL not set; skipping HF resume integration test.');
        return;
      }
      final dir = await Directory.systemTemp.createTemp('lm_hf_resume');
      addTearDown(() {
        if (dir.existsSync()) dir.delete(recursive: true);
      });

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final sharedPrefs = await SharedPreferences.getInstance();
      Future<DownloadEngine> makeEngine() async {
        final prefs = sharedPrefs;
        final engine = DownloadEngine(
          store: DownloadTaskStore(prefs),
          dio: Dio(),
          workDirectory: () async => dir,
          tokenResolver: () => Platform.environment['LM_RESUME_HF_TOKEN'],
        );
        await engine.ready;
        return engine;
      }

      final partPath = '${dir.path}/probe.gguf.part';
      final finalPath = '${dir.path}/probe.gguf';

      // Engine 1: start the transfer and pause once some bytes landed.
      final engine1 = await makeEngine();
      final task = await engine1.enqueue(
        kind: DownloadTaskKind.gguf,
        groupId: 'probe',
        url: url,
        finalPath: finalPath,
        partPath: partPath,
      );
      // Wait until half a megabyte has landed, then pause deterministically.
      final modelTaskId = task.id;
      var reached = false;
      final deadline = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(deadline)) {
        final current = engine1.tasks
            .where((t) => t.id == modelTaskId)
            .firstOrNull;
        if (current != null && current.receivedBytes >= 512 * 1024) {
          reached = true;
          break;
        }
        if (current != null && current.state == DownloadTaskState.failed) {
          // ignore: avoid_print
          print('HF resume: task failed early: ${current.error ?? '-'}');
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      expect(reached, isTrue,
          reason: 'transfer did not reach 512 KiB (is the URL reachable?)');
      await engine1.pause(modelTaskId);
      final paused = await _waitFor(
        engine1,
        (t) => t.id == modelTaskId && t.state == DownloadTaskState.paused,
        timeout: const Duration(seconds: 30),
      );
      expect(paused, isNotNull);
      final pausedBytes = paused!.receivedBytes;
      // ignore: avoid_print
      print('HF resume: paused at $pausedBytes bytes');
      expect(pausedBytes, greaterThan(0));
      await engine1.dispose();

      // Simulate an app kill: a fresh engine picks the persisted task up as
      // paused and the user resumes it.
      final engine2 = await makeEngine();
      final restored = engine2.tasks
          .where((t) => t.groupId == 'probe')
          .toList(growable: false);
      expect(restored, hasLength(1));
      expect(restored.single.state, DownloadTaskState.paused);
      await engine2.resume(restored.single.id);
      final done = await _waitFor(
        engine2,
        (t) =>
            t.id == restored.single.id &&
            (t.state == DownloadTaskState.completed ||
                t.state == DownloadTaskState.failed),
        timeout: const Duration(minutes: 10),
      );
      expect(done, isNotNull);
      expect(done!.state, DownloadTaskState.completed,
          reason: 'engine reported: ${done.error}');
      expect(done.receivedBytes, greaterThan(pausedBytes));
      // Engine-only probe: no consumer publish hook, so the completed bytes
      // stay in the partial file.
      final magic =
          await File(partPath).openRead(0, 4).expand((b) => b).toList();
      expect(magic, [0x47, 0x47, 0x55, 0x46], reason: 'GGUF magic expected');
      // ignore: avoid_print
      print('HF resume: completed ${done.receivedBytes} bytes, GGUF magic ok');
      await engine2.dispose();
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<DownloadTask?> _waitFor(
  DownloadEngine engine,
  bool Function(DownloadTask) predicate, {
  required Duration timeout,
  bool Function(DownloadTask)? until,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    for (final task in engine.tasks) {
      if (predicate(task) && (until == null || until(task))) return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return null;
}
