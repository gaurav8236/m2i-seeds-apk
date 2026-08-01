import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/models.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../utils/analytics.dart';

class RecordingScreen extends StatefulWidget {
  final List<StockItem> stockList;
  const RecordingScreen({super.key, required this.stockList});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with TickerProviderStateMixin {
  bool _isRecording = false;
  bool _isProcessing = false;
  String _transcript = '';

  late List<AnimationController> _ringControllers;
  late AnimationController _breatheController;

  // Simulated transcript words that cycle while recording
  final _transcriptHints = [
    'बोलते रहें...',
    'सुन रहा है...',
    'आगे बोलें...',
  ];
  int _hintIdx = 0;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _ringControllers = List.generate(3, (i) {
      final ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1800));
      Future.delayed(Duration(milliseconds: i * 600), () {
        if (mounted) ctrl.repeat();
      });
      return ctrl;
    });
    _breatheController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);

    _startRecording();
  }

  @override
  void dispose() {
    for (final c in _ringControllers) c.dispose();
    _breatheController.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        Analytics.micPermissionDenied();
        if (mounted) Navigator.pop(context);
        return;
      }
    }
    try {
      await VoiceService.startRecording();
      Analytics.recordingStarted();
      setState(() {
        _isRecording = true;
        _transcript = _transcriptHints[0];
      });
      _hintTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (!mounted) return;
        _hintIdx = (_hintIdx + 1) % _transcriptHints.length;
        setState(() => _transcript = _transcriptHints[_hintIdx]);
      });
    } catch (e) {
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _stopAndProcess() async {
    _hintTimer?.cancel();
    Analytics.recordingStopped();
    setState(() {
      _isRecording = false;
      _isProcessing = true;
      _transcript = 'AI आइटम पहचान रहा है...';
    });

    final path = await VoiceService.stopRecording();
    if (path == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      final results = await VoiceService.processVoice(audioPath: path);
      final items = _processResults(results);
      final matched = items.length;
      if (matched == 0) {
        Analytics.voiceApiNoItems(reason: 'no_match');
      } else {
        Analytics.voiceApiSuccess(
          itemsFound: results.length,
          itemsMatched: matched,
        );
      }
      if (mounted) Navigator.pop(context, items);
    } catch (e) {
      Analytics.voiceApiError(error: e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('त्रुटि: $e')));
        Navigator.pop(context);
      }
    }
  }

  List<BillItem> _processResults(List<Map<String, dynamic>> results) {
    final processed = <BillItem>[];
    for (final r in results) {
      final hasError = r['error'] != null && r['error'] != false;
      if (!hasError) {
        processed.add(BillItem.fromMap(r));
      } else if (r['error'] is String) {
        final errorStr = r['error'] as String;
        final match =
            RegExp(r'Closest:\s*(.+?)\s*\(\d+%\)').firstMatch(errorStr);
        if (match != null) {
          final closestName = match.group(1)!.trim();
          final stockItem = widget.stockList.firstWhere(
            (s) => s.itemName == closestName,
            orElse: () => StockItem(
                id: '', currentStock: 0, sellingPrice: 0, lowStockLimit: 0,
                aliases: [], itemName: '', category: '', unit: ''),
          );
          if (stockItem.id.isNotEmpty) {
            final qty = (r['quantity_billed'] as num?)?.toDouble() ?? 1;
            final price = stockItem.sellingPrice;
            processed.add(BillItem(
              itemName: closestName,
              quantity: qty,
              pricePerUnit: price,
              itemTotal: qty * price,
              stockRemaining: stockItem.currentStock - qty,
              stockId: stockItem.id,
              currentStock: stockItem.currentStock,
              unit: stockItem.unit,
            ));
          }
        }
      }
    }
    return processed;
  }

  Widget _pulseRing(AnimationController ctrl) {
    return AnimatedBuilder(
      animation: ctrl,
      builder: (_, __) {
        final t = ctrl.value;
        return Transform.scale(
          scale: 0.9 + t * 1.35,
          child: Container(
            width: 88, height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.danger.withValues(alpha: (1 - t) * 0.4),
                width: 2.5,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          // Back button
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: () async {
                  await VoiceService.stopRecording();
                  if (mounted) Navigator.pop(context);
                },
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ),

          const Spacer(),

          // Pulsing mic
          SizedBox(
            width: 220, height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_isRecording)
                  ..._ringControllers.map((c) => _pulseRing(c)),
                AnimatedBuilder(
                  animation: _breatheController,
                  builder: (_, child) => Transform.scale(
                    scale: _isRecording
                        ? 1.0 + _breatheController.value * 0.07
                        : 1.0,
                    child: child,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 96, height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _isRecording
                          ? const LinearGradient(
                              colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRecording
                                  ? AppColors.danger
                                  : AppColors.primary)
                              .withValues(alpha: _isRecording ? 0.5 : 0.3),
                          blurRadius: 32,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: _isProcessing
                        ? const Padding(
                            padding: EdgeInsets.all(28),
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                          )
                        : const Icon(Icons.mic, color: Colors.white, size: 40),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Transcript / status
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              _transcript,
              key: ValueKey(_transcript),
              style: TextStyle(
                fontSize: _isProcessing ? 14 : 18,
                fontWeight: FontWeight.w600,
                color: _isProcessing
                    ? AppColors.textSecondary
                    : AppColors.danger,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'हिंदी या अंग्रेज़ी में बोलें',
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),

          const Spacer(),

          // Stop button
          if (_isRecording && !_isProcessing)
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _stopAndProcess,
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: AppColors.danger),
                  label: const Text('रोकें और पहचानें',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.danger)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            )
          else
            const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
