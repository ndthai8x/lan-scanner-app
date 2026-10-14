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
      title: 'Tool Đức Thái 0909272412',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF121824),
        cardColor: const Color(0xFF1E2638),
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
    this.mac = 'Không xác định',
    this.vendor = 'éo rõ',
    this.hostName = '',
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
    'D8:32:14': 'Samsung Electronics',
    '70:4F:57': 'Intel Corporate',
  };

  String _lookupVendor(String mac) {
    if (mac.length >= 8) {
      String prefix = mac.substring(0, 8).toUpperCase();
      if (_vendorPrefixes.containsKey(prefix)) {
        return _vendorPrefixes[prefix]!;
      }
    }
    return 'éo rõ';
  }

  @override
  void initState() {
    super.initState();
    _detectLocalSubnet();
  }

  Future<void> _detectLocalSubnet() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            List<String> parts = addr.address.split('.');
            if (parts.length == 4) {
              setState(() {
                _subnetController.text = '${parts[0]}.${parts[1]}.${parts[2]}';
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
              arpMap[ip] = mac.toUpperCase();
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
    int total = 254;
    int completed = 0;
    List<Future> batch = [];

    for (int i = 1; i <= 254; i++) {
      String targetIp = '$subnet.$i';

      batch.add(() async {
        final stopwatch = Stopwatch()..start();
        bool alive = false;
        List<int> detectedPorts = [];

        for (int p in testPorts) {
          try {
            final socket = await Socket.connect(targetIp, p, timeout: const Duration(milliseconds: 320));
            socket.destroy();
            alive = true;
            detectedPorts.add(p);
          } catch (_) {}
        }
        stopwatch.stop();

        if (alive) {
          DeviceItem item = DeviceItem(
            ip: targetIp,
            pingMs: stopwatch.elapsedMilliseconds,
            openPorts: detectedPorts,
          );

          if (detectedPorts.contains(80) || detectedPorts.contains(443)) {
            item.hasWeb = true;
          }
          if (detectedPorts.contains(554) || detectedPorts.contains(8000)) {
            item.deviceType = 'camera';
          } else if (detectedPorts.contains(37777)) {
            item.deviceType = 'nvr';
          } else if (i == 1 || i == 254) {
            item.isGateway = true;
            item.deviceType = 'router';
          }

          setState(() {
            _devices.add(item);
          });
        }

        completed++;
        if (mounted && completed % 5 == 0) {
          setState(() {
            _progress = completed / total;
          });
        }
      }());

      if (batch.length >= 35) {
        await Future.wait(batch);
        batch.clear();
      }
    }

    if (batch.isNotEmpty) {
      await Future.wait(batch);
    }

    Map<String, String> arpTable = await _readArpTable();
    for (var dev in _devices) {
      if (arpTable.containsKey(dev.ip)) {
        dev.mac = arpTable[dev.ip]!;
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
      SnackBar(content: Text('Đã sao chép $label: $text'), duration: const Duration(seconds: 1)),
    );
  }

  void _showPortScanModal(DeviceItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E2638),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => PortScanSheet(ip: item.ip),
    );
  }

  Widget _buildTypeIcon(String type) {
    switch (type) {
      case 'camera':
        return const Icon(Icons.videocam, color: Colors.amber, size: 28);
      case 'nvr':
        return const Icon(Icons.dns, color: Colors.orange, size: 28);
      case 'router':
        return const Icon(Icons.router, color: Colors.blueAccent, size: 28);
      default:
        return const Icon(Icons.devices, color: Colors.cyan, size: 28);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tool mạng - ĐứcThái 0909272412', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF182030),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF182030),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _subnetController,
                    decoration: InputDecoration(
                      labelText: 'Dải mạng (Lớp C)',
                      hintText: '192.168.1',
                      prefixIcon: const Icon(Icons.swap_horiz, color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF253046),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isScanning ? null : _startScan,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4C6EF5),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: _isScanning
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.radar),
                  label: Text(_isScanning ? 'Đang dò...' : 'Quét'),
                ),
              ],
            ),
          ),
          if (_isScanning)
            LinearProgressIndicator(value: _progress, backgroundColor: Colors.transparent, color: const Color(0xFF4C6EF5)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Tìm thấy: ${_devices.length} thiết bị', style: const TextStyle(color: Colors.grey)),
                const Text('Chạm vào để quét chi tiết cổng', style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final d = _devices[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showPortScanModal(d),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          _buildTypeIcon(d.deviceType),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(d.ip, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 16, color: Colors.blueAccent),
                                      onPressed: () => _copy(d.ip, 'IP'),
                                      padding: const EdgeInsets.only(left: 6),
                                      constraints: const BoxConstraints(),
                                    ),
                                    const Spacer(),
                                    if (d.hasWeb)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('WEB', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                    if (d.isGateway)
                                      Container(
                                        margin: const EdgeInsets.only(left: 4),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                                        child: const Text('GATEWAY', style: TextStyle(color: Colors.lightBlueAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text('MAC: ${d.mac}', style: TextStyle(fontSize: 13, color: Colors.grey[400])),
                                    if (d.mac != 'Không xác định' && d.mac != 'Đang lấy...')
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 15, color: Colors.grey),
                                        onPressed: () => _copy(d.mac, 'MAC'),
                                        padding: const EdgeInsets.only(left: 4),
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                                if (d.vendor != 'Không rõ' || d.pingMs >= 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        if (d.pingMs >= 0)
                                          Text('Ping: ${d.pingMs}ms   ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        if (d.vendor != 'éo rõ')
                                          Flexible(
                                            child: Text(
                                              d.vendor,
                                              style: const TextStyle(fontSize: 12, color: Colors.orangeAccent),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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

class PortScanSheet extends StatefulWidget {
  final String ip;
  const PortScanSheet({super.key, required this.ip});

  @override
  State<PortScanSheet> createState() => _PortScanSheetState();
}

class _PortScanSheetState extends State<PortScanSheet> {
  final Map<int, String> _commonPorts = {
    21: 'FTP (Truyền file)',
    22: 'SSH (Quản trị từ xa)',
    23: 'Telnet',
    80: 'HTTP (Trang Web)',
    443: 'HTTPS (Web Bảo mật)',
    445: 'SMB (Chia sẻ file)',
    554: 'RTSP (Luồng Video Camera)',
    8000: 'Hikvision / DVR Port',
    8080: 'HTTP Proxy/Web thay thế',
    37777: 'Dahua DVR/NVR Port',
  };

  final List<int> _openPorts = [];
  bool _scanningPorts = true;

  @override
  void initState() {
    super.initState();
    _scanAllPorts();
  }

  Future<void> _scanAllPorts() async {
    for (var port in _commonPorts.keys) {
      try {
        final s = await Socket.connect(widget.ip, port, timeout: const Duration(milliseconds: 350));
        s.destroy();
        if (mounted) {
          setState(() {
            _openPorts.add(port);
          });
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _scanningPorts = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Quét Cổng: ${widget.ip}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (_scanningPorts)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          Flexible(
            child: _openPorts.isEmpty && !_scanningPorts
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Không tìm thấy cổng mở thông dụng nào.')))
                : ListView(
                    shrinkWrap: true,
                    children: _commonPorts.entries.map((entry) {
                      bool isOpen = _openPorts.contains(entry.key);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isOpen ? Icons.check_circle : Icons.remove_circle_outline,
                          color: isOpen ? Colors.greenAccent : Colors.grey[700],
                        ),
                        title: Text('Port ${entry.key}: ${entry.value}'),
                        trailing: Text(
                          isOpen ? 'MỞ (OPEN)' : 'ĐÓNG',
                          style: TextStyle(color: isOpen ? Colors.greenAccent : Colors.grey, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}
