import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_config.dart';

class StudentTimetableScreen extends StatefulWidget {
  final String username;
  const StudentTimetableScreen({super.key, required this.username});

  @override
  State<StudentTimetableScreen> createState() => _StudentTimetableScreenState();
}

class _StudentTimetableScreenState extends State<StudentTimetableScreen> {
  bool isLoading = true;
  
  // Data Storage
  Map<String, List<dynamic>> _timetableData = {}; // Day -> List of Periods
  List<String> _allDays = [];
  List<String> _allStaffList = []; // Global list for reference
  
  // Filters
  String? _selectedDay;
  String? _selectedStaffFilter;

  @override
  void initState() {
    super.initState();
    fetchTimetableData();
  }

  Future<void> fetchTimetableData() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Resolve ID exactly like Attendance API
      final identifier = prefs.getString('std_id') ?? 
                         prefs.getString('username') ?? 
                         widget.username;

      if (identifier == null) throw Exception("User identifier not found");

      final url = Uri.parse(await AppConfig.getUrl('/api/student/timetable'));
      
      // Pass identifier as query param
      final response = await http.get(
        url.replace(queryParameters: {'std_id': identifier}),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['success']) {
          setState(() {
            // 1. Parse Days
            _allDays = List<String>.from(data['config']['days']);
            if (_allDays.isNotEmpty) {
              // Keep current selection if valid, else default to first
              if (_selectedDay == null || !_allDays.contains(_selectedDay)) {
                _selectedDay = _allDays[0];
              }
            }

            // 2. Parse Global Staff List (for reference)
            _allStaffList = List<String>.from(data['filters']['staff_list']);

            // 3. Parse Timetable Structure
            Map<String, dynamic> rawTable = data['timetable'];
            _timetableData = {};
            
            rawTable.forEach((day, entries) {
              _timetableData[day] = List<dynamic>.from(entries);
            });
            
            isLoading = false;
          });
        } else {
           throw Exception(data['message'] ?? 'Failed to load data');
        }
      } else {
        throw Exception('Server Error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Timetable Fetch Exception: $e');
      setState(() => isLoading = false);
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetFilters() {
    setState(() {
      _selectedStaffFilter = null;
    });
  }

  // Get staff list specific to the SELECTED DAY for better filtering UX
  List<String> get _daySpecificStaffList {
    if (_selectedDay == null || !_timetableData.containsKey(_selectedDay)) return [];
    
    Set<String> staffSet = {};
    for (var period in _timetableData[_selectedDay]!) {
      String staff = period['staff_name'];
      if (staff != 'Not Assigned' && staff.isNotEmpty) {
        staffSet.add(staff);
      }
    }
    return staffSet.toList()..sort();
  }

  List<dynamic> get _filteredPeriods {
    if (_selectedDay == null || !_timetableData.containsKey(_selectedDay)) return [];
    
    List<dynamic> dayPeriods = _timetableData[_selectedDay]!;
    
    if (_selectedStaffFilter == null || _selectedStaffFilter!.isEmpty) {
      return dayPeriods;
    } else {
      return dayPeriods.where((p) {
        String staff = p['staff_name'] ?? '';
        return staff == _selectedStaffFilter;
      }).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Class Timetable', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(widget.username, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Data',
            onPressed: fetchTimetableData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Color.fromRGBO(110, 115, 225, 1)))
          : RefreshIndicator(
              onRefresh: fetchTimetableData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildFilterSection(),
                  const SizedBox(height: 16),
                  
                  // Header for List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$_selectedDay Schedule',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${_filteredPeriods.length} Periods',
                          style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  _filteredPeriods.isEmpty
                      ? Container(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade200, style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.event_busy, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 10),
                              Text('No classes found.', style: TextStyle(color: Colors.grey.shade600)),
                              if (_selectedStaffFilter != null)
                                TextButton(onPressed: _resetFilters, child: const Text("Clear Filter"))
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredPeriods.length,
                          itemBuilder: (context, index) {
                            return _buildPeriodCard(_filteredPeriods[index]);
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
                const Icon(Icons.filter_list, color: Color.fromRGBO(110, 115, 225, 1)),
                const SizedBox(width: 8),
                const Text('Filters', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Day Selector
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    value: _selectedDay,
                    decoration: const InputDecoration(
                      labelText: 'Day',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    items: _allDays.map((day) => DropdownMenuItem(value: day, child: Text(day))).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedDay = val;
                        _selectedStaffFilter = null; // Reset staff filter when day changes
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                // Staff Filter (Dynamic based on Day)
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedStaffFilter,
                    hint: const Text("Filter by Teacher"),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      suffixIcon: _selectedStaffFilter != null 
                        ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: _resetFilters)
                        : null,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text("All Teachers")),
                      ..._daySpecificStaffList.map((staff) => DropdownMenuItem(value: staff, child: Text(staff))).toList(),
                    ],
                    onChanged: (val) => setState(() => _selectedStaffFilter = val),
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
    bool isBreak = entry['is_break'] ?? false;
    
    // Styling based on type
    Color cardBg = isBreak ? Colors.orange.shade50 : Colors.white;
    Color borderColor = isBreak ? Colors.orange.shade200 : Colors.grey.shade200;
    Color accentColor = isBreak ? Colors.orange : const Color.fromRGBO(110, 115, 225, 1);
    IconData icon = isBreak ? Icons.coffee : Icons.book;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time Column
            Container(
              width: 65,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  Text(
                    _formatTime(entry['time_from']), 
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                  ),
                  const Icon(Icons.arrow_downward, size: 12, color: Colors.grey),
                  Text(
                    _formatTime(entry['time_to']), 
                    style: const TextStyle(fontSize: 12, color: Colors.grey)
                  ),
                ],
              ),
            ),
            
            VerticalDivider(width: 20, thickness: 1, color: Colors.grey.shade300),
            
            // Details Column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 18, color: accentColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          entry['subject'] ?? 'Free Period',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "P${entry['period_number']}",
                          style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  
                  if (!isBreak) ...[
                    Text("${entry['staff_name'] ?? 'Not Assigned'}", 
                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                        ),
                    const SizedBox(height: 2),
                    Text("Room: ${entry['room'] ?? 'N/A'}", 
                        style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                      ),
                  ] else ...[
                    Text("Break / Lunch Time", 
                         style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.orange[800])),
                  ]
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
    // Handle HH:MM:SS or HH:MM
    if (s.length >= 5) return s.substring(0, 5);
    return s;
  }
}