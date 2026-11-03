import 'package:flutter/material.dart';

/// A tappable card with a large icon and a label. Greyed out when [onTap] is null.
class OptionTile extends StatelessWidget {
  const OptionTile({super.key, required this.icon, required this.label, this.caption, this.onTap});

  final IconData icon;
  final String label;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Card.filled(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(label, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
              if (caption != null) Text(caption!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
