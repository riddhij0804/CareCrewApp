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
  String? _syncedForUid;
  String? _resolvedForAuthUid;
  String? _activeCareUid;
  bool _resolvingCareUid = false;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return const SizedBox.shrink();
    }

    final repository = ref.watch(repositoryProvider);

    if (_resolvedForAuthUid != user.uid && !_resolvingCareUid) {
      _resolvingCareUid = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final resolvedUid = await repository.resolveCareContextUid(user);
        if (!mounted) return;
        setState(() {
          _resolvedForAuthUid = user.uid;
          _activeCareUid = resolvedUid;
          _resolvingCareUid = false;
          _syncedForUid = null;
        });
      });
    }

    final effectiveUid = _activeCareUid ?? user.uid;

    if (_syncedForUid != effectiveUid) {
      _syncedForUid = effectiveUid;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await repository.syncMedicationStatuses(effectiveUid);
        } catch (_) {
          // Keep shell usable even when sync fails due to backend permissions.
        }
      });
    }

    final pages = [
      HomeScreen(uid: effectiveUid),
      MedicationsScreen(uid: effectiveUid),
      VitalsScreen(uid: effectiveUid),
      HistoryScreen(uid: effectiveUid),
      CareCircleScreen(uid: effectiveUid),
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
