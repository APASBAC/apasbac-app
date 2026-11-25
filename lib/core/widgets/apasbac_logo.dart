import 'package:flutter/material.dart';

/// Logo Socorro Bicho / APASBAC. O arquivo já vem recortado rente ao desenho,
/// então a logo aparece inteira, sem cortes, em qualquer altura.
class ApasbacLogo extends StatelessWidget {
  final double height;
  const ApasbacLogo({super.key, this.height = 64});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/images/apasbac_logo.png',
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'APASBAC',
        errorBuilder: (_, __, ___) => Semantics(
            label: 'APASBAC',
            child: Icon(Icons.pets,
                size: height, color: Theme.of(context).colorScheme.primary)),
      );
}
