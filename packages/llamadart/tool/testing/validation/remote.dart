import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'bundle.dart';
import 'image_profile.dart';
import 'npu.dart';
import 'process.dart';

Object? _freeze(Object? value) => value is Map
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, item) => MapEntry(key as String, _freeze(item))),
      )
    : value is List
    ? List<dynamic>.unmodifiable(value.map(_freeze))
    : value;

// Budget inputs are decimal USD. Scaling their binary doubles can cross a cent
// boundary, so round the canonical decimal form with integer arithmetic.
BigInt _usdCents(num value, {required bool roundUp}) {
  final parts = value.toString().toLowerCase().split('e');
  final decimal = parts.first.split('.');
  final coefficient = BigInt.parse(decimal.join());
  final exponent = parts.length == 1 ? 0 : int.parse(parts.last);
  final fractionalDigits = decimal.length == 1 ? 0 : decimal.last.length;
  final shift = exponent + 2 - fractionalDigits;
  if (shift >= 0) return coefficient * BigInt.from(10).pow(shift);
  final divisor = BigInt.from(10).pow(-shift);
  final cents = coefficient ~/ divisor;
  return roundUp && coefficient.remainder(divisor) != BigInt.zero
      ? cents + BigInt.one
      : cents;
}

/// Explicit provider/account configuration and immutable upload identity.
class RemotePlan {
  RemotePlan(Map<String, dynamic> input)
    : json = _freeze(input) as Map<String, dynamic> {
    validate();
  }
  final Map<String, dynamic> json;
  String get runId => json['run_id'] as String;
  String get target => json['target'] as String;
  String get project => json['project'] as String;
  String get account => json['account'] as String;
  String get bundle => json['bundle'] as String;
  String get profile => json['profile'] as String;
  Map<String, dynamic> get settings => json['settings'] as Map<String, dynamic>;
  bool get firebase => target.startsWith('firebase-');
  bool get blaze => firebase && settings['billing_mode'] == 'blaze';
  bool get windows => target == 'gce-windows-cuda';

  static const firebaseTimeoutMinutes = 20;
  static const firebasePhysicalHourlyUsd = 5;
  int get testTimeoutMinutes =>
      settings['test_timeout_minutes'] as int? ?? firebaseTimeoutMinutes;
  bool get usesFreeAllowance =>
      blaze && (settings['budget'] as Map?)?['funding'] == 'free_allowance';

  /// Gross cost reservation, before any free allowance or promotional credit.
  /// Fractional cents round up; exact decimal cents remain unchanged.
  int get reservedUsdCents {
    final cents = _usdCents(
      (settings['budget'] as Map)['maximum_run_usd'] as num,
      roundUp: true,
    );
    if (!cents.isValidInt) {
      throw StateError('USD reservation exceeds the supported integer range');
    }
    return cents.toInt();
  }

  void validate() {
    if (json['schema_version'] != 1 ||
        !const [
          'firebase-android',
          'firebase-ios',
          'gce-linux-cuda',
          'gce-windows-cuda',
        ].contains(target)) {
      throw const FormatException('Invalid remote target/schema');
    }
    for (final value in [runId, project, profile]) {
      if (!RegExp(r'^[a-z][a-z0-9-]{0,62}$').hasMatch(value)) {
        throw const FormatException('Invalid remote identifier');
      }
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(account)) {
      throw const FormatException('Explicit account email required');
    }
    if (!p.isAbsolute(bundle) ||
        !RegExp(
          r'^[0-9a-f]{64}$',
        ).hasMatch(json['bundle_sha256'] as String? ?? '')) {
      throw const FormatException(
        'Absolute verified bundle and checksum required',
      );
    }
    if (firebase) {
      if (settings['test_timeout_minutes'] != null &&
          (settings['test_timeout_minutes'] is! int ||
              testTimeoutMinutes < 1 ||
              testTimeoutMinutes > firebaseTimeoutMinutes)) {
        throw const FormatException('Firebase timeout must be 1-20 minutes');
      }
      if (!const [null, 'spark', 'blaze'].contains(settings['billing_mode'])) {
        throw const FormatException(
          'Firebase billing_mode must be spark or blaze',
        );
      }
      if (blaze &&
          !RegExp(
            r'^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$',
          ).hasMatch(settings['billing_account'] as String? ?? '')) {
        throw const FormatException(
          'Blaze requires an exact billing account ID',
        );
      }
      for (final field in ['device_model', 'device_version']) {
        if (!RegExp(
          r'^[A-Za-z0-9_.-]+$',
        ).hasMatch(settings[field] as String? ?? '')) {
          throw FormatException('Exact Firebase $field required');
        }
      }
    } else {
      for (final field in ['zone', 'machine_type', 'network', 'iap_tag']) {
        if (!RegExp(
          r'^[a-z0-9-]+$',
        ).hasMatch(settings[field] as String? ?? '')) {
          throw FormatException('Explicit GCE $field required');
        }
      }
      final image = settings['image'] as String? ?? '';
      if (!RegExp(
        r'^projects/[a-z0-9-]+/global/images/[a-z0-9-]+$',
      ).hasMatch(image)) {
        throw const FormatException(
          'Use an immutable GCE image, not an image family',
        );
      }
      if (settings['gpu_ready_image'] != true ||
          (settings['driver_version'] as String? ?? '').isEmpty) {
        throw const FormatException(
          'A qualified GPU-ready image and expected driver version are required',
        );
      }
      if (settings['accelerator'] != null &&
          !RegExp(
            r'^[a-z0-9-]+$',
          ).hasMatch(settings['accelerator'] as String)) {
        throw const FormatException('Invalid accelerator type');
      }
      final disk = settings['disk_gb'] as int? ?? 40;
      if (disk < 20 || disk > 100) {
        throw const FormatException('Disk size must be 20-100 GB');
      }
    }
  }

  /// Enforces dated quota/credit evidence; this is not a billing guarantee.
  void validateBudget(DateTime now) {
    final receipt = _receipt(firebase ? 'quota' : 'credit', now);
    if (firebase) {
      if ((receipt['remaining_physical'] as int? ?? 0) < 1) {
        throw StateError('No physical execution quota');
      }
      if (blaze) _validateBlazeBudget(now);
    } else {
      _validateCredit(receipt, now);
    }
  }

  Map _receipt(String name, DateTime now) {
    final receipt = settings[name] as Map?;
    if (receipt == null) {
      throw StateError('Missing current $name evidence');
    }
    final verified = DateTime.tryParse(receipt['verified_at'] as String? ?? '');
    if (verified == null ||
        verified.isAfter(now) ||
        now.difference(verified) > const Duration(minutes: 15)) {
      throw StateError(
        'Budget evidence must be verified within the last 15 minutes',
      );
    }
    if ((receipt['evidence'] as String? ?? '').trim().isEmpty) {
      throw StateError('Budget evidence must identify its checked source');
    }
    return receipt;
  }

