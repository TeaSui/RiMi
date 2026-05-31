import 'dart:async';

import 'channel_status.dart';
import 'realtime_manager.dart';

typedef SocketConnector = Future<void> Function(String channelKey);

class RealtimeManagerImpl implements RealtimeManager {
  RealtimeManagerImpl({
    required SocketConnector connector,
    List<Duration>? reconnectDelays,
  })  : _connector = connector,
        _reconnectDelays = reconnectDelays ??
            const [
              Duration(seconds: 1),
              Duration(seconds: 2),
              Duration(seconds: 4),
              Duration(seconds: 8),
              Duration(seconds: 16),
            ];

  final SocketConnector _connector;
  final List<Duration> _reconnectDelays;
  final Map<String, _ChannelEntry> _channels = {};

  /// Exposed for tests only — do not call from production code.
  int get debugChannelCount => _channels.length;

  @override
  RealtimeSubscription subscribe(String channelKey) {
    final entry = _channels.putIfAbsent(channelKey, () {
      final created = _ChannelEntry();
      _open(channelKey, created);
      return created;
    });
    entry.refCount++;
    return _Subscription(() => _cancel(channelKey));
  }

  @override
  Stream<Map<String, dynamic>> messageStream(String channelKey) {
    return _channels[channelKey]?.messageCtrl.stream ?? const Stream.empty();
  }

  @override
  Stream<ChannelStatus> statusStream(String channelKey) {
    return _channels[channelKey]?.statusCtrl.stream ?? const Stream.empty();
  }

  Future<void> _open(String channelKey, _ChannelEntry entry) async {
    // Guard: entry may have been cancelled before the async frame resumes.
    if (entry.refCount <= 0 || entry.statusCtrl.isClosed) return;

    entry.status = ChannelStatus.connecting;
    entry.statusCtrl.add(entry.status);
    try {
      await _connector(channelKey);

      // Re-check after the await — could be cancelled during connection.
      if (entry.refCount <= 0 || entry.statusCtrl.isClosed) return;

      entry.status = ChannelStatus.open;
      entry.backoffIndex = 0;
      entry.statusCtrl.add(entry.status);
    } catch (_) {
      if (entry.refCount <= 0 || entry.statusCtrl.isClosed) return;
      entry.status = ChannelStatus.error;
      entry.statusCtrl.add(entry.status);
      _scheduleReconnect(channelKey, entry);
    }
  }

  void _scheduleReconnect(String channelKey, _ChannelEntry entry) {
    if (entry.refCount <= 0) return;
    final delay =
        _reconnectDelays[entry.backoffIndex.clamp(0, _reconnectDelays.length - 1)];
    entry.backoffIndex++;
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = Timer(delay, () => _open(channelKey, entry));
  }

  void _cancel(String channelKey) {
    final entry = _channels[channelKey];
    if (entry == null) return;
    entry.refCount--;
    if (entry.refCount <= 0) {
      entry.reconnectTimer?.cancel();
      entry.status = ChannelStatus.closed;
      entry.statusCtrl.add(entry.status);
      entry.statusCtrl.close();
      entry.messageCtrl.close();
      _channels.remove(channelKey);
    }
  }
}

class _ChannelEntry {
  int refCount = 0;
  int backoffIndex = 0;
  ChannelStatus status = ChannelStatus.closed;
  final statusCtrl = StreamController<ChannelStatus>.broadcast();
  final messageCtrl = StreamController<Map<String, dynamic>>.broadcast();
  Timer? reconnectTimer;
}

class _Subscription implements RealtimeSubscription {
  _Subscription(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel();
  }
}
