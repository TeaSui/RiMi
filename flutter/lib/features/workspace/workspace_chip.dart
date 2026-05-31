import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/workspace/workspace_notifier.dart';
import '../../theme/tokens.dart';
import 'workspace_switcher_sheet.dart';

/// Small workspace indicator chip for the Home header.
///
/// Tapping opens the [WorkspaceSwitcherSheet]. Shows the active workspace name
/// (or a placeholder during loading). Non-breaking: returns empty if no auth.
class WorkspaceChip extends ConsumerWidget {
  const WorkspaceChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final wsState = ref.watch(workspaceNotifierProvider);

    // Find active workspace name from list if available.
    String label = 'Cửa hàng';
    if (authState.activeWorkspaceId != null && wsState.workspaces.isNotEmpty) {
      final match = wsState.workspaces.where(
        (w) => w.id == authState.activeWorkspaceId,
      );
      if (match.isNotEmpty) label = match.first.name;
    }

    return GestureDetector(
      onTap: () => WorkspaceSwitcherSheet.show(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: RM.brandSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: RM.brand.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_rounded, size: 13, color: RM.brand),
            const SizedBox(width: 5),
            Text(
              label,
              style: RMType.body(
                size: 11.5,
                weight: FontWeight.w700,
                color: RM.brand,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more_rounded, size: 13, color: RM.brand),
          ],
        ),
      ),
    );
  }
}
