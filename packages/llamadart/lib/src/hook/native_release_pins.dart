/// Native runtime release pins consumed by `hook/build.dart`.
///
/// `tool/native/sync_native_release_pins.py` rewrites this file from published
/// release metadata. Hook logic stays in `hook/build.dart`.
library;

/// `leehack/llamadart-native` release tag downloaded for the llama.cpp runtime.
const llamaCppTag = 'v1.0.0-4';

/// The first `llamadart_llama_cpp_flutter` release whose `Package.swift` pins
/// [llamaCppTag].
///
/// Incompatible-companion build errors name it, because a caret constraint on
/// an earlier companion can never resolve it. A core from
/// `appleCompanionLockstepStart` on names it only when it shares the core's
/// `MAJOR.MINOR`, and its own minor's first release otherwise. The native pin
/// sync sets it to the companion's next release whenever it moves the
/// companion pin.
const llamaCppAppleCompanionVersion = '0.20.4';

/// Earlier `leehack/llamadart-native` tags that a published Apple llama.cpp
/// companion pins and the build still accepts, each mapped to what its
/// frameworks lack compared with [llamaCppTag].
///
/// The Apple artifacts for `v1.0.0-1` through `v1.0.0-3` share the current
/// ABI for singleton budgets. The SDK probes the multi-end export at runtime.
/// Pre-`v1.0.0` artifacts lack the ARM F16 accumulation fix. Native pin sync
/// clears this map on a pin change, so earlier tags need new compatibility proof.
const llamaCppCompatibleAppleCompanionTags = <String, String>{
  'v1.0.0-1': 'the v1.0.0-3 speech fixes and multi-end thinking-budget export',
  'v1.0.0-2': 'the v1.0.0-3 speech fixes and multi-end thinking-budget export',
  'v1.0.0-3': 'the multi-end thinking-budget export',
};

/// Exact XCFramework checksums for [llamaCppTag] and any admitted earlier
/// [llamaCppCompatibleAppleCompanionTags] entries.
///
/// Native pin sync preserves this proof on a same-tag refresh and replaces it
/// with the newly published artifact's checksum when the pin moves.
const llamaCppCompatibleAppleCompanionChecksums = <String, String>{
  'v1.0.0-1':
      '0c66ca422bfc8ba266845b57fea99d2792ea67c84233f49358301a640846d669',
  'v1.0.0-2':
      '641020c50159a001096dcd66cc7356fe3c81915b26f985ebd48b2cec87169bcb',
  'v1.0.0-3':
      '0ba46bb6428ce0f32633aea84bdb4d9530089850461ea721cfb0430961ca24c1',
  'v1.0.0-4':
      '6c1ee1100497518363022f9acac1e381f9ae40d73b2b39fb56628b1beb85c07e',
};

/// SHA-256 of each published `llamadart-native-<bundle>-<llamaCppTag>.tar.gz`
/// archive, keyed by bundle.
///
/// The hook verifies a downloaded or cached archive of the pinned release
/// against this map before extracting it.
const llamaCppBundleSha256 = <String, String>{
  'android-arm64':
      '0770358efdc51146261092f90068c4bd19da4c5fa1e3956bba4a9e5f753f6ef3',
  'android-x64':
      '5feb388cc3c6f26b04e613d8e159c4d65a60c1e2f7f60389b0de108f60adf3ef',
  'ios-arm64':
      'a85b35453181f52b1989f8d5a308fd1215bf7e7e8e9fe8432d2bfd7fe104ac7d',
  'ios-arm64-sim':
      '9bbfbce86024cdeed1de2035e6261101ff104a12e66720e1eef84796aa1484b1',
  'ios-x86_64-sim':
      'd11e0e95b5753943ebbe96270e82f53ed3f4dcdf0b682c9911602b6d5fda7fb2',
  'linux-arm64':
      'caa889d3d2e678141d9e2c11ff543f8569c084cd5b53cd50a27bbdb9b5fadf66',
  'linux-x64':
      '3d59223a83610c9b155ef1c4f522f27b404c7bd3ff6539f0444aca1b1ee48e45',
  'macos-arm64':
      '5e1393a8c7f51c2a1e2228146689601a8b884154fd11e23fd7d60e3103b29bc8',
  'macos-x86_64':
      'e6265ccdb0e9ee275af7f0acb32df2162a0e64411b4bc0eb447a7e77226b63b3',
  'windows-arm64':
      '64f6b3afc13cea1212a6a1b57dd6a6b81a1e8addace210c8f24c94b9452640a8',
  'windows-x64':
      '60d025ba02543f43005e7fc778b27526881277009430081940fcc857fd82733a',
};

