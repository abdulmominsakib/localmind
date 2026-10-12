import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:localmind/core/providers/app_providers.dart';
import 'package:localmind/features/chat/providers/tooling_providers.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  test('keeps one server manager after package info loads', () async {
    final packageInfo = Completer<PackageInfo>();
    final container = ProviderContainer(
      overrides: [
        packageInfoProvider.overrideWith((ref) => packageInfo.future),
      ],
    );
    addTearDown(container.dispose);

    final manager = container.read(mcpServerManagerProvider);
    expect(manager.appVersion, '1.0.0');

    packageInfo.complete(
      PackageInfo(
        appName: 'LocalMind',
        packageName: 'pro.momin.localmind',
        version: '1.8.8',
        buildNumber: '1',
      ),
    );
    await container.read(packageInfoProvider.future);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(mcpServerManagerProvider), same(manager));
    expect(manager.appVersion, '1.8.8');
  });
}
