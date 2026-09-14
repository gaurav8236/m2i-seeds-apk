import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/models.dart';
import 'screens/home_screen.dart';
import 'screens/voice_billing_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/reports_screen.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.initialTabForTest,
    this.initialBillItemsForTest,
  });

  // Test-only seams for BUG-5a (`.claude/qa/BUGS.md`): let a widget test
  // land directly on the voice-billing tab with a non-empty bill so
  // `VoiceBillingScreen`'s `_autoSaveDraft()` (called from its own
  // `PopScope`, nested inside this widget's `PopScope` below — the exact
  // structure the bug's hypothesis is about) actually takes its real async
  // path instead of early-returning on an empty bill. Never set in
  // production code — both default null, preserving existing behavior
  // exactly (cold start always begins on tab 0, per #56).
  @visibleForTesting
  final int? initialTabForTest;
  @visibleForTesting
  final List<BillItem>? initialBillItemsForTest;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _currentIndex = widget.initialTabForTest ?? 0;
  DateTime? _lastBackPress;

  // BUG-5a instrumentation (`.claude/qa/BUGS.md`,
  // `.claude/records/2026-09-13-bug5-architecture-review.md`). A
  // `flutter_test` widget test that fires two overlapping back-navigation
  // attempts while `VoiceBillingScreen`'s own `PopScope` callback (see that
  // file's `onPopInvokedWithResult`) is still awaiting `_autoSaveDraft()`
  // did NOT reproduce the `_dependents.isEmpty` assertion — it confirmed
  // the overlapping-call sequencing is real (both calls fire) but the
  // crash itself needs real device/engine timing (the working theory is
  // Android's OS-level predictive-back preview animation being started
  // then cancelled) that a synthetic, single-threaded pump loop can't
  // drive. This counter + timestamp is lightweight, no-op-cost-when-unused
  // production logging only: if BUG-5a recurs on a real device, `adb
  // logcat` timestamps on this line and the matching one in
  // `voice_billing_screen.dart`'s `_buildInput()` will show directly
  // whether this shell-level callback and that screen-level callback
  // overlapped, and in what order — finally answering the "what action
  // preceded it" question this bug has been stuck on. Remove once BUG-5a
  // is confirmed one way or another.
  int _backPressSeq = 0;

  // Each screen registers its reload fn here
  final Map<int, VoidCallback> _reloaders = {};
  VoidCallback? _lowStockTrigger;

  @override
  void initState() {
    super.initState();
    // Always start on the Home tab on cold start (#56).
    // Tab state is intentionally NOT persisted across restarts.
  }

  void _registerReload(int tabIndex, VoidCallback fn) {
    _reloaders[tabIndex] = fn;
  }

  void _changeTab(int index) {
    setState(() => _currentIndex = index);
    // Refresh the screen we're switching TO. All 4 tabs go through the same
    // reloader map now — VoiceBillingScreen used to be skipped here (its
    // stock/customer lists went stale until app restart), but it now
    // registers its own gated reloader that no-ops while mid-checkout.
    _reloaders[index]?.call();
  }

  void _onBackPressed() {
    if (_currentIndex != 0) {
      // On any non-home tab — go to Home
      _changeTab(0);
      return;
    }
    // On Home tab — require double-back to exit
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('बाहर निकलने के लिए फिर से दबाएं'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // BUG-5a instrumentation — see field doc above.
        final seq = ++_backPressSeq;
        debugPrint('[BUG-5a] AppShell.onPopInvokedWithResult call #$seq at '
            '${DateTime.now().toIso8601String()}, didPop=$didPop, '
            'currentIndex=$_currentIndex');
        if (!didPop) _onBackPressed();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: [
            HomeScreen(
              onTabChange: _changeTab,
              onRegisterReload: (fn) => _registerReload(0, fn),
              onLowStockTap: () => _lowStockTrigger?.call(),
            ),
            VoiceBillingScreen(
              onRegisterReload: (fn) => _registerReload(1, fn),
              initialBillItemsForTest: widget.initialBillItemsForTest,
            ),
            InventoryScreen(
              onRegisterReload: (fn) => _registerReload(2, fn),
              onRegisterShowLowStock: (fn) => _lowStockTrigger = fn,
            ),
            ReportsScreen(
              onRegisterReload: (fn) => _registerReload(3, fn),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _changeTab,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textMuted,
          backgroundColor: Colors.white,
          type: BottomNavigationBarType.fixed,
          elevation: 12,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.w500, fontSize: 11),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'होम',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.mic_outlined),
              activeIcon: Icon(Icons.mic),
              label: 'बिक्री',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'स्टॉक',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.menu_book_outlined),
              activeIcon: Icon(Icons.menu_book),
              label: 'खाता',
            ),
          ],
        ),
      ),
    );
  }
}
