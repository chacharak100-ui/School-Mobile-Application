import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ParentDashboard extends StatefulWidget {
  final String username;
  const ParentDashboard({super.key, required this.username});

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _ParentDashboardState extends State<ParentDashboard> {
  bool isLoading = true;
  List<dynamic> students = [];
  Map<String, dynamic>? selectedStudent;
  final storage = const FlutterSecureStorage();
  
  // Base URL for your Flask backend (Change to your actual server IP/port)
  final String baseUrl = "https://mizora.aksoftware.info"; 

  @override
  void initState() {
    super.initState();
    _fetchChildrenData();
  }

  Future<void> _fetchChildrenData() async {
    try {
      String? token = await storage.read(key: 'jwt_token');
      final response = await http.get(
        Uri.parse('$baseUrl/api/parent/dashboard'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          setState(() {
            students = data['students'];
            if (students.isNotEmpty) {
              selectedStudent = students[0]; // Default to first child
            }
            isLoading = false;
          });
        }
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Parent Portal - ${widget.username}'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : students.isEmpty
              ? const Center(child: Text("No children found linked to this account."))
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select Child:',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      
                      // --- HORIZONTAL SELECTABLE STUDENT CARDS (DIVS) ---
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: students.length,
                          itemBuilder: (context, index) {
                            var student = students[index];
                            bool isSelected = selectedStudent?['std_id'] == student['std_id'];

                            String? photoFilename = student['photo'];
                            String photoUrl = (photoFilename != null && photoFilename != 'None' && photoFilename.isNotEmpty)
                                ? '$baseUrl/view_photo/$photoFilename'
                                : '';

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  selectedStudent = student;
                                });
                              },
                              child: Container(
                                width: 90,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.indigo.shade50 : Colors.white,
                                  border: Border.all(
                                    color: isSelected ? Colors.indigo : Colors.grey.shade300,
                                    width: isSelected ? 2 : 1,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.grey.shade200,
                                      backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                                      child: photoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey) : null,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      student['student_name'] ?? 'Student',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 20),

                      // --- SELECTED STUDENT ACTIVE VIEW SUMMARY ---
                      if (selectedStudent != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.school, color: Colors.indigo),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedStudent!['student_name'] ?? '',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    'Class: ${selectedStudent!['current_class'] ?? 'N/A'} | ID: ${selectedStudent!['std_id']}',
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // --- GRID MENU OPTIONS FOR ACTIVE CHILD ---
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          children: [
                            _parentCard(context, Icons.person_pin, 'Profile Details', Colors.indigo, () {}),
                            _parentCard(context, Icons.assignment_turned_in, 'Attendance', Colors.teal, () {}),
                            _parentCard(context, Icons.receipt_long, 'Fee Vouchers', Colors.deepOrange, () {}),
                            _parentCard(context, Icons.notifications, 'Announcements', Colors.pink, () {}),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _parentCard(BuildContext context, IconData icon, String title, Color color, VoidCallback onTap) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 42, color: color),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}