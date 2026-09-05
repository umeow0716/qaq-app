import 'package:flutter/cupertino.dart';

class OverRepaintBoundary extends StatefulWidget {
  final Widget child;

  const OverRepaintBoundary({super.key, required this.child});

  @override
  OverRepaintBoundaryState createState() => OverRepaintBoundaryState();
}

class OverRepaintBoundaryState extends State<OverRepaintBoundary> {
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