  void _validateCredit(Map receipt, DateTime now, {num? requiredUsd}) {
    final expiry = DateTime.tryParse(receipt['expires_at'] as String? ?? '');
    final balance = receipt['available_usd'] as num? ?? 0;
    final maximum = requiredUsd ?? receipt['maximum_run_usd'] as num? ?? 0;
    if (receipt['applicable'] != true ||
        expiry == null ||
        expiry.difference(now) < const Duration(hours: 2) ||
        !maximum.isFinite ||
        !balance.isFinite ||
        maximum <= 0 ||
        balance < maximum * 2) {
      throw StateError(
        'Credit must cover all run costs with reserve and expiry margin',
      );
    }
  }

  void _validateBlazeBudget(DateTime now) {
    final budget = _receipt('budget', now);
    final start = DateTime.tryParse(budget['window_start'] as String? ?? '');
    final end = DateTime.tryParse(budget['expires_at'] as String? ?? '');
    final perRun = budget['maximum_run_usd'] as num? ?? 0;
    final total = budget['maximum_total_usd'] as num? ?? 0;
    if (start == null ||
        end == null ||
        start.isAfter(now) ||
        end.difference(now) < const Duration(hours: 1) ||
        end.difference(start) > const Duration(hours: 24) ||
        !perRun.isFinite ||
        !total.isFinite ||
        perRun < testTimeoutMinutes * firebasePhysicalHourlyUsd / 60 ||
        total < perRun ||
        !const [
          'credit',
          'approved_charges',
          'free_allowance',
        ].contains(budget['funding'])) {
      throw StateError(
        'Blaze requires a bounded, authorized gross-cost budget',
      );
    }
    if (budget['funding'] == 'credit') {
      _validateCredit(_receipt('credit', now), now, requiredUsd: total);
    } else if (usesFreeAllowance) {
      final allowance = _receipt('free_allowance', now);
      final remaining = allowance['remaining_physical_minutes'];
      if (remaining is! int ||
          remaining > 30 ||
          remaining < testTimeoutMinutes + 1 ||
          DateTime.parse(allowance['verified_at'] as String).isBefore(start)) {
        throw StateError(
          'Verified free minutes must cover the timeout plus a rounding reserve',
        );
      }
    }
  }
}

/// Safe categories, never provider response bodies or credential-bearing URLs.
enum RemoteFailureKind {
  authentication,
  http,
  timeout,
  transport,
  invalidResponse,
}

/// A provider failure whose journal representation cannot contain secrets.
class RemoteProviderFailure implements Exception {
  const RemoteProviderFailure(this.kind, {this.httpStatus});
  final RemoteFailureKind kind;
  final int? httpStatus;

  bool get retryable =>
      kind == RemoteFailureKind.timeout ||
      kind == RemoteFailureKind.transport ||
      (kind == RemoteFailureKind.http &&
          (httpStatus == 408 ||
              httpStatus == 429 ||
              (httpStatus != null && httpStatus! >= 500)));

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    if (httpStatus != null) 'http_status': httpStatus,
  };
}

/// An assessment step failure whose [message] is redacted, so the controller
/// records it as the run's `error`.
class ValidationAssessmentFailure implements Exception {
  const ValidationAssessmentFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

Map<String, dynamic> _safeFailure(Object error, String operation) => {
  'operation': operation,
  'error_type': error.runtimeType.toString(),
  if (error is RemoteProviderFailure) ...error.toJson(),
};

/// Provider adapter boundary exercised with deterministic fake responses.
abstract interface class RemoteProvider {
  Future<void> preflight(RemotePlan plan);
  Future<Map<String, dynamic>> identify(RemotePlan plan, String remoteId);
  Future<Map<String, dynamic>> start(
    RemotePlan plan,
    void Function(Map<String, dynamic>) checkpoint,
  );
  Future<Map<String, dynamic>> status(
    RemotePlan plan,
    Map<String, dynamic> remote,
  );
  Future<void> collect(
    RemotePlan plan,
    Map<String, dynamic> remote,
    Directory output,
  );
  Future<Map<String, dynamic>> cleanup(
    RemotePlan plan,
    Map<String, dynamic> remote,
  );
}

class _OperationLock {
  _OperationLock(this.file, this.onRelease);
  final RandomAccessFile file;
  final void Function() onRelease;
  void release() {
    try {
      file.unlockSync();
    } finally {
      file.closeSync();
      onRelease();
    }
  }
}

/// Binds uploaded and replayed bundles to the saved target, including GCE ABI.
void requireRemoteBundleTarget(RemotePlan plan, Map<String, dynamic> manifest) {
  final expectedTarget = plan.firebase
      ? (plan.windows ? 'invalid' : plan.target.substring(9))
      : 'desktop';
  if (manifest['target'] != expectedTarget) {
    throw StateError('Bundle target mismatch');
  }
  if (plan.firebase && manifest['profile'] != plan.profile) {
    throw StateError('Compiled mobile profile mismatch');
  }
  if (!plan.firebase &&
      (manifest['build_os'] != (plan.windows ? 'windows' : 'linux') ||
          manifest['build_abi'] !=
              (plan.windows ? 'windows_x64' : 'linux_x64'))) {
    throw StateError('GCE requires a matching x64 OS bundle');
  }
}

/// Persists intent before mutation and never replaces an uncertain submission.
class RemoteController {
  static final _lockedRoots = <String>{};
  RemoteController(
    this.root,
    this.provider, {
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
    this.assess,
  }) : now = now ?? DateTime.now,
       delay = delay ?? Future<void>.delayed;
  final Future<bool> Function(RemotePlan, Directory)? assess;
  bool cancelled = false;
  void cancel() => cancelled = true;
  final Directory root;
  final RemoteProvider provider;
  final DateTime Function() now;
  final Future<void> Function(Duration) delay;

  File _journal(String id) => File(p.join(root.path, id, 'orchestration.json'));
  void _save(String id, Map<String, dynamic> state) {
    final file = _journal(id);
    file.parent.createSync(recursive: true);
    final temporary = File('${file.path}.tmp');
    temporary.writeAsStringSync(jsonEncode(state), flush: true);
    temporary.renameSync(file.path);
  }

  Map<String, dynamic> read(String id) =>
      jsonDecode(_journal(id).readAsStringSync()) as Map<String, dynamic>;

