import 'package:flutter/material.dart';
import '../theme/tokens.dart';

// ─────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────

class Order {
  Order({
    required this.id,
    required this.cust,
    required this.ch,
    required this.items,
    required this.total,
    required this.status,
    required this.time,
    this.late = false,
    this.seed = 0,
    this.note,
  });

  final String id;
  final String cust;
  final String ch; // online | app | phone | walkin
  final String items;
  final int total;
  String status; // new | cooking | ready | delivering | done
  String time;
  bool late;
  final int seed;
  final String? note;

  Order copy() => Order(
        id: id,
        cust: cust,
        ch: ch,
        items: items,
        total: total,
        status: status,
        time: time,
        late: late,
        seed: seed,
        note: note,
      );
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.cat,
    required this.price,
    required this.stock,
    required this.sold,
    required this.seed,
    required this.status, // ok | low | out
    required this.on,
  });

  final String id;
  final String name;
  final String cat;
  final int price;
  final int stock;
  final int sold;
  final int seed;
  final String status;
  bool on;
}

class Customer {
  Customer({
    required this.name,
    required this.phone,
    required this.orders,
    required this.spent,
    required this.last,
    required this.tier, // vip | gold | reg | risk
    required this.seed,
    required this.fav,
    required this.area,
  });

  final String name;
  final String phone;
  final int orders;
  final String spent;
  final String last;
  final String tier;
  final int seed;
  final String fav;
  final String area;
}

class Bot {
  const Bot(this.id, this.name, this.vn, this.icon, this.color, this.bg, this.desc);
  final String id;
  final String name;
  final String vn;
  final String icon;
  final Color color;
  final Color bg;
  final String desc;
}

// ─────────────────────────────────────────────────────────────────────
// Style maps (channel / status / stock / tier)
// ─────────────────────────────────────────────────────────────────────

const channelColor = <String, Color>{
  'online': RM.herb,
  'app': RM.gold,
  'phone': RM.info,
  'walkin': RM.muted,
};
const channelLabel = <String, String>{
  'online': 'Web shop',
  'app': 'GrabFood',
  'phone': 'Điện thoại',
  'walkin': 'Khách lẻ',
};

class StatusStyle {
  const StatusStyle(this.color, this.label);
  final Color color;
  final String label;
}

const statusStyle = <String, StatusStyle>{
  'new': StatusStyle(RM.brand, 'Mới'),
  'cooking': StatusStyle(RM.gold, 'Đang nấu'),
  'ready': StatusStyle(RM.herb, 'Sẵn sàng'),
  'delivering': StatusStyle(RM.info, 'Đang giao'),
  'done': StatusStyle(RM.muted, 'Hoàn thành'),
};

const nextStatus = <String, String>{
  'new': 'cooking',
  'cooking': 'ready',
  'ready': 'delivering',
  'delivering': 'done',
};
const nextAction = <String, String>{
  'new': 'Bắt đầu nấu',
  'cooking': 'Xong món',
  'ready': 'Đang giao',
  'delivering': 'Hoàn thành',
  'done': 'Hoàn thành',
};

const statusTabs = [
  ('new', 'Mới'),
  ('cooking', 'Đang nấu'),
  ('ready', 'Sẵn sàng'),
  ('delivering', 'Đang giao'),
  ('done', 'Hoàn thành'),
];

const channels = [
  ('all', 'Tất cả kênh', null),
  ('online', 'Web shop', RM.herb),
  ('app', 'GrabFood', RM.gold),
  ('phone', 'Phone', RM.info),
  ('walkin', 'Walk-in', RM.muted),
];

class StockStyle {
  const StockStyle(this.color, this.bg);
  final Color color;
  final Color bg;
}

const stockStyle = <String, StockStyle>{
  'ok': StockStyle(RM.herb, RM.herbSoft),
  'low': StockStyle(RM.gold, RM.goldSoft),
  'out': StockStyle(RM.danger, RM.dangerSoft),
};

class TierStyle {
  const TierStyle(this.color, this.bg, this.label);
  final Color color;
  final Color bg;
  final String label;
}

const tiers = <String, TierStyle>{
  'vip': TierStyle(RM.tierVip, RM.tierVipSoft, 'VIP'),
  'gold': TierStyle(RM.gold, RM.goldSoft, 'Vàng'),
  'reg': TierStyle(RM.herb, RM.herbSoft, 'Thường'),
  'risk': TierStyle(RM.danger, RM.dangerSoft, 'Nguy cơ'),
};

