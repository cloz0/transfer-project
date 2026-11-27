import 'dart:async';
import 'dart:math' as math;

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
      title: 'UQZELA',
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF55D9F5),
          brightness: Brightness.dark,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B10),
        useMaterial3: true,
        fontFamily: 'Inter',
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF141923),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            side: BorderSide(color: Color(0x1A8C98AA)),
          ),
        ),
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

enum ConnectionVisualState { idle, scanning, connecting, connected, rejected }

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

class _DeviceDiscoveryPageState extends State<DeviceDiscoveryPage>
    with SingleTickerProviderStateMixin {
  List<Device> devices = const [];
  bool isScanning = false;
  String? discoveryError;
  Timer? pairingPollTimer;
  final Set<String> seenPairingRequests = {};
  bool showingPairingDialog = false;
  bool isPairing = false;
  ConnectionVisualState visualState = ConnectionVisualState.idle;
  late final AnimationController connectionAnimationController;

  Device? selectedDevice;

  @override
  void initState() {
    super.initState();
    connectionAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
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
    connectionAnimationController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    if (widget.rustProtocolVersion == null) return;

    setState(() {
      isScanning = true;
      discoveryError = null;
      selectedDevice = null;
      visualState = ConnectionVisualState.scanning;
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
        visualState = ConnectionVisualState.idle;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isScanning = false;
        discoveryError = 'Cihaz keşfi başarısız: $error';
        visualState = ConnectionVisualState.rejected;
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
            'Şifreli bağlantı kurulacak. Karşı cihazdaki güvenlik kodunu '
            'kontrol etmeden isteği kabul etme.',
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
    setState(() {
      isPairing = true;
      visualState = ConnectionVisualState.connecting;
    });
    try {
      final securityCode = await sendPairingRequest(
        address: device.address,
        port: device.port,
        deviceId: widget.localDeviceId,
        deviceName: widget.localDeviceName,
      );
      if (mounted) {
        setState(() => visualState = ConnectionVisualState.connected);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${device.name} cihazıyla eşleşildi. Güvenlik kodu: $securityCode',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('İstek gönderilemedi: $error')));
      if (mounted) {
        setState(() => visualState = ConnectionVisualState.rejected);
      }
    } finally {
      if (mounted) setState(() => isPairing = false);
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
          'Güvenlik kodu: ${request.securityCode}\n\n'
          'Bu kodu karşı cihazdaki kodla karşılaştır. '
          'İsteği yalnızca kod aynıysa ve tanıdığın cihazdan geldiyse kabul et.',
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
    try {
      await respondToPairingRequest(
        requestId: request.requestId,
        accepted: accepted,
      );
      if (mounted) {
        setState(() {
          visualState = accepted
              ? ConnectionVisualState.connected
              : ConnectionVisualState.rejected;
        });
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'İstek kabul edildi; şifreli kanal hazır.'
                : 'Eşleştirme isteği reddedildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Güvenli cevap gönderilemedi: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(titleSpacing: 20, title: const _Wordmark()),
      body: RefreshIndicator(
        color: const Color(0xFF55D9F5),
        backgroundColor: const Color(0xFF1B2330),
        displacement: 32,
        onRefresh: _scan,
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 520),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _AmbientNetworkBackground(
                    key: ValueKey(visualState),
                    animation: connectionAnimationController,
                    state: visualState,
                  ),
                ),
              ),
            ),
            ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    final hero = _ConnectionHero(
                      animation: connectionAnimationController,
                      state: visualState,
                      deviceCount: devices.length,
                    );
                    final intro = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Move files. Move freely.',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFF4F7FC),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Aynı ağdaki cihazları bul, güvenli bir bağlantıyla eşleş.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF8C98AA),
                                height: 1.45,
                              ),
                        ),
                        const SizedBox(height: 18),
                        _StatusPill(
                          ready: widget.rustProtocolVersion != null,
                          label: widget.rustProtocolVersion == null
                              ? 'Bağlantı servisi hazır değil'
                              : 'Yerel bağlantı aktif',
                        ),
                      ],
                    );
                    return wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(child: intro),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 380),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    child: KeyedSubtree(
                                      key: ValueKey(visualState),
                                      child: hero,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              intro,
                              const SizedBox(height: 12),
                              Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 380),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: KeyedSubtree(
                                    key: ValueKey(visualState),
                                    child: hero,
                                  ),
                                ),
                              ),
                            ],
                          );
                  },
                ),
                if (widget.rustStartupError != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: const Color(0x33FF647C),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        widget.rustStartupError!,
                        style: const TextStyle(color: Color(0xFFFFB4C0)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Yakındaki cihazlar',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFF4F7FC),
                      ),
                    ),
                    Text(
                      '${devices.length} cihaz',
                      style: const TextStyle(color: Color(0xFF778397)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isScanning) const _ScanningCard(),
                if (isScanning) const SizedBox(height: 12),
                if (!isScanning && discoveryError != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.error_outline_rounded,
                        color: Color(0xFFFF647C),
                      ),
                      title: Text(discoveryError!),
                      trailing: IconButton(
                        onPressed: _scan,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Tekrar tara',
                      ),
                    ),
                  )
                else if (!isScanning &&
                    discoveryError == null &&
                    devices.isEmpty)
                  const _EmptyDevicesCard()
                else if (!isScanning && discoveryError == null)
                  ...devices.map(
                    (device) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _DeviceCard(
                        device: device,
                        selected: selectedDevice == device,
                        onTap: () => setState(() => selectedDevice = device),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: selectedDevice == null || isScanning || isPairing
                        ? null
                        : _requestPairing,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF55D9F5),
                      foregroundColor: const Color(0xFF071014),
                      disabledBackgroundColor: const Color(0xFF1B2330),
                      disabledForegroundColor: const Color(0xFF778397),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: isPairing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.bolt_rounded),
                    label: Text(
                      isPairing
                          ? 'Güvenli bağlantı kuruluyor...'
                          : 'Güvenli bağlantı başlat',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: isScanning || isPairing ? null : _scan,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF55D9F5),
                      disabledForegroundColor: const Color(0xFF778397),
                      side: const BorderSide(color: Color(0x6655D9F5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: Text(
                      isScanning ? 'Cihazlar aranıyor...' : 'Cihazları yenile',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.all(Radius.circular(9)),
          child: SizedBox(
            width: 38,
            height: 32,
            child: Image(
              image: AssetImage('assets/branding/icon.png'),
              fit: BoxFit.cover,
              alignment: Alignment.center,
            ),
          ),
        ),
        SizedBox(width: 9),
        Text(
          'Uqzela',
          style: TextStyle(
            color: Color(0xFFF4F7FC),
            fontSize: 21,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.ready, required this.label});

  final bool ready;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = ready ? const Color(0xFF45D6A0) : const Color(0xFFFF647C);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.animation,
    required this.state,
    required this.deviceCount,
  });

  final Animation<double> animation;
  final ConnectionVisualState state;
  final int deviceCount;

  bool get isScanning => state == ConnectionVisualState.scanning;

  Color get accent => switch (state) {
    ConnectionVisualState.connected => const Color(0xFF45D6A0),
    ConnectionVisualState.rejected => const Color(0xFFFF647C),
    ConnectionVisualState.connecting => const Color(0xFF8B7CFF),
    _ => const Color(0xFF55D9F5),
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      height: 190,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final pulse = isScanning ? (animation.value * 2 - 1).abs() : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (isScanning)
                Container(
                  width: 108 + pulse * 36,
                  height: 108 + pulse * 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: accent.withValues(alpha: 0.28 - pulse * 0.16),
                      width: 1.5,
                    ),
                  ),
                ),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF141923),
                  border: Border.all(color: accent.withValues(alpha: 0.65)),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.16),
                      blurRadius: 28,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(
                  state == ConnectionVisualState.connected
                      ? Icons.check_rounded
                      : state == ConnectionVisualState.rejected
                      ? Icons.close_rounded
                      : state == ConnectionVisualState.connecting
                      ? Icons.link_rounded
                      : isScanning
                      ? Icons.radar_rounded
                      : deviceCount > 0
                      ? Icons.hub_rounded
                      : Icons.wifi_find_rounded,
                  size: 38,
                  color: accent,
                ),
              ),
              Positioned(
                top: 13,
                right: 22,
                child: _ConnectionDot(
                  color: state == ConnectionVisualState.rejected
                      ? const Color(0xFFFF647C)
                      : const Color(0xFF8B7CFF),
                  offset: isScanning ? animation.value * 10 : 0,
                ),
              ),
              Positioned(
                bottom: 19,
                left: 17,
                child: _ConnectionDot(
                  color: accent,
                  offset: isScanning ? -animation.value * 8 : 0,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AmbientNetworkBackground extends StatelessWidget {
  const _AmbientNetworkBackground({
    super.key,
    required this.animation,
    required this.state,
  });

  final Animation<double> animation;
  final ConnectionVisualState state;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _AmbientNetworkPainter(animation, state),
      child: const SizedBox.expand(),
    );
  }
}

