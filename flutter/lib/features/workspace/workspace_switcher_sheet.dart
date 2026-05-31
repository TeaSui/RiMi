import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/workspace/workspace_notifier.dart';
import '../../core/workspace/workspace_repository.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import '../../widgets/primitives.dart';

/// Bottom sheet showing workspace list and switch action (AUTH-06).
///
/// To open: `WorkspaceSwitcherSheet.show(context)`.
class WorkspaceSwitcherSheet extends ConsumerStatefulWidget {
  const WorkspaceSwitcherSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const WorkspaceSwitcherSheet(),
    );
  }

  @override
  ConsumerState<WorkspaceSwitcherSheet> createState() =>
      _WorkspaceSwitcherSheetState();
}

class _WorkspaceSwitcherSheetState
    extends ConsumerState<WorkspaceSwitcherSheet> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workspaceNotifierProvider.notifier).loadWorkspaces();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceNotifierProvider);
    final authState = ref.watch(authNotifierProvider);
    final activeId = authState.activeWorkspaceId;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (context, scrollCtrl) {
        return Column(
          children: [
            SheetHeader('Chuyển cửa hàng'),
            Expanded(
              child: state.isLoading
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : state.error != null
                      ? Center(
                          child: Text(
                            state.error!,
                            style: RMType.body(size: 14, color: RM.danger),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: state.workspaces.length,
                          itemBuilder: (ctx, i) {
                            final ws = state.workspaces[i];
                            return _WorkspaceTile(
                              workspace: ws,
                              isActive: ws.id == activeId,
                              onTap: () => _switch(ws),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _switch(WorkspaceModel workspace) async {
    final authState = ref.read(authNotifierProvider);
    if (workspace.id == authState.activeWorkspaceId) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref
        .read(workspaceNotifierProvider.notifier)
        .switchWorkspace(workspace.id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _WorkspaceTile extends StatelessWidget {
  const _WorkspaceTile({
    required this.workspace,
    required this.isActive,
    required this.onTap,
  });

  final WorkspaceModel workspace;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Avatar(name: workspace.name, seed: workspace.id.hashCode),
      title: Text(
        workspace.name,
        style: RMType.body(
          size: 14,
          weight: isActive ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      subtitle: Text(
        workspace.role == 'owner' ? 'Chủ cửa hàng' : 'Nhân viên',
        style: RMType.body(size: 12, color: RM.muted),
      ),
      trailing: isActive
          ? const Icon(Icons.check_circle_rounded, color: RM.herb, size: 20)
          : null,
    );
  }
}
