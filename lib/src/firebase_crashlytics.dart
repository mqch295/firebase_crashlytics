// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
part of firebase_crashlytics;

/// The entry point for accessing Crashlytics.
///
/// You can get an instance by calling `Crashlytics.instance`.
class Crashlytics {
  static final instance = Crashlytics();

  /// Set to true to have errors sent to Crashlytics while in debug mode. By
  /// default this is false.
  var enableInDevMode = false;

  bool get _shouldReport => !kDebugMode || enableInDevMode;

  @visibleForTesting
  static const MethodChannel channel =
      MethodChannel('plugins.flutter.io/firebase_crashlytics');

  /// Submits report of a non-fatal error caught by the Flutter framework.
  /// to Firebase Crashlytics.
  Future<void> recordFlutterError(FlutterErrorDetails details) async {
    print('Flutter error caught by Crashlytics plugin:');
    // Since multiple errors can be caught during a single session, we set
    // forceReport=true.
    FlutterError.dumpErrorToConsole(details, forceReport: true);

    _recordError(details.exceptionAsString(), details.stack,
        context: details.context,
        information: details.informationCollector == null
            ? null
            : details.informationCollector(),
        printDetails: false);
  }

  /// Submits a report of a non-fatal error.
  ///
  /// For errors generated by the Flutter framework, use [recordFlutterError] instead.
  Future<void> recordError(
    dynamic exception,
    StackTrace stack, {
    dynamic context,
  }) async {
    print('Error caught by Crashlytics plugin <recordError>:');
    _recordError(exception, stack, context: context);
  }

  void crash() {
    throw StateError('Error thrown by Crashlytics plugin');
  }

  /// Add text logging that will be sent to Crashlytics.
  Future<void> log(String msg) async {
    if (!_shouldReport) return;
    ArgumentError.checkNotNull(msg, 'msg');
    return channel.invokeMethod<void>(
      'Crashlytics#log',
      <String, dynamic>{'log': msg},
    );
  }

  /// Sets a [value] to be associated with a given [key] for your crash data.
  ///
  /// The [value] will be converted to a string by calling [toString] on it.
  /// An error will be thrown if it is null.
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_shouldReport) return;
    ArgumentError.checkNotNull(key, 'key');
    ArgumentError.checkNotNull(value, 'value');
    return channel.invokeMethod<void>(
      'Crashlytics#setKey',
      <String, dynamic>{
        'key': key,
        'value': value.toString(),
      },
    );
  }

  /// Specify a user identifier which will be visible in the Crashlytics UI.
  /// Please be mindful of end-user's privacy.
  Future<void> setUserIdentifier(String identifier) async {
    await channel.invokeMethod<void>('Crashlytics#setUserIdentifier',
        <String, dynamic>{'identifier': identifier});
  }

  @visibleForTesting
  List<Map<String, String>> getStackTraceElements(List<String> lines) {
    final List<Map<String, String>> elements = <Map<String, String>>[];
    for (String line in lines) {
      final List<String> lineParts = line.split(RegExp('\\s+'));
      try {
        final String fileName = lineParts[0];
        final String lineNumber = lineParts[1].contains(":")
            ? lineParts[1].substring(0, lineParts[1].indexOf(":")).trim()
            : lineParts[1];

        final Map<String, String> element = <String, String>{
          'file': fileName,
          'line': lineNumber,
        };

        // The next section would throw an exception in some cases if there was no stop here.
        if (lineParts.length < 3) {
          elements.add(element);
          continue;
        }

        if (lineParts[2].contains(".")) {
          final String className =
              lineParts[2].substring(0, lineParts[2].indexOf(".")).trim();
          final String methodName =
              lineParts[2].substring(lineParts[2].indexOf(".") + 1).trim();

          element['class'] = className;
          element['method'] = methodName;
        } else {
          element['method'] = lineParts[2];
        }

        elements.add(element);
      } catch (e) {
        print(e.toString());
      }
    }
    return elements;
  }

  // On top of the default exception components, [information] can be passed as well.
  // This allows the developer to get a better understanding of exceptions thrown
  // by the Flutter framework. [FlutterErrorDetails] often explain why an exception
  // occurred and give useful background information in [FlutterErrorDetails.informationCollector].
  // Crashlytics will log this information in addition to the stack trace.
  // If [information] is `null` or empty, it will be ignored.
  Future<void> _recordError(
    dynamic exception,
    StackTrace stack, {
    dynamic context,
    Iterable<DiagnosticsNode> information,
    bool printDetails,
  }) async {
    printDetails ??= kDebugMode;

    final String _information = (information == null || information.isEmpty)
        ? ''
        : (StringBuffer()..writeAll(information, '\n')).toString();

    if (printDetails) {
      // If available, give context to the exception.
      if (context != null)
        print('The following exception was thrown $context:');

      // Need to print the exception to explain why the exception was thrown.
      print(exception);

      // Print information provided by the Flutter framework about the exception.
      if (_information.isNotEmpty) print('\n$_information');

      // Not using Trace.format here to stick to the default stack trace format
      // that Flutter developers are used to seeing.
      if (stack != null) print('\n$stack');
    }

    if (_shouldReport) {
      // The stack trace can be null. To avoid the following exception:
      // Invalid argument(s): Cannot create a Trace from null.
      // We can check for null and provide an empty stack trace.
      stack ??= StackTrace.current ?? StackTrace.fromString('');

      // Report error.
      final List<String> stackTraceLines =
          Trace.format(stack).trimRight().split('\n');
      final List<Map<String, String>> stackTraceElements =
          getStackTraceElements(stackTraceLines);

      // The context is a string that "should be in a form that will make sense in
      // English when following the word 'thrown'" according to the documentation for
      // [FlutterErrorDetails.context]. It is displayed to the user on Crashlytics
      // as the "reason", which is forced by iOS, with the "thrown" prefix added.
      final String result = await channel
          .invokeMethod<String>('Crashlytics#onError', <String, dynamic>{
        'exception': "${exception.toString()}",
        'context': '$context',
        'information': _information,
        'stackTraceElements': stackTraceElements,
      });

      // Print result.
      print('firebase_crashlytics: $result');
    }
  }
}
