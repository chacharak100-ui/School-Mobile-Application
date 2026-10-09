import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentAttendanceScreen extends StatefulWidget {
  final String username;
  const StudentAttendanceScreen({super.key, required this.username});

  @override
  State<StudentAttendanceScreen> createState() => _StudentAttendanceScreenState();
}

class _StudentAttendanceScreenState extends State<StudentAttendanceScreen> {
  bool isLoading = true;
  Map<String, dynamic> stats = {
    'total_days': 0,
    'present': 0,
    'absent': 0,
    'leave': 0,
    'attendance_percentage': 0.0
  };
  List<dynamic> attendanceHistory = [];

  // Filter states
  String? selectedStatus;
  String? selectedMonth;
  String? selectedYear;

  final List<String> statuses = ['All', 'Present', 'Absent', 'Leave'];
  final List<String> months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final List<String> years = ['2024', '2025', '2026', '2027'];

  @override
  void initState() {
    super.initState();
    fetchAttendanceData();
  }

  Future<void> fetchAttendanceData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('username') ?? prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/attendance-history'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'status': selectedStatus == 'All' ? null : selectedStatus,
          'month': selectedMonth,
          'year': selectedYear,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          stats = data['statistics'] ?? stats;
          attendanceHistory = data['history'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Attendance Fetch Exception: $e');
      setState(() => isLoading = false);
    }
  }

  void _resetFilters() {
    setState(() {
      selectedStatus = 'All';
      selectedMonth = null;
      selectedYear = null;
    });
    fetchAttendanceData();
  }

  void _showAttendanceDetailModal(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Attendance Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          item['status'] == 'Present'
                              ? Icons.check_circle_rounded
                              : (item['status'] == 'Leave' ? Icons.event_busy : Icons.cancel_rounded),
                          size: 50,
                          color: item['status'] == 'Present'
                              ? Colors.green
                              : (item['status'] == 'Leave' ? Colors.orange : Colors.red),
                        ),
                        const SizedBox(height: 8),
                        Text('Status: ${item['status']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Date: ${item['formatted_date']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                        const Divider(height: 24),
                      ],
                    ),
                  ),
                  _detailRow('Entry Time:', '${item['entry_time']}'),
                  _detailRow('Verification Mode:', '${item['verification_method']}'),
                  _detailRow('Latitude:', item['latitude'] != null ? '${item['latitude']}' : 'N/A'),
                  _detailRow('Longitude:', item['longitude'] != null ? '${item['longitude']}' : 'N/A'),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1)),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Attendance Logs'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: fetchAttendanceData,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'Reset Filters',
            onPressed: _resetFilters,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchAttendanceData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildFilterSection(),
                  const SizedBox(height: 16),
                  _buildStatisticsGrid(),
                  const SizedBox(height: 20),
                  const Text(
                    'Daily Attendance Logs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                  ),
                  const SizedBox(height: 8),
                  attendanceHistory.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('No attendance records found.')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: attendanceHistory.length,
                          itemBuilder: (context, index) {
                            return _buildAttendanceCard(attendanceHistory[index]);
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterSection() {
    return ExpansionTile(
      title: const Text('Filter Attendance Records', style: TextStyle(fontWeight: FontWeight.w600)),
      leading: const Icon(Icons.filter_list, color: Color.fromRGBO(110, 115, 225, 1)),
      backgroundColor: Colors.grey.shade50,
      collapsedBackgroundColor: Colors.grey.shade100,
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              DropdownButtonFormField<String>(
                value: selectedStatus ?? 'All',
                decoration: const InputDecoration(labelText: 'Status Filter', border: OutlineInputBorder()),
                items: statuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) => setState(() => selectedStatus = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedMonth,
                decoration: const InputDecoration(labelText: 'Month Filter', border: OutlineInputBorder()),
                items: months.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (val) => setState(() => selectedMonth = val),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selectedYear,
                decoration: const InputDecoration(labelText: 'Year Filter', border: OutlineInputBorder()),
                items: years.map((y) => DropdownMenuItem(value: y, child: Text(y))).toList(),
                onChanged: (val) => setState(() => selectedYear = val),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1)),
                icon: const Icon(Icons.search, color: Colors.white),
                label: const Text('Apply Filters', style: TextStyle(color: Colors.white)),
                onPressed: fetchAttendanceData,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsGrid() {
    double percentage = (stats['attendance_percentage'] ?? 0.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Overall Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Chip(
                label: Text('$percentage%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: percentage >= 75 ? Colors.green : Colors.orange,
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _statItem('Present', '${stats['present']}', Colors.green),
              _statItem('Absent', '${stats['absent']}', Colors.red),
              _statItem('Leave', '${stats['leave']}', Colors.orange),
              _statItem('Total Days', '${stats['total_days']}', Colors.indigo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String count, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildAttendanceCard(Map<String, dynamic> item) {
    String status = item['status'];
    Color badgeColor = status == 'Present' ? Colors.green : (status == 'Leave' ? Colors.orange : Colors.red);
    IconData statusIcon = status == 'Present' ? Icons.check_circle : (status == 'Leave' ? Icons.event_busy : Icons.cancel);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showAttendanceDetailModal(item),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: badgeColor.withOpacity(0.15),
                child: Icon(statusIcon, color: badgeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['formatted_date'] ?? 'N/A',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Entry Time: ${item['entry_time']} • ${item['verification_method']}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}