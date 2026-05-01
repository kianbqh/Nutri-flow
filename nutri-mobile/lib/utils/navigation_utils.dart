import 'package:flutter/material.dart';

class RoutePaths {
  static const String auth = '/auth';
  static const String home = '/home';
  static const String upload = '/upload';
  static const String profile = '/profile';
  static const String goals = '/goals';
  static const String history = '/history';
}

Future<void> backOrGo(BuildContext context, {String fallbackRoute = RoutePaths.home}) async {
  final navigator = Navigator.of(context);
  final popped = await navigator.maybePop();
  if (!popped && context.mounted) {
    navigator.pushNamedAndRemoveUntil(fallbackRoute, (_) => false);
  }
}

class SafeBackButton extends StatelessWidget {
  const SafeBackButton({super.key, this.fallbackRoute = RoutePaths.home});

  final String fallbackRoute;

  @override
  Widget build(BuildContext context) {
    return BackButton(
      onPressed: () => backOrGo(context, fallbackRoute: fallbackRoute),
    );
  }
}
