import 'package:flutter/material.dart';
import '../models/device.dart';

class PairRequestCard extends StatelessWidget {
  final Device device;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const PairRequestCard({
    super.key,
    required this.device,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.orange.shade900.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade700, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Icône animée
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.orange.shade800,
              ),
              child: const Icon(Icons.motorcycle, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 14),
            // Nom + info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Demande à rejoindre la session',
                    style: TextStyle(
                        color: Colors.orange.shade300, fontSize: 12),
                  ),
                ],
              ),
            ),
            // Boutons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ActionButton(
                  icon: Icons.close,
                  color: Colors.red.shade600,
                  tooltip: 'Refuser',
                  onTap: onReject,
                ),
                const SizedBox(width: 8),
                _ActionButton(
                  icon: Icons.check,
                  color: Colors.green.shade600,
                  tooltip: 'Approuver',
                  onTap: onApprove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