// ─────────────────────────────────────────────────────────────────────
// Stores — ChangeNotifier singletons (mirror the JS module stores)
// ─────────────────────────────────────────────────────────────────────

class OrderStore extends ChangeNotifier {
  OrderStore._();
  static final OrderStore instance = OrderStore._();

  int _seq = 1047;
  final List<Order> _data = [
    Order(id: '1042', cust: 'Chị Lan · Q.3', ch: 'online', items: 'Bún bò Huế ×2, Chả giò ×1', total: 148000, status: 'cooking', time: '8 min', late: true, seed: 1, note: 'Ít cay, nhiều giò'),
    Order(id: '1043', cust: 'Anh Dũng · GrabFood', ch: 'app', items: 'Cơm tấm sườn bì ×2', total: 120000, status: 'cooking', time: '3 min', seed: 0),
    Order(id: '1044', cust: 'Chị Mai · Q.1', ch: 'phone', items: 'Bánh mì thịt ×3, Cà phê sữa ×1', total: 92000, status: 'new', time: '2 min', seed: 2),
    Order(id: '1045', cust: 'Khách lẻ', ch: 'walkin', items: 'Nước mía ×2', total: 24000, status: 'new', time: '1 min', seed: 5),
    Order(id: '1046', cust: 'Anh Phúc · Q.5', ch: 'online', items: 'Gỏi cuốn ×4, Trà đào ×2', total: 116000, status: 'new', time: 'just now', seed: 4),
    Order(id: '1041', cust: 'Chị Hoa', ch: 'app', items: 'Cơm gà xối mỡ ×1', total: 58000, status: 'ready', time: '5 min', seed: 3),
    Order(id: '1040', cust: 'Anh Bình · Q.10', ch: 'phone', items: 'Bún bò Huế ×1, Chả giò ×2', total: 131000, status: 'ready', time: '6 min', seed: 1),
    Order(id: '1039', cust: 'Chị Thu', ch: 'online', items: 'Cơm tấm sườn ×1', total: 50000, status: 'delivering', time: '12 min', seed: 0),
    Order(id: '1038', cust: 'Anh Khoa · GrabFood', ch: 'app', items: 'Bánh mì ×2', total: 50000, status: 'delivering', time: '14 min', seed: 3),
    Order(id: '1035', cust: 'Chị Trang', ch: 'online', items: 'Cơm tấm ×2, Cà phê ×1', total: 130000, status: 'done', time: '30 min', seed: 0),
    Order(id: '1034', cust: 'Khách lẻ', ch: 'walkin', items: 'Gỏi cuốn ×2', total: 64000, status: 'done', time: '42 min', seed: 4),
  ];

  List<Order> get all => _data;
  int get activeCount => _data.where((o) => o.status != 'done').length;

  void advance(String id) {
    final o = _data.firstWhere((x) => x.id == id);
    o.status = nextStatus[o.status] ?? o.status;
    o.late = false;
    notifyListeners();
  }

  void add({
    required String cust,
    required String ch,
    required String items,
    required int total,
    required int seed,
  }) {
    _data.insert(
      0,
      Order(id: '${_seq++}', cust: cust, ch: ch, items: items, total: total, status: 'new', time: 'just now', seed: seed),
    );
    notifyListeners();
  }
}

class ProductStore extends ChangeNotifier {
  ProductStore._();
  static final ProductStore instance = ProductStore._();