  Future<void> _verifyUpload(RemotePlan plan) async {
    final bundle = Directory(plan.bundle);
    final manifest = await verifyBundle(bundle);
    if (manifest['source_dirty'] != false) {
      throw StateError('Remote runs require a clean committed bundle');
    }
    requireRemoteBundleTarget(plan, manifest);
    final profileFile = File(
      p.join(
        bundle.path,
        plan.firebase ? 'profile.json' : 'assets/profiles/${plan.profile}.json',
      ),
    );
    final profile = jsonDecode(profileFile.readAsStringSync()) as Map;
    final npu = manifest['npu'];
    final validNpu =
        plan.target == 'firebase-android' &&
        npu is Map &&
        npu['schema_version'] == 1 &&
        npu['runtime_tag'] == npuRuntimeTag &&
        npu['model_sha256'] == (profile['model'] as Map?)?['sha256'] &&
        npu['device_model'] == plan.settings['device_model'] &&
        manifest['execution_path'] == profile['execution_path'];
    requireExecutableValidationProfile(profile, verifiedAndroidKit: validNpu);
    if (isImageGenerationProfile(profile)) {
      requireImageGenerationProfile(profile, manifest['target'] as String);
      if (manifest['test_target'] != imageProfileTestTarget(profile) ||
          manifest['stable_diffusion_tag'] is! String) {
        throw StateError('Image bundle lacks its test target or runtime pin');
      }
    }
    if (profile['backend'] == 'npu') {
      var checkout = Directory.current.absolute;
      while (!File(
        p.join(checkout.path, 'tool/testing/validation/check_npu_apk.py'),
      ).existsSync()) {
        if (checkout.parent.path == checkout.path) {
          throw StateError('Cannot locate NPU APK verifier');
        }
        checkout = checkout.parent;
      }
      await verifyNpuApks(checkout.path, bundle);
    }
    if (profile['id'] != plan.profile ||
        (!plan.firebase &&
            (profile['backend'] != 'cuda' || profile['runtime'] != 'gguf'))) {
      throw StateError('Profile/backend is incompatible with remote target');
    }
    final digest = await sha256
        .bind(File(p.join(bundle.path, 'bundle-manifest.json')).openRead())
        .first;
    if (digest.toString() != plan.json['bundle_sha256']) {
      throw StateError('Bundle changed after planning');
    }
  }

