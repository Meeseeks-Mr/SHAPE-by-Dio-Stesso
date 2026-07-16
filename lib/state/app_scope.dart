import 'package:flutter/widgets.dart';

import 'editor_model.dart';

/// Lightweight dependency-injection for [EditorModel] via [InheritedNotifier],
/// standing in for Riverpod/Bloc (§25.1) with zero external dependencies.
/// `AppScope.of(context)` both reads the model and subscribes the caller to
/// rebuilds.
class AppScope extends InheritedNotifier<EditorModel> {
  // `child` can't be a super-parameter here because we also forward `notifier`
  // via the super-initializer; const is impossible since `model` is mutable.
  // ignore: prefer_const_constructors_in_immutables, use_super_parameters
  AppScope({super.key, required EditorModel model, required Widget child})
      : super(notifier: model, child: child);

  static EditorModel of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }

  /// Read the model without subscribing to rebuilds (for event handlers).
  static EditorModel read(BuildContext context) {
    final scope = context
        .getElementForInheritedWidgetOfExactType<AppScope>()!
        .widget as AppScope;
    return scope.notifier!;
  }
}
