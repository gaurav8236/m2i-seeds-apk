/// Bilingual unit and category constants for SmartDukan.
///
/// Each [UnitCategoryItem] stores a canonical Hindi value (written to the DB),
/// an English display label (shown alongside Hindi in dropdowns), and a list of
/// recognised English aliases used to normalise free-text input.
///
/// Usage:
///   - Dropdowns display [dropdownLabel] ("किलो / KG") but use [canonical] as value.
///   - [normalizeUnit] / [normalizeCategory] map any alias → canonical before DB write.
///   - The DB migration SQL (SPRINT_8.md) back-fills existing rows.
// ignore_for_file: constant_identifier_names
class UnitCategoryItem {
  final String canonical; // stored in DB — always Hindi
  final String displayEn; // English label shown next to Hindi in dropdown
  final List<String> aliases; // recognised English inputs (lower-case)

  const UnitCategoryItem({
    required this.canonical,
    required this.displayEn,
    this.aliases = const [],
  });

  /// Label rendered inside the DropdownButton: "किलो / KG"
  String get dropdownLabel => '$canonical / $displayEn';
}

// ── Units ──────────────────────────────────────────────────────────────────────

const kUnits = [
  UnitCategoryItem(canonical: 'किलो',   displayEn: 'KG',     aliases: ['kg', 'kilo', 'kilogram', 'kgs', 'k.g.']),
  UnitCategoryItem(canonical: 'ग्राम',   displayEn: 'Gram',   aliases: ['gram', 'g', 'gm', 'grams']),
  UnitCategoryItem(canonical: 'लीटर',   displayEn: 'Litre',  aliases: ['litre', 'liter', 'l', 'ltr', 'liters', 'litres']),
  UnitCategoryItem(canonical: 'मिली',   displayEn: 'ML',     aliases: ['ml', 'millilitre', 'milliliter', 'milli', 'mls']),
  UnitCategoryItem(canonical: 'पैकेट',  displayEn: 'Packet', aliases: ['packet', 'pack', 'pkt', 'packets', 'packs']),
  UnitCategoryItem(canonical: 'पीस',    displayEn: 'Piece',  aliases: ['piece', 'pc', 'pcs', 'nos', 'no', 'nos.', 'नग']),
  UnitCategoryItem(canonical: 'बोतल',   displayEn: 'Bottle', aliases: ['bottle', 'btl', 'bottles', 'btls']),
  UnitCategoryItem(canonical: 'थैला',   displayEn: 'Bag',    aliases: ['bag', 'sack', 'bora', 'bags']),
  UnitCategoryItem(canonical: 'दर्जन',  displayEn: 'Dozen',  aliases: ['dozen', 'dz', 'doz']),
  UnitCategoryItem(canonical: 'अन्य',   displayEn: 'Other',  aliases: ['other', 'misc']),
];

// ── Categories ─────────────────────────────────────────────────────────────────

const kCategories = [
  UnitCategoryItem(canonical: 'अनाज',           displayEn: 'Grains',         aliases: ['grain', 'grains', 'cereal', 'cereals']),
  UnitCategoryItem(canonical: 'दाल',             displayEn: 'Pulses',         aliases: ['pulse', 'pulses', 'dal', 'daal', 'lentil', 'lentils']),
  UnitCategoryItem(canonical: 'तेल/घी',         displayEn: 'Oil & Ghee',     aliases: ['oil', 'ghee', 'oils', 'fat', 'fats', 'oil/ghee']),
  UnitCategoryItem(canonical: 'मसाले',           displayEn: 'Spices',         aliases: ['spice', 'spices', 'masala', 'masalas']),
  UnitCategoryItem(canonical: 'आटा/सूजी',       displayEn: 'Flour',          aliases: ['flour', 'atta', 'maida', 'suji', 'sooji', 'atta/maida']),
  UnitCategoryItem(canonical: 'चीनी/नमक',       displayEn: 'Sugar & Salt',   aliases: ['sugar', 'salt', 'shakkar', 'cheeni', 'namak', 'sugar/salt']),
  UnitCategoryItem(canonical: 'बिस्कुट/नाश्ता', displayEn: 'Snacks',         aliases: ['snack', 'snacks', 'biscuit', 'namkeen', 'chips', 'biscuits']),
  UnitCategoryItem(canonical: 'साबुन/सफाई',     displayEn: 'Soap & Cleaning',aliases: ['soap', 'detergent', 'cleaning', 'sabun', 'detergents']),
  UnitCategoryItem(canonical: 'पेय पदार्थ',     displayEn: 'Beverages',      aliases: ['drink', 'drinks', 'beverage', 'beverages', 'juice', 'tea', 'chai']),
  UnitCategoryItem(canonical: 'अन्य',            displayEn: 'Other',          aliases: ['other', 'misc']),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Maps any alias or canonical value → canonical Hindi unit string.
/// Returns null when [input] is unrecognised — caller should keep the raw value.
String? normalizeUnit(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return null;
  for (final item in kUnits) {
    if (item.canonical.toLowerCase() == lower) return item.canonical;
    if (item.aliases.contains(lower)) return item.canonical;
  }
  return null;
}

/// Maps any alias or canonical value → canonical Hindi category string.
/// Returns null when [input] is unrecognised — caller should keep the raw value.
String? normalizeCategory(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return null;
  for (final item in kCategories) {
    if (item.canonical.toLowerCase() == lower) return item.canonical;
    if (item.aliases.contains(lower)) return item.canonical;
  }
  return null;
}

/// Finds the [UnitCategoryItem] whose [canonical] matches [value].
/// Returns null for custom (अन्य) values not in the standard list.
UnitCategoryItem? findUnitItem(String value) {
  try {
    return kUnits.firstWhere((u) => u.canonical == value);
  } catch (_) {
    return null;
  }
}

/// Finds the [UnitCategoryItem] whose [canonical] matches [value].
UnitCategoryItem? findCategoryItem(String value) {
  try {
    return kCategories.firstWhere((c) => c.canonical == value);
  } catch (_) {
    return null;
  }
}
