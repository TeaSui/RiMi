import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/network/api_exception.dart';
import '../../core/router/app_router.dart';
import '../../theme/tokens.dart';
import '../../widgets/forms.dart';
import 'widgets/auth_scaffold.dart';

/// "Enter the code from your email" interim flow (Phase 1 — no deep links).
///
/// EMAIL-06: token submitted in request body, never a URL query string.
class EmailVerificationPendingPage extends ConsumerStatefulWidget {
  const EmailVerificationPendingPage({super.key, required this.email});
  final String email;

  @override
  ConsumerState<EmailVerificationPendingPage> createState() =>
      _EmailVerificationPendingPageState();
}

class _EmailVerificationPendingPageState
    extends ConsumerState<EmailVerificationPendingPage> {
  final _tokenCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _tokenCtrl.text.trim().length >= 6 && !_loading;

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).verifyEmail(_tokenCtrl.text.trim());
      if (!mounted) return;
      setState(() => _success = true);
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      context.go(AppRoutes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = switch (e.code) {
          ApiErrorCode.tokenInvalidOrExpired =>
            'Mã xác nhận không hợp lệ hoặc đã hết hạn.',
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
      title: 'Xác nhận email',
      subtitle:
          'Chúng tôi đã gửi mã xác nhận đến ${widget.email}. Nhập mã để kích hoạt tài khoản.',
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
                'Xác nhận thành công! Đang chuyển hướng...',
                style: RMType.body(size: 14, color: RM.herb),
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            RmTextField(
              label: 'Mã xác nhận',
              controller: _tokenCtrl,
              hint: 'Nhập mã từ email',
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
              label: _loading ? 'Đang xác nhận...' : 'Xác nhận',
              enabled: _canSubmit,
              onPressed: _verify,
            ),
          ],
        ],
      ),
      bottomAction: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Đã có tài khoản?',
            style: RMType.body(size: 14, color: RM.muted),
          ),
          TextButton(
            onPressed: () => context.go(AppRoutes.login),
            child: Text(
              'Đăng nhập',
              style: RMType.body(
                size: 14,
                weight: FontWeight.w700,
                color: RM.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