class _AmbientNetworkPainter extends CustomPainter {
  const _AmbientNetworkPainter(this.animation, this.state)
    : super(repaint: animation);

  final Animation<double> animation;
  final ConnectionVisualState state;

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    final primary = switch (state) {
      ConnectionVisualState.connected => const Color(0xFF45D6A0),
      ConnectionVisualState.rejected => const Color(0xFFFF647C),
      ConnectionVisualState.connecting => const Color(0xFF8B7CFF),
      _ => const Color(0xFF55D9F5),
    };
    final secondary = switch (state) {
      ConnectionVisualState.connected => const Color(0xFF55D9F5),
      ConnectionVisualState.rejected => const Color(0xFFFF8A9B),
      ConnectionVisualState.connecting => const Color(0xFF55D9F5),
      _ => const Color(0xFF8B7CFF),
    };
    final isRejected = state == ConnectionVisualState.rejected;
    final glows = [
      (
        Offset(
          size.width * (0.18 + math.sin(phase) * 0.08),
          size.height * 0.18,
        ),
        primary.withValues(alpha: isRejected ? 0.22 : 0.16),
        280.0,
      ),
      (
        Offset(
          size.width * (0.82 + math.cos(phase * 0.8) * 0.08),
          size.height * 0.42,
        ),
        secondary.withValues(alpha: isRejected ? 0.18 : 0.13),
        330.0,
      ),
      (
        Offset(
          size.width * 0.42,
          size.height * (0.80 + math.sin(phase * 0.6) * 0.05),
        ),
        primary.withValues(alpha: 0.12),
        260.0,
      ),
    ];
    for (final (center, color, radius) in glows) {
      final paint = Paint()
        ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final flowColors = [
      primary.withValues(alpha: 0.22),
      secondary.withValues(alpha: 0.18),
    ];
    for (var index = 0; index < 5; index++) {
      final path = Path()
        ..moveTo(-40, size.height * (0.12 + index * 0.19))
        ..cubicTo(
          size.width * 0.28,
          size.height * (0.02 + index * 0.19),
          size.width * 0.62,
          size.height * (0.28 + index * 0.16),
          size.width + 40,
          size.height * (0.12 + index * 0.17),
        );
      canvas.drawPath(
        path,
        Paint()
          ..color = flowColors[index.isEven ? 0 : 1]
          ..style = PaintingStyle.stroke
          ..strokeWidth = index == 2 ? 1.5 : 0.8,
      );

      for (var particle = 0; particle < 3; particle++) {
        final progress = (animation.value + particle * 0.31 + index * 0.09) % 1;
        final x = size.width * progress;
        final y =
            size.height *
            (0.12 +
                index * 0.17 +
                math.sin(progress * math.pi * 2 + index) * 0.07);
        final dot = Paint()
          ..color = flowColors[index.isEven ? 0 : 1].withValues(alpha: 0.62);
        canvas.drawCircle(Offset(x, y), index == 2 ? 2.5 : 1.6, dot);
      }
    }

    final gridDot = Paint();
    for (var index = 0; index < 26; index++) {
      final x = size.width * ((index * 0.173 + 0.04) % 0.94);
      final y = size.height * ((index * 0.097 + 0.08) % 0.86);
      gridDot.color = (index.isEven ? primary : secondary).withValues(
        alpha: 0.08 + (math.sin(phase + index) + 1) * 0.025,
      );
      canvas.drawCircle(Offset(x, y), index % 4 == 0 ? 2 : 1, gridDot);
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientNetworkPainter oldDelegate) =>
      oldDelegate.state != state;
}

class _ConnectionDot extends StatelessWidget {
  const _ConnectionDot({required this.color, required this.offset});