/// The `hook_contract_version` of the [llamaCppTag] release's `assets.json`.
const llamaCppHookContractVersion = 2;

/// A backend module that [llamaCppTag] publishes as its own archive,
/// `llamadart-native-<archive>-<llamaCppTag>.tar.gz`, extracted over the
/// [bundle] archive when [backend] is selected.
class LlamaCppBackendSidecarSpec {
  /// Core bundle the sidecar extends, such as `windows-x64`.
  final String bundle;

  /// Backend the sidecar adds, such as `cuda`.
  final String backend;

  /// Archive key, such as `windows-x64-cuda12`.
  final String archive;

  /// SHA-256 of the published `.tar.gz` archive.
  final String sha256;

  /// Creates a spec for the [archive] sidecar.
  const LlamaCppBackendSidecarSpec({
    required this.bundle,
    required this.backend,
    required this.archive,
    required this.sha256,
  });
}

/// Every backend sidecar archive the [llamaCppTag] release publishes.
const llamaCppBackendSidecarSpecs = <LlamaCppBackendSidecarSpec>[
  LlamaCppBackendSidecarSpec(
    bundle: 'windows-x64',
    backend: 'cuda',
    archive: 'windows-x64-cuda12',
    sha256: 'b7440cd3f6d7a393443dc5f21b0b171277365652d00b930c33216aca5b876a3b',
  ),
];

/// `leehack/litert-lm-native` release tag downloaded for the LiteRT-LM runtime.
const liteRtLmReleaseTag = 'v0.19.1-7';

/// LiteRT-LM cache directory version derived from [liteRtLmReleaseTag].
const liteRtLmVersion = '0.19.1-7';

/// A published LiteRT-LM runtime archive and the libraries it must contain.
class LiteRtLmBundleSpec {
  /// Release bundle key such as `linux-x64`.
  final String bundle;

  /// SHA-256 of the published `.tar.gz` archive.
  final String sha256;

  /// Library file names the extracted archive must provide.
  final Set<String> requiredLibraries;

  /// Creates a spec for [bundle].
  const LiteRtLmBundleSpec(
    this.bundle, {
    required this.sha256,
    required this.requiredLibraries,
  });
}