  /// Executes one attempt. Reusing an ID cannot consume quota twice.
  Future<Map<String, dynamic>> run(RemotePlan plan) async {
    root.createSync(recursive: true);
    final lock = _lock();
    // The duplicate check must be inside the same lock as dispatch.
    if (_journal(plan.runId).existsSync()) {
      lock.release();
      throw StateError('Run already exists; use status, collect or cleanup');
    }
    var started = false;
    final state = <String, dynamic>{
      'schema_version': 1,
      'plan': plan.json,
      'phase': 'PREFLIGHT',
      'cleanup': 'NOT_REQUIRED',
      'remote': <String, dynamic>{},
    };
    try {
      for (final directory in root.listSync().whereType<Directory>()) {
        final file = File(p.join(directory.path, 'orchestration.json'));
        if (!file.existsSync()) continue;
        final prior = jsonDecode(file.readAsStringSync()) as Map;
        if (prior['cleanup'] != 'VERIFIED' &&
            prior['cleanup'] != 'NOT_REQUIRED') {
          throw StateError('An earlier remote run has unresolved cleanup');
        }
      }
      plan.validateBudget(now().toUtc());
      if (plan.firebase) {
        final cutoff = plan.blaze
            ? DateTime.parse(
                (plan.settings['budget'] as Map)['window_start'] as String,
              )
            : now().toUtc().subtract(const Duration(hours: 24));
        var count = 0;
        var reserved = BigInt.zero;
        var reservedMinutes = 0;
        final allowanceChecked = plan.usesFreeAllowance
            ? DateTime.parse(
                (plan.settings['free_allowance'] as Map)['verified_at']
                    as String,
              )
            : null;
        for (final directory in root.listSync().whereType<Directory>()) {
          final file = File(p.join(directory.path, 'orchestration.json'));
          if (file.existsSync()) {
            final previous = jsonDecode(file.readAsStringSync()) as Map;
            if ((DateTime.tryParse(
                      previous['dispatched_at'] as String? ?? '',
                    )?.isBefore(cutoff) ==
                    false) &&
                (previous['plan'] as Map?)?['project'] == plan.project &&
                ((previous['plan'] as Map?)?['target'] as String? ?? '')
                    .startsWith('firebase-')) {
              count++;
              if (plan.blaze &&
                  ((previous['plan'] as Map?)?['settings']
                          as Map?)?['billing_mode'] ==
                      'blaze') {
                final cost = previous['reserved_usd_cents'];
                if (cost is! int || cost <= 0) {
                  throw StateError(
                    'Earlier Blaze submission has no cost reservation',
                  );
                }
                reserved += BigInt.from(cost);
                final dispatched = DateTime.parse(
                  previous['dispatched_at'] as String,
                );
                if (allowanceChecked != null &&
                    !dispatched.isBefore(allowanceChecked)) {
                  final minutes = previous['reserved_physical_minutes'];
                  if (minutes is! int || minutes <= 0) {
                    throw StateError(
                      'Earlier Blaze submission has no minute reservation',
                    );
                  }
                  reservedMinutes += minutes;
                }
              }
            }
          }
        }
        if (plan.blaze) {
          final total =
              (plan.settings['budget'] as Map)['maximum_total_usd'] as num;
          if (reserved + BigInt.from(plan.reservedUsdCents) >
              _usdCents(total, roundUp: false)) {
            throw StateError(
              'Blaze budget is already reserved by earlier submissions',
            );
          }
          state['reserved_usd_cents'] = plan.reservedUsdCents;
          state['reserved_physical_minutes'] = plan.testTimeoutMinutes + 1;
          if (plan.usesFreeAllowance &&
              reservedMinutes + plan.testTimeoutMinutes + 1 >
                  (plan.settings['free_allowance']
                      as Map)['remaining_physical_minutes']) {
            throw StateError(
              'Free minutes are already reserved by earlier submissions',
            );
          }
        } else if (count >= 4) {
          throw StateError(
            'Four physical submissions already dispatched in the last 24 hours',
          );
        }
      }
      await _verifyUpload(plan);
      await provider.preflight(plan);
      plan.validateBudget(now().toUtc());
      if (cancelled) throw StateError('Cancelled before submission');
      state['phase'] = 'SUBMITTING';
      state['cleanup'] = 'UNKNOWN';
      state['dispatched_at'] = now().toUtc().toIso8601String();
      state['deadline'] = now()
          .toUtc()
          .add(Duration(minutes: plan.firebase ? 45 : 60))
          .toIso8601String();
      _save(plan.runId, state);
      started = true;
      state['remote'] = await provider.start(plan, (remote) {
        (state['remote'] as Map).addAll(remote);
        _save(plan.runId, state);
        if (cancelled) throw StateError('Cancelled during setup');
      });
      state['phase'] = 'RUNNING';
      _save(plan.runId, state);
      final deadline = DateTime.parse(state['deadline'] as String);
      var consecutivePollFailures = 0;
      while (true) {
        if (cancelled) throw StateError('Run cancelled by operator');
        if (!now().isBefore(deadline)) {
          throw TimeoutException('Remote run deadline exceeded');
        }
        final Map<String, dynamic> result;
        try {
          result = await provider.status(
            plan,
            Map<String, dynamic>.from(state['remote'] as Map),
          );
          consecutivePollFailures = 0;
        } on RemoteProviderFailure catch (error) {
          consecutivePollFailures++;
          final failures =
              state.putIfAbsent('poll_failures', () => <dynamic>[]) as List;
          failures.add({
            ..._safeFailure(error, 'status'),
            'attempt': consecutivePollFailures,
          });
          if (failures.length > 16) failures.removeAt(0);
          _save(plan.runId, state);
          if (!error.retryable ||
              consecutivePollFailures >= 3 ||
              !now().isBefore(deadline)) {
            rethrow;
          }
          await delay(Duration(seconds: consecutivePollFailures * 2));
          continue;
        }
        (state['remote'] as Map).addAll(result);
        _save(plan.runId, state);
        if (result['terminal'] == true) break;
        if (!now().isBefore(deadline)) {
          throw TimeoutException('Remote run deadline exceeded');
        }
        await delay(const Duration(seconds: 15));
      }
      state['phase'] = 'COLLECTING';
      _save(plan.runId, state);
      await provider.collect(
        plan,
        Map<String, dynamic>.from(state['remote'] as Map),
        Directory(p.join(root.path, plan.runId, 'remote-results')),
      );
      state['collection'] = 'COMPLETE';
    } catch (error) {
      state['failure'] = _safeFailure(error, state['phase'] as String);
      state['error'] =
          'Remote operation failed (${error.runtimeType}); inspect journal failure diagnostics';
      state['phase'] = started ? 'INTERRUPTED' : 'PREFLIGHT_FAILED';
      _save(plan.runId, state);
    } finally {
      if (started) {
        // GCE results must be retrieved before deleting its disk. Firebase
        // artifacts remain available and must be collected after cancellation.
        if (!plan.firebase &&
            state['collection'] != 'COMPLETE' &&
            (state['remote'] as Map).isNotEmpty) {
          try {
            await provider.collect(
              plan,
              Map<String, dynamic>.from(state['remote'] as Map),
              Directory(p.join(root.path, plan.runId, 'remote-results')),
            );
            state['collection'] = 'COMPLETE';
          } catch (_) {
            state['collection'] = 'INCOMPLETE';
          }
        }
        try {
          final cleanup = await provider.cleanup(
            plan,
            Map<String, dynamic>.from(state['remote'] as Map),
          );
          state['cleanup_details'] = cleanup;
          state['cleanup'] = cleanup['verified'] == true
              ? 'VERIFIED'
              : 'UNKNOWN';
        } catch (_) {
          state['cleanup'] = 'UNKNOWN';
        }
        if (plan.firebase &&
            state['collection'] != 'COMPLETE' &&
            (state['remote'] as Map).isNotEmpty) {
          try {
            final terminal = await provider.status(
              plan,
              Map<String, dynamic>.from(state['remote'] as Map),
            );
            (state['remote'] as Map).addAll(terminal);
            if (terminal['terminal'] != true) {
              throw StateError(
                'Final Firebase artifacts are not available yet',
              );
            }
            await provider.collect(
              plan,
              Map<String, dynamic>.from(state['remote'] as Map),
              Directory(p.join(root.path, plan.runId, 'remote-results')),
            );
            state['collection'] = 'COMPLETE';
          } catch (error) {
            state['collection'] = 'INCOMPLETE';
            state['collection_failure'] = _safeFailure(
              error,
              'collect_terminal',
            );
          }
        }
        await _finishAssessment(plan, state);
        _save(plan.runId, state);
        File(p.join(root.path, plan.runId, 'cleanup.json')).writeAsStringSync(
          jsonEncode({
            'status': state['cleanup'],
            'details': state['cleanup_details'],
          }),
          flush: true,
        );
      }
      lock.release();
    }
    return state;
  }

  _OperationLock _lock() {
    root.createSync(recursive: true);
    final key = root.resolveSymbolicLinksSync();
    if (_lockedRoots.contains(key)) {
      throw StateError('Another remote operation is active');
    }
    final file = File(
      p.join(root.path, '.remote.lock'),
    ).openSync(mode: FileMode.append);
    _lockedRoots.add(key);
    try {
      // OS-held lock releases on process exit, without deleting another owner's file.
      file.lockSync(FileLock.exclusive);
      return _OperationLock(file, () => _lockedRoots.remove(key));
    } catch (_) {
      _lockedRoots.remove(key);
      file.closeSync();
      throw StateError('Another remote operation is active');
    }
  }

  Future<void> _finishAssessment(
    RemotePlan plan,
    Map<String, dynamic> state,
  ) async {
    final remote = state['remote'] as Map;
    final providerPassed = savedProviderPassed(plan, remote);
    var assertions = false;
    final previousFailure = state.remove('assessment_error');
    if (previousFailure != null && state['error'] == previousFailure) {
      state['error'] = null;
    }
    if (state['collection'] == 'COMPLETE' && assess != null) {
      try {
        assertions = await assess!(
          plan,
          Directory(p.join(root.path, plan.runId)),
        );
      } on ValidationAssessmentFailure catch (failure) {
        state['assessment'] = 'INCOMPLETE';
        if (state['error'] == null) {
          state['error'] = state['assessment_error'] = failure.message;
        }
      } catch (_) {
        state['assessment'] = 'INCOMPLETE';
      }
    }
    state['qualified'] =
        providerPassed &&
        assertions &&
        state['error'] == null &&
        state['cleanup'] == 'VERIFIED';
    if (state['collection'] == 'COMPLETE' && state['cleanup'] == 'VERIFIED') {
      state['phase'] = state['qualified'] == true ? 'COMPLETE' : 'FAILED';
    }
    File(
      p.join(root.path, plan.runId, 'remote-summary.json'),
    ).writeAsStringSync(
      jsonEncode({
        'qualified': state['qualified'],
        'provider_passed': providerPassed,
        'assertions_passed': assertions,
        'cleanup': state['cleanup'],
        'collection': state['collection'],
        'error': state['error'],
      }),
      flush: true,
    );
  }

