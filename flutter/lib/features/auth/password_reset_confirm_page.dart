import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import 'widgets/auth_scaffold.dart';

/// Confirm password reset using the code from the email (interim paste-code flow).
///
/// EMAIL-06: token is submitted in the request body, never a URL query string.
/// AUTH-09: on success, all sessions are revoked server-side.
class PasswordResetConfirmPage extends ConsumerStatefulWidget {
  const PasswordResetConfirmPage({super.key});

  @override
  ConsumerState<PasswordResetConfirmPage> createState() =>
      _PasswordResetConfirmPageState();
}

class _PasswordResetConfirmPageState
    extends ConsumerState<PasswordResetConfirmPage> {
  final _tokenCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;
  bool _obscure = true;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _tokenCtrl.text.trim().length >= 6 &&
      _passwordCtrl.text.length >= 8 &&
      !_loading;

  Future<void> _confirm() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).confirmPasswordReset(
            token: _tokenCtrl.text.trim(),
            newPassword: _passwordCtrl.text,
          );
      if (!mounted) return;
      setState(() => _success = true);
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppRoutes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          ApiErrorCode.tokenInvalidOrExpired =>
            'Mã không hợp lệ hoặc đã hết hạn.',
          ApiErrorCode.weakPassword =>
            'Mật khẩu quá yếu. Vui lòng chọn mật khẩu mạnh hơn.',
          ApiErrorCode.validationError =>
            'Thông tin không hợp lệ.',
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
      title: 'Đặt lại mật khẩu',
      subtitle: 'Nhập mã từ email và mật khẩu mới của bạn',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_success)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: RM.herbSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Mật khẩu đã được đặt lại thành công. Đang chuyển hướng...',
                style: RMType.body(size: 14, color: RM.herb),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            RmTextField(
              label: 'Mã đặt lại',
              controller: _tokenCtrl,
              hint: 'Mã từ email',
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            _PasswordField(
              controller: _passwordCtrl,
              obscure: _obscure,
              onToggle: () => setState(() => _obscure = !_obscure),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 4),
            Text('Tối thiểu 8 ký tự', style: RMType.body(size: 12, color: RM.muted)),
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
              label: _loading ? 'Đang xử lý...' : 'Đặt lại mật khẩu',
              enabled: _canSubmit,
              onPressed: _confirm,
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

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mật khẩu mới', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted)),
        const SizedBox(height: 7),
        TextField(
          controller: controller,
          obscureText: obscure,
          onChanged: onChanged,
          style: RMType.body(size: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: RM.card,
            hintText: '••••••••',
            hintStyle: RMType.body(size: 14, color: RM.faint),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: RM.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: RM.brand, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                size: 20,
                color: RM.muted,
              ),
              onPressed: onToggle,
            ),
          ),
        ),
      ],
    );
  }
}
