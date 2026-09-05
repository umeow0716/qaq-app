import 'dart:async';

import 'package:flutter/cupertino.dart';

class Animator extends StatefulWidget {
  final Widget child;
  final Duration time;

  const Animator(this.child, this.time, {super.key});

  @override
  State<Animator> createState() => _AnimatorState();
}

class _AnimatorState extends State<Animator> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(widget.time).then((_) {
      if (mounted) setState(() => _started = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _started ? 1 : 0),
      duration: const Duration(milliseconds: 290),
      curve: Curves.easeInOut,
      child: widget.child,
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(offset: Offset(0.0, (1 - value) * 20), child: child),
        );
      },
    );
  }
}

Timer? timer;
Duration duration = const Duration();

Duration wait() {
  final activeTimer = timer;
  if (activeTimer == null || !activeTimer.isActive) {
    timer = Timer(const Duration(microseconds: 120), () {
      duration = const Duration();
    });
  }
  duration += const Duration(milliseconds: 100);
  return duration;
}

class WidgetAnimator extends StatelessWidget {
  final Widget child;

  const WidgetAnimator(this.child, {super.key});

  @override
  Widget build(BuildContext context) => Animator(child, wait());
}