  /// Reads a saved run under the lifecycle lock, without consulting a provider.
  Future<Map<String, dynamic>> reassess(
    String id,
    Directory output, {
    required Future<Map<String, dynamic>> Function(Directory, Directory) replay,
  }) async {
    if (!RegExp(r'^qa-[a-z0-9-]+$').hasMatch(id)) {
      throw const FormatException('Invalid run ID');
    }
    final lock = _lock();
    try {
      return await replay(Directory(p.join(root.path, id)), output);
    } finally {
      lock.release();
    }
  }

  /// Recovery operations use saved IDs under the same lock; never resubmit.
  Future<Map<String, dynamic>> recover(
    String id,
    String action, {
    String? remoteId,
  }) async {
    if (!RegExp(r'^[a-z][a-z0-9-]{0,62}$').hasMatch(id)) {
      throw const FormatException('Invalid run id');
    }
    final lock = _lock();
    Map<String, dynamic>? recoveryState;
    try {
      final state = read(id);
      recoveryState = state;
      final plan = RemotePlan(Map<String, dynamic>.from(state['plan'] as Map));
      final remote = Map<String, dynamic>.from(state['remote'] as Map);
      if (action == 'reconcile') {
        if (remoteId == null || state['dispatched_at'] == null) {
          throw StateError(
            'Reconciliation requires a submitted run and remote ID',
          );
        }
        final key = plan.firebase ? 'matrix_id' : 'instance_id';
        if (remote[key] != null && remote[key] != remoteId) {
          throw StateError('Cannot replace an established remote identity');
        }
        final identified = await provider.identify(plan, remoteId);
        if (identified[key] != remoteId) {
          throw StateError('Provider did not establish the requested identity');
        }
        remote.addAll(identified);
        state['remote'] = remote;
        state['reconciled_at'] = now().toUtc().toIso8601String();
        // Persist identity before report generation or a later cleanup operation.
        _save(id, state);
      } else if (action == 'status') {
        remote.addAll(await provider.status(plan, remote));
        state['remote'] = remote;
      } else if (action == 'collect') {
        state['collection'] = 'INCOMPLETE';
        state['qualified'] = false;
        _save(id, state);
        if (plan.firebase) {
          remote.addAll(await provider.status(plan, remote));
          state['remote'] = remote;
          _save(id, state);
          if (remote['terminal'] != true) {
            throw StateError('Firebase collection requires terminal status');
          }
        }
        await provider.collect(
          plan,
          remote,
          Directory(p.join(root.path, id, 'remote-results')),
        );
        state['collection'] = 'COMPLETE';
      } else if (action == 'cleanup') {
        if (plan.firebase) {
          // A legacy collection may contain only a queued snapshot. Cleanup
          // changes provider state, so explicit recollection is required.
          state['collection'] = 'INCOMPLETE';
          state['qualified'] = false;
          _save(id, state);
        }
        final result = await provider.cleanup(plan, remote);
        state['cleanup_details'] = result;
        state['cleanup'] = result['verified'] == true ? 'VERIFIED' : 'UNKNOWN';
        File(p.join(root.path, id, 'cleanup.json')).writeAsStringSync(
          jsonEncode({'status': state['cleanup'], 'details': result}),
          flush: true,
        );
        _save(id, state);
        if (plan.firebase) {
          remote.addAll(await provider.status(plan, remote));
          state['remote'] = remote;
        }
      } else {
        throw const FormatException('Unknown recovery action');
      }
      await _finishAssessment(plan, state);
      _save(id, state);
      return state;
    } catch (error) {
      final state = recoveryState;
      if (state != null) {
        state['collection'] = 'INCOMPLETE';
        state['recovery_failure'] = _safeFailure(error, 'recovery_$action');
        await _finishAssessment(
          RemotePlan(Map<String, dynamic>.from(state['plan'] as Map)),
          state,
        );
        _save(id, state);
      }
      rethrow;
    } finally {
      lock.release();
    }
  }
}

/// gcloud transport with explicit account/project, never global config changes.
class GcloudProvider implements RemoteProvider {
  GcloudProvider({
    this.execute = executeCommand,
    this.gcloud = 'gcloud',
    http.Client Function()? createHttpClient,
  }) : createHttpClient = createHttpClient ?? http.Client.new;
  final CommandExecutor execute;
  final String gcloud;
  final http.Client Function() createHttpClient;

  @override
  Future<Map<String, dynamic>> identify(
    RemotePlan plan,
    String remoteId,
  ) async {
    if (plan.firebase) {
      final value = await matrix(plan, remoteId);
      final labels =
          ((value['clientInfo'] as Map?)?['clientInfoDetails'] as List? ?? [])
              .whereType<Map>()
              .where((item) => item['key'] == 'matrixLabel')
              .toList();
      if (value['projectId'] != plan.project ||
          value['testMatrixId'] != remoteId ||
          labels.length != 1 ||
          labels.single['value'] != plan.runId) {
        throw StateError('Matrix project, ID or run label mismatch');
      }
      return {'matrix_id': remoteId, 'matrix': value};
    }
    if (!RegExp(r'^[0-9]+$').hasMatch(remoteId)) {
      throw const FormatException('Expected the numeric GCE instance ID');
    }
    final vm = await _describeVm(plan);
    final disks = (vm['disks'] as List? ?? []).whereType<Map>().toList();
    final disk =
        '/projects/${plan.project}/zones/${plan.settings['zone']}/disks/${plan.runId}';
    if (vm['id'] != remoteId ||
        vm['name'] != plan.runId ||
        (vm['labels'] as Map?)?['llamadart-validation'] != plan.runId ||
        !(vm['zone'] as String? ?? '').endsWith(
          '/zones/${plan.settings['zone']}',
        ) ||
        disks.length != 1 ||
        disks.single['boot'] != true ||
        disks.single['autoDelete'] != true ||
        !(disks.single['source'] as String? ?? '').endsWith(disk)) {
      throw StateError('VM identity or owned boot disk mismatch');
    }
    return {
      'instance_id': remoteId,
      'creation_confirmed': true,
      'disks': [disks.single['source']],
    };
  }

  Future<CommandResult> command(
    RemotePlan plan,
    List<String> args, {
    Duration? timeout,
  }) => execute(gcloud, [
    ...args,
    '--project=${plan.project}',
    '--account=${plan.account}',
    '--quiet',
  ], timeout: timeout);

