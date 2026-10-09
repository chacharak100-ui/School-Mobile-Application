import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentLeaveScreen extends StatefulWidget {
  final String username;
  const StudentLeaveScreen({super.key, required this.username});

  @override
  State<StudentLeaveScreen> createState() => _StudentLeaveScreenState();
}

class _StudentLeaveScreenState extends State<StudentLeaveScreen> {
  bool isLoading = true;
  List<dynamic> leavesList = [];
  final _formKey = GlobalKey<FormState>();
  
  String _leaveType = 'Sick Leave';
  final TextEditingController _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;

  final List<String> _leaveTypes = ['Sick Leave', 'Casual Leave', 'Emergency Leave', 'Family Event'];

  @override
  void initState() {
    super.initState();
    _fetchLeaves();
  }

  Future<void> _fetchLeaves() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;
      
      final url = Uri.parse(AppConfig.getUrl('api/student/leaves')).replace(
        queryParameters: {'std_id': stdId},
      );
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          leavesList = data['leaves'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _submitLeave() async {
    if (!_formKey.currentState!.validate() || _startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select date range and fill all fields.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(AppConfig.getUrl('api/student/leaves'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'leave_type': _leaveType,
          'start_date': _startDate.toString().split(' ')[0],
          'end_date': _endDate.toString().split(' ')[0],
          'reason': _reasonController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        _reasonController.clear();
        setState(() {
          _startDate = null;
          _endDate = null;
        });
        Navigator.pop(context);
        _fetchLeaves();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Leave application submitted successfully!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to submit leave.'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Network error occurred.'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  void _showApplyModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Apply for Leave', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _leaveType,
                    decoration: InputDecoration(labelText: 'Leave Type', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: _leaveTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                    onChanged: (val) => setState(() => _leaveType = val!),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_startDate == null ? 'Start Date' : _startDate.toString().split(' ')[0]),
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (picked != null) setState(() => _startDate = picked);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(_endDate == null ? 'End Date' : _endDate.toString().split(' ')[0]),
                          onPressed: () async {
                            final picked = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: _startDate ?? DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                            if (picked != null) setState(() => _endDate = picked);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _reasonController,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: 'Reason for leave', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    validator: (val) => val == null || val.isEmpty ? 'Please enter a reason' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _isSubmitting ? null : _submitLeave,
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Application', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    if (status == 'Accepted') return Colors.green;
    if (status == 'Rejected') return Colors.red;
    return Colors.amber.shade800;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color.fromRGBO(110, 115, 225, 1);
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Requests'), backgroundColor: primaryColor),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Apply Leave', style: TextStyle(color: Colors.white)),
        onPressed: _showApplyModal,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchLeaves,
              child: leavesList.isEmpty
                  ? const Center(child: Text('No leave history found.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: leavesList.length,
                      itemBuilder: (context, index) {
                        final item = leavesList[index];
                        final statusColor = _getStatusColor(item['status']);
                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(item['leave_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                      child: Text(item['status'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('From: ${item['start_date']}  To: ${item['end_date']}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                                const Divider(height: 16),
                                Text('Reason: ${item['reason']}', style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 6),
                                Text('Admin Remark: ${item['admin_remark']}', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12, color: Colors.grey.shade700)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}