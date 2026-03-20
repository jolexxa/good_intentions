import 'package:intentions/intentions.dart' as annotations;

/// Minimal logger with consistent prefixed output.
@annotations.model
class Logger {
  /// Creates a logger that writes to [sink].
  const Logger(this.sink);

  /// The prefix prepended to all log messages.
  static const prefix = '[good_intentions]';

  /// The output sink for log messages.
  final StringSink sink;

  /// Logs an informational message.
  void info(String message) => sink.writeln('$prefix $message');

  /// Logs a warning.
  void warn(String message) => sink.writeln('$prefix WARN: $message');

  /// Logs an error.
  void error(String message) => sink.writeln('$prefix ERROR: $message');
}
