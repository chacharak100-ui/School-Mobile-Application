import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentComplaintsScreen extends StatefulWidget {
  final String username;
  const StudentComplaintsScreen({super.key, required this.username});

  @override
  State<StudentComplaintsScreen> createState() => _StudentComplaintsScreenState();
}

class _StudentComplaintsScreenState extends State<StudentComplaintsScreen> {
  bool isLoading = true;
  List<dynamic> complaintsList = [];
  final _formKey = GlobalKey<FormState>();

  String _complaintType = 'Academic Issue';
  final TextEditingController _descController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _types = ['Academic Issue', 'Infrastructure', 'Fee/Billing', 'Transport', 'Other'];

  @override
  void initState() {
    super.initState();
    _fetchComplaints();
  }

  Future<void> _fetchComplaints() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('/api/student/complaints?std_id=$stdId'));
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          complaintsList = data['complaints'] ?? [];
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _submitComplaint() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final stdId = prefs.getString('std_id') ?? widget.username;

      final url = Uri.parse(await AppConfig.getUrl('api/student/complaints'));
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'std_id': stdId,
          'complaint_type': _complaintType,
          'description': _descController.text.trim(),
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 201 && data['success'] == true) {
        _descController.clear();
        Navigator.pop(context);
        _fetchComplaints();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complaint filed successfully!'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Failed to file complaint.'), backgroundColor: Colors.red),
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

  void _showAddModal() {
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
                  const Text('Register Complaint / Query', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _complaintType,
                    decoration: InputDecoration(labelText: 'Category', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (val) => setState(() => _complaintType = val!),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _descController,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: 'Describe your issue in detail', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    validator: (val) => val == null || val.isEmpty ? 'Description is required' : null,
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color.fromRGBO(110, 115, 225, 1), padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: _isSubmitting ? null : _submitComplaint,
                    child: _isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('Submit Complaint', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color.fromRGBO(110, 115, 225, 1);
    return Scaffold(
      appBar: AppBar(title: const Text('Complaints & Support'), backgroundColor: primaryColor),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: primaryColor,
        icon: const Icon(Icons.support_agent, color: Colors.white),
        label: const Text('New Complaint', style: TextStyle(color: Colors.white)),
        onPressed: _showAddModal,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchComplaints,
              child: complaintsList.isEmpty
                  ? const Center(child: Text('No complaints registered yet.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: complaintsList.length,
                      itemBuilder: (context, index) {
                        final item = complaintsList[index];
                        final isResolved = item['status'] == 'Resolved';
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
                                    Text(item['complaint_type'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: (isResolved ? Colors.green : Colors.amber.shade800).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                      child: Text(item['status'], style: TextStyle(color: isResolved ? Colors.green : Colors.amber.shade800, fontWeight: FontWeight.bold, fontSize: 12)),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text('Logged on: ${item['created_at']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                const Divider(height: 16),
                                Text(item['description'], style: const TextStyle(fontSize: 14)),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.admin_panel_settings, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text('Resolution: ${item['resolve_note']}', style: const TextStyle(fontSize: 12, color: Colors.black87))),
                                    ],
                                  ),
                                ),
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