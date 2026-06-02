import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/device.dart';

// ── État de connexion ─────────────────────────────────────────────────────────

class ConnectionState {
  final bool connected;
  final String? error;
  final String hostIp;
  final List<Device> devices;

  const ConnectionState({
    this.connected = false,
    this.error,
    this.hostIp = '192.168.50.1',
    this.devices = const [],
  });

  ConnectionState copyWith({
    bool? connected,
    String? error,
    String? hostIp,
    List<Device>? devices,
  }) =>
      ConnectionState(
        connected: connected ?? this.connected,
        error: error,
        hostIp: hostIp ?? this.hostIp,
        devices: devices ?? this.devices,
      );

  List<Device> get pending =>
      devices.where((d) => d.status == DeviceStatus.pending).toList();

  List<Device> get active => devices
      .where((d) => d.status == DeviceStatus.approved && d.online)
      .toList();

  List<Device> get offline => devices
      .where((d) => d.status == DeviceStatus.approved && !d.online)
      .toList();
}

// ── Provider ──────────────────────────────────────────────────────────────────

class ConnectionNotifier extends StateNotifier<ConnectionState> {
  ConnectionNotifier() : super(const ConnectionState()) {
    _loadSavedIp();
  }

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  String get _apiBase => 'http://${state.hostIp}:8080';
  String get _wsUrl => 'ws://${state.hostIp}:8080/ws';

  // ── Persistance IP ────────────────────────────────────────────────────────

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('host_ip') ?? '192.168.50.1';
    state = state.copyWith(hostIp: ip);
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host_ip', ip);
  }

  // ── Connexion WebSocket ───────────────────────────────────────────────────

  Future<void> connect(String ip) async {
    await _disconnect();
    await _saveIp(ip);
    state = state.copyWith(hostIp: ip, connected: false, error: null);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_wsUrl));
      await _channel!.ready;

      _sub = _channel!.stream.listen(
        _onMessage,
        onError: (e) => _onDisconnected('Erreur réseau'),
        onDone: () => _onDisconnected('Connexion perdue'),
      );

      // Ping toutes les 30s pour maintenir la connexion
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _channel?.sink.add('ping');
      });

      state = state.copyWith(connected: true, error: null);
    } catch (e) {
      state = state.copyWith(error: 'Impossible de joindre le RPi : $e');
    }
  }

  void _onMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String;

      switch (type) {
        case 'initial_state':
          final list = (msg['devices'] as List)
              .map((e) => Device.fromMap(e as Map<String, dynamic>))
              .toList();
          state = state.copyWith(devices: list);

        case 'pair_request':
          final d = Device.fromMap(msg['device'] as Map<String, dynamic>);
          _upsertDevice(d);

        case 'device_approved':
          _updateDeviceStatus(msg['device_id'] as String, DeviceStatus.approved);

        case 'device_rejected':
          _updateDeviceStatus(msg['device_id'] as String, DeviceStatus.rejected);

        case 'device_connected':
          _setOnline(msg['device_id'] as String, true);

        case 'device_disconnected':
          _setOnline(msg['device_id'] as String, false);
      }
    } catch (_) {}
  }

  void _onDisconnected(String reason) {
    state = state.copyWith(connected: false, error: reason);
    _pingTimer?.cancel();
    // Reconnexion automatique après 5s
    _reconnectTimer = Timer(
      const Duration(seconds: 5),
      () => connect(state.hostIp),
    );
  }

  Future<void> _disconnect() async {
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _channel = null;
  }

  // ── Actions REST ──────────────────────────────────────────────────────────

  Future<void> approve(String deviceId) async {
    try {
      await http.post(Uri.parse('$_apiBase/approve/$deviceId'));
      _updateDeviceStatus(deviceId, DeviceStatus.approved);
    } catch (e) {
      state = state.copyWith(error: 'Erreur approbation : $e');
    }
  }

  Future<void> reject(String deviceId) async {
    try {
      await http.post(Uri.parse('$_apiBase/reject/$deviceId'));
      _updateDeviceStatus(deviceId, DeviceStatus.rejected);
    } catch (e) {
      state = state.copyWith(error: 'Erreur rejet : $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _upsertDevice(Device device) {
    final existing = state.devices.any((d) => d.id == device.id);
    if (existing) {
      state = state.copyWith(
        devices: state.devices
            .map((d) => d.id == device.id ? device : d)
            .toList(),
      );
    } else {
      state = state.copyWith(devices: [...state.devices, device]);
    }
  }

  void _updateDeviceStatus(String id, DeviceStatus status) {
    state = state.copyWith(
      devices: state.devices
          .map((d) => d.id == id ? d.copyWith(status: status) : d)
          .toList(),
    );
  }

  void _setOnline(String id, bool online) {
    state = state.copyWith(
      devices: state.devices
          .map((d) => d.id == id ? d.copyWith(online: online) : d)
          .toList(),
    );
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }
}

final connectionProvider =
    StateNotifierProvider<ConnectionNotifier, ConnectionState>(
  (ref) => ConnectionNotifier(),
);
