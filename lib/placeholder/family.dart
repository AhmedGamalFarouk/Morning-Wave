/// Illustrative family used until the screens read from Supabase.
/// Nothing here is real user data.
abstract final class PlaceholderFamily {
  /// What the child calls the parent; the app greets the parent the same way.
  static const parentName = 'Mom';
  static const childName = 'Sara';
  static const childRelation = 'daughter';

  static const note = 'Morning Mom! Don’t forget your coffee.';

  static const usualMorningBy = '9:00 AM';
  static const awayUntil = 'Friday';

  static final checkedInAt = DateTime(2026, 9, 28, 8, 14);
}

enum ChildView { heard, waiting, away }
