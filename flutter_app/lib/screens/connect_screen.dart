import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/connection_provider.dart';
import 'dashboard_screen.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});

  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  late final TextEditingController _ipCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final savedIp = ref.read(connectionProvider).hostIp;
    _ipCtrl = TextEditingController(text: savedIp);
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;

    setState(() => _loading = true);
    await ref.read(connectionProvider.notifier).connect(ip);

    if (!mounted) return;
    setState(() => _loading = false);

    final conn = ref.read(connectionProvider);
    if (conn.connected) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DashboardScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(conn.error ?? 'Connexion échouée'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.headset, color: Colors.white, size: 46),
              ),
              const SizedBox(height: 20),
              Text(
                'Moto Family',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              Text(
                'Console hôte',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 56),
              TextField(
                controller: _ipCtrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: 'Adresse IP du RPi hôte',
                  hintText: '192.168.50.1',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.wifi_tethering),
                  suffixText: ':8080',
                ),
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  icon: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.link),
                  label: Text(_loading ? 'Connexion…' : 'Se connecter'),
                  onPressed: _loading ? null : _connect,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Assurez-vous d\'être connecté au réseau MotoFamily\n'
                'ou au même Wi-Fi que le RPi hôte.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
