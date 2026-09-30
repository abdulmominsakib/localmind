import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:localmind/core/components/server_logo.dart';
import 'package:localmind/core/models/enums.dart';

void main() {
  group('ServerTypeLogoExtension', () {
    test('provides correct asset paths for brand logos', () {
      expect(ServerType.lmStudio.logoAsset, 'assets/images/lmstudio.webp');
      expect(ServerType.lmStudio.hasLogo, isTrue);

      expect(ServerType.ollama.logoAsset, 'assets/images/ollama.webp');
      expect(ServerType.ollama.hasLogo, isTrue);

      expect(ServerType.ollamaCloud.logoAsset, 'assets/images/ollama.webp');
      expect(ServerType.ollamaCloud.hasLogo, isTrue);

      expect(ServerType.openRouter.logoAsset, 'assets/images/openrouter.webp');
      expect(ServerType.openRouter.hasLogo, isTrue);

      expect(ServerType.requesty.logoAsset, 'assets/images/requesty.webp');
      expect(ServerType.requesty.hasLogo, isTrue);

      expect(ServerType.openAICompatible.logoAsset, isNull);
      expect(ServerType.openAICompatible.hasLogo, isFalse);

      expect(ServerType.onDevice.logoAsset, isNull);
      expect(ServerType.onDevice.hasLogo, isFalse);
    });
  });

  group('ServerLogo widget', () {
    testWidgets('renders Image for server types with brand logos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerLogo(type: ServerType.lmStudio, size: 24),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(HugeIcon), findsNothing);
    });

    testWidgets('renders HugeIcon for server types without brand logos', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerLogo(type: ServerType.openAICompatible, size: 24),
          ),
        ),
      );

      expect(find.byType(HugeIcon), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders custom HugeIcon when customIcon is explicitly provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ServerLogo(
              type: ServerType.lmStudio,
              customIcon: HugeIcons.strokeRoundedStar,
              size: 24,
            ),
          ),
        ),
      );

      expect(find.byType(HugeIcon), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });
  });
}
