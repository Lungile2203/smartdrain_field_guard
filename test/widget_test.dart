import 'package:flutter_test/flutter_test.dart';
import 'package:smartdrain_field/models/report.dart';

void main() {
  test('report survives a JSON round trip (same format as the website)', () {
    final r = Report(id: Report.newId(), type: 'blocked', severity: 'high', reporter: 'Test', ts: 0);
    final back = Report.fromJson(r.toJson());
    expect(back.type, 'blocked');
    expect(back.typeLabel, 'Blocked');
    expect(back.status, 'reported');
  });
}