  final Color color;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(offset, -offset * 0.35),
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 10),
          ],
        ),
      ),
    );
  }
}

class _ScanningCard extends StatelessWidget {
  const _ScanningCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Color(0xFF55D9F5),
              ),
            ),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yakındaki cihazlar aranıyor...',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                const Text(
                  'Aşağı çekerek yeniden tarayabilirsin.',
                  style: TextStyle(color: Color(0xFF8C98AA), fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDevicesCard extends StatelessWidget {
  const _EmptyDevicesCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1B2330),
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Icon(
                Icons.devices_other_rounded,
                color: Color(0xFF778397),
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Henüz cihaz yok'),
                  SizedBox(height: 4),
                  Text(
                    'Aynı Wi‑Fi ağında Uqzela açık mı?',
                    style: TextStyle(color: Color(0xFF8C98AA), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.device,
    required this.selected,
    required this.onTap,
  });

  final Device device;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = selected ? const Color(0xFF55D9F5) : const Color(0xFF778397);
    return Card(
      color: selected ? const Color(0xFF182B35) : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0x2255D9F5)
                      : const Color(0xFF1B2330),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  device.platform.toLowerCase().contains('android')
                      ? Icons.phone_android_rounded
                      : device.platform.toLowerCase().contains('linux')
                      ? Icons.computer_rounded
                      : Icons.devices_other_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${device.platform}  ·  ${device.address}:${device.port}',
                      style: const TextStyle(
                        color: Color(0xFF8C98AA),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: selected ? 7 : 2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