/// Every LiteRT-LM bundle the hook can download, keyed by [LiteRtLmBundleSpec.bundle].
const liteRtLmBundleSpecs = <LiteRtLmBundleSpec>[
  LiteRtLmBundleSpec(
    'android-arm64',
    sha256: 'ad437e55e0c2c56b0d76c4711923eca71b027bcdffee293b2b48ffe6de3a7d3a',
    requiredLibraries: {
      'libGemmaModelConstraintProvider.so',
      'libLiteRtGpuAccelerator.so',
      'libLiteRtLm.so',
      'libLiteRtOpenClAccelerator.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    },
  ),
  LiteRtLmBundleSpec(
    'android-x64',
    sha256: '582064587651cf6bb1e052b552a5354dbc7b29a3636cdd745ca2d4c9c91e7aef',
    requiredLibraries: {
      'libGemmaModelConstraintProvider.so',
      'libLiteRtGpuAccelerator.so',
      'libLiteRtLm.so',
      'libLiteRtOpenClAccelerator.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    },
  ),
  LiteRtLmBundleSpec(
    'ios-arm64',
    sha256: '0f6fdae5b44084567fb1d5289974ae8658b64464bad7887403b3ec3b20d4a28f',
    requiredLibraries: {'CLiteRTLM', 'LiteRtLm'},
  ),
  LiteRtLmBundleSpec(
    'ios-arm64-sim',
    sha256: 'be9703e8ff7e4c78868d3d91c253ff397fe909022f8aefeb1e8882bbfb54f684',
    requiredLibraries: {'CLiteRTLM', 'LiteRtLm'},
  ),
  LiteRtLmBundleSpec(
    'macos-arm64',
    sha256: '9e45acc2fc27c633b04e4f60a4f5317c25cd85debce7076e3489f25edae328e5',
    requiredLibraries: {
      'libCLiteRTLM_mac.dylib',
      'libGemmaModelConstraintProvider.dylib',
      'libLiteRtLm.dylib',
      'libwebgpu_dawn.dylib',
    },
  ),
  LiteRtLmBundleSpec(
    'linux-arm64',
    sha256: '142df84cf8c13eb402764315fe742a7fe8a2ee35f34198a382c930b91d4c8d3b',
    requiredLibraries: {
      'libGemmaModelConstraintProvider.so',
      'libLiteRtLm.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    },
  ),
  LiteRtLmBundleSpec(
    'linux-x64',
    sha256: '0e80f8f9610af11472d45494ce0397cf6b51d404af83868767a25413126de6cc',
    requiredLibraries: {
      'libGemmaModelConstraintProvider.so',
      'libLiteRtLm.so',
      'libLiteRtWebGpuAccelerator.so',
      'libwebgpu_dawn.so',
    },
  ),
  LiteRtLmBundleSpec(
    'windows-x64',
    sha256: '1c78794969fe00cb02649368423c97b3e4321e5708de4371c0b6cef4af10975e',
    requiredLibraries: {
      'LiteRtLm.dll',
      'dxcompiler.dll',
      'dxil.dll',
      'libGemmaModelConstraintProvider.dll',
      'libLiteRtWebGpuAccelerator.dll',
      'libwebgpu_dawn.dll',
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
      'vcruntime140_threads.dll',
      'webgpu_dawn.dll',
    },
  ),
];

/// `leehack/stable-diffusion-native` release tag downloaded for the opt-in
/// stable-diffusion.cpp runtime.
const stableDiffusionReleaseTag = 'v0.4.0-1';

/// First Apple companion release containing [stableDiffusionReleaseTag].
const stableDiffusionAppleCompanionVersion = '0.20.7';

/// Explicitly qualified older Apple SD pins that preserve existing app locks.
///
/// The v0.4.0 image generation parameter layout is incompatible with the
/// v0.3.0 line. Clear and requalify this map whenever
/// [stableDiffusionReleaseTag] changes.
const stableDiffusionCompatibleAppleCompanionTags = <String, String>{
  'v0.4.0':
      'no Apple changes (v0.4.0-1 only bundles Windows Visual C++ runtime DLLs)',
};

/// Checksums of the exact published XCFrameworks accepted by the SD hook.
const stableDiffusionAppleCompanionChecksums = <String, String>{
  'v0.4.0': '3a9d99a0f818c1511c62b585d3170c41c68f35756143979fe29f4a476bece3ce',
  'v0.4.0-1':
      '3a9d99a0f818c1511c62b585d3170c41c68f35756143979fe29f4a476bece3ce',
};

/// stable_diffusion cache directory version derived from
/// [stableDiffusionReleaseTag].
const stableDiffusionVersion = '0.4.0-1';

/// A published stable-diffusion-native runtime archive and its required libraries.
class StableDiffusionBundleSpec {
  /// Release bundle key such as `linux-x64-vulkan`.
  final String bundle;

  /// SHA-256 of the published `.tar.gz` archive.
  final String sha256;

  /// Library file names the archive must provide under `lib/`.
  final Set<String> requiredLibraries;

  /// Library that exposes the stable-diffusion.cpp API.
  String get primaryLibrary => switch (bundle.split('-').first) {
    'windows' => 'stable-diffusion.dll',
    'android' || 'linux' => 'libstable-diffusion.so',
    _ => 'libstable-diffusion.dylib',
  };

  /// Creates a spec for [bundle].
  const StableDiffusionBundleSpec(
    this.bundle, {
    required this.sha256,
    required this.requiredLibraries,
  });
}

/// Every stable_diffusion bundle the hook can download, keyed by
/// [StableDiffusionBundleSpec.bundle].
const stableDiffusionBundleSpecs = <StableDiffusionBundleSpec>[
  StableDiffusionBundleSpec(
    'android-arm64',
    sha256: 'b0bac4c11847536d3562e155bca021292666963729514ae80eec86d6a15f2613',
    requiredLibraries: {'libstable-diffusion.so'},
  ),
  StableDiffusionBundleSpec(
    'ios-arm64',
    sha256: '10fd003b6e4742abf4815960d2105ba60b39a3fda36b1c021754b254f98d4b66',
    requiredLibraries: {'libstable-diffusion.dylib'},
  ),
  StableDiffusionBundleSpec(
    'ios-arm64-sim',
    sha256: '2a84e5bedf05fba1eb151c45d2b47cfc11137db743bb69b5309dde4c2acb05b3',
    requiredLibraries: {'libstable-diffusion.dylib'},
  ),
  StableDiffusionBundleSpec(
    'ios-x64-sim',
    sha256: 'f5ce1616472c5ba8cbcb03cc4c52156b2856e2dd384e4578db97b147ffb152ff',
    requiredLibraries: {'libstable-diffusion.dylib'},
  ),
  StableDiffusionBundleSpec(
    'macos-arm64',
    sha256: '7ba9cbfc3f37193c945bfbd0816b048d138f057076490e94d7c024543a10478d',
    requiredLibraries: {'libstable-diffusion.dylib'},
  ),
  StableDiffusionBundleSpec(
    'macos-x64',
    sha256: 'd873ece9051f6713d776e4e4ea762866ebc9c0dabb371e894609bb4828d8a2e5',
    requiredLibraries: {'libstable-diffusion.dylib'},
  ),
  StableDiffusionBundleSpec(
    'linux-arm64',
    sha256: '5b1425402f8c3ab704b2c3817dc5d57f78a1054669a6bd5d170fa14e8790df12',
    requiredLibraries: {'libstable-diffusion.so'},
  ),
  StableDiffusionBundleSpec(
    'linux-arm64-vulkan',
    sha256: '5201da9d08501d9f5d27e7e78c8d3c83624ef6a27417339fef03813539aa6180',
    requiredLibraries: {'libstable-diffusion.so'},
  ),
  StableDiffusionBundleSpec(
    'linux-x64',
    sha256: '02db0554b8eee4adf5d46f75ee5869d5fb81d75de0059d55136cd614b70368fb',
    requiredLibraries: {'libstable-diffusion.so'},
  ),
  StableDiffusionBundleSpec(
    'linux-x64-vulkan',
    sha256: 'ff7104003c6bdb3a2bd2fc04ac11bdb636192a71aa33f57d18f2673624a6e6f3',
    requiredLibraries: {'libstable-diffusion.so'},
  ),
  StableDiffusionBundleSpec(
    'windows-x64',
    sha256: 'd09e8b322fcbdbfb09869e7f6362ec9a52d0c36efb3e3f2b1a90d445bbfd0ff9',
    requiredLibraries: {
      'msvcp140.dll',
      'msvcp140_codecvt_ids.dll',
      'stable-diffusion.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    },
  ),
  StableDiffusionBundleSpec(
    'windows-x64-vulkan',
    sha256: '5c5663f5460c933236d48da579affd7af0beee167a10bda64ef45e7f4a9439f0',
    requiredLibraries: {
      'msvcp140.dll',
      'msvcp140_codecvt_ids.dll',
      'stable-diffusion.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    },
  ),
];
