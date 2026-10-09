import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';

class StudentReportScreen extends StatefulWidget {
  final String stdId;
  const StudentReportScreen({super.key, required this.stdId});

  @override
  State<StudentReportScreen> createState() => _StudentReportScreenState();
}

class _StudentReportScreenState extends State<StudentReportScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _reportData;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');

      // ✅ No username in URL, relying on JWT
      final url = Uri.parse(AppConfig.getUrl('/api/staff/student-report'))
          .replace(queryParameters: {'std_id': widget.stdId});

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json'
    
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _reportData = data;
            _isLoading = false;
          });
        } else {
          setState(() { _errorMessage = data['message']; _isLoading = false; });
        }
      } else {
         setState(() { _errorMessage = "Server Error ${response.statusCode}"; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _errorMessage = "Network Error: $e"; _isLoading = false; });
    }
  }

  // ✅ Function to Open Web Portal
  Future<void> _openPortal() async {
    if (_reportData == null) return;
    
    // Use the portal_url from API or fallback to login page
    String portalLink = _reportData!['portal_url'] ?? AppConfig.getUrl('/staff/portal/my-class');
    
    final url = Uri.parse(portalLink);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication); // Opens in Chrome/External Browser
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not open portal link")));
    }
  }

  Future<void> _sendWhatsApp(String type) async {
    if (_reportData == null) return;
    final r = _reportData!;
    final student = r['student'];
    final whatsappNo = student['whatsapp_no'] ?? '';
    
    if (whatsappNo.toString().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No WhatsApp number found")));
      return;
    }

    String message = "";
    final name = student['name'];
    final month = r['current_month'];
    
    if (type == 'attendance') {
      message = "Dear Parent, Attendance Summary for $name ($month):\n"
                "✅ Present: ${r['present_count']}\n❌ Absent: ${r['absent_count']}\n"
                "📊 Consistency: ${r['att_percentage']}%";
    } else if (type == 'fee') {
      message = "Dear Parent, Fee Status for $name ($month): ${r['fee_status']}";
    } else {
      message = "Dear Parent, this is an update regarding $name from School.";
    }

    final url = Uri.parse("https://wa.me/$whatsappNo?text=${Uri.encodeComponent(message)}");
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_errorMessage != null) return Scaffold(appBar: AppBar(title: const Text("Error")), body: Center(child: Text(_errorMessage!)));
    if (_reportData == null) return const Scaffold(body: Center(child: Text("No Data")));

    final r = _reportData!;
    final student = r['student'];
    final photoUrl = student['photo'] != null ? AppConfig.getUrl('/api/student/view_photo/${student['photo']}') : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(student['name']), 
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.message, color: Colors.green),
            onSelected: _sendWhatsApp,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'attendance', child: Text("Send Attendance Summary")),
              const PopupMenuItem(value: 'fee', child: Text("Send Fee Status")),
              const PopupMenuItem(value: 'custom', child: Text("Custom Message")),
            ],
          ),
        ]
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Card
            Card(
              child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
                CircleAvatar(radius: 40, backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null, child: photoUrl == null ? const Icon(Icons.person, size: 40) : null),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(student['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text("${student['current_class']} - ${student['section']} | ID: ${student['std_id']}"),
                  Text("Father: ${student['father_name'] ?? 'N/A'}", style: TextStyle(color: Colors.grey[600])),
                ])),
              ])),
            ),
            const SizedBox(height: 16),

            // ✅ UPDATE ON PORTAL BUTTON (Opens External Browser)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openPortal,
                icon: const Icon(Icons.open_in_browser),
                label: const Text("Update Marks/Attendance on Portal"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Stats Row
            Row(children: [
              Expanded(child: _buildStatBox("Attendance", "${r['att_percentage']}%", r['att_percentage'] >= 75 ? Colors.green : Colors.orange)),
              const SizedBox(width: 12),
              Expanded(child: _buildStatBox("Academic", "${r['overall_academic_avg']}%", Colors.blue)),
            ]),
            const SizedBox(height: 16),

            // Attendance History (Read Only)
            const Text("Recent Attendance", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Card(
              child: ListView.separated(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                itemCount: (r['attendance_history'] as List).length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final att = r['attendance_history'][index];
                  return ListTile(
                    title: Text(att['date']),
                    subtitle: Text("Entry: ${att['entry_time'] ?? '--:--'}"),
                    trailing: Chip(label: Text(att['status']), backgroundColor: att['status'] == 'Present' ? Colors.green.shade50 : (att['status'] == 'Absent' ? Colors.red.shade50 : Colors.orange.shade50)),
                  );
                },
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Fee History
            if (!r['fee_exempt']) ...[
              const Text("Fee History", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Card(
                child: ListView.separated(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                  itemCount: (r['fee_history'] as List).length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final fee = r['fee_history'][index];
                    return ListTile(
                      title: Text("${fee['month']} ${fee['year']}"),
                      subtitle: Text("Rs. ${fee['payable_amount']}"),
                      trailing: Chip(label: Text(fee['status']), backgroundColor: fee['status'] == 'Paid' ? Colors.green.shade50 : Colors.orange.shade50),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Column(children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
    );
  }
}