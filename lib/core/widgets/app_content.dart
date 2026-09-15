import 'package:flutter/material.dart';

/// Keeps reading and form controls comfortable on tablets and desktop.
class AppContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const AppContent({super.key, required this.child, this.maxWidth = 760});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: SizedBox(width: double.infinity, child: child),
        ),
      );
}
