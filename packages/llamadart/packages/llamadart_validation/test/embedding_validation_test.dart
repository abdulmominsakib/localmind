import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:llamadart/llamadart.dart';
import 'package:llamadart_validation/io.dart';
import 'package:llamadart_validation/llamadart_validation.dart';
import 'package:test/test.dart';

import 'decision_validation_test.dart';

ValidationProfile profile() => ValidationProfile.fromJson(
  jsonDecode(File('assets/profiles/embedding-gguf-cpu.json').readAsStringSync())
      as Map<String, dynamic>,
);
Map<String, Uint8List> assets() => {
  for (final name in (embeddingValidationFixture['files'] as Map).keys)
    name as String: File('assets/embeddings/v1/$name').readAsBytesSync(),
};
List<List<double>> vectors() => [
  for (final row
      in (jsonDecode(
                File('assets/embeddings/v1/reference.json').readAsStringSync(),
              )
              as Map)['vectors']
          as List)
    (row as List).map((v) => (v as num).toDouble()).toList(),
];

class FakeEmbeddingEngine extends FakeDecisionEngine
    implements EmbeddingValidationEngine {
  bool web = false;
  bool noText = false, noImage = false, noAudio = false;
  bool shortBatch = false, failRecovery = false;
  bool failTextRecovery = false, failMediaRecovery = false, recovering = false;
  String? unsupportedReason;
  bool rejectSource = true, rejectMarker = true, reverseBatch = false;
  bool cancelPrecondition = true, cancelled = true, wrongDispatch = false;
  bool ignoreNormalize = false, badNorm = false;
  double cancelMs = 1;
  double perturbation = 0;
  final seen = <int>[];
  final refs = vectors();
  @override
  bool get isWeb => web;
  @override
  Future<LlamaEmbeddingCapabilities> embeddingCapabilities() async =>
      LlamaEmbeddingCapabilities(
        text: supported && !noText,
        image: supported && !noImage,
        audio: supported && !noAudio,
        mediaUnsupportedReason: unsupportedReason,
      );
  @override
  Future<List<double>> embedContent(
    LlamaEmbeddingInput input, {
    bool normalize = true,
  }) async {
    if (input.parts.any((p) => p is LlamaImageContent && p.bytes == null) &&
        rejectSource) {
      throw LlamaUnsupportedException('No source');
    }
    if (input.parts.any(
          (p) => p is LlamaTextContent && p.text.contains('<__media__>'),
        ) &&
        rejectMarker) {
      throw LlamaUnsupportedException('Reserved marker');
    }
    final media = input.parts.where((p) => p is! LlamaTextContent).toList();
    final row = media.length > 1
        ? (media.first is LlamaImageContent ? 3 : 4)
        : media.isEmpty
        ? 0
        : media.single is LlamaImageContent
        ? 1
        : 2;
    seen.add(row);
    final result = refs[row].toList();
    result[0] += perturbation;
    if (recovering &&
        (failTextRecovery && row == 0 || failMediaRecovery && row == 1)) {
      result[0] += 0.1;
    }
    final scale = badNorm
        ? (normalize ? 1.00001 : 2.0)
        : normalize || ignoreNormalize
        ? 1.0
        : 2.0;
    return result.map((v) => v * scale).toList();
  }

  @override
  Future<List<List<double>>> embedContentBatch(
    List<LlamaEmbeddingInput> inputs,
  ) async {
    final result = [for (final input in inputs) await embedContent(input)];
    if (shortBatch) result.removeLast();
    return reverseBatch ? result.reversed.toList() : result;
  }

  @override
  Future<Map<String, dynamic>> cancelEmbedding(
    LlamaEmbeddingInput input, {
    required bool afterDispatch,
  }) async {
    recovering = true;
    if (failRecovery) perturbation = 0.1;
    return {
      'precondition_met': cancelPrecondition,
      'in_flight': cancelPrecondition,
      'dispatch_observed': wrongDispatch ? !afterDispatch : afterDispatch,
      'cancelled': cancelled,
      'cancel_ms': cancelMs,
      'error_type': 'LlamaInferenceException',
    };
  }
}

