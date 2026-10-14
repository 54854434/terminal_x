import 'package:flutter_test/flutter_test.dart';

import '../lib/main_terminal.dart';

void main() {
  test('legacy widget entrypoint remains available', () {
    expect(const TerminalXV024(), isA<TerminalXV024>());
  });
}
