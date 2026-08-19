import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/voice_billing_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/reports_screen.dart';
import 'theme.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;
  DateTime? _lastBackPress;

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
    // Refresh the screen we're switching TO (skip VoiceBillingScreen tab 1)
    if (index != 1) {
      _reloaders[index]?.call();
    }
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
            const VoiceBillingScreen(),
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
