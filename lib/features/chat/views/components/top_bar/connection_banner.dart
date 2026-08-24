import 'package:hugeicons/hugeicons.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:localmind/core/models/enums.dart';
import 'package:localmind/core/routes/app_routes.dart';
import 'package:localmind/l10n/app_localizations.dart';

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key, required this.status});

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isError = status == ConnectionStatus.error;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: isError
          ? Colors.red.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      child: Row(
        children: [
          HugeIcon(
            icon: isError
                ? HugeIcons.strokeRoundedInformationCircle
                : HugeIcons.strokeRoundedWifiOff01,
            size: 16,
            color: isError ? Colors.red : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isError ? l10n.connection_error : l10n.disconnected,
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.red : Colors.orange[700],
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.servers),
            child: Text(
              l10n.configure,
              style: TextStyle(
                fontSize: 13,
                color: isError ? Colors.red : Colors.orange[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
