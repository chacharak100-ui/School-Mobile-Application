import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentAcademicScreen extends StatefulWidget {
  final String username;
  const StudentAcademicScreen({super.key, required this.username});

  @override
  State<StudentAcademicScreen> createState() => _StudentAcademicScreenState();
}

class _StudentAcademicScreenState extends State<StudentAcademicScreen> {
  bool isLoading = true;
  Map<String, dynamic>? recentAlert;
  List<dynamic> distinctExams = [];
  Map<String, dynamic> analytics = {
    'strongest_subject': 'N/A',
    'weakest_subject': 'N/A',
    'tracked_exams_count': 0
  };
  List<dynamic> marksHistory = [];
  
  String? selectedExamFilter = 'All Exams';

  @override
  void initState() {
    super.initState();
    fetchAcademicData();
  }

  Future<void> fetchAcademicData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('username') ?? prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/academic-marks'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'exam_name': selectedExamFilter,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          recentAlert = data['recent_alert'];
          distinctExams = data['distinct_exams'] ?? [];
          analytics = data['analytics'] ?? analytics;
          marksHistory = data['history'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      debugPrint('Academic Fetch Exception: $e');
      setState(() => isLoading = false);
    }
  }

  void _resetFilters() {
    setState(() {
      selectedExamFilter = 'All Exams';
    });
    fetchAcademicData();
  }

  void _showMarkDetailModal(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('${item['subject_name']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
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
                        const Icon(Icons.menu_book_rounded, size: 48, color: Color.fromRGBO(110, 115, 225, 1)),
                        const SizedBox(height: 8),
                        Text('${item['exam_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Text('Class: ${item['current_class']} (${item['section']}) • Session: ${item['session']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        const Divider(height: 24),
                      ],
                    ),
                  ),
                  _detailRow('Obtained Marks:', '${item['obtained_marks']} / ${item['total_marks']}'),
                  _detailRow('Passing Marks:', '${item['passing_marks']}'),
                  _detailRow('Percentage:', '${item['percentage']}%'),
                  _detailRow('Grade Assigned:', '${item['grade'] ?? 'N/A'}'),
                  _detailRow('Exam Date:', '${item['exam_date'] ?? 'N/A'}'),
                  _detailRow('Record Logged:', '${item['date_added'] ?? 'N/A'}'),
                  if (item['remark'] != null && item['remark'].toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('Teacher Remark:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                    const SizedBox(height: 4),
                    Text('${item['remark']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
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
      padding: const EdgeInsets.symmetric(vertical: 4.0),
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
    List<String> examDropdownItems = ['All Exams', ...distinctExams.map((e) => e.toString())];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Academic Marks & Reports'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: fetchAcademicData,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off),
            tooltip: 'Clear Filter',
            onPressed: _resetFilters,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchAcademicData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  if (recentAlert != null) ...[
                    _buildRecentAlertBanner(recentAlert!),
                    const SizedBox(height: 16),
                  ],
                  _buildAnalyticsSummaryCard(),
                  const SizedBox(height: 16),
                  _buildExamFilterDropdown(examDropdownItems),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Subject Marks Breakdown',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      Text('${marksHistory.length} Records', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  marksHistory.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: Text('No academic records found for this selection.')),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: marksHistory.length,
                          itemBuilder: (context, index) {
                            return _buildMarkRecordCard(marksHistory[index]);
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildRecentAlertBanner(Map<String, dynamic> alert) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade400),
      ),
      child: Row(
        children: [
          Icon(Icons.notification_important, color: Colors.amber.shade800, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Recent Exam Update!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown)),
                const SizedBox(height: 2),
                Text(alert['message'], style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Performance Intelligence (Last 3 Exams)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigo)),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Strongest Subject', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(analytics['strongest_subject'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Needs Improvement', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(analytics['weakest_subject'], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExamFilterDropdown(List<String> items) {
    return DropdownButtonFormField<String>(
      value: items.contains(selectedExamFilter) ? selectedExamFilter : 'All Exams',
      decoration: const InputDecoration(
        labelText: 'Filter by Exam Name',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.filter_list, color: Color.fromRGBO(110, 115, 225, 1)),
      ),
      items: items.map((ex) => DropdownMenuItem(value: ex, child: Text(ex))).toList(),
      onChanged: (val) {
        setState(() => selectedExamFilter = val);
        fetchAcademicData();
      },
    );
  }

  Widget _buildMarkRecordCard(Map<String, dynamic> item) {
    double percentage = (item['percentage'] ?? 0.0).toDouble();
    Color gradeColor = percentage >= 60 ? Colors.green : (percentage >= 33 ? Colors.orange : Colors.red);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showMarkDetailModal(item),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: gradeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item['grade'] ?? 'N/A',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: gradeColor),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['subject_name'],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${item['exam_name']} • Date: ${item['exam_date'] ?? 'N/A'}',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${item['obtained_marks']}/${item['total_marks']}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$percentage%',
                    style: TextStyle(color: gradeColor, fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}