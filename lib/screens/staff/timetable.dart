import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StaffTimetableScreen extends StatefulWidget {
  final String username;
  const StaffTimetableScreen({super.key, required this.username});

  @override
  State<StaffTimetableScreen> createState() => _StaffTimetableScreenState();
}

class _StaffTimetableScreenState extends State<StaffTimetableScreen> {
  bool isLoading = true;
  
  // Data
  List<dynamic> _timetableList = [];
  List<Map<String, dynamic>> _classFilters = [];
  List<int> _periodFilters = [];
  String _currentDay = '';
  
  // Active Filters
  String? _selectedClassFilter; // Format: "Class-Section"
  int? _selectedPeriodFilter;

  @override
  void initState() {
    super.initState();
    fetchTimetableData();
  }

  Future<void> fetchTimetableData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token') ?? '';
      final storedUsername = prefs.getString('username') ?? '';
      
   
      final queryParams = <String, String>{
      'username': storedUsername,
      if (_selectedClassFilter != null && _selectedClassFilter!.contains('-')) ...{
        'class_name': _selectedClassFilter!.split('-')[0],
        'section': _selectedClassFilter!.split('-')[1],
      },
      if (_selectedPeriodFilter != null)
        'period_number': _selectedPeriodFilter.toString(),
      };
      
      final url = Uri.parse(AppConfig.getUrl('/api/staff/my-class'))
          .replace(queryParameters: {'username': storedUsername});



      final response = await http.get(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _timetableList = List<dynamic>.from(data['timetable']);
            _currentDay = data['config']['current_day'];
            
            // Parse Class Filters
            _classFilters = List<Map<String, dynamic>>.from(data['filters']['classes'])
                .map((c) => {"value": "${c['class']}-${c['section']}", "label": "${c['class']} - ${c['section']}"})
                .toList();
                
            // Parse Period Filters
            _periodFilters = List<int>.from(data['filters']['periods']);
            
            isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint("Timetable Error: $e");
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedClassFilter = null;
      _selectedPeriodFilter = null;
    });
    fetchTimetableData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Timetable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(_currentDay, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color(0xFF1A3A4F),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchTimetableData),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchTimetableData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildFilterSection(),
                  const SizedBox(height: 16),
                  
                  if (_timetableList.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          children: [
                            Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text('No classes scheduled for this filter.', 
                                 style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _timetableList.length,
                      itemBuilder: (context, index) {
                        return _buildPeriodCard(_timetableList[index]);
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildFilterSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Color(0xFF1A3A4F)),
                const SizedBox(width: 8),
                const Text('Filters', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const Spacer(),
                TextButton(
                  onPressed: _resetFilters,
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                )
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Class Filter
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _selectedClassFilter,
                    hint: const Text("All Classes"),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String>(value: null, child: Text("All Classes")),
                      ..._classFilters.map((c) => DropdownMenuItem<String>(value: c['value'].toString(),child: Text(c['label'].toString()),)).toList(),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedClassFilter = val);
                      fetchTimetableData();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Period Filter
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<int>(
                    value: _selectedPeriodFilter,
                    hint: const Text("Per."),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<int>(value: null, child: Text("All")),
                      ..._periodFilters.map((p) => DropdownMenuItem(value: p, child: Text("P$p"))).toList(),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedPeriodFilter = val);
                      fetchTimetableData();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodCard(Map<String, dynamic> entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Time Column
            Container(
              width: 60,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Text(_formatTime(entry['time_from']), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const Icon(Icons.arrow_downward, size: 12, color: Colors.grey),
                  Text(_formatTime(entry['time_to']), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            VerticalDivider(width: 20, thickness: 1, color: Colors.grey.shade300),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF1A3A4F), borderRadius: BorderRadius.circular(4)),
                        child: Text("P${entry['period_number']}", style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(entry['subject'] ?? 'Free Period', 
                             style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text("🏫 ${entry['class_name']} - ${entry['section']}", style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                  Text("📍 Room: ${entry['room'] ?? '-'}", style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic timeStr) {
    if (timeStr == null) return '--:--';
    String s = timeStr.toString();
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }
}