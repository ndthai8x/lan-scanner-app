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
      title: 'Camera,Vi tính Đức Thái 0909272412',
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
  int pingMs;
  bool hasWeb;
  bool isGateway;
  String deviceType; // 'camera', 'router', 'pc', 'generic'
  List<int> openPorts;

  DeviceItem({
    required this.ip,
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

  // Danh mục các port dùng để phát hiện nhanh thiết bị trên mạng LAN
  final List<int> _discoveryPorts = [
    80, 81, 88, 443, 8080, 8888, // Các cổng Web quản trị
    554, 8000, 34567, 37777,      // Cổng Camera: RTSP, Hikvision, Xiongmai/CMS, Dahua
    22, 23, 445                   // SSH, Telnet, SMB
  ];

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

  Future<void> _startScan() async {
    String subnet = _subnetController.text.trim();
    if (subnet.isEmpty) return;

    setState(() {
      _isScanning = true;
      _progress = 0.0;
      _devices.clear();
    });

    int total = 254;
    int completed = 0;
    List<Future> batch = [];

    for (int i = 1; i <= 254; i++) {
      String targetIp = '$subnet.$i';

      batch.add(() async {
        final stopwatch = Stopwatch()..start();
        bool alive = false;
        List<int> foundPorts = [];

        for (int p in _discoveryPorts) {
          try {
            final s = await Socket.connect(targetIp, p, timeout: const Duration(milliseconds: 280));
            s.destroy();
            alive = true;
            foundPorts.add(p);
          } catch (_) {}
        }
        stopwatch.stop();

        if (alive) {
          DeviceItem item = DeviceItem(
            ip: targetIp,
            pingMs: stopwatch.elapsedMilliseconds,
            openPorts: foundPorts,
          );

          // Nhận diện Web nếu mở bất kỳ cổng web thông dụng nào
          if (foundPorts.any((p) => [80, 81, 88, 443, 8080, 8888].contains(p))) {
            item.hasWeb = true;
          }

          // Nhận diện thiết bị Camera / Đầu ghi hình
          if (foundPorts.any((p) => [554, 8000, 34567, 37777].contains(p))) {
            item.deviceType = 'camera';
          } else if (i == 1 || i == 254) {
            item.isGateway = true;
            item.deviceType = 'router';
          } else if (foundPorts.contains(445)) {
            item.deviceType = 'pc';
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
      builder: (context) => PortScanSheet(ip: item.ip, initialOpenPorts: item.openPorts),
    );
  }

  Widget _buildTypeIcon(String type) {
    switch (type) {
      case 'camera':
        return const Icon(Icons.videocam, color: Colors.amber, size: 28);
      case 'router':
        return const Icon(Icons.router, color: Colors.blueAccent, size: 28);
      case 'pc':
        return const Icon(Icons.computer, color: Colors.tealAccent, size: 28);
      default:
        return const Icon(Icons.devices, color: Colors.cyan, size: 28);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera,Vi tính - Đức Thái 0909272412', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
                      padding: const EdgeInsets.all(14),
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
                                    if (d.pingMs >= 0)
                                      Text('Độ trễ: ${d.pingMs} ms', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const SizedBox(width: 12),
                                    Text('Cổng mở: ${d.openPorts.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
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
  final List<int> initialOpenPorts;
  const PortScanSheet({super.key, required this.ip, required this.initialOpenPorts});

  @override
  State<PortScanSheet> createState() => _PortScanSheetState();
}

class _PortScanSheetState extends State<PortScanSheet> {
  // Danh mục chi tiết các cổng phổ biến
  final Map<int, String> _portDefinitions = {
    21: 'FTP (Truyền file)',
    22: 'SSH (Quản trị mạng từ xa)',
    23: 'Telnet (Giao diện dòng lệnh)',
    53: 'DNS',
    80: 'HTTP (Trang Web quản trị)',
    81: 'HTTP (Web phụ / Camera Web)',
    88: 'HTTP (Web phụ)',
    443: 'HTTPS (Web bảo mật SSL)',
    445: 'SMB (Chia sẻ file nội bộ)',
    554: 'RTSP (Luồng Video Stream)',
    1935: 'RTMP (Stream Video)',
    8000: 'Hikvision / DVR Service Port',
    8080: 'HTTP Proxy / Web thay thế',
    8888: 'HTTP Web Port',
    34567: 'Xiongmai / CMS Port (Đầu ghi/Cam)',
    37777: 'Dahua TCP Service Port',
  };

  final List<int> _openPorts = [];
  bool _scanningPorts = true;

  @override
  void initState() {
    super.initState();
    _openPorts.addAll(widget.initialOpenPorts);
    _scanAllPorts();
  }

  Future<void> _scanAllPorts() async {
    for (var port in _portDefinitions.keys) {
      if (_openPorts.contains(port)) continue;
      try {
        final s = await Socket.connect(widget.ip, port, timeout: const Duration(milliseconds: 320));
        s.destroy();
        if (mounted) {
          setState(() {
            if (!_openPorts.contains(port)) _openPorts.add(port);
          });
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _scanningPorts = false;
        _openPorts.sort();
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
              Text('Cổng Mở: ${widget.ip}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if (_scanningPorts)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          Flexible(
            child: _openPorts.isEmpty && !_scanningPorts
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('éo tìm thấy cổng mở thông dụng nào.', style: TextStyle(color: Colors.grey))),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: _openPorts.map((port) {
                      String desc = _portDefinitions[port] ?? 'Dịch vụ tùy chỉnh';
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle, color: Colors.greenAccent),
                        title: Text('Port $port: $desc', style: const TextStyle(fontWeight: FontWeight.w600)),
                        trailing: const Text(
                          'MỞ (OPEN)',
                          style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
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
