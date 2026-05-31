import 'package:flutter/material.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/primitives.dart';

/// Shared scaffold for all auth screens.
///
/// Provides the branded header (RiMiMark + title), cream background,
/// and a scrollable body that avoids the keyboard.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.bottomAction,
  });

  final String title;
  final String? subtitle;
  final Widget body;

  /// Widget displayed below the scrollable body (e.g., sign-in/up link row).
  final Widget? bottomAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RM.cream,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand mark
                    const RiMiMark(size: 52, radius: 16),
                    const SizedBox(height: 28),

                    // Title
                    Text(
                      title,
                      style: RMType.display(size: 26, weight: FontWeight.w800),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        subtitle!,
                        style: RMType.body(size: 14, color: RM.muted),
                      ),
                    ],
                    const SizedBox(height: 32),

                    // Screen-specific content
                    body,
                  ],
                ),
              ),
            ),

            // Bottom action row (optional — sign-in link etc.)
            if (bottomAction != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: bottomAction!,
              ),
          ],
        ),
      ),
    );
  }
}
