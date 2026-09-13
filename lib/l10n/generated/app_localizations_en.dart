// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonOk => 'OK';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get voiceInputTapToSpeak => 'Tap to speak';

  @override
  String get voiceInputListening => 'Listening...';

  @override
  String get voiceInputProcessing => 'Working on it...';

  @override
  String get languageSwitchLabel => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageHindi => 'Hindi';

  @override
  String get feedbackSuccessDefault => 'Done';

  @override
  String get feedbackErrorDefault => 'Something went wrong';

  @override
  String get emptyStateDefaultMessage => 'Nothing here yet';

  @override
  String get emptyStateRetryAction => 'Try again';
}
