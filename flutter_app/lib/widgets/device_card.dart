import 'package:flutter/material.dart';
import '../models/device.dart';

class DeviceCard extends StatelessWidget {
  final Device device;

  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final isOnline = device.online;
    final dotColor = isOnline ? Colors.greenAccent : Colors.grey.shade600;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16213E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOnline
              ? Colors.greenAccent.withAlpha(60)
              : Colors.white.withAlpha(15),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withAlpha(20),
                child: Text(
                  device.name.isNotEmpty
                      ? device.name[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: Border.all(
                        color: const Color(0xFF16213E), width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isOnline ? 'Connecté' : 'Hors ligne',
                  style: TextStyle(
                    color: isOnline
                        ? Colors.greenAccent
                        : Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.headset,
            color: isOnline ? Colors.greenAccent : Colors.grey.shade700,
            size: 20,
          ),
        ],
      ),
    );
  }
}
