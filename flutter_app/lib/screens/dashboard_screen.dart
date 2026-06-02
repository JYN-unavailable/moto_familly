import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_provider.dart';
import '../widgets/device_card.dart';
import '../widgets/pair_request_card.dart';
import 'connect_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conn = ref.watch(connectionProvider);
    final notifier = ref.read(connectionProvider.notifier);

    // Déconnexion imprévue → retour écran connexion
    if (!conn.connected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(conn.error ?? 'Connexion perdue — reconnexion…'),
              backgroundColor: Colors.orange.shade800,
            ),
          );
        }
      });
    }

    final totalOnline = conn.active.length + 1; // +1 pour l'hôte

    return Scaffold(
      backgroundColor: const Color(0xFF0F0E17),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0E17),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Icon(Icons.headset, size: 20),
            const SizedBox(width: 8),
            const Text('Moto Family'),
            const SizedBox(width: 10),
            // Indicateur connexion RPi
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: conn.connected
                    ? Colors.green.shade800
                    : Colors.red.shade800,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: conn.connected ? Colors.greenAccent : Colors.red,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    conn.connected ? 'RPi connecté' : 'RPi hors ligne',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white54),
            tooltip: 'Déconnecter',
            onPressed: () {
              notifier.dispose();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const ConnectScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => notifier.connect(conn.hostIp),
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            // ── Compteur global ───────────────────────────────────────────
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _StatChip(
                    icon: Icons.people,
                    label: '$totalOnline / 6',
                    sublabel: 'en session',
                    color: Colors.blue.shade700,
                  ),
                  const SizedBox(width: 10),
                  _StatChip(
                    icon: Icons.pending_actions,
                    label: '${conn.pending.length}',
                    sublabel: 'en attente',
                    color: conn.pending.isEmpty
                        ? Colors.grey.shade800
                        : Colors.orange.shade800,
                  ),
                ],
              ),
            ),

            // ── Demandes d'appairage ──────────────────────────────────────
            if (conn.pending.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.notifications_active,
                title: 'Demandes d\'appairage',
                color: Colors.orange.shade400,
              ),
              ...conn.pending.map(
                (d) => PairRequestCard(
                  device: d,
                  onApprove: () => notifier.approve(d.id),
                  onReject: () => notifier.reject(d.id),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // ── Participants actifs ───────────────────────────────────────
            _SectionHeader(
              icon: Icons.sensors,
              title: 'En session (${conn.active.length})',
              color: Colors.greenAccent,
            ),
            if (conn.active.isEmpty)
              _EmptyHint('Aucun satellite connecté pour l\'instant')
            else
              ...conn.active.map((d) => DeviceCard(device: d)),

            const SizedBox(height: 16),

            // ── Appareils connus hors ligne ───────────────────────────────
            if (conn.offline.isNotEmpty) ...[
              _SectionHeader(
                icon: Icons.history,
                title: 'Appareils connus (${conn.offline.length})',
                color: Colors.grey,
              ),
              ...conn.offline.map((d) => DeviceCard(device: d)),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Widgets internes ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String sublabel;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: color.withAlpha(40),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  sublabel,
                  style:
                      TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
      ),
    );
  }
}
