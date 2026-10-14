import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const LanScannerApp());
}

class LanScannerApp extends StatelessWidget {
  const LanScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LAN Scanner Tool',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF1E1E1E),
        cardColor: const Color(0xFF2D2D2D),
      ),
      home: const ScannerHomePage(),
    );
  }
}

class DeviceItem {
  final String ip;
  String mac;
  String vendor;
  String hostName;
  int pingMs;
  bool hasWeb;
  bool isGateway;
  String deviceType;
  List<int> openPorts;

  DeviceItem({
    required this.ip,
    this.mac = 'Unknown',
    this.vendor = 'Unknown',
    this.hostName = 'Unknown',
    this.pingMs = -1,
    this.hasWeb = false,
    this.isGateway = false,
    this.deviceType = 'generic',
    List<int>? openPorts,
  }) : openPorts = openPorts ?? [];
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  final TextEditingController _subnetController = TextEditingController(text: '192.168.1');
  bool _isScanning = false;
  double _progress = 0.0;
  final List<DeviceItem> _devices = [];

  // Bảng OUI tra cứu nhà sản xuất phần cứng
  final Map<String, String> _vendorPrefixes = {
    'B4:2E:99': 'GIGA-BYTE TECHNOLOGY CO.,LTD',
    '00:12:33': 'JRC TOKKI Co.,Ltd',
    'E0:2E:FE': 'Apple Inc.',
    'E4:60:4D': 'Network Router / AP',
    '44:03:A7': 'Hikvision Digital',
    '50:C7:BF': 'TP-Link Corporation',
    '3C:CD:36': 'Dahua Technology',
    'BC:54:51': 'Xiaomi Communications',
    '00:0C:29': 'VMware, Inc.',
    'B8:27:EB': 'Raspberry Pi Foundation',
    'DC:A6:32': 'Raspberry Pi Trading',
    'D8:32:14': 'Samsung Electronics',
    'F4:F5:D8': 'Google LLC',
    '70:4F:57': 'Intel Corporate',
  };

  String _lookupVendor(String mac) {
    if (mac.length >= 8) {
      String prefix = mac.substring(0, 8).toUpperCase();
      if (_vendorPrefixes.containsKey(prefix)) {
        return _vendorPrefixes[prefix]!;
      }
    }
    return 'Unknown';
  }

  @override
  void initState() {
    super.initState();
    _detectLocalSubnet();
  }

  Future<void> _detectLocalSubnet() async {
    try {
      for (var iface in await NetworkInterface.list()) {
        for (var addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            List<String> p = addr.address.split('.');
            if (p.length == 4) {
              setState(() {
                _subnetController.text = '${p[0]}.${p[1]}.${p[2]}';
              });
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<Map<String, String>> _readArpTable() async {
    Map<String, String> arpMap = {};
    try {
      final file = File('/proc/net/arp');
      if (await file.exists()) {
        final lines = await file.readAsLines();
        for (var line in lines.skip(1)) {
          final parts = line.split(RegExp(r'\s+'));
          if (parts.length >= 4) {
            String ip = parts[0];
            String mac = parts[3];
            if (mac != '00:00:00:00:00:00') {
              arpMap[ip] = mac.toLowerCase();
            }
          }
        }
      }
    } catch (_) {}
    return arpMap;
  }

  Future<void> _startScan() async {
    String subnet = _subnetController.text.trim();
    if (subnet.isEmpty) return;

    setState(() {
      _isScanning = true;
      _progress = 0.0;
      _devices.clear();
    });

    List<int> testPorts = [80, 443, 554, 8000, 37777, 22, 445];
    int completed = 0;
    List<Future> tasks = [];

    for (int i = 1; i <= 254; i++) {
      String ip = '$subnet.$i';

      tasks.add(() async {
        final stopwatch = Stopwatch()..start();
        bool alive = false;
        List<int> openPorts = [];

        for (int p in testPorts) {
          try {
            final s = await Socket.connect(ip, p, timeout: const Duration(milliseconds: 300));
            s.destroy();
            alive = true;
            openPorts.add(p);
          } catch (_) {}
        }
        stopwatch.stop();

        if (alive) {
          DeviceItem dev = DeviceItem(
            ip: ip,
            pingMs: stopwatch.elapsedMilliseconds,
            openPorts: openPorts,
          );

          if (openPorts.contains(80) || openPorts.contains(443)) dev.hasWeb = true;
          if (openPorts.contains(554) || openPorts.contains(8000)) {
            dev.deviceType = 'camera';
          } else if (openPorts.contains(37777)) {
            dev.deviceType = 'nvr';
          } else if (i == 1 || i == 254) {
            dev.isGateway = true;
            dev.deviceType = 'router';
          }

          // Tra cứu tên host qua reverse DNS
          try {
            final res = await InternetAddress(ip).reverse();
            if (res.host != ip) dev.hostName = res.host;
          } catch (_) {}

          setState(() {
            _devices.add(dev);
          });
        }

        completed++;
        if (mounted && completed % 5 == 0) {
          setState(() {
            _progress = completed / 254;
          });
        }
      }());

      if (tasks.length >= 35) {
        await Future.wait(tasks);
        tasks.clear();
      }
    }

    if (tasks.isNotEmpty) await Future.wait(tasks);

    // Gán địa chỉ MAC và hãng sản xuất
    Map<String, String> arp = await _readArpTable();
    for (var dev in _devices) {
      if (arp.containsKey(dev.ip)) {
        dev.mac = arp[dev.ip]!;
        dev.vendor = _lookupVendor(dev.mac);
      }
    }

    setState(() {
      _isScanning = false;
      _progress = 1.0;
    });
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Đã copy $label: $text'), duration: const Duration(seconds: 1)),
    );
  }

  Widget _getLeadingIcon(String type) {
    IconData icon;
    Color color = Colors.orangeAccent;
    switch (type) {
      case 'router':
        icon = Icons.router;
        color = Colors.lightBlueAccent;
        break;
      case 'camera':
      case 'nvr':
        icon = Icons.videocam;
        color = Colors.greenAccent;
        break;
      default:
        icon = Icons.devices;
    }
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, size: 32, color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('List of connected devices (${_devices.length})', style: const TextStyle(fontSize: 16, color: Colors.orangeAccent)),
        backgroundColor: const Color(0xFF262626),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: const Color(0xFF262626),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subnetController,
                    decoration: const InputDecoration(
                      labelText: 'Subnet',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isScanning ? null : _startScan,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: Text(_isScanning ? 'Scanning...' : 'Scan Subnet'),
                ),
              ],
            ),
          ),
          if (_isScanning)
            LinearProgressIndicator(value: _progress, color: Colors.orange, backgroundColor: Colors.transparent),
          Expanded(
            child: ListView.separated(
              itemCount: _devices.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.orangeAccent, height: 1),
              itemBuilder: (context, index) {
                final d = _devices[index];
                return Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _getLeadingIcon(d.deviceType),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () => _copy(d.ip, 'IP'),
                              child: Text(
                                'IP address: ${d.ip}${d.isGateway ? " (router)" : ""}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ),
                            Text('Name: ${d.hostName}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            GestureDetector(
                              onTap: () => _copy(d.mac, 'MAC'),
                              child: Text(
                                'MAC address: ${d.mac}',
                                style: TextStyle(color: d.mac != 'Unknown' ? Colors.white : Colors.grey, fontSize: 13),
                              ),
                            ),
                            Text('Ping: ${d.pingMs >= 0 ? "${d.pingMs} ms" : "Unknown"}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                            Text('Vendor: ${d.vendor}', style: const TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
