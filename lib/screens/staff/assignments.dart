import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class ProfileScreen extends StatefulWidget {
  final String username;
  const ProfileScreen({super.key, required this.username});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _profile;
  List<dynamic> _leaves = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');

      final url = Uri.parse(AppConfig.getUrl('/api/staff/full-profile'))
          .replace(queryParameters: {'username': widget.username});

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null) 'Authorization': 'Bearer $jwtToken',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _profile = data['staff'];
            _leaves = data['staff']['leaves'] ?? [];
            _isLoading = false;
          });
        } else {
          setState(() {
            _errorMessage = data['message'];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = "Server Error";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network Error";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Text(_errorMessage!));
    if (_profile == null) return const Center(child: Text("No Data"));

    final p = _profile!;
    final photoUrl = p['photo_url'] != null ? AppConfig.getUrl(p['photo_url']) : null;

    return RefreshIndicator(
      onRefresh: _fetchProfile,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 1. HEADER BANNER CARD ---
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Photo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(60),
                          child: photoUrl != null
                              ? Image.network(photoUrl, width: 110, height: 110, fit: BoxFit.cover)
                              : Container(
                                  width: 110, height: 110,
                                  color: Colors.grey.shade300,
                                  child: const Icon(Icons.person, size: 60, color: Colors.white),
                                ),
                        ),
                        const SizedBox(width: 20),
                        // Name & IDs
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p['name'], style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text("${p['designation'] ?? 'Staff'} • ${p['department'] ?? ''}", 
                                   style: TextStyle(color: Colors.grey[600])),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildChip("ID: ${p['staff_id']}", Icons.badge),
                                  _buildChip("Emp: ${p['employ_id'] ?? 'N/A'}", Icons.tag),
                                  _buildChip("Code: ${p['staff_code'] ?? 'N/A'}", Icons.code),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                                    child: Text(p['status'], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Certificate No: ", style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(p['certificate_number'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // --- 2. TWO COLUMN LAYOUT SIMULATION ---
            // Since Flutter doesn't have easy grid columns for mixed heights, we stack them vertically 
            // but group them logically like the HTML.

            // LEFT COLUMN CONTENT (Contact, Personal, Emergency)
            _buildSectionCard("Contact Details", Icons.phone, [
              _buildRow("Phone", p['phone']),
              _buildRow("WhatsApp", p['whatsapp']),
              _buildRow("Email", p['email']),
              _buildRow("City", p['city']),
              _buildRow("Address", p['address']),
            ]),

            _buildSectionCard("Personal Info", Icons.person_outline, [
              _buildRow("Father's Name", p['father_name']),
              _buildRow("CNIC", p['cnic']),
              _buildRow("DOB", p['dob']),
              _buildRow("Gender", p['gender']),
              _buildRow("Religion", p['religion']),
              _buildRow("Marital Status", p['marital_status']),
              _buildRow("Nationality", p['nationality']),
            ]),

            _buildSectionCard("Emergency Contact", Icons.warning_amber_rounded, [
              _buildRow("Name", p['emergency_name'], color: Colors.red.shade700),
              _buildRow("Relation", p['emergency_relation']),
              _buildRow("Number", p['emergency_number'], color: Colors.red.shade700),
            ], headerColor: Colors.red.shade700),

            const SizedBox(height: 20),

            // RIGHT COLUMN CONTENT (Job, Permissions, Payroll, Leaves)
            
            _buildSectionCard("Job & Academic Profile", Icons.work, [
              _buildRow("Staff Type", p['staff_type']),
              _buildRow("Grade Level", p['grade_level']),
              _buildRow("Joining Date", p['joining_date']),
              _buildRow("Reporting To", p['reporting_to']),
              _buildRow("Qualification", "${p['qualification']} (${p['institute']})"),
              _buildRow("Specialist Subject", p['specialist_subject']),
            ]),

            _buildSectionCard("Portal Permissions", Icons.security, [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildPermChip("Portal Login", p['permissions']['can_login']),
                  _buildPermChip("Marks Entry", p['permissions']['can_marks']),
                  _buildPermChip("Attendance", p['permissions']['can_attendance']),
                  _buildPermChip("Edit Students", p['permissions']['can_edit_students']),
                  _buildPermChip("View Finance", p['permissions']['can_finance']),
                ],
              ),
            ]),

            _buildSectionCard("Payroll & Bank Details", Icons.payments, [
              Row(
                children: [
                  Expanded(child: _buildStatBox("Basic Salary", "${p['basic_salary']}", Colors.green)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatBox("Allowances", "${p['allowances']}", Colors.blue)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatBox("Deductions", "${p['deductions']}", Colors.red)),
                ],
              ),
              const SizedBox(height: 12),
              Text("Bank: ${p['bank_name']} • Acc: ${p['account_number']} • IBAN: ${p['iban']}", 
                   style: const TextStyle(fontSize: 12)),
            ]),

            _buildSectionCard("Leave History", Icons.history, [
              _leaves.isEmpty 
                ? const Padding(padding: EdgeInsets.all(10), child: Text("No leave requests found."))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _leaves.length,
                    itemBuilder: (context, index) {
                      final l = _leaves[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(l['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text("${l['start_date']} to ${l['end_date']} • ${l['reason']}"),
                        trailing: _buildStatusBadge(l['status']),
                      );
                    },
                  ),
            ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // --- Helper Widgets ---

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 12, color: Colors.grey[600]), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10))],
      ),
    );
  }

  Widget _buildPermChip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? Colors.green.shade200 : Colors.grey.shade300),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isActive ? Colors.green.shade800 : Colors.grey.shade600)),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color c = Colors.grey;
    if (status == 'Approved') c = Colors.green;
    if (status == 'Rejected') c = Colors.red;
    if (status == 'Pending') c = Colors.orange;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String? value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
            TextSpan(text: value ?? 'N/A', style: TextStyle(color: color, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, List<Widget> children, {Color? headerColor}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: headerColor ?? Colors.blue, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: headerColor ?? Colors.blue)),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }
}