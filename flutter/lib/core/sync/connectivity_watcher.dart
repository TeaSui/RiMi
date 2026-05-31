import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkStatus { online, offline }

class ConnectivityWatcher {
  ConnectivityWatcher({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  Stream<NetworkStatus> get status {
    return _connectivity.onConnectivityChanged.map((results) {
      return results.every((r) => r == ConnectivityResult.none)
          ? NetworkStatus.offline
          : NetworkStatus.online;
    }).distinct();
  }
}
