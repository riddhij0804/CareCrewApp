import 'package:carecrew_app/src/providers.dart';
import 'package:carecrew_app/src/screens/feature_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  int _index = 0;
  bool _syncedForUid = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final repository = ref.watch(repositoryProvider);
    if (!_syncedForUid) {
      _syncedForUid = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await repository.syncMedicationStatuses(user.uid);
      });
    }

    final pages = [
      HomeScreen(uid: user.uid),
      MedicationsScreen(uid: user.uid),
      VitalsScreen(uid: user.uid),
      HistoryScreen(uid: user.uid),
      CareCircleScreen(uid: user.uid),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => setState(() => _index = index),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication_rounded), label: 'Meds'),
              NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite_rounded), label: 'Vitals'),
              NavigationDestination(icon: Icon(Icons.history_outlined), selectedIcon: Icon(Icons.history_rounded), label: 'History'),
              NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups_rounded), label: 'Care Team'),
            ],
          ),
        ),
      ),
    );
  }
}