Future<({List<Map<String, dynamic>> events, ValidationReport report})> runPack(
  FakeEmbeddingEngine engine, {
  Map<String, Uint8List>? supplied,
  Map<String, dynamic>? preparation,
  ValidationProfile? selectedProfile,
}) async {
  final p = selectedProfile ?? profile();
  final events = <Map<String, dynamic>>[];
  await ValidationRunner(
    profile: p,
    engine: engine,
    emit: (e) async => events.add(e),
    embeddingAssets: supplied ?? assets(),
  ).run(
    'model.gguf',
    runId: 'embedding-test',
    environment: {
      'source_commit': 'a' * 40,
      'source_dirty': false,
      'hook_sha256': 'b' * 64,
      'native_tag': 'v0.7.0-1',
    },
    preparation:
        preparation ??
        {
          'verified': true,
          'sha256': p.modelHash,
          'bytes': p.model['bytes'],
          'embedding_projector': {
            'verified': true,
            'sha256': p.embeddingProjector['sha256'],
            'bytes': p.embeddingProjector['bytes'],
          },
        },
  );
  return (
    events: events,
    report: ValidationReport.parse(events.map(jsonEncode).join('\n')),
  );
}

Map<String, dynamic> caseOf(ValidationReport r, String id) =>
    r.cases.singleWhere((c) => c['case_id'] == id);