  Future<Map<String, dynamic>> matrix(
    RemotePlan plan,
    String id, {
    bool cancel = false,
  }) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid matrix ID');
    }
    final token = await execute(gcloud, [
      'auth',
      'print-access-token',
      '--account=${plan.account}',
    ]);
    if (token.code != 0) {
      throw const RemoteProviderFailure(RemoteFailureKind.authentication);
    }
    final client = createHttpClient();
    try {
      final url = Uri.parse(
        'https://testing.googleapis.com/v1/projects/${plan.project}/testMatrices/$id${cancel ? ':cancel' : ''}',
      );
      final headers = {'Authorization': 'Bearer ${token.output.trim()}'};
      final response =
          await (cancel
                  ? client.post(url, headers: headers)
                  : client.get(url, headers: headers))
              .timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw RemoteProviderFailure(
          RemoteFailureKind.http,
          httpStatus: response.statusCode,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const RemoteProviderFailure(RemoteFailureKind.invalidResponse);
      }
      return decoded;
    } on TimeoutException {
      throw const RemoteProviderFailure(RemoteFailureKind.timeout);
    } on SocketException {
      throw const RemoteProviderFailure(RemoteFailureKind.transport);
    } on http.ClientException {
      throw const RemoteProviderFailure(RemoteFailureKind.transport);
    } on FormatException {
      throw const RemoteProviderFailure(RemoteFailureKind.invalidResponse);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> preflight(RemotePlan plan) async {
    if (Platform.isWindows && !plan.firebase) {
      throw UnsupportedError(
        'Run the GCE controller on macOS/Linux; Windows is supported as a test guest',
      );
    }
    final billing = jsonObject(
      await command(plan, [
        'billing',
        'projects',
        'describe',
        plan.project,
        '--format=json',
      ]),
    );
    if (plan.firebase) {
      if (plan.blaze) {
        if (billing['billingEnabled'] != true ||
            billing['billingAccountName'] !=
                'billingAccounts/${plan.settings['billing_account']}') {
          throw StateError(
            'Blaze billing account does not match the approved plan',
          );
        }
      } else if (billing['billingEnabled'] != false) {
        throw StateError('Firebase project must remain unbilled Spark');
      }
      final platform = plan.target == 'firebase-ios' ? 'ios' : 'android';
      final result = await command(plan, [
        'firebase',
        'test',
        platform,
        'models',
        'list',
        '--format=json',
      ]);
      if (result.code != 0) throw StateError('Cannot verify Firebase catalog');
      final models = (jsonDecode(result.output) as List).cast<Map>();
      final selected = models
          .where((m) => m['id'] == plan.settings['device_model'])
          .toList();
      if (selected.length != 1 ||
          (!plan.target.endsWith('-ios') &&
              selected.single['form'] != 'PHYSICAL') ||
          !(selected.single['supportedVersionIds'] as List? ?? []).contains(
            plan.settings['device_version'],
          )) {
        throw StateError(
          'Selected device/OS is unavailable in the current catalog',
        );
      }
    } else {
      if (billing['billingEnabled'] != true) {
        throw StateError('GCE project has no active billing/credit link');
      }
      final result = await command(plan, [
        'compute',
        'instances',
        'list',
        '--filter=name=${plan.runId}',
        '--format=json',
      ]);
      if (result.code != 0 || (jsonDecode(result.output) as List).isNotEmpty) {
        throw StateError('GCE run name already exists or cannot be checked');
      }
      final firewalls = await command(plan, [
        'compute',
        'firewall-rules',
        'list',
        '--format=json',
      ]);
      if (firewalls.code != 0) throw StateError('Cannot verify IAP access');
      final usable = (jsonDecode(firewalls.output) as List).cast<Map>().any(
        (rule) =>
            rule['disabled'] != true &&
            rule['direction'] == 'INGRESS' &&
            (rule['network'] as String? ?? '').endsWith(
              '/networks/${plan.settings['network']}',
            ) &&
            (rule['sourceRanges'] as List? ?? []).contains('35.235.240.0/20') &&
            (rule['targetTags'] as List? ?? []).contains(
              plan.settings['iap_tag'],
            ) &&
            (rule['allowed'] as List? ?? []).cast<Map>().any(
              (allow) =>
                  allow['IPProtocol'] == 'tcp' &&
                  (allow['ports'] as List? ?? []).contains('22'),
            ),
      );
      if (!usable) {
        throw StateError(
          'Prepare the configured IAP SSH firewall before VM use',
        );
      }
      final image = jsonObject(
        await command(plan, [
          'compute',
          'images',
          'describe',
          plan.settings['image'] as String,
          '--format=json',
        ]),
      );
      if (image['status'] != 'READY') {
        throw StateError('Pinned GPU-ready image is unavailable');
      }
    }
  }

  @override
  Future<Map<String, dynamic>> start(
    RemotePlan plan,
    void Function(Map<String, dynamic>) checkpoint,
  ) async {
    if (!plan.firebase) return _startVm(plan, checkpoint);
    final ios = plan.target == 'firebase-ios';
    final profile =
        jsonDecode(File(p.join(plan.bundle, 'profile.json')).readAsStringSync())
            as Map;
    final image = isImageGenerationProfile(profile);
    final args = [
      'firebase',
      'test',
      ios ? 'ios' : 'android',
      'run',
      '--type=${ios ? 'xctest' : 'instrumentation'}',
      if (!ios) '--app=${p.join(plan.bundle, 'app.apk')}',
      '--test=${p.join(plan.bundle, ios ? 'tests.zip' : 'test.apk')}',
      '--device=model=${plan.settings['device_model']},version=${plan.settings['device_version']}',
      '--async',
      '--timeout=${plan.testTimeoutMinutes}m',
      '--num-flaky-test-attempts=0',
      '--no-record-video',
      '--client-details=matrixLabel=${plan.runId}',
      '--results-dir=${plan.runId}',
      '--format=json',
      if (!ios)
        '--directories-to-pull=${image ? androidImageProfileDirectory(profile) : androidValidationDirectory}',
    ];
    final result = await command(
      plan,
      args,
      timeout: const Duration(minutes: 10),
    );
    // gcloud --async returns a console URL, even with --format=json. Its
    // creation receipt names the matrix; verify ownership through the API.
    final ids = RegExp(
      r'^Test \[([A-Za-z0-9_-]+)\] has been created in the Google Cloud\.\s*$',
      multiLine: true,
    ).allMatches(result.error).map((match) => match[1]!).toSet();
    if (ids.length != 1) {
      throw StateError(
        'Submission response lacks matrix ID; reconcile without resubmitting',
      );
    }
    final id = ids.single;
    checkpoint({'submission_candidate_id': id});
    final remote = await identify(plan, id);
    checkpoint(remote);
    if (result.code != 0) {
      throw StateError('Submission failed after creating a verified matrix');
    }
    return remote;
  }

  @override
  Future<Map<String, dynamic>> status(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    if (!plan.firebase) return _vmStatus(plan, remote);
    final id = remote['matrix_id'] as String?;
    if (id == null) {
      throw StateError('Unknown matrix ID; manual reconciliation required');
    }
    final result = await matrix(plan, id);
    return {
      'matrix': result,
      'state': result['state'],
      'terminal': const [
        'FINISHED',
        'ERROR',
        'INVALID',
        'CANCELLED',
      ].contains(result['state']),
    };
  }

  @override
  Future<void> collect(
    RemotePlan plan,
    Map<String, dynamic> remote,
    Directory output,
  ) async {
    output.createSync(recursive: true);
    if (!plan.firebase) {
      final result = await command(plan, [
        'compute',
        'scp',
        if (plan.windows) '--scp-flag=-O',
        '--recurse',
        '--tunnel-through-iap',
        '--zone=${plan.settings['zone']}',
        '${plan.runId}:validation/${plan.runId}/results',
        output.path,
      ], timeout: const Duration(minutes: 10));
      if (result.code != 0) throw StateError('VM result retrieval failed');
      return;
    }
    final result = await matrix(plan, remote['matrix_id'] as String);
    if (!const [
      'FINISHED',
      'ERROR',
      'INVALID',
      'CANCELLED',
    ].contains(result['state'])) {
      throw StateError('Firebase collection requires a terminal matrix');
    }
    final uri =
        ((result['resultStorage'] as Map?)?['googleCloudStorage']
                as Map?)?['gcsPath']
            as String?;
    if (uri == null ||
        !uri.startsWith('gs://test-lab-') ||
        !uri.contains(plan.runId)) {
      throw StateError('No verified default Test Lab result location');
    }
    final transfer = await command(plan, [
      'storage',
      'cp',
      '--recursive',
      uri,
      output.path,
    ], timeout: const Duration(minutes: 10));
    if (transfer.code != 0) {
      throw StateError('Firebase result retrieval failed');
    }
    File(
      p.join(output.path, 'matrix.json'),
    ).writeAsStringSync(jsonEncode(result));
  }

  @override
  Future<Map<String, dynamic>> cleanup(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    if (!plan.firebase) return _deleteVm(plan, remote);
    final id = remote['matrix_id'] as String?;
    if (id == null) {
      return {
        'verified': false,
        'reason': 'unknown submission; recover matrix ID first',
      };
    }
    var value = await status(plan, remote);
    if (value['terminal'] != true) {
      await matrix(plan, id, cancel: true);
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        value = await status(plan, remote);
        if (value['terminal'] == true) break;
      }
    }
    return {
      'verified': value['terminal'] == true,
      'matrix_id': id,
      'state': value['state'],
    };
  }

