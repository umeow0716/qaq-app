import 'package:flutter/material.dart';
import 'package:flutter_app/src/r.dart';

class ScorePageAppBarActionButtons extends StatelessWidget {
  const ScorePageAppBarActionButtons({
    super.key,
    required this.onRefreshPressed,
    required this.onCalculateCreditPressed,
  });

  final VoidCallback onRefreshPressed;
  final VoidCallback onCalculateCreditPressed;

  Widget get _refreshButton => Tooltip(
    message: R.current.refresh,
    child: IconButton(icon: const Icon(Icons.refresh), onPressed: onRefreshPressed),
  );

  Widget get _calculateCreditButton => Tooltip(
    message: R.current.calculationCredit,
    child: IconButton(icon: const Icon(Icons.calculate), onPressed: onCalculateCreditPressed),
  );

  @override
  Widget build(BuildContext context) => Row(children: [_refreshButton, _calculateCreditButton]);
}
