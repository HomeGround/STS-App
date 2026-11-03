/// A racket sport the app can score and stream.
///
/// Adding a value here adds it to the Select Sport screen.
enum Sport {
  pickleball('pickleball', 'Pickleball', isAvailable: true),
  tennis('tennis', 'Tennis'),
  badminton('badminton', 'Badminton'),
  tableTennis('table_tennis', 'Table Tennis');

  const Sport(this.key, this.label, {this.isAvailable = false});

  /// Stable identifier, shared with the backend's `game_sports` table.
  final String key;

  /// Name shown to people.
  final String label;

  /// Whether scoring is built for this sport yet. Others are shown as coming soon.
  final bool isAvailable;
}
