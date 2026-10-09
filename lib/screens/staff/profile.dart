import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import '../login_screen.dart'; // Import for logout navigation

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
      final storedUsername = prefs.getString('username') ?? '';

      if (jwtToken == null || jwtToken.isEmpty) {
        _handleLogout();
        return;
      }

      // Backend extracts user from Token, so no username param needed in URL
      final url = Uri.parse(AppConfig.getUrl('/api/staff/my-class'))
          .replace(queryParameters: {'username': storedUsername});

      final response = await http.get(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
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
          if (response.statusCode == 401 || response.statusCode == 403) {
            _handleLogout();
          }
        }
      } else {
        setState(() {
          _errorMessage = "Server Error";
          _isLoading = false;
        });
        if (response.statusCode == 401 || response.statusCode == 403) {
          _handleLogout();
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = "Network Error: $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF1A3A4F),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3A4F)))
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _fetchProfile, child: const Text("Retry"))
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchProfile,
                  color: const Color(0xFF1A3A4F),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- 1. HEADER PROFILE CARD ---
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
                          ),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Photo
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(60),
                                    child: _buildPhoto(),
                                  ),
                                  const SizedBox(width: 16),
                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _profile!['name'],
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A3A4F)),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${_profile!['designation'] ?? 'Staff'} • ${_profile!['department'] ?? ''}",
                                          style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            _buildChip("ID: ${_profile!['staff_id']}", Icons.badge),
                                            _buildChip("Emp: ${_profile!['employ_id'] ?? 'N/A'}", Icons.tag),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: _profile!['status'] == 'Active' ? Colors.green : Colors.red,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                _profile!['status'],
                                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              const Divider(height: 1),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.verified_user, size: 14, color: Colors.grey),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Cert: ${_profile!['certificate_number'] ?? 'N/A'}",
                                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // --- 2. CONTACT & PERSONAL INFO ---
                        _buildSectionCard("Contact Details", Icons.phone, const Color(0xFF4A90D9), [
                          _buildRow("Phone", _profile!['phone']),
                          _buildRow("WhatsApp", _profile!['whatsapp']),
                          _buildRow("Email", _profile!['email']),
                          _buildRow("City", _profile!['city']),
                          _buildRow("Address", _profile!['address']),
                        ]),

                        _buildSectionCard("Personal Information", Icons.person_outline, const Color(0xFF50C878), [
                          Row(
                            children: [
                              Expanded(child: _buildRow("Father's Name", _profile!['father_name'])),
                              Expanded(child: _buildRow("Gender", _profile!['gender'])),
                            ],
                          ),
                          _buildRow("CNIC", _profile!['cnic']),
                          _buildRow("Date of Birth", _profile!['dob']),
                          _buildRow("Religion", _profile!['religion']),
                          _buildRow("Marital Status", _profile!['marital_status']),
                        ]),

                        _buildSectionCard("Emergency Contact", Icons.warning_amber_rounded, Colors.redAccent, [
                          _buildRow("Name", _profile!['emergency_name'], valueColor: Colors.red.shade700),
                          _buildRow("Relation", _profile!['emergency_relation']),
                          _buildRow("Number", _profile!['emergency_number'], valueColor: Colors.red.shade700),
                        ]),

                        const SizedBox(height: 20),

                        // --- 3. JOB & PAYROLL ---
                        _buildSectionCard("Job Profile", Icons.work, const Color(0xFF6C5CE7), [
                          _buildRow("Staff Type", _profile!['staff_type']),
                          _buildRow("Grade Level", _profile!['grade_level']),
                          _buildRow("Joining Date", _profile!['joining_date']),
                          _buildRow("Reporting To", _profile!['reporting_to']),
                          _buildRow("Qualification", "${_profile!['qualification']} (${_profile!['institute']})"),
                        ]),

                        _buildSectionCard("Portal Permissions", Icons.security, const Color(0xFF1A3A4F), [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPermChip("Login", _profile!['permissions']['can_login']),
                              _buildPermChip("Marks", _profile!['permissions']['can_marks']),
                              _buildPermChip("Attendance", _profile!['permissions']['can_attendance']),
                              _buildPermChip("Edit Students", _profile!['permissions']['can_edit_students']),
                              _buildPermChip("Finance", _profile!['permissions']['can_finance']),
                            ],
                          ),
                        ]),

                        _buildSectionCard("Payroll Details", Icons.payments, const Color(0xFFE67E50), [
                          Row(
                            children: [
                              Expanded(child: _buildStatBox("Basic", "${_profile!['basic_salary']}", Colors.green)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildStatBox("Allowance", "${_profile!['allowances']}", Colors.blue)),
                              const SizedBox(width: 8),
                              Expanded(child: _buildStatBox("Deduct", "${_profile!['deductions']}", Colors.red)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Bank: ${_profile!['bank_name']}", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text("Acc: ${_profile!['account_number']}", style: const TextStyle(fontSize: 12)),
                                Text("IBAN: ${_profile!['iban']}", style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                              ],
                            ),
                          ),
                        ]),

                        // --- 4. LEAVE HISTORY ---
                        _buildSectionCard("Recent Leave History", Icons.history, Colors.grey.shade700, [
                          _leaves.isEmpty
                              ? const Padding(padding: EdgeInsets.all(10), child: Text("No leave requests found."))
                              : ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _leaves.length > 5 ? 5 : _leaves.length, // Show last 5
                                  itemBuilder: (context, index) {
                                    final l = _leaves[index];
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(l['type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      subtitle: Text("${l['start_date']} to ${l['end_date']}"),
                                      trailing: _buildStatusBadge(l['status']),
                                    );
                                  },
                                ),
                        ]),

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildPhoto() {
    final photoUrl = _profile!['photo_url'] != null ? AppConfig.getUrl(_profile!['photo_url']) : null;
    return photoUrl != null
        ? Image.network(photoUrl, width: 100, height: 100, fit: BoxFit.cover, errorBuilder: (c,e,s) => _placeholderIcon())
        : _placeholderIcon();
  }

  Widget _placeholderIcon() {
    return Container(
      width: 100,
      height: 100,
      color: Colors.grey.shade200,
      child: const Icon(Icons.person, size: 50, color: Colors.grey),
    );
  }

  Widget _buildChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 12, color: Colors.grey[600]), const SizedBox(width: 4), Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500))],
      ),
    );
  }

  Widget _buildPermChip(String label, bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String? value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black87),
          children: [
            TextSpan(text: "$label: ", style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
            TextSpan(text: value ?? 'N/A', style: TextStyle(color: valueColor, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, IconData icon, Color color, List<Widget> children) {
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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
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