  int _seq = 100;
  final List<Product> _data = [
    Product(id: 'p0', name: 'Bún bò Huế đặc biệt', cat: 'Noodles', price: 55000, stock: 8, sold: 24, seed: 1, status: 'low', on: true),
    Product(id: 'p1', name: 'Cơm tấm sườn bì chả', cat: 'Mains', price: 50000, stock: 32, sold: 31, seed: 0, status: 'ok', on: true),
    Product(id: 'p2', name: 'Bánh mì thịt nướng', cat: 'Mains', price: 25000, stock: 45, sold: 18, seed: 3, status: 'ok', on: true),
    Product(id: 'p3', name: 'Chả giò (cuốn)', cat: 'Sides', price: 38000, stock: 5, sold: 12, seed: 4, status: 'low', on: true),
    Product(id: 'p4', name: 'Gỏi cuốn tôm thịt', cat: 'Sides', price: 32000, stock: 20, sold: 9, seed: 5, status: 'ok', on: true),
    Product(id: 'p5', name: 'Cà phê sữa đá', cat: 'Drinks', price: 20000, stock: 0, sold: 40, seed: 2, status: 'out', on: false),
    Product(id: 'p6', name: 'Cơm gà xối mỡ', cat: 'Mains', price: 58000, stock: 18, sold: 14, seed: 0, status: 'ok', on: true),
    Product(id: 'p7', name: 'Trà đào cam sả', cat: 'Drinks', price: 28000, stock: 26, sold: 22, seed: 5, status: 'ok', on: true),
  ];

  List<Product> get all => _data;
  int get lowCount => _data.where((p) => p.status != 'ok' || p.stock <= 8).length;

  void toggle(String id) {
    final p = _data.firstWhere((x) => x.id == id);
    p.on = !p.on;
    notifyListeners();
  }

  void add({required String name, required String cat, required int price, required int seed}) {
    _data.insert(0, Product(id: 'p${_seq++}', name: name, cat: cat, price: price, stock: 20, sold: 0, seed: seed, status: 'ok', on: true));
    notifyListeners();
  }
}

class CustomerStore extends ChangeNotifier {
  CustomerStore._();
  static final CustomerStore instance = CustomerStore._();

  final List<Customer> _data = [
    Customer(name: 'Chị Lan Nguyễn', phone: '0908 123 456', orders: 23, spent: '3.2M₫', last: '2h ago', tier: 'vip', seed: 0, fav: 'Bún bò Huế', area: 'Q.3'),
    Customer(name: 'Anh Dũng Trần', phone: '0912 887 654', orders: 14, spent: '1.8M₫', last: 'Today', tier: 'gold', seed: 1, fav: 'Cơm tấm sườn', area: 'GrabFood'),
    Customer(name: 'Chị Mai Phạm', phone: '0938 222 111', orders: 9, spent: '980k₫', last: 'Yesterday', tier: 'reg', seed: 2, fav: 'Bánh mì thịt', area: 'Q.1'),
    Customer(name: 'Anh Phúc Lê', phone: '0977 555 333', orders: 4, spent: '420k₫', last: '18 days ago', tier: 'risk', seed: 3, fav: 'Gỏi cuốn', area: 'Q.5'),
    Customer(name: 'Chị Hoa Đỗ', phone: '0905 444 222', orders: 19, spent: '2.6M₫', last: 'Today', tier: 'vip', seed: 4, fav: 'Cơm gà', area: 'Q.7'),
    Customer(name: 'Anh Khoa Vũ', phone: '0933 121 343', orders: 11, spent: '1.3M₫', last: '3 days ago', tier: 'gold', seed: 1, fav: 'Bún bò Huế', area: 'GrabFood'),
    Customer(name: 'Chị Trang Bùi', phone: '0918 765 432', orders: 6, spent: '640k₫', last: '6 days ago', tier: 'reg', seed: 0, fav: 'Trà đào', area: 'Q.10'),
    Customer(name: 'Anh Bình Hồ', phone: '0966 010 909', orders: 3, spent: '310k₫', last: '24 days ago', tier: 'risk', seed: 3, fav: 'Bánh mì', area: 'Q.4'),
  ];

  List<Customer> get all => _data;

