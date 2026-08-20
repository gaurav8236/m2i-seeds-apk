import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../supabase_config.dart';
import 'auth_service.dart';

class VoiceService {
  static final _recorder = AudioRecorder();

  static Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  static Future<void> startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_recording.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  static Future<String?> stopRecording() async {
    return await _recorder.stop();
  }

  static Future<bool> isRecording() async {
    return await _recorder.isRecording();
  }

  static Future<List<Map<String, dynamic>>> processVoice({
    required String audioPath,
    String? webSpeechText,
  }) async {
    final userId = AuthService.userId;
    if (userId == null) throw Exception('Not authenticated');

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('${SupabaseConfig.railwayBaseUrl}/voice-search/'),
    );
    request.headers['X-Api-Key'] = SupabaseConfig.apiSecret;

    request.files.add(await http.MultipartFile.fromPath('file', audioPath,
        filename: 'recording.m4a'));
    request.fields['user_id'] = userId;
    request.fields['preview_only'] = 'true';
    request.fields['language'] = 'hi';
    if (webSpeechText != null && webSpeechText.isNotEmpty) {
      request.fields['web_speech_text'] = webSpeechText;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('API error: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['results'] ?? []);
  }

  static void dispose() {
    _recorder.dispose();
  }
}
