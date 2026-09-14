import 'package:flutter/material.dart';

class ApasbacLogo extends StatelessWidget {
  final double height;
  const ApasbacLogo({super.key, this.height = 44});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/apasbac_logo.png',
        height: height,
        fit: BoxFit.contain,
        semanticLabel: 'APASBAC',
        errorBuilder: (_, __, ___) => Semantics(
            label: 'APASBAC',
            child: Icon(Icons.pets,
                size: height, color: Theme.of(context).colorScheme.primary)),
      );
}
