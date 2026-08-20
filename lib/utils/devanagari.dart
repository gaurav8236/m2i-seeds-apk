/// The PDF renderer used for bill receipts (`package:pdf`) has no Devanagari
/// shaping engine — it draws each codepoint in raw Unicode order. Devanagari's
/// short-i vowel sign (ि, U+093F) is a "pre-base" mark that visually attaches
/// to the LEFT of its base consonant even though it's encoded immediately
/// AFTER it, so words like "दिनांक" or "बिल" render with the mark shifted
/// onto the next letter (e.g. "बिल" → "बलि"). Flutter's own text widgets use
/// a proper shaper and are unaffected — this fix-up is only needed for text
/// handed to the `pdf` package.
String fixDevanagariMatra(String text) =>
    text.replaceAllMapped(RegExp('(.)ि'), (m) => 'ि${m.group(1)}');
