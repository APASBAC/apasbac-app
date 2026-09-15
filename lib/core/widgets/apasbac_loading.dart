import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'apasbac_logo.dart';

class ApasbacLoading extends StatefulWidget {
  const ApasbacLoading({super.key});
  @override
  State<ApasbacLoading> createState() => _ApasbacLoadingState();
}

class _ApasbacLoadingState extends State<ApasbacLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
            label: 'APASBAC. Carregando',
            liveRegion: true,
            child: ExcludeSemantics(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ApasbacLogo(height: 140),
                const SizedBox(height: 22),
                AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(
                              3,
                              (i) => Transform.translate(
                                    offset: Offset(
                                        0,
                                        -8 *
                                            math.max(
                                                0,
                                                math.sin((_controller.value -
                                                        i * .16) *
                                                    math.pi *
                                                    2))),
                                    child: Container(
                                        width: 8,
                                        height: 8,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 5),
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            shape: BoxShape.circle)),
                                  )),
                        )),
                const SizedBox(height: 14),
                Text('Carregando',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            )),
      );
}
