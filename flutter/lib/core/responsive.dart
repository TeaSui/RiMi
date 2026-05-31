import 'package:flutter/widgets.dart';

/// Single tablet breakpoint. Mobile frames are 390pt; tablet layouts kick in
/// at the iPad's shortest comfortable width.
bool isTablet(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 700;

double screenW(BuildContext context) => MediaQuery.sizeOf(context).width;
