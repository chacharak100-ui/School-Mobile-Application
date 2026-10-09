import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import '../../config/app_config.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart'; // Import File Picker
import 'package:url_launcher/url_launcher.dart';

class StudentAssignmentsScreen extends StatefulWidget {
  final String? username;
  const StudentAssignmentsScreen({super.key, this.username});

  @override
  State<StudentAssignmentsScreen> createState() => _StudentAssignmentsScreenState();
}

class _StudentAssignmentsScreenState extends State<StudentAssignmentsScreen> {
  bool _isLoading = true;
  List<dynamic> _assignments = [];
  Map<String, dynamic> _filters = {}; 
  Map<String, dynamic> _stats = {};
  
  // Active Filters
  String _selectedSubject = 'All';
  String _selectedStatus = 'All';
  String _selectedTeacher = 'All';
  String _selectedSort = 'newest';
  
  late String _activeUsername;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initUser();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() {}); // Refresh countdowns dynamically
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _initUser() async {
    if (widget.username != null && widget.username!.isNotEmpty) {
      _activeUsername = widget.username!;
    } else {
      final prefs = await SharedPreferences.getInstance();
      _activeUsername = prefs.getString('username') ?? prefs.getString('std_id') ?? '';
    }
    _fetchAssignments();
  }

  Future<void> _fetchAssignments() async {
    setState(() => _isLoading = true);
    try {
      final url = Uri.parse(AppConfig.getUrl('/api/student/assignments')).replace(queryParameters: {
        'username': _activeUsername,
        'subject': _selectedSubject,
        'status': _selectedStatus,
        'teacher': _selectedTeacher,
        'sort': _selectedSort,
      });

      final response = await http.get(url).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            _assignments = data['assignments'] ?? [];
            _filters = data['filters'] ?? {};
            _stats = data['stats'] ?? {};
            _isLoading = false;
          });
        } else {
          setState(() => _isLoading = false);
          _showError(data['message'] ?? "Failed to load assignments");
        }
      } else {
        setState(() => _isLoading = false);
        _showError("Server error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showError("Failed to load assignments");
    }
  }

  Future<void> _viewAttachment(String? filename) async {
    if (filename == null || filename.isEmpty) {
      _showError("No attachment provided for this assignment");
      return;
    }
    
    final urlStr = AppConfig.getUrl('/api/student/view-assignment-file/$filename');
    final uri = Uri.parse(urlStr);
    
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showError("Could not open the attachment file");
      }
    } catch (e) {
      _showError("Error opening file: $e");
    }
  }

  // --- NEW: Pick File from Manager with Validation ---
  Future<void> _pickAndSubmit(String assignId) async {
    try {
      // Open File Manager
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'xls', 'xlsx'], // Only these types
      );

      if (result != null && result.files.single.path != null) {
        final File file = File(result.files.single.path!);
        final int fileSize = await file.length();

        // Check Size (Max 2MB = 2 * 1024 * 1024 bytes)
        if (fileSize > 2 * 1024 * 1024) {
          _showError("File size exceeds 2MB limit. Please choose a smaller file.");
          return;
        }

        // Confirm Upload
        bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Confirm Submission"),
            content: Text("Upload '${result.files.single.name}' (${(fileSize / 1024).toStringAsFixed(1)} KB)?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Upload")),
            ],
          ),
        ) ?? false;

        if (confirm) {
          await _submitAssignment(assignId, file);
        }
      }
    } catch (e) {
      _showError("Error picking file: $e");
    }
  }

  Future<void> _submitAssignment(String assignId, File file) async {
    // Show Loading Indicator
    showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));

    try {
      final url = Uri.parse(AppConfig.getUrl('/api/student/submit-assignment'));
      var request = http.MultipartRequest('POST', url);
      
      request.fields['username'] = _activeUsername;
      request.fields['assignment_id'] = assignId;
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      // Close Loading
      if (mounted) Navigator.of(context).pop();

      final data = jsonDecode(response.body);
      
      if (data['success'] == true) {
        _showSuccess("Submitted Successfully!");
        _fetchAssignments(); 
      } else {
        _showError(data['message'] ?? "Submission failed");
      }
    } catch (e) {
      // Close Loading
      if (mounted) Navigator.of(context).pop();
      _showError("Upload failed: $e");
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  String _getTimeLeft(String? dueDateStr) {
    if (dueDateStr == null) return "";
    try {
      final due = DateTime.parse(dueDateStr);
      final now = DateTime.now();
      final diff = due.difference(now);
      
      if (diff.isNegative) return "Expired";
      
      final days = diff.inDays;
      final hours = diff.inHours % 24;
      final minutes = diff.inMinutes % 60;
      
      if (days > 0) return "${days}d ${hours}h left";
      if (hours > 0) return "${hours}h ${minutes}m left";
      return "${minutes}m left";
    } catch (e) {
      return "";
    }
  }

  String _getTeacherDisplayName() {
    if (_selectedTeacher == 'All') return 'All';
    final teachers = _filters['teachers'] as List? ?? [];
    for (var t in teachers) {
      if (t is Map && t['id'].toString() == _selectedTeacher) {
        return t['name'].toString();
      }
    }
    return _selectedTeacher;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text("Assignments"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(_stats['total']?.toString() ?? '0', "Total", Colors.blue),
                      _buildStatItem(_stats['submitted']?.toString() ?? '0', "Done", Colors.green),
                      _buildStatItem(_stats['pending']?.toString() ?? '0', "Pending", Colors.orange),
                    ],
                  ),
                ),
                
                // Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      _buildFilterChip("Subject", _selectedSubject, _filters['subjects'] ?? [], (val) {
                        setState(() => _selectedSubject = val);
                        _fetchAssignments();
                      }),
                      const SizedBox(width: 8),
                      _buildFilterChip("Teacher", _getTeacherDisplayName(), _filters['teachers'] ?? [], (val) {
                        setState(() => _selectedTeacher = val);
                        _fetchAssignments();
                      }),
                      const SizedBox(width: 8),
                      _buildFilterChip("Status", _selectedStatus, ['All', 'Pending', 'Submitted', 'Expired'], (val) {
                        setState(() => _selectedStatus = val);
                        _fetchAssignments();
                      }),
                      const SizedBox(width: 8),
                      _buildFilterChip("Sort", _selectedSort, ['Newest', 'Due Soon', 'Oldest'], (val) {
                        setState(() => _selectedSort = val.toLowerCase().replaceAll(' ', '_'));
                        _fetchAssignments();
                      }),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: _assignments.isEmpty
                      ? const Center(child: Text("No assignments found"))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _assignments.length,
                          itemBuilder: (context, index) {
                            final item = _assignments[index];
                            return _buildAssignmentCard(item);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatItem(String count, String label, Color color) {
    return Column(
      children: [
        Text(count, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildFilterChip(String label, String selectedDisplay, List<dynamic> options, Function(String) operatorOnSelected) {
    bool isTeacherFilter = label == "Teacher";

    return PopupMenuButton<String>(
      onSelected: operatorOnSelected,
      itemBuilder: (context) {
        List<PopupMenuItem<String>> menuItems = [
          const PopupMenuItem(value: 'All', child: Text('All'))
        ];
        
        for (var e in options) {
          if (isTeacherFilter && e is Map) {
            menuItems.add(PopupMenuItem(
              value: e['id'].toString(), 
              child: Text(e['name'].toString())
            ));
          } else {
            menuItems.add(PopupMenuItem(
              value: e.toString(), 
              child: Text(e.toString())
            ));
          }
        }
        return menuItems;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("$label: $selectedDisplay", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentCard(dynamic item) {
    final bool isSubmitted = item['is_submitted'] ?? false;
    final bool isExpired = item['is_expired'] ?? false;
    final String statusColor = isSubmitted ? '0xFF10B981' : (isExpired ? '0xFFEF4444' : '0xFF3B82F6');
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        border: Border(left: BorderSide(color: Color(int.parse(statusColor)), width: 4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Color(int.parse(statusColor)).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(item['subject_name'] ?? '', style: TextStyle(color: Color(int.parse(statusColor)), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Text(_getTimeLeft(item['due_date']), style: TextStyle(fontSize: 11, color: isExpired ? Colors.red : Colors.grey[600], fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            
            // Title & Desc
            Text(item['title'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 4),
            Text(item['description'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
            
            const SizedBox(height: 12),
            
            // Meta
            Row(
              children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(item['due_date']?.split('T')[0] ?? 'N/A', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(width: 12),
                Icon(Icons.star, size: 12, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text("${item['total_marks'] ?? 0} Marks", style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Teacher
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)),
              child: Row(
                children: [
                  CircleAvatar(radius: 12, backgroundColor: Color(int.parse(statusColor)), child: const Icon(Icons.person, size: 12, color: Colors.white)),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['teacher_name'] ?? 'Unknown', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      Text("Assigned: ${item['date_created']?.split('T')[0] ?? ''}", style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                    ],
                  )
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Actions
            if (isSubmitted)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text("Submitted Successfully", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))),
              )
            else if (isExpired)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Center(child: Text("Submission Closed", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _viewAttachment(item['attachment_path']),
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text("View Task"),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.grey[700]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _pickAndSubmit(item['assignment_id']),
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text("Submit"),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}