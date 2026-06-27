import 'package:flutter/material.dart';

import '../theme/shed_colors.dart';
import '../theme/shed_theme.dart';

/// An AppBar title that stacks a name over a mono "N nouns" subtitle (the design's
/// shed/session screen header). [count] is null while the list is still loading,
/// which hides the subtitle. Plural is the noun + "s".
class AppBarCountTitle extends StatelessWidget {
  const AppBarCountTitle({
    super.key,
    required this.title,
    required this.count,
    required this.noun,
  });

  final String title;
  final int? count;
  final String noun;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, overflow: TextOverflow.ellipsis),
        if (count != null)
          Text(
            '$count ${count == 1 ? noun : '${noun}s'}',
            style: monoStyle(fontSize: 11, color: context.shed.fg3),
          ),
      ],
    );
  }
}