void main() {
  test('catalog 5 embedding journals retain their qualification', () async {
    final selected = profile();
    final result = await runPack(FakeEmbeddingEngine());
    final events = (jsonDecode(jsonEncode(result.events)) as List)
        .cast<Map<String, dynamic>>();
    events.first['catalog'] = selected.catalogForVersion(5);
    events.first['catalog_hash'] = jsonHash(events.first['catalog']);
    final old = ValidationReport.parse(events.map(jsonEncode).join('\n'));
    expect(old.problems, isEmpty);
    expect(old.qualified, result.report.qualified);
  });

  test('embedding profiles select the complete embedding pack', () {
    for (final backend in ['cpu', 'metal']) {
      final profile = ValidationProfile.fromJson(
        jsonDecode(
              File(
                'assets/profiles/embedding-gguf-$backend.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(profile.caseIds, [
        'C01.load',
        'E01.capabilities',
        'E02.text',
        'E03.image',
        'E04.audio',
        'E05.mixed',
        'E06.batch',
        'E07.normalization',
        'E08.guards',
        'E09.cancel.before',
        'E10.cancel.after',
      ]);
      expect(profile.catalog['features'], containsPair('embeddings', 1));
      expect(
        (profile.catalog['fixtures'] as Map)['embeddings'],
        embeddingValidationFixture,
      );
      final catalogCases = (profile.catalog['cases'] as List).cast<Map>();
      expect(
        catalogCases.where((c) => c['selected'] == true).map((c) => c['id']),
        profile.caseIds,
      );
      for (final c in catalogCases.where((c) => c['selected'] != true)) {
        expect(c['omission_reason'], 'embedding_model_has_no_text_generation');
      }
      for (final id in profile.caseIds.skip(1)) {
        expect(
          profile.caseFixtures(id)['embeddings'],
          embeddingValidationFixture,
        );
      }

      expect(profile.loadParams.batchSize, 2048);
      expect(profile.loadParams.microBatchSize, 2048);
      expect(profile.effectiveConfig['batch_size'], 2048);
      expect(profile.effectiveConfig['micro_batch_size'], 2048);
    }
  });
  test(
    'reference-backed cases pass and journal the feature identity',
    () async {
      final fake = FakeEmbeddingEngine();
      final result = await runPack(fake);
      expect(result.report.problems, isEmpty);
      expect(result.report.assertionsPassed, isTrue);
      expect(result.report.qualified, isTrue);
      expect(fake.seen, containsAllInOrder([0, 1, 2, 3, 2, 0, 4, 2, 2, 2]));
      for (final c in result.report.cases.where(
        (c) => '${c['case_id']}'.startsWith('E'),
      )) {
        expect(c['feature_id'], 'embeddings');
        expect(c['status'], 'PASS', reason: '$c');
      }
    },
  );
  test('missing or damaged fixture/reference fails closed', () async {
    for (final file in ['checker.png', 'tone.wav', 'reference.json']) {
      for (final missing in [true, false]) {
        final bytes = assets();
        if (missing) {
          bytes.remove(file);
        } else {
          bytes[file] = Uint8List.fromList([1, 2, 3]);
        }
        final result = await runPack(FakeEmbeddingEngine(), supplied: bytes);
        expect(result.report.qualified, isFalse);
        for (final c in result.report.cases.skip(1)) {
          expect(c['status'], 'ERROR', reason: '$file $missing $c');
        }
      }
    }
  });
  test(
    'numerical gates reject dimensions, nonfinite, cosine and max abs independently',
    () {
      final ref = List<double>.filled(768, 0)..[0] = 1;
      expect(compareEmbeddingVectors(ref, ref)['passed'], isTrue);
      expect(compareEmbeddingVectors(ref.sublist(1), ref)['passed'], isFalse);
      expect(
        compareEmbeddingVectors([...ref]..[1] = double.nan, ref)['passed'],
        isFalse,
      );
      expect(
        compareEmbeddingVectors(List.filled(768, 0.0), ref)['passed'],
        isFalse,
      );
      // Same direction exceeds max-abs while cosine remains one.
      expect(
        compareEmbeddingVectors([...ref]..[0] = 1.011, ref)['passed'],
        isFalse,
      );
      // Each difference stays below max-abs, but total angular error is too big.
      final angular = [1.0, ...List.filled(767, 0.003)];
      expect(compareEmbeddingVectors(angular, ref)['passed'], isFalse);
      expect(
        compareEmbeddingVectors([...ref]..[0] = 1.009, ref)['passed'],
        isTrue,
      );
    },
  );
  test(
    'runtime predicates reject capability, order, normalization, error and cancellation regressions',
    () async {
      final mutations = <(String, void Function(FakeEmbeddingEngine))>[
        ('E01.capabilities', (e) => e.supported = false),
        ('E01.capabilities', (e) => e.noText = true),
        ('E01.capabilities', (e) => e.noImage = true),
        ('E01.capabilities', (e) => e.noAudio = true),
        ('E01.capabilities', (e) => e.unsupportedReason = 'unavailable'),
        ('E02.text', (e) => e.perturbation = 0.1),
        ('E06.batch', (e) => e.reverseBatch = true),
        ('E06.batch', (e) => e.shortBatch = true),
        ('E07.normalization', (e) => e.ignoreNormalize = true),
        ('E07.normalization', (e) => e.badNorm = true),
        ('E08.guards', (e) => e.rejectSource = false),
        ('E08.guards', (e) => e.rejectMarker = false),
        ('E09.cancel.before', (e) => e.cancelled = false),
        ('E10.cancel.after', (e) => e.cancelMs = 5001),
        ('E09.cancel.before', (e) => e.failRecovery = true),
        ('E09.cancel.before', (e) => e.failTextRecovery = true),
        ('E10.cancel.after', (e) => e.failMediaRecovery = true),
      ];
      for (final (id, change) in mutations) {
        final fake = FakeEmbeddingEngine();
        change(fake);
        final result = await runPack(fake);
        expect(caseOf(result.report, id)['status'], 'FAIL', reason: id);
        expect(result.report.qualified, isFalse);
      }
    },
  );
  test('missed cancellation preconditions and Web stay NOT_RUN', () async {
    final missing = await runPack(
      FakeEmbeddingEngine()..cancelPrecondition = false,
    );
    expect(caseOf(missing.report, 'E10.cancel.after')['status'], 'NOT_RUN');
    final web = await runPack(FakeEmbeddingEngine()..web = true);
    expect(web.report.cases.every((c) => c['status'] == 'NOT_RUN'), isTrue);
    expect(web.report.qualified, isFalse);
  });
  test(
    'reporter rejects forged PASS metrics, identity and missing projector proof',
    () async {
      final result = await runPack(FakeEmbeddingEngine());
      for (final id in profile().caseIds.skip(1)) {
        final events = [
          for (final e in result.events)
            jsonDecode(jsonEncode(e)) as Map<String, dynamic>,
        ];
        final record = events.singleWhere(
          (e) => e['type'] == 'case' && e['case_id'] == id,
        );
        // Retain the declared PASS but remove the supporting evidence.
        for (final key in [
          'comparisons',
          'text',
          'raw_norm',
          'unsupported_input',
          'cancelled',
        ]) {
          record.remove(key);
        }
        final report = ValidationReport.parse(
          events.map(jsonEncode).join('\n'),
        );
        expect(
          report.problems,
          contains('Invalid embedding case evidence: $id'),
        );
        expect(report.qualified, isFalse);
      }
      final forged = [
        for (final e in result.events)
          jsonDecode(jsonEncode(e)) as Map<String, dynamic>,
      ];
      (forged.singleWhere(
                    (e) => e['case_id'] == 'E02.text' && e['type'] == 'case',
                  )['comparisons']
                  as List)
              .single['cosine'] =
          0.1;
      expect(
        ValidationReport.parse(forged.map(jsonEncode).join('\n')).qualified,
        isFalse,
      );
      final noProjector = await runPack(
        FakeEmbeddingEngine(),
        preparation: {
          'verified': true,
          'sha256': profile().modelHash,
          'bytes': profile().model['bytes'],
        },
      );
      expect(
        noProjector.report.provenanceProblems,
        contains(
          'Verified embedding projector hash and byte size do not match the profile lock',
        ),
      );
    },
  );
  test(
    'profile rejects incomplete locks, mutable URLs and conflicting cohort settings',
    () {
      final changes = <void Function(Map<String, dynamic>)>[
        (p) => p.remove('embedding'),
        (p) => p['embedding'] = {},
        (p) => p['selection'] = 'release',
        (p) => p['threads'] = 8,
        (p) => p['context_size'] = 1024,
        (p) => p['backend'] = 'vulkan',
        (p) => p['fixtures'] = {},
        (p) => p['embedding']['projector']['revision'] = 'a' * 40,
        (p) => p['embedding']['projector']['url'] += '?secret=redacted',
        (p) => p['embedding']['projector']['bytes'] = 0,
        (p) => p['embedding']['projector']['sha256'] = 'bad',
      ];
      for (final change in changes) {
        final data = profile().toJson();
        change(data);
        expect(() => ValidationProfile.fromJson(data), throwsFormatException);
      }
      for (var v = 1; v < 5; v++) {
        expect(() => profile().catalogForVersion(v), throwsFormatException);
      }
      final chat = ValidationProfile.fromJson(
        jsonDecode(
              File('assets/profiles/chat-gguf-cpu.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      expect(chat.catalog['features'], isNot(contains('embeddings')));
    },
  );
  test(
    'projector preparation verifies supplied and downloaded bytes',
    () async {
      final cache = Directory.systemTemp.createTempSync('embedding-projector-');
      addTearDown(() => cache.deleteSync(recursive: true));
      final data = profile().toJson();
      final bytes = utf8.encode('synthetic projector');
      data['embedding']['projector']['sha256'] = sha256
          .convert(bytes)
          .toString();
      data['embedding']['projector']['bytes'] = bytes.length;
      final selected = ValidationProfile.fromJson(data);
      var requests = 0;
      final downloaded = await prepareEmbeddingProjector(
        selected,
        cache,
        client: MockClient((request) async {
          requests++;
          expect(request.url.toString(), selected.embeddingProjector['url']);
          return http.Response.bytes(bytes, 200);
        }),
      );
      expect(requests, 1);
      expect(downloaded.evidence['verified'], isTrue);
      expect(File(downloaded.path).readAsBytesSync(), bytes);
      final supplied = await prepareEmbeddingProjector(
        selected,
        cache,
        suppliedPath: downloaded.path,
      );
      expect(supplied.evidence['cache_hit'], isTrue);
      File(downloaded.path).writeAsBytesSync([1]);
      await expectLater(
        prepareEmbeddingProjector(
          selected,
          cache,
          suppliedPath: downloaded.path,
        ),
        throwsFormatException,
      );
      await expectLater(
        prepareEmbeddingProjector(
          selected,
          Directory('${cache.path}/bad'),
          client: MockClient((_) async => http.Response.bytes([1], 200)),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'reporter rejects feature identity and impossible dispatch claims',
    () async {
      final result = await runPack(FakeEmbeddingEngine());
      final event = result.events.singleWhere(
        (e) => e['type'] == 'case' && e['case_id'] == 'E01.capabilities',
      );
      event['feature_id'] = 'text';
      expect(
        ValidationReport.parse(
          result.events.map(jsonEncode).join('\n'),
        ).qualified,
        isFalse,
      );
      expect(
        (await runPack(
          FakeEmbeddingEngine()..wrongDispatch = true,
        )).report.qualified,
        isFalse,
      );
      expect(
        () => profile().requireRunnable(web: true),
        throwsA(isA<LlamaUnsupportedException>()),
      );
    },
  );
  test('reference cohort cannot be reused for different weights', () async {
    final data = profile().toJson();
    data['model']['sha256'] = 'c' * 64;
    final run = await runPack(
      FakeEmbeddingEngine(),
      selectedProfile: ValidationProfile.fromJson(data),
    );
    expect(
      run.report.cases.skip(1).every((c) => c['status'] == 'ERROR'),
      isTrue,
    );
  });
  test('nonfinite comparisons remain JSON serializable', () {
    for (final bad in [double.nan, double.infinity, double.negativeInfinity]) {
      final actual = vectors().first.toList()..[0] = bad;
      expect(
        () => jsonEncode(compareEmbeddingVectors(actual, vectors().first)),
        returnsNormally,
      );
    }
    expect(validEmbeddingCaseEvidence('E99.unknown', {}), isFalse);
  });
  test(
    'reporter cannot qualify a Web host claiming native embedding passes',
    () async {
      final result = await runPack(FakeEmbeddingEngine());
      (result.events.first['environment'] as Map)['web'] = true;
      final report = ValidationReport.parse(
        result.events.map(jsonEncode).join('\n'),
      );
      expect(
        report.problems,
        contains('Web embedding pack must remain NOT_RUN: E01.capabilities'),
      );
      expect(report.qualified, isFalse);
    },
  );
}
