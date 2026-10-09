import 'package:flutter/material.dart';

class AdminDashboard extends StatelessWidget {
  final String username;
  const AdminDashboard({super.key, required this.username});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Portal - $username'),
        backgroundColor: const Color.fromRGBO(110, 115, 225, 1),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome, Administrator',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: _buildAdminCards(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAdminCards(BuildContext context) {
    return [
      _dashboardCard(context, Icons.people, 'Manage Users', Colors.blue),
      _dashboardCard(context, Icons.school, 'School Settings', Colors.orange),
      _dashboardCard(context, Icons.payment, 'Fee Collection', Colors.green),
      _dashboardCard(context, Icons.assessment, 'Reports', Colors.purple),
    ];
  }

  Widget _dashboardCard(BuildContext context, IconData icon, String title, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title clicked')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}