import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:gal/gal.dart';
import '../../config/app_config.dart';

class StudentIdCardScreen extends StatefulWidget {
  final String username;
  const StudentIdCardScreen({super.key, required this.username});

  @override
  State<StudentIdCardScreen> createState() => _StudentIdCardScreenState();
}

class _StudentIdCardScreenState extends State<StudentIdCardScreen> {
  bool isLoading = true;
  Map<String, dynamic>? _studentData;
  final ScreenshotController _screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    fetchIdCardData();
  }

  Future<void> fetchIdCardData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final identifier = prefs.getString('std_id') ?? 
                         prefs.getString('username') ?? 
                         widget.username;

      final url = Uri.parse(await AppConfig.getUrl('/api/student/id-card'))
          .replace(queryParameters: {'std_id': identifier});

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _studentData = data['data'];
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("ID Card Error: $e");
      setState(() => isLoading = false);
    }
  }

  String? get _photoUrl {
    if (_studentData == null) return null;
    final photo = _studentData!['photo'];
    if (photo != null && photo.toString().isNotEmpty && photo != 'None') {
      // Construct full URL for the photo
      return AppConfig.baseUrl + '/api/student/view_photo/$photo'; 
    }
    return null;
  }

  Future<void> _saveIdCard() async {
    try {
      // Capture the widget
      final Uint8List? imageBytes = await _screenshotController.capture(pixelRatio: 3.0);
      
      if (imageBytes != null) {
        // Save to Gallery
        await Gal.putImageBytes(imageBytes.buffer.asUint8List());
        
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("ID Card saved to gallery!"), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      debugPrint("Save Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital ID Card'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _saveIdCard,
            tooltip: "Save to Gallery",
          )
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : _studentData == null
              ? const Center(child: Text("Failed to load data"))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        // The ID Card Widget
                        Screenshot(
                          controller: _screenshotController,
                          child: Container(
                            width: 340, // Standard ID Card Ratio
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.15),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                // 1. Header Gradient
                                Container(
                                  height: 110,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xFF4338ca), Color(0xFF1e1b4b)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(20),
                                      topRight: Radius.circular(20),
                                    ),
                                  ),
                                  child: Stack(
                                    children: [
                                      // Dot Pattern Overlay
                                      Opacity(
                                        opacity: 0.1,
                                        child: Image.network(
                                          'https://www.transparenttextures.com/patterns/cubes.png', 
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                      Center(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              _studentData!['school_name'].toString().toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                letterSpacing: 1.2,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                              decoration: BoxDecoration(
                                                border: Border.all(color: Colors.white30),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                "STUDENT IDENTITY CARD",
                                                style: TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 8,
                                                  letterSpacing: 2,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // 2. Profile Photo (Overlapping)
                                Transform.translate(
                                  offset: const Offset(0, -40),
                                  child: Container(
                                    width: 110,
                                    height: 110,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white, width: 5),
                                      boxShadow: [
                                        BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10),
                                      ],
                                    ),
                                    child: ClipOval(
                                      child: _photoUrl != null
                                          ? Image.network(
                                              _photoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 50, color: Colors.grey),
                                            )
                                          : Container(
                                              color: Colors.grey[200],
                                              child: const Icon(Icons.person, size: 50, color: Colors.grey),
                                            ),
                                    ),
                                  ),
                                ),

                                // 3. Student Name & Class
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                  child: Column(
                                    children: [
                                      Text(
                                        _studentData!['student_name'],
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Class: ${_studentData!['current_class']} - ${_studentData!['section']}",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.indigo.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Divider(height: 24, thickness: 1, color: Colors.grey.shade300),
                                    ],
                                  ),
                                ),

                                // 4. Details Grid
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                                    ),
                                    child: Column(
                                      children: [
                                        _buildInfoRow("Student ID", _studentData!['std_id']),
                                        _buildInfoRow("Father's Name", _studentData!['father_name']),
                                        _buildInfoRow("Session", _studentData!['session']),
                                        _buildInfoRow("Blood Group", _studentData!['blood_group'], valueColor: Colors.red),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 15),

                                // 5. QR Code & Footer
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.indigo.shade100),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: QrImageView(
                                    data: _studentData!['std_id'].toString(),
                                    version: QrVersions.auto,
                                    size: 70.0,
                                    backgroundColor: Colors.white,
                                    eyeStyle: const QrEyeStyle(
                                      eyeShape: QrEyeShape.square,
                                      color: Color(0xFF1e1b4b),
                                    ),
                                    dataModuleStyle: const QrDataModuleStyle(
                                      dataModuleShape: QrDataModuleShape.square,
                                      color: Color(0xFF1e1b4b),
                                    ),
                                  ),
                                ),
                                
                                // Security Strip
                                Container(
                                  height: 8,
                                  width: double.infinity,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF4338ca),
                                    borderRadius: BorderRadius.only(
                                      bottomLeft: Radius.circular(20),
                                      bottomRight: Radius.circular(20),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        
                        ElevatedButton.icon(
                          onPressed: _saveIdCard,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text("Download ID Card"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
                            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          Text(
            value ?? '-',
            style: TextStyle(
              fontSize: 12, 
              color: valueColor ?? Colors.black87, 
              fontWeight: FontWeight.bold
            ),
          ),
        ],
      ),
    );
  }
}