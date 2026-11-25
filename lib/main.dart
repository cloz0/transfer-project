import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'bridge/api.dart';
import 'bridge/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? rustProtocolVersion;
  String? rustStartupError;
  final platformName = _platformName();
  final localDeviceId =
      'transfer-${DateTime.now().millisecondsSinceEpoch % 100000}';
  final localDeviceName = 'Transfer-$platformName';
  try {
    await RustLib.init();
    rustProtocolVersion = await protocolVersion();
    await startLocalService(
      instanceName: localDeviceName,
      deviceId: localDeviceId,
      platform: platformName,
    );
  } catch (error) {
    rustStartupError = error.toString();
    debugPrint('Rust çekirdeği başlatılamadı: $error');
  }

  runApp(
    TransferApp(
      rustProtocolVersion: rustProtocolVersion,
      rustStartupError: rustStartupError,
      localDeviceId: localDeviceId,
      localDeviceName: localDeviceName,
    ),
  );
}

String _platformName() {
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

class TransferApp extends StatelessWidget {
  const TransferApp({
    super.key,
    this.rustProtocolVersion,
    this.rustStartupError,
    this.localDeviceId = 'test-device',
    this.localDeviceName = 'Transfer-Test',
  });

  final String? rustProtocolVersion;
  final String? rustStartupError;
  final String localDeviceId;
  final String localDeviceName;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transfer',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F141C),
        useMaterial3: true,
      ),
      home: TransferHomePage(
        rustProtocolVersion: rustProtocolVersion,
        rustStartupError: rustStartupError,
        localDeviceId: localDeviceId,
        localDeviceName: localDeviceName,
      ),
    );
  }
}

class TransferHomePage extends StatelessWidget {
  const TransferHomePage({
    super.key,
    this.rustProtocolVersion,
    this.rustStartupError,
    required this.localDeviceId,
    required this.localDeviceName,
  });

  final String? rustProtocolVersion;
  final String? rustStartupError;
  final String localDeviceId;
  final String localDeviceName;

  @override
  Widget build(BuildContext context) {
    return DeviceDiscoveryPage(
      rustProtocolVersion: rustProtocolVersion,
      rustStartupError: rustStartupError,
      localDeviceId: localDeviceId,
      localDeviceName: localDeviceName,
    );
  }
}

class Device {
  const Device({
    required this.name,
    required this.platform,
    required this.address,
    required this.port,
    required this.deviceId,
    required this.isPaired,
  });

  final String name;
  final String platform;
  final String address;
  final int port;
  final String deviceId;
  final bool isPaired;

  factory Device.fromDiscovery(DiscoveredDevice device) {
    return Device(
      name: device.name,
      platform: device.platform,
      address: device.address,
      port: device.port,
      deviceId: device.deviceId,
      isPaired: false,
    );
  }
}

class DeviceDiscoveryPage extends StatefulWidget {
  const DeviceDiscoveryPage({
    super.key,
    this.rustProtocolVersion,
    this.rustStartupError,
    required this.localDeviceId,
    required this.localDeviceName,
  });

  final String? rustProtocolVersion;
  final String? rustStartupError;
  final String localDeviceId;
  final String localDeviceName;

  @override
  State<DeviceDiscoveryPage> createState() => _DeviceDiscoveryPageState();
}

class _DeviceDiscoveryPageState extends State<DeviceDiscoveryPage> {
  List<Device> devices = const [];
  bool isScanning = false;
  String? discoveryError;
  Timer? pairingPollTimer;
  final Set<String> seenPairingRequests = {};
  bool showingPairingDialog = false;

  Device? selectedDevice;

  @override
  void initState() {
    super.initState();
    if (widget.rustProtocolVersion != null) {
      _scan();
      pairingPollTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _pollPairingRequests(),
      );
    }
  }

  @override
  void dispose() {
    pairingPollTimer?.cancel();
    super.dispose();
  }

  Future<void> _scan() async {
    if (widget.rustProtocolVersion == null) return;

    setState(() {
      isScanning = true;
      discoveryError = null;
      selectedDevice = null;
    });

    try {
      final discovered = await discoverDevices(timeoutMs: 4000);
      if (!mounted) return;
      setState(() {
        devices = discovered
            .where((device) => device.deviceId != widget.localDeviceId)
            .map(Device.fromDiscovery)
            .toList();
        isScanning = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isScanning = false;
        discoveryError = 'Cihaz keşfi başarısız: $error';
      });
    }
  }

  Future<void> _requestPairing() async {
    final device = selectedDevice;
    if (device == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eşleştirme isteği'),
          content: Text(
            '${device.name} cihazıyla eşleştirme başlatılacak.\n\n'
            'Bu sürümde yalnızca şifrelenmemiş bir eşleştirme isteği gönderilir. '
            'Güvenlik kodu doğrulaması ve dosya aktarımı henüz desteklenmiyor.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('İstek gönder'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    try {
      await sendPairingRequest(
        address: device.address,
        port: device.port,
        deviceId: widget.localDeviceId,
        deviceName: widget.localDeviceName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.name} cihazına istek gönderildi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İstek gönderilemedi: $error')),
      );
    }
  }

  Future<void> _pollPairingRequests() async {
    if (!mounted || widget.rustProtocolVersion == null) return;
    try {
      final requests = await pollPairingRequests();
      for (final request in requests) {
        if (seenPairingRequests.contains(request.requestId)) continue;
        seenPairingRequests.add(request.requestId);
        if (showingPairingDialog) continue;
        showingPairingDialog = true;
        await _showIncomingPairingRequest(request);
        showingPairingDialog = false;
      }
    } catch (error) {
      debugPrint('Pairing isteği okunamadı: $error');
    }
  }

  Future<void> _showIncomingPairingRequest(
    IncomingPairingRequest request,
  ) async {
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gelen eşleştirme isteği'),
        content: Text(
          '${request.deviceName} (${request.address}) cihazı eşleşmek istiyor.\n\n'
          'İsteği yalnızca tanıdığın cihazlardan kabul et.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Reddet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kabul et'),
          ),
        ],
      ),
    );
    if (!mounted || accepted == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          accepted
              ? 'İstek kabul edildi; güvenli kanal sonraki aşamada kurulacak.'
              : 'Eşleştirme isteği reddedildi.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer'),
        actions: [
          IconButton(
            onPressed: isScanning ? null : _scan,
            tooltip: 'Cihazları yenile',
            icon: isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _scan,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Yakındaki cihazlar',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Aynı yerel ağdaki cihazlar burada görünecek. '
              'Yalnızca aynı ağdaki Transfer cihazları listelenir.',
            ),
            const SizedBox(height: 12),
            Chip(
              avatar: Icon(
                widget.rustProtocolVersion == null
                    ? Icons.error_outline
                    : Icons.check,
              ),
              label: Text(
                widget.rustProtocolVersion == null
                    ? 'Rust çekirdeği hazır değil'
                    : 'Rust çekirdeği hazır · protokol v${widget.rustProtocolVersion}',
              ),
            ),
            if (widget.rustStartupError != null) ...[
              const SizedBox(height: 8),
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    widget.rustStartupError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            if (isScanning)
              const Card(
                child: ListTile(
                  leading: CircularProgressIndicator(),
                  title: Text('Yerel ağ taranıyor...'),
                ),
              )
            else if (discoveryError != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: Text(discoveryError!),
                  trailing: IconButton(
                    onPressed: _scan,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Tekrar tara',
                  ),
                ),
              )
            else if (devices.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.wifi_find),
                  title: Text('Cihaz bulunamadı'),
                  subtitle: Text('Aynı Wi-Fi ağında Transfer açık mı?'),
                ),
              )
            else
              RadioGroup<Device>(
                groupValue: selectedDevice,
                onChanged: (value) => setState(() => selectedDevice = value),
                child: Column(
                  children: [
                    ...devices.map(
                      (device) => Card(
                        child: RadioListTile<Device>(
                          value: device,
                          title: Text(device.name),
                          subtitle: Text(
                            '${device.platform} · ${device.address}:${device.port}',
                          ),
                          secondary: Icon(
                            device.isPaired
                                ? Icons.verified_user
                                : Icons.devices,
                            color: device.isPaired
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: selectedDevice == null || isScanning
                  ? null
                  : _requestPairing,
              icon: const Icon(Icons.link),
              label: const Text('Eşleştirme isteği gönder'),
            ),
          ],
        ),
      ),
    );
  }
}