  Future<Map<String, dynamic>> _describeVm(RemotePlan plan) async => jsonObject(
    await command(plan, [
      'compute',
      'instances',
      'describe',
      plan.runId,
      '--zone=${plan.settings['zone']}',
      '--format=json',
    ]),
  );

  Future<CommandResult> _ssh(RemotePlan plan, String script) => command(plan, [
    'compute',
    'ssh',
    plan.runId,
    '--tunnel-through-iap',
    '--zone=${plan.settings['zone']}',
    '--command=$script',
  ], timeout: const Duration(minutes: 3));

  Future<Map<String, dynamic>> _startVm(
    RemotePlan plan,
    void Function(Map<String, dynamic>) checkpoint,
  ) async {
    final deadline = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 60))
        .toIso8601String();
    final instance =
        jsonDecode(
              (await command(plan, [
                'compute',
                'instances',
                'create',
                plan.runId,
                '--zone=${plan.settings['zone']}',
                '--machine-type=${plan.settings['machine_type']}',
                '--image=${plan.settings['image']}',
                '--boot-disk-size=${plan.settings['disk_gb'] ?? 40}GB',
                '--boot-disk-auto-delete',
                '--labels=llamadart-validation=${plan.runId}',
                '--termination-time=$deadline',
                '--instance-termination-action=DELETE',
                '--maintenance-policy=TERMINATE',
                '--no-service-account',
                '--no-scopes',
                if (plan.settings['accelerator'] != null)
                  '--accelerator=type=${plan.settings['accelerator']},count=1',
                '--metadata=block-project-ssh-keys=TRUE${plan.windows ? ',enable-windows-ssh=TRUE' : ''}',
                '--network=${plan.settings['network']}',
                '--tags=${plan.settings['iap_tag']}',
                '--format=json',
              ], timeout: const Duration(minutes: 5))).output,
            )
            as List;
    if (instance.length != 1) {
      throw StateError('Unexpected GCE creation response');
    }
    final vm = Map<String, dynamic>.from(instance.single as Map);
    final remote = <String, dynamic>{
      'instance_id': vm['id'],
      'deadline': deadline,
      'disks': [
        for (final disk in vm['disks'] as List) (disk as Map)['source'],
      ],
      'creation_confirmed': true,
    };
    checkpoint(remote);
    final scheduling = vm['scheduling'] as Map?;
    if (scheduling?['instanceTerminationAction'] != 'DELETE' ||
        scheduling?['terminationTime'] == null) {
      throw StateError('Provider did not confirm deletion deadline');
    }
    // SSH-ready images include pinned GPU drivers and (on Windows) Google SSH.
    var ready = false;
    final readyDeadline = DateTime.now().add(const Duration(minutes: 15));
    while (DateTime.now().isBefore(readyDeadline)) {
      checkpoint(remote);
      final probe = await _ssh(
        plan,
        'nvidia-smi --query-gpu=driver_version --format=csv,noheader',
      );
      if (probe.code == 0 &&
          probe.output.trim().isNotEmpty &&
          probe.output
              .trim()
              .split('\n')
              .every((v) => v.trim() == plan.settings['driver_version'])) {
        final prerequisites = await _ssh(
          plan,
          plan.windows
              ? 'powershell -NoProfile -Command "if (-not (Get-Command Get-FileHash)) { exit 65 }"'
              : 'python3 --version && timeout --version && command -v sha256sum',
        );
        ready = prerequisites.code == 0;
        break;
      }
      await Future<void>.delayed(const Duration(seconds: 15));
    }
    if (!ready) {
      throw StateError('Pinned GPU image/driver did not become ready');
    }
    final base = 'validation/${plan.runId}';
    final make = plan.windows
        ? 'powershell -NoProfile -Command "New-Item -ItemType Directory -Force ${powershellQuote(base)} | Out-Null"'
        : 'mkdir -p ${shellQuote(base)}';
    if ((await _ssh(plan, make)).code != 0) {
      throw StateError('Remote directory preparation failed');
    }
    checkpoint(remote);
    final upload = await command(plan, [
      'compute',
      'scp',
      if (plan.windows) '--scp-flag=-O',
      '--recurse',
      '--tunnel-through-iap',
      '--zone=${plan.settings['zone']}',
      '${plan.bundle}/.',
      '${plan.runId}:$base/',
    ], timeout: const Duration(minutes: 10));
    if (upload.code != 0) throw StateError('Bundle upload failed');
    checkpoint(remote);
    // Verify the manifest against the controller's immutable upload identity before executing code.
    final manifest = await verifyBundle(Directory(plan.bundle));
    final wrapper = plan.windows ? 'run-remote.ps1' : 'run-remote.sh';
    final wrapperHash = (manifest['files'] as Map)[wrapper]['sha256'];
    final verify = plan.windows
        ? 'powershell -NoProfile -Command "if ((Get-FileHash -Algorithm SHA256 ${powershellQuote('$base/bundle-manifest.json')}).Hash.ToLower() -ne ${powershellQuote(plan.json['bundle_sha256'] as String)}) { exit 65 }; if ((Get-FileHash -Algorithm SHA256 ${powershellQuote('$base/$wrapper')}).Hash.ToLower() -ne ${powershellQuote(wrapperHash as String)}) { exit 65 }"'
        : 'cd ${shellQuote(base)} && echo ${shellQuote('${plan.json['bundle_sha256']}  bundle-manifest.json\n$wrapperHash  $wrapper')} | sha256sum -c -';
    if ((await _ssh(plan, verify)).code != 0) {
      throw StateError('Uploaded manifest checksum mismatch');
    }
    // The execution wrapper must be included and checksum-verified in the bundle.
    final script = plan.windows
        ? 'powershell -NoProfile -Command "Start-Process powershell -ArgumentList ${powershellQuote('-NoProfile -File $base/run-remote.ps1 -Profile ${plan.profile}')}"'
        : 'cd ${shellQuote(base)} && nohup sh run-remote.sh ${shellQuote(plan.profile)} > supervisor.log 2>&1 < /dev/null &';
    if ((await _ssh(plan, script)).code != 0) {
      throw StateError('Uncertain VM job start; do not rerun');
    }
    return remote;
  }

  Future<Map<String, dynamic>> _vmStatus(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    final vm = await _describeVm(plan);
    if (remote['instance_id'] != null && vm['id'] != remote['instance_id']) {
      throw StateError('VM identity changed');
    }
    if (vm['status'] == 'TERMINATED') {
      return {'terminal': true, 'state': 'STOPPED'};
    }
    final result = await _ssh(
      plan,
      plan.windows
          ? 'powershell -NoProfile -Command "Get-Content validation/${plan.runId}/exit-code.txt"'
          : 'cat validation/${plan.runId}/exit-code.txt',
    );
    final code = int.tryParse(result.output.trim());
    return {
      'terminal': result.code == 0 && code != null,
      'test_exit_code': code,
      'state': vm['status'],
    };
  }

  Future<Map<String, dynamic>> _deleteVm(
    RemotePlan plan,
    Map<String, dynamic> remote,
  ) async {
    final found = await command(plan, [
      'compute',
      'instances',
      'list',
      '--filter=name=${plan.runId}',
      '--format=json',
    ]);
    if (found.code != 0) {
      return {'verified': false, 'reason': 'cannot inventory VM'};
    }
    final instances = (jsonDecode(found.output) as List).cast<Map>();
    if (instances.isNotEmpty) {
      if (instances.length != 1 ||
          (instances.single['labels'] as Map?)?['llamadart-validation'] !=
              plan.runId ||
          (remote['instance_id'] != null &&
              instances.single['id'] != remote['instance_id'])) {
        throw StateError('Cleanup refused: VM ownership/identity mismatch');
      }
      final vm = instances.single;
      final disks = (vm['disks'] as List? ?? []).cast<Map>();
      final expectedDisk =
          '/projects/${plan.project}/zones/${plan.settings['zone']}/disks/${plan.runId}';
      if (remote['instance_id'] == null ||
          vm['id'] != remote['instance_id'] ||
          !(vm['zone'] as String? ?? '').endsWith(
            '/zones/${plan.settings['zone']}',
          ) ||
          disks.length != 1 ||
          disks.single['boot'] != true ||
          disks.single['autoDelete'] != true ||
          !(disks.single['source'] as String? ?? '').endsWith(expectedDisk) ||
          !(remote['disks'] as List? ?? []).contains(disks.single['source'])) {
        return {
          'verified': false,
          'reason':
              'resource identity or owned boot disk not established; manual reconciliation required',
        };
      }
      final result = await command(plan, [
        'compute',
        'instances',
        'delete',
        plan.runId,
        '--zone=${plan.settings['zone']}',
        '--delete-disks=boot',
      ]);
      if (result.code != 0) {
        return {'verified': false, 'reason': 'VM deletion failed'};
      }
    }
    if (remote['creation_confirmed'] != true || remote['instance_id'] == null) {
      return {
        'verified': false,
        'reason': 'uncertain creation cannot be resolved by an empty inventory',
      };
    }
    final after = await command(plan, [
      'compute',
      'instances',
      'list',
      '--filter=name=${plan.runId}',
      '--format=json',
    ]);
    final disks = await command(plan, [
      'compute',
      'disks',
      'list',
      '--filter=name=${plan.runId}',
      '--format=json',
    ]);
    return {
      'verified':
          after.code == 0 &&
          disks.code == 0 &&
          (jsonDecode(after.output) as List).isEmpty &&
          (jsonDecode(disks.output) as List).isEmpty,
      'instance': plan.runId,
      'disk_policy':
          'only automatic boot disk; no persistent auxiliary resources',
    };
  }
}

/// Interprets a captured provider result; this does not refresh remote status.
bool savedProviderPassed(RemotePlan plan, Map remote) {
  if (plan.firebase) {
    return remote['state'] == 'FINISHED' &&
        (remote['matrix'] as Map?)?['outcomeSummary'] == 'SUCCESS';
  }
  return remote['terminal'] == true && remote['test_exit_code'] == 0;
}
