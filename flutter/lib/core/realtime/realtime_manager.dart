import 'channel_status.dart';

abstract class RealtimeManager {
  RealtimeSubscription subscribe(String channelKey);
  Stream<ChannelStatus> statusStream(String channelKey);
  Stream<Map<String, dynamic>> messageStream(String channelKey);
}

abstract class RealtimeSubscription {
  void cancel();
}
