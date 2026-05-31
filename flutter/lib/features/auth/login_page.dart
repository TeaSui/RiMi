import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_notifier.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import 'widgets/auth_scaffold.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _emailCtrl.text.trim().isNotEmpty &&
      _passwordCtrl.text.isNotEmpty &&
      !_loading;

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).login(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          );
      // Router redirect guard handles navigation.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          ApiErrorCode.invalidCredentials =>
            'Email hoặc mật khẩu không đúng.',
          ApiErrorCode.accountLocked =>
            'Tài khoản tạm khóa. Vui lòng thử lại sau.',
          ApiErrorCode.rateLimited =>
            'Quá nhiều yêu cầu. Vui lòng thử lại sau.',
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
      title: 'Đăng nhập',
      subtitle: 'Chào mừng bạn trở lại RiMi',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RmTextField(
            label: 'Email',
            controller: _emailCtrl,
            hint: 'ten@example.com',
            keyboard: TextInputType.emailAddress,
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.resetPassword),
              child: Text(
                'Quên mật khẩu?',
                style: RMType.body(size: 13, color: RM.brand),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(
              _error!,
              style: RMType.body(size: 13, color: RM.danger),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          SheetSubmit(
            label: _loading ? 'Đang đăng nhập...' : 'Đăng nhập',
            enabled: _canSubmit,
            onPressed: _login,
          ),
        ],
      ),
      bottomAction: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Chưa có tài khoản?', style: RMType.body(size: 14, color: RM.muted)),
          TextButton(
            onPressed: () => context.go(AppRoutes.signup),
            child: Text('Đăng ký', style: RMType.body(size: 14, weight: FontWeight.w700, color: RM.brand)),
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
