import 'package:flutter/material.dart';

import '../widgets/option_tile.dart';
import 'sport.dart';

/// The first screen: pick the sport to score or stream.
class SelectSportScreen extends StatefulWidget {
  const SelectSportScreen({super.key, required this.onSportSelected});

  final void Function(BuildContext context, Sport sport) onSportSelected;

  @override
  State<SelectSportScreen> createState() => _SelectSportScreenState();
}

class _SelectSportScreenState extends State<SelectSportScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final sports = Sport.values.where((sport) => sport.label.toLowerCase().contains(_query.trim().toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Select Sport')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: SearchBar(
              hintText: 'Search sports',
              leading: const Icon(Icons.search),
              onChanged: (query) => setState(() => _query = query),
            ),
          ),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 200,
              padding: const EdgeInsets.all(16),
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              children: [
                for (final sport in sports)
                  OptionTile(
                    icon: Icons.sports_tennis,
                    label: sport.label,
                    caption: sport.isAvailable ? null : 'Coming soon',
                    onTap: sport.isAvailable ? () => widget.onSportSelected(context, sport) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