  void add({required String name, required String phone, required String area, required String tier, required int seed}) {
    _data.insert(0, Customer(name: name, phone: phone, area: area, tier: tier, orders: 0, spent: '0₫', last: 'New', seed: seed, fav: '—'));
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────
// Static reference data
// ─────────────────────────────────────────────────────────────────────

const productCats = ['All', 'Mains', 'Noodles', 'Sides', 'Drinks'];

const composerMenu = [
  ('Bún bò Huế', 55000, 1),
  ('Cơm tấm sườn bì', 50000, 0),
  ('Bánh mì thịt', 25000, 3),
  ('Chả giò', 38000, 4),
  ('Gỏi cuốn', 32000, 5),
  ('Cà phê sữa đá', 20000, 2),
];

const bots = <Bot>[
  Bot('sales', 'Sales', 'Trợ lý Bán hàng', 'orders', RM.brand, RM.brandSoft, 'Upsell tips, order summaries, daily targets'),
  Bot('mkt', 'Marketing', 'Trợ lý Marketing', 'content', RM.gold, RM.goldSoft, 'Captions, promo ideas, post scheduling'),
  Bot('acct', 'Accountant', 'Trợ lý Kế toán', 'finance', RM.herb, RM.herbSoft, 'Books, profit, tax & cash reminders'),
  Bot('stock', 'Stock', 'Trợ lý Kho', 'box', RM.info, Color(0xFFE1ECF8), 'Restock alerts, supplier orders'),
  Bot('care', 'Customer Care', 'Trợ lý CSKH', 'users', RM.tierVip, RM.tierVipSoft, 'Auto-replies, reviews, loyalty'),
];

// Finance datasets per period
class FinPeriod {
  const FinPeriod({
    required this.label,
    required this.max,
    required this.data,
    required this.profit,
    required this.rev,
    required this.exp,
    required this.kpi,
    required this.spend,
  });
  final String label;
  final double max;
  final List<(String, double, double)> data; // (label, rev, exp)
  final String profit;
  final String rev;
  final String exp;
  final List<(String, String, String)> kpi; // (label, value, delta)
  final List<(String, String, int, Color)> spend; // (label, value, pct, color)
}

const _week = [
  ('Mon', 2.1, 1.2), ('Tue', 2.8, 1.4), ('Wed', 2.4, 1.1),
  ('Thu', 3.2, 1.5), ('Fri', 3.9, 1.8), ('Sat', 4.6, 2.0), ('Sun', 4.1, 1.7),
];

const finance = <String, FinPeriod>{
  'Day': FinPeriod(
    label: 'Today · 30 May',
    max: 0.85,
    data: [('8a', 0.22, 0.12), ('10a', 0.5, 0.24), ('12p', 0.72, 0.3), ('2p', 0.38, 0.18), ('4p', 0.46, 0.2), ('6p', 0.68, 0.28), ('8p', 0.4, 0.16)],
    profit: '+1.620.000₫',
    rev: '2.84M₫',
    exp: '1.22M₫',
    kpi: [('Revenue', '2.84M₫', '+12%'), ('Expenses', '1.22M₫', '+4%'), ('Net profit', '1.62M₫', '+18%'), ('Orders', '38', '+8%')],
    spend: [('Ingredients', '720k₫', 62, RM.brand), ('Staff', '320k₫', 27, RM.gold), ('Delivery & fees', '180k₫', 11, RM.info)],
  ),
  'Week': FinPeriod(
    label: 'This week · 24–30 May',
    max: 5,
    data: _week,
    profit: '+12.640.000₫',
    rev: '23.1M₫',
    exp: '10.5M₫',
    kpi: [('Revenue', '23.1M₫', '+14%'), ('Expenses', '10.5M₫', '+6%'), ('Net profit', '12.6M₫', '+19%'), ('Orders', '264', '+11%')],
    spend: [('Ingredients', '6.8M₫', 65, RM.brand), ('Staff', '2.4M₫', 23, RM.gold), ('Delivery & fees', '1.3M₫', 12, RM.info)],
  ),
  'Month': FinPeriod(
    label: 'May 2026',
    max: 20,
    data: [('W1', 14.0, 7.0), ('W2', 17.0, 8.0), ('W3', 15.0, 7.5), ('W4', 19.0, 9.0)],
    profit: '+52.400.000₫',
    rev: '96.2M₫',
    exp: '43.8M₫',
    kpi: [('Revenue', '96.2M₫', '+16%'), ('Expenses', '43.8M₫', '+9%'), ('Net profit', '52.4M₫', '+22%'), ('Orders', '1.12k', '+13%')],
    spend: [('Ingredients', '28.4M₫', 65, RM.brand), ('Staff', '10.1M₫', 23, RM.gold), ('Delivery & fees', '5.3M₫', 12, RM.info)],
  ),
};

const topDishes = [
  ('Cơm tấm sườn bì', '5.4M₫', 0),
  ('Bún bò Huế', '4.8M₫', 1),
  ('Bánh mì thịt', '3.1M₫', 3),
  ('Gỏi cuốn', '2.2M₫', 5),
];
