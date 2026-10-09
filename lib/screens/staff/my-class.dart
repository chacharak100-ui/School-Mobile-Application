import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';
import 'student_report.dart'; 
// Import your main dashboard to reuse the drawer logic if needed
import 'dashboard.dart'; 

class ClassDashboardScreen extends StatefulWidget {
  const ClassDashboardScreen({super.key});

  @override
  State<ClassDashboardScreen> createState() => _ClassDashboardScreenState();
}

class _ClassDashboardScreenState extends State<ClassDashboardScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _classInfo;
  Map<String, dynamic>? _stats;
  List<dynamic> _students = [];
  bool _hasPermission = false;
  bool _canMark = false;
  String? _alertMsg;
  String _alertType = "danger";

  @override
  void initState() {
    super.initState();
    _fetchClassData();
  }

  Future<void> _fetchClassData() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');
      String? username = prefs.getString('username');

      final url = Uri.parse(AppConfig.getUrl('/api/staff/my-class'))
          .replace(queryParameters: {'username': username});

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
            _classInfo = data['assignment'];
            _stats = data['stats'];
            _students = data['students'];
            _hasPermission = data['has_attendance_permission'] ?? false;
            _canMark = data['can_mark'] ?? false;
            _alertMsg = data['alert_msg'];
            _alertType = data['alert_type'] ?? 'danger';
            _isLoading = false;
          });
        } else {
           setState(() => _isLoading = false);
           if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message'] ?? "Error")));
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Network Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _markAttendance(String stdId, String status) async {
    // Optimistic Update or Local Loader could be added here, but for now we rely on refresh
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');
      final url = Uri.parse(AppConfig.getUrl('/api/staff/mark-class-attendance'));
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null) 'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'std_id': stdId, 'status': status}),
      );

      final data = jsonDecode(response.body);
      if (data['success']) {
        _fetchClassData(); // Refresh list to show updated status
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.green),
        );
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message']), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Network Error"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _bulkMarkAllPresent() async {
    final unmarkedStudents = _students.where((s) => !s['is_marked']).toList();
    if (unmarkedStudents.isEmpty) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All students marked."), backgroundColor: Colors.orange));
      return;
    }

    // Show local feedback
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Processing bulk attendance..."), duration: Duration(seconds: 1)));

    final bulkData = unmarkedStudents.map((s) => {'std_id': s['std']['std_id'], 'status': 'Present'}).toList();

    try {
      final prefs = await SharedPreferences.getInstance();
      String? jwtToken = prefs.getString('jwt_token');
      final url = Uri.parse(AppConfig.getUrl('/api/staff/mark-class-attendance'));
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          if (jwtToken != null) 'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'students': bulkData}),
      );

      final data = jsonDecode(response.body);
      if (data['success']) {
        _fetchClassData();
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.green));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(data['message']), backgroundColor: Colors.red));
      }
    } catch (e) {
      print(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Class Dashboard", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: const Color(0xFF1A3A4F),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF1A3A4F)))
          : _classInfo == null
              ? const Center(child: Text("Not assigned to any class."))
              : RefreshIndicator(
                  onRefresh: _fetchClassData,
                  color: const Color(0xFF1A3A4F),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- 1. HEADER BANNER ---
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: const Border(left: BorderSide(color: Color(0xFF1A3A4F), width: 6)),
                            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "${_classInfo!['class_name']} - Section ${_classInfo!['section']}",
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1A3A4F)),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Teacher: ${_classInfo!['staff_name']}",
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.class_, size: 40, color: Colors.blue.shade100),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // --- 2. STATS GRID ---
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          childAspectRatio: 1.1,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          children: [
                            _buildStatCard("Total", "${_stats!['total_students']}", const Color(0xFF1A3A4F), Icons.people),
                            _buildStatCard("Male", "${_stats!['male_count']}", Colors.blue, Icons.male),
                            _buildStatCard("Female", "${_stats!['female_count']}", Colors.pink, Icons.female),
                            _buildStatCard("Islam", "${_stats!['islam_count']}", Colors.green, Icons.nights_stay),
                            _buildStatCard("Hindu", "${_stats!['hindu_count']}", Colors.orange, Icons.wb_sunny),
                            _buildStatCard("Christian", "${_stats!['christian_count']}", Colors.grey, Icons.church),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // --- 3. PERMISSION ALERT ---
                        if (!_hasPermission)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.shield_outlined, color: Colors.amber, size: 28),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    "You do not have permission to take attendance for this class.",
                                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // --- 4. BULK ACTIONS ---
                        if (_hasPermission && _canMark)
                          Card(
                            color: Colors.white,
                            margin: const EdgeInsets.only(bottom: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Bulk Actions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  ElevatedButton.icon(
                                    onPressed: _bulkMarkAllPresent,
                                    icon: const Icon(Icons.done_all, size: 18),
                                    label: const Text("Mark All Present"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                        // --- 5. STUDENT GRID ---
                        const Text(
                          "Student List",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1A3A4F)),
                        ),
                        const SizedBox(height: 12),
                        
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _students.length,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.75, // Taller cards for more info
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemBuilder: (context, index) {
                            final item = _students[index];
                            final std = item['std'];
                            return _buildStudentCard(std, item['is_marked'], item['status'], item['fee_status'], std['std_id']);
                          },
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.9), size: 24),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> std, bool isMarked, String? status, String feeStatus, String stdId) {
    Color feeColor = Colors.grey;
    IconData feeIcon = Icons.help;
    if (feeStatus == 'Paid') { feeColor = Colors.green; feeIcon = Icons.check_circle; }
    else if (feeStatus == 'Not Paid') { feeColor = Colors.red; feeIcon = Icons.cancel; }
    else { feeColor = Colors.orange; feeIcon = Icons.warning; }

    String? photoUrl;
    if (std['photo'] != null && std['photo'].toString().isNotEmpty) {
      photoUrl = std['photo'].startsWith('http') ? std['photo'] : AppConfig.getUrl('/api/student/view_photo/${std['photo']}');
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                  child: photoUrl == null ? const Icon(Icons.person, color: Colors.grey, size: 20) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(std['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(std['std_id'], style: TextStyle(fontSize: 10, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            
            // Badges
            Row(children: [
              _buildSmallBadge(std['gender'] ?? 'N/A', Icons.person_outline),
              const SizedBox(width: 4),
              _buildSmallBadge(std['religion'] ?? 'N/A', Icons.favorite_outline),
              const Spacer(),
              Icon(feeIcon, size: 14, color: feeColor),
            ]),
            
            const SizedBox(height: 8),
            
            // Fee Status Text
            Text("Fee: $feeStatus", style: TextStyle(fontSize: 10, color: feeColor, fontWeight: FontWeight.bold)),
            
            const Divider(height: 16),
            
            // Attendance Action
            if (isMarked)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 14),
                  const SizedBox(width: 4),
                  Text(status ?? "Present", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11)),
                ]),
              )
            else if (!_hasPermission || !_canMark)
              const Center(child: Text("N/A", style: TextStyle(fontSize: 11, color: Colors.grey)))
            else
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: const Text("Mark Now", style: TextStyle(fontSize: 11)),
                  items: ['Present', 'Absent', 'Leave'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 11)))).toList(),
                  onChanged: (val) { if (val != null) _markAttendance(stdId, val); },
                ),
              ),
            
            const SizedBox(height: 8),
            
            // View Report Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => StudentReportScreen(stdId: stdId)));
                },
                icon: const Icon(Icons.article, size: 14),
                label: const Text("Report", style: TextStyle(fontSize: 10)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(color: Colors.grey.shade300),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 9, color: Colors.grey), const SizedBox(width: 2), Text(text, style: const TextStyle(fontSize: 8))]),
    );
  }
}