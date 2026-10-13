import 'package:balikobot_dart/balikobot_dart.dart';
import 'package:test/test.dart';

void main() {
  Matcher invalidResponse() => throwsA(
    isA<BalikobotException>().having(
      (error) => error.code,
      'code',
      BalikobotError.invalidResponse,
    ),
  );

  group('parseTrackingNotifications', () {
    test('accepts a single object and prefers status_id_v2', () {
      final notifications = parseTrackingNotifications('''
        {
          "package_id": "add-ppl-8728035",
          "eid": "order-2026-000123-S1",
          "carrier_id": "DR1536622512M",
          "status_id": 1,
          "status_id_v2": 1.2,
          "name": "Zásilka byla doručena příjemci.",
          "status_text": "Doručeno"
        }
      ''');

      expect(notifications, hasLength(1));
      final notification = notifications.single;
      expect(notification.packageId, 'add-ppl-8728035');
      expect(notification.eid, 'order-2026-000123-S1');
      expect(notification.carrierId, 'DR1536622512M');
      expect(notification.statusId, '1.2');
      expect(notification.statusText, 'Zásilka byla doručena příjemci.');
    });

    test('accepts an array with numeric identifiers', () {
      final notifications = parseTrackingNotifications('''
        [
          {
            "carrier_id": "TRACK-1",
            "status_id": 2,
            "status_text": "Zásilka v přepravě."
          },
          {
            "package_id": 42,
            "eid": 12345678,
            "carrier_id": "TRACK-2",
            "status_id_v2": 2.2,
            "name": "Zásilka byla převzata do přepravy."
          },
          {
            "carrier_id": "TRACK-3",
            "status_id": -1,
            "name": "Zásilka zatím nebyla předána dopravci."
          }
        ]
      ''');

      expect(notifications, hasLength(3));
      final first = notifications[0];
      expect(first.carrierId, 'TRACK-1');
      expect(first.packageId, isEmpty);
      expect(first.eid, isEmpty);
      expect(first.statusId, '2');
      expect(first.statusText, 'Zásilka v přepravě.');
      final second = notifications[1];
      expect(second.packageId, '42');
      expect(second.eid, '12345678');
      expect(second.carrierId, 'TRACK-2');
      expect(second.statusId, '2.2');
      expect(second.statusText, 'Zásilka byla převzata do přepravy.');
      final third = notifications[2];
      expect(third.statusId, '-1');
      expect(third.statusText, 'Zásilka zatím nebyla předána dopravci.');
    });

    test('tolerates null identifiers', () {
      final notifications = parseTrackingNotifications('''
        {
          "package_id": null,
          "eid": null,
          "carrier_id": "TRACK-1",
          "status_id": 2,
          "status_text": "Zásilka v přepravě."
        }
      ''');

      expect(notifications, hasLength(1));
      expect(notifications.single.packageId, isEmpty);
      expect(notifications.single.eid, isEmpty);
      expect(notifications.single.carrierId, 'TRACK-1');
    });

    test('accepts an empty array', () {
      expect(parseTrackingNotifications('[]'), isEmpty);
    });

    test('rejects malformed input', () {
      final cases = <String, String>{
        'empty body': '',
        'whitespace only': ' \t\n ',
        'null body': 'null',
        'scalar body': '"status"',
        'malformed json': '{"carrier_id":',
        'missing identity': '{"status_id":1,"name":"Delivered"}',
        'empty identity': '{"package_id":"","eid":"","carrier_id":"","status_id":1,"name":"Delivered"}',
        'null identity': '{"package_id":null,"eid":null,"carrier_id":null,"status_id":1,"name":"Delivered"}',
        'missing status': '{"carrier_id":"TRACK-1","name":"Delivered"}',
        'quoted status':
            '{"carrier_id":"TRACK-1","status_id":"1.2","name":"Delivered"}',
        'too precise status':
            '{"carrier_id":"TRACK-1","status_id":1.2345,"name":"Delivered"}',
        'null trailing status': '{"carrier_id":"TRACK-1","status_id":1,"status_id_v2":null,"name":"Delivered"}',
        'missing text': '{"carrier_id":"TRACK-1","status_id":1}',
        'empty text':
            '{"carrier_id":"TRACK-1","status_id":1,"name":"","status_text":""}',
        'overlong identity':
            '{"carrier_id":"${'x' * 101}","status_id":1,"name":"Delivered"}',
        'overlong numeric identity':
            '{"carrier_id":${'1' * 101},"status_id":1,"name":"Delivered"}',
        'control character':
            '{"carrier_id":"TRACK-1","status_id":1,"name":"Delivered\\nNow"}',
        'boolean identity':
            '{"carrier_id":true,"status_id":1,"name":"Delivered"}',
        'object identity': '{"carrier_id":{},"status_id":1,"name":"Delivered"}',
        'array entry not object': '[1]',
        'null array entry': '[null]',
        'one bad entry fails all':
            '[\n'
            '  {"carrier_id":"TRACK-1","status_id":1,"name":"Delivered"},\n'
            '  {"status_id":1,"name":"Delivered"}\n'
            ']',
      };
      for (final MapEntry(key: name, value: body) in cases.entries) {
        expect(
          () => parseTrackingNotifications(body),
          invalidResponse(),
          reason: name,
        );
      }
    });

    test('rejects more than 1000 entries', () {
      final body = StringBuffer('[');
      for (var index = 0; index <= 1000; index++) {
        if (index > 0) {
          body.write(',');
        }
        body.write(
          '{"carrier_id":"TRACK-$index","status_id":2,"name":"Transit"}',
        );
      }
      body.write(']');

      expect(
        () => parseTrackingNotifications(body.toString()),
        invalidResponse(),
      );
    });
  });
}
