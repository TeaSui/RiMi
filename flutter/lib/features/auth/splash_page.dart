import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_notifier.dart';
import '../../theme/tokens.dart';
import '../../widgets/primitives.dart';

/// Bootstrap screen shown during cold-start session restore (AUTH-04).
///
/// Calls [AuthNotifier.bootstrap] once, then the GoRouter redirect guard
/// transitions automatically based on the resulting [AuthState].
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    // Schedule bootstrap after the first frame so GoRouter is mounted.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    await ref.read(authNotifierProvider.notifier).bootstrap();
    // Router redirect guard handles navigation automatically.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RM.cream,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const RiMiMark(size: 72, radius: 22),
            const SizedBox(height: 28),
            Text(
              'RiMi',
              style: RMType.display(size: 32, weight: FontWeight.w800, color: RM.brand),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: RM.brand.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
