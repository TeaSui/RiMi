import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/workspace/workspace_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import '../../widgets/primitives.dart';

/// Create workspace screen (AUTH-05).
///
/// Shown after successful login/signup when no workspace exists.
/// On success, [WorkspaceNotifier.createWorkspace] updates [AuthState]
/// to ready, triggering the router redirect to /shell.
class CreateWorkspacePage extends ConsumerStatefulWidget {
  const CreateWorkspacePage({super.key});

  @override
  ConsumerState<CreateWorkspacePage> createState() =>
      _CreateWorkspacePageState();
}

class _CreateWorkspacePageState extends ConsumerState<CreateWorkspacePage> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final name = _nameCtrl.text.trim();
    return name.isNotEmpty && name.length <= 120;
  }

  Future<void> _create() async {
    await ref
        .read(workspaceNotifierProvider.notifier)
        .createWorkspace(_nameCtrl.text.trim());
    // Router redirect guard handles navigation to /shell on state change.
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(workspaceNotifierProvider);

    return Scaffold(
      backgroundColor: RM.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const RiMiMark(size: 52, radius: 16),
              const SizedBox(height: 28),
              Text(
                'Tạo cửa hàng',
                style: RMType.display(size: 26, weight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Đặt tên cho cửa hàng của bạn để bắt đầu.',
                style: RMType.body(size: 14, color: RM.muted),
              ),
              const SizedBox(height: 32),
              RmTextField(
                label: 'Tên cửa hàng',
                controller: _nameCtrl,
                hint: 'Phở Hà Nội',
                autofocus: true,
                onChanged: (_) => setState(() {}),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  state.error!,
                  style: RMType.body(size: 13, color: RM.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
              SheetSubmit(
                label: state.isLoading ? 'Đang tạo...' : 'Tạo cửa hàng',
                enabled: _canSubmit && !state.isLoading,
                onPressed: _create,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
