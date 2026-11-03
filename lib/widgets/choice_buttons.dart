import 'package:flutter/material.dart';

/// A full-width row of options where exactly one is selected.
class ChoiceButtons<T> extends StatelessWidget {
  const ChoiceButtons({
    super.key,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  final T selected;

  /// Each option's value and the label shown for it, in order.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<T>(
      segments: [
        for (final option in options.entries) ButtonSegment(value: option.key, label: Text(option.value)),
      ],
      selected: {selected},
      showSelectedIcon: false,
      expandedInsets: EdgeInsets.zero,
      onSelectionChanged: (values) => onChanged(values.first),
    );
  }
}

/// A heading above a group of form fields.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
