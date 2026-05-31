import 'package:flutter_test/flutter_test.dart';
import 'package:rimi/core/realtime/realtime_manager_impl.dart';

void main() {
  test('open close ten times leaves no channel entry', () {
    final manager = RealtimeManagerImpl(
      connector: fakeSocketConnector,
      reconnectDelays: const [Duration(milliseconds: 1)],
    );

    final subs = [
      for (var i = 0; i < 10; i++) manager.subscribe('workspace:X:orders'),
    ];
    for (final sub in subs) {
      sub.cancel();
    }

    expect(manager.debugChannelCount, 0);
  });

  test('double cancel is a no-op', () {
    final manager = RealtimeManagerImpl(
      connector: fakeSocketConnector,
      reconnectDelays: const [Duration(milliseconds: 1)],
    );
    final sub = manager.subscribe('workspace:X:orders');

    sub.cancel();
    sub.cancel();

    expect(manager.debugChannelCount, 0);
  });

  test('two subscribers share one channel entry', () {
    final manager = RealtimeManagerImpl(
      connector: fakeSocketConnector,
      reconnectDelays: const [Duration(milliseconds: 1)],
    );

    final sub1 = manager.subscribe('workspace:X:orders');
    final sub2 = manager.subscribe('workspace:X:orders');

    expect(manager.debugChannelCount, 1);

    sub1.cancel();
    expect(manager.debugChannelCount, 1); // still alive because sub2 holds it

    sub2.cancel();
    expect(manager.debugChannelCount, 0); // now gone
  });
}

Future<void> fakeSocketConnector(String channelKey) async {}
