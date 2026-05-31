import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import 'widgets/auth_scaffold.dart';

class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _nameCtrl.text.trim().isNotEmpty &&
      _emailCtrl.text.trim().isNotEmpty &&
      _passwordCtrl.text.length >= 8 &&
      !_loading;

  Future<void> _register() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).register(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
            displayName: _nameCtrl.text.trim(),
          );
      if (!mounted) return;
      // Navigate to verify-email pending screen.
      context.go(
        '${AppRoutes.verifyEmail}?email=${Uri.encodeComponent(_emailCtrl.text.trim())}',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          ApiErrorCode.validationError => 'Thông tin không hợp lệ. Kiểm tra lại email và mật khẩu.',
          ApiErrorCode.weakPassword => 'Mật khẩu quá yếu. Vui lòng chọn mật khẩu mạnh hơn.',
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
      title: 'Tạo tài khoản',
      subtitle: 'Bắt đầu quản lý cửa hàng của bạn',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RmTextField(
            label: 'Tên hiển thị',
            controller: _nameCtrl,
            hint: 'Nguyễn Văn A',
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          RmTextField(
            label: 'Email',
            controller: _emailCtrl,
            hint: 'ten@example.com',
            keyboard: TextInputType.emailAddress,
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
          Text(
            'Tối thiểu 8 ký tự',
            style: RMType.body(size: 12, color: RM.muted),
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
            label: _loading ? 'Đang tạo tài khoản...' : 'Tạo tài khoản',
            enabled: _canSubmit,
            onPressed: _register,
          ),
        ],
      ),
      bottomAction: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Đã có tài khoản?', style: RMType.body(size: 14, color: RM.muted)),
          TextButton(
            onPressed: () => context.go(AppRoutes.login),
            child: Text(
              'Đăng nhập',
              style: RMType.body(size: 14, weight: FontWeight.w700, color: RM.brand),
            ),
          ),
        ],
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
        Text('Mật khẩu', style: RMType.body(size: 12, weight: FontWeight.w700, color: RM.muted)),
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
