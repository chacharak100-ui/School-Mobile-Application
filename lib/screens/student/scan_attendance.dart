import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class ScanAttendanceScreen extends StatefulWidget {
  final String? username;
  const ScanAttendanceScreen({super.key, this.username});

  @override
  State<ScanAttendanceScreen> createState() => _ScanAttendanceScreenState();
}

class _ScanAttendanceScreenState extends State<ScanAttendanceScreen> with WidgetsBindingObserver {
  final MobileScannerController _scannerController = MobileScannerController();
  
  // State Variables
  bool _isGpsLocked = false;
  Position? _currentPosition;
  String? _scannedQrCode;
  bool _isSubmitting = false;
  bool _isLoadingStatus = true;
  
  // Attendance Status Logic
  String _attendanceMode = "ENTRY"; // ENTRY or EXIT
  String _currentStatus = "Unknown"; // In School, Left, Present, etc.
  Color _uiThemeColor = Colors.green; // Dynamic color based on status
  
  // Cooldown Logic
  int _cooldownSeconds = 0;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle to restart camera if it was paused
    if (!_scannerController.value.isInitialized) return;

    switch (state) {
      case AppLifecycleState.resumed:
        _scannerController.start();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _scannerController.stop();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  // --- INITIALIZATION ---
  Future<void> _initializeScreen() async {
    await _checkServerCooldown();
    await _fetchCurrentAttendanceStatus();
  }

  // --- 1. CHECK SERVER COOLDOWN ---
  Future<void> _checkServerCooldown() async {
    // Optional: You can store last scan time locally to show immediate feedback
    // But real security is handled by backend. 
    // Here we just reset local state.
    setState(() {
      _cooldownSeconds = 0; 
    });
  }

  // --- 2. FETCH CURRENT STATUS (Entry vs Exit) ---
  Future<void> _fetchCurrentAttendanceStatus() async {
    setState(() => _isLoadingStatus = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = widget.username ?? prefs.getString('username') ?? prefs.getString('std_id');
      
      if (username == null) {
        _showError("User not logged in");
        return;
      }

      final url = Uri.parse(AppConfig.getUrl('/api/student/today-attendance'))
          .replace(queryParameters: {'username': username});
      
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final attendance = data['attendance'];
          
          setState(() {
            if (attendance == null) {
              // No record today -> ENTRY Mode
              _attendanceMode = "ENTRY";
              _currentStatus = "Absent";
              _uiThemeColor = Colors.green;
            } else {
              String status = attendance['current_status'] ?? '';
              if (status == 'In School') {
                // Already entered -> EXIT Mode
                _attendanceMode = "EXIT";
                _currentStatus = "In School";
                _uiThemeColor = Colors.red; // Red for Exit/Stop
              } else {
                // Already left or other status -> Disabled
                _attendanceMode = "COMPLETED";
                _currentStatus = status;
                _uiThemeColor = Colors.grey;
              }
            }
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching status: $e");
    } finally {
      setState(() => _isLoadingStatus = false);
    }
  }

  // --- 3. GPS LOCK ---
  Future<void> _lockGps() async {
    if (_attendanceMode == "COMPLETED") {
      _showWarning("Attendance already completed for today.");
      return;
    }

    setState(() {
      _statusMessage = "Acquiring high-precision GPS...";
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showError("Location permissions denied. Please enable in settings.");
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );

      if (position.accuracy > 35) {
        _showError("GPS Accuracy too low (${position.accuracy.toStringAsFixed(0)}m). Move to an open area.");
        return;
      }

      setState(() {
        _currentPosition = position;
        _isGpsLocked = true;
        _statusMessage = "GPS Locked! Scan QR Code to Mark $_attendanceMode";
      });

      await _scannerController.start();

    } catch (e) {
      _showError("Failed to get location: $e");
    }
  }

  // --- 4. QR SCAN HANDLER ---
  void _handleScan(BarcodeCapture capture) {
    if (_scannedQrCode != null || _isSubmitting || !_isGpsLocked) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? '';
      
      // Stop scanner immediately to prevent double reads
      _scannerController.stop();
      
      setState(() {
        _scannedQrCode = code;
        _isSubmitting = true;
        _statusMessage = "Verifying Secure Token...";
      });

      _submitAttendance(code);
    }
  }

  // --- 5. SUBMIT TO BACKEND ---
  Future<void> _submitAttendance(String qrCode) async {
    if (_currentPosition == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final username = widget.username ?? prefs.getString('username') ?? prefs.getString('std_id');

      final url = Uri.parse(AppConfig.getUrl('api/student/scan-attendance'));
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'qr_code': qrCode,
          'latitude': _currentPosition!.latitude,
          'longitude': _currentPosition!.longitude,
          'accuracy': _currentPosition!.accuracy,
          'speed': _currentPosition!.speed ?? 0,
          'action_type': _attendanceMode,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (data['status'] == 'success') {
        _showSuccess(data['message']);
        
        // Update local state to reflect completion
        setState(() {
          _attendanceMode = "COMPLETED";
          _uiThemeColor = Colors.grey;
          _currentStatus = _attendanceMode == "ENTRY" ? "In School" : "Left";
        });

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) Navigator.pop(context, true); // Return true to refresh dashboard
        });

      } else if (data['code'] == 'COOLDOWN_ACTIVE') {
        // Handle 2-minute cooldown
        _startCooldownTimer(120);
        _showWarning(data['message']);
        _resetScanner();

      } else {
        _showError(data['message'] ?? "Scan Failed");
        _resetScanner();
      }

    } catch (e) {
      _showError("Network Error: Check your connection");
      _resetScanner();
    }
  }

  void _resetScanner() {
    setState(() {
      _isSubmitting = false;
      _scannedQrCode = null;
      _statusMessage = "Scan Failed. Try Again.";
    });
    // Restart scanner after short delay
    Future.delayed(const Duration(seconds: 1), () {
      if (_isGpsLocked && mounted) _scannerController.start();
    });
  }

  void _startCooldownTimer(int seconds) {
    setState(() {
      _cooldownSeconds = seconds;
      _isGpsLocked = false; // Disable scanning during cooldown
      _scannerController.stop();
    });
    
    // Simple countdown for UI
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_cooldownSeconds > 0) {
        setState(() => _cooldownSeconds--);
        return true;
      }
      return false;
    }).then((_) {
      setState(() {
        _statusMessage = "Cooldown ended. Verify GPS again.";
        _isGpsLocked = false; // Force re-check GPS
      });
    });
  }

  // --- UI HELPERS ---
  String _statusMessage = "Step 1: Verify Location";

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }
  
  void _showWarning(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.orange),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDisabled = _attendanceMode == "COMPLETED" || _cooldownSeconds > 0;
    bool isExitMode = _attendanceMode == "EXIT";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("${_attendanceMode == 'EXIT' ? 'Exit' : 'Entry'} Attendance"),
        backgroundColor: _uiThemeColor,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: _isLoadingStatus 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
              children: [
                // Status Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.security, color: _uiThemeColor, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            "Mode: ${_attendanceMode}",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Current Status: $_currentStatus",
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _cooldownSeconds > 0 
                          ? "Wait $_cooldownSeconds seconds" 
                          : _statusMessage,
                        style: TextStyle(
                          color: _cooldownSeconds > 0 ? Colors.orange : Colors.grey[600], 
                          fontWeight: FontWeight.w500
                        ),
                      ),
                    ],
                  ),
                ),

                // Main Action Area
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      if (!_isGpsLocked && _cooldownSeconds == 0)
                        ElevatedButton.icon(
                          onPressed: isDisabled ? null : _lockGps,
                          icon: const Icon(Icons.my_location),
                          label: Text(isDisabled ? "Attendance Completed" : "Verify GPS Coordinates"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDisabled ? Colors.grey : _uiThemeColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        )
                      else if (_cooldownSeconds > 0)
                         Container(
                           padding: const EdgeInsets.all(20),
                           decoration: BoxDecoration(
                             color: Colors.orange.shade50,
                             borderRadius: BorderRadius.circular(12),
                             border: Border.all(color: Colors.orange)
                           ),
                           child: Column(
                             children: [
                               Icon(Icons.timer, color: Colors.orange, size: 40),
                               const SizedBox(height: 10),
                               Text("Anti-Cheat Cooldown Active", style: TextStyle(fontWeight: FontWeight.bold)),
                               Text("$_cooldownSeconds seconds remaining"),
                             ],
                           )
                         )
                      else
                        Column(
                          children: [
                            // Camera Viewfinder with Dynamic Border
                            Container(
                              height: 300,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _uiThemeColor, width: 4), // Dynamic Color
                                color: Colors.black,
                                boxShadow: [
                                  BoxShadow(
                                    color: _uiThemeColor.withOpacity(0.3),
                                    blurRadius: 15,
                                    spreadRadius: 2,
                                  )
                                ]
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  children: [
                                    MobileScanner(
                                      controller: _scannerController,
                                      onDetect: _handleScan,
                                    ),
                                    // Overlay Target Box
                                    Center(
                                      child: Container(
                                        width: 200,
                                        height: 200,
                                        decoration: BoxDecoration(
                                          border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                    if (_isSubmitting)
                                      Container(
                                        color: Colors.black.withOpacity(0.7),
                                        child: const Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircularProgressIndicator(color: Colors.white),
                                              SizedBox(height: 10),
                                              Text("Processing...", style: TextStyle(color: Colors.white))
                                            ],
                                          ),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              "Align QR Code within the frame",
                              style: TextStyle(color: Colors.grey[600]),
                            )
                          ],
                        ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 30),
                
                // Info Footer
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    "Secure Geo-Fencing • Anti-Spoofing • Live Validation",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[400], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}