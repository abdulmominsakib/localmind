import 'package:llamadart/llamadart.dart';

/// An application extension that must remain unambiguous on ordinary sessions.
extension ApplicationTemplateClock on ChatSession {
  DateTime get templateNow => DateTime.utc(1984, 6, 1);
}
