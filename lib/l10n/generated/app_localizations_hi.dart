// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class AppLocalizationsHi extends AppLocalizations {
  AppLocalizationsHi([String locale = 'hi']) : super(locale);

  @override
  String get commonCancel => 'रद्द करें';

  @override
  String get commonConfirm => 'पुष्टि करें';

  @override
  String get commonOk => 'ठीक है';

  @override
  String get commonRetry => 'फिर से कोशिश करें';

  @override
  String get commonLoading => 'लोड हो रहा है...';

  @override
  String get voiceInputTapToSpeak => 'बोलने के लिए दबाएं';

  @override
  String get voiceInputListening => 'सुन रहा हूँ...';

  @override
  String get voiceInputProcessing => 'प्रोसेस हो रहा है...';

  @override
  String get languageSwitchLabel => 'भाषा';

  @override
  String get languageEnglish => 'अंग्रेज़ी';

  @override
  String get languageHindi => 'हिंदी';

  @override
  String get feedbackSuccessDefault => 'हो गया';

  @override
  String get feedbackErrorDefault => 'कुछ गड़बड़ हो गई';

  @override
  String get emptyStateDefaultMessage => 'अभी यहाँ कुछ नहीं है';

  @override
  String get emptyStateRetryAction => 'फिर कोशिश करें';
}
