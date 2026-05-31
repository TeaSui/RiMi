import 'package:flutter/material.dart';

/// Maps the design's semantic icon names (ICONS in tokens.jsx) to the closest
/// Material icon. The source uses a custom 24×24 rounded stroke set; these are
/// faithful Material equivalents so the build runs with no asset pipeline.
abstract final class AppIcons {
  static const _map = <String, IconData>{
    'home': Icons.home_rounded,
    'orders': Icons.shopping_bag_outlined,
    'products': Icons.inventory_2_outlined,
    'content': Icons.chat_bubble_outline_rounded,
    'finance': Icons.account_balance_wallet_outlined,
    'search': Icons.search_rounded,
    'bell': Icons.notifications_outlined,
    'plus': Icons.add_rounded,
    'sparkle': Icons.auto_awesome_rounded,
    'filter': Icons.filter_alt_outlined,
    'chevR': Icons.chevron_right_rounded,
    'chevD': Icons.keyboard_arrow_down_rounded,
    'check': Icons.check_rounded,
    'clock': Icons.schedule_rounded,
    'truck': Icons.local_shipping_outlined,
    'store': Icons.storefront_outlined,
    'phone': Icons.call_outlined,
    'user': Icons.person_outline_rounded,
    'users': Icons.people_alt_outlined,
    'up': Icons.north_east_rounded,
    'down': Icons.south_east_rounded,
    'star': Icons.star_border_rounded,
    'edit': Icons.edit_outlined,
    'camera': Icons.photo_camera_outlined,
    'wifi_off': Icons.wifi_off_rounded,
    'box': Icons.inventory_2_outlined,
    'grid': Icons.grid_view_rounded,
    'list': Icons.format_list_bulleted_rounded,
    'arrowR': Icons.arrow_forward_rounded,
    'arrowL': Icons.arrow_back_rounded,
    'close': Icons.close_rounded,
    'more': Icons.more_vert_rounded,
    'calendar': Icons.calendar_today_outlined,
    'tag': Icons.sell_outlined,
    'download': Icons.file_download_outlined,
    'refresh': Icons.refresh_rounded,
    'pin': Icons.location_on_outlined,
    'heart': Icons.favorite_border_rounded,
    'heartFill': Icons.favorite_rounded,
    'gift': Icons.card_giftcard_rounded,
    'flame': Icons.local_fire_department_outlined,
    'mic': Icons.mic_none_rounded,
    'send': Icons.send_rounded,
    'layers': Icons.layers_outlined,
    'sliders': Icons.tune_rounded,
    'ramen': Icons.ramen_dining_rounded,
  };

  static IconData of(String name) => _map[name] ?? Icons.circle_outlined;
}

/// Convenience widget mirroring the source `<Icon name= size= color= />`.
class RmIcon extends StatelessWidget {
  const RmIcon(this.name, {super.key, this.size = 24, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Icon(AppIcons.of(name), size: size, color: color);
}
