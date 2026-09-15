import 'package:flutter/material.dart';

class ApasbacLogo extends StatelessWidget {
  final double height;
  const ApasbacLogo({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) => ClipRect(
      child: Align(
          widthFactor: .68,
          heightFactor: .62,
          child: Image.asset(
            'assets/images/apasbac_logo.png',
            height: height / .62,
            fit: BoxFit.contain,
            semanticLabel: 'APASBAC',
            errorBuilder: (_, __, ___) => Semantics(
                label: 'APASBAC',
                child: Icon(Icons.pets,
                    size: height / .62,
                    color: Theme.of(context).colorScheme.primary)),
          )));
}
