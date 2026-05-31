import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import 'widgets/auth_scaffold.dart';

/// Request a password-reset email.
///
/// Anti-enumeration (EMAIL-04): the server always returns sent:true.
/// We show a consistent "check your email" message regardless.
class PasswordResetRequestPage extends ConsumerStatefulWidget {
  const PasswordResetRequestPage({super.key});

  @override
  ConsumerState<PasswordResetRequestPage> createState() =>
      _PasswordResetRequestPageState();
}

class _PasswordResetRequestPageState
    extends ConsumerState<PasswordResetRequestPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailCtrl.text.trim().isNotEmpty && !_loading && !_sent;

  Future<void> _request() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_emailCtrl.text.trim());
      if (!mounted) return;
      setState(() => _sent = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          ApiErrorCode.rateLimited => 'Quá nhiều yêu cầu. Vui lòng thử lại sau.',
          _ => 'Đã có lỗi xảy ra. Vui lòng thử lại.',
        };
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Không thể kết nối đến máy chủ.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Quên mật khẩu',
      subtitle: 'Nhập email để nhận hướng dẫn đặt lại mật khẩu',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RM.herbSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Nếu email của bạn tồn tại trong hệ thống, chúng tôi đã gửi hướng dẫn đặt lại mật khẩu.',
                style: RMType.body(size: 14, color: RM.herb),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => context.go(AppRoutes.resetPasswordConfirm),
              child: Text(
                'Tôi đã có mã → Đặt lại mật khẩu',
                style: RMType.body(size: 14, weight: FontWeight.w700, color: RM.brand),
              ),
            ),
          ] else ...[
            RmTextField(
              label: 'Email',
              controller: _emailCtrl,
              hint: 'ten@example.com',
              keyboard: TextInputType.emailAddress,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: RMType.body(size: 13, color: RM.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
            SheetSubmit(
              label: _loading ? 'Đang gửi...' : 'Gửi hướng dẫn',
              enabled: _canSubmit,
              onPressed: _request,
            ),
          ],
        ],
      ),
      bottomAction: TextButton(
        onPressed: () => context.go(AppRoutes.login),
        child: Text(
          '← Quay lại đăng nhập',
          style: RMType.body(size: 14, color: RM.muted),
        ),
      ),
    );
  }
}
