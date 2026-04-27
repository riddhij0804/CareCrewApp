import 'package:carecrew_app/src/models.dart';
import 'package:carecrew_app/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PendingInvitesScreen extends ConsumerStatefulWidget {
  const PendingInvitesScreen({
    super.key,
    required this.uid,
    required this.invites,
  });

  final String uid;
  final List<CareInvite> invites;

  @override
  ConsumerState<PendingInvitesScreen> createState() => _PendingInvitesScreenState();
}

class _PendingInvitesScreenState extends ConsumerState<PendingInvitesScreen> {
  final Set<String> _processingIds = <String>{};

  Future<void> _accept(CareInvite invite) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _processingIds.add(invite.id));
    try {
      await ref.read(repositoryProvider).acceptInvite(user: user, invite: invite);
      ref.invalidate(pendingInvitesProvider(widget.uid));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined ${invite.patientName ?? "care circle"}.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not accept invite: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(invite.id));
      }
    }
  }

  Future<void> _reject(CareInvite invite) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    setState(() => _processingIds.add(invite.id));
    try {
      await ref.read(repositoryProvider).rejectInvite(user: user, invite: invite);
      ref.invalidate(pendingInvitesProvider(widget.uid));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invite rejected.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reject invite: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(invite.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = widget.invites;

    return Scaffold(
      appBar: AppBar(title: const Text('Pending Invites')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        children: [
          Text(
            'You have ${invites.length} pending care circle invite${invites.length == 1 ? '' : 's'}.',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...invites.map((invite) {
            final busy = _processingIds.contains(invite.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.patientName?.trim().isNotEmpty == true
                          ? invite.patientName!
                          : 'Patient ${invite.patientId}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text('Assigned role: ${invite.roleValue.label}'),
                    Text('Invited by: ${invite.invitedByName?.trim().isNotEmpty == true ? invite.invitedByName : invite.invitedBy}'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: busy ? null : () => _accept(invite),
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Accept'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: busy ? null : () => _reject(invite),
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('Reject'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
