// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/employee_provider.dart';
import 'package:go_router/go_router.dart';
import '../models/employee.dart';
import '../utils/constants.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        context.read<EmployeeProvider>().loadEmployees();
      }
    });
  }

  void _showAddEmployeeDialog(BuildContext context) {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final roleCtrl = TextEditingController();
    final idCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Add Employee',
          style: TextStyle(
            color: AppColors.darkBlue,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          // Pour éviter l'overflow
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(
                  hintText: 'Bracelet ID',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: firstNameCtrl,
                decoration: const InputDecoration(
                  hintText: 'First Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Last Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: roleCtrl,
                decoration: const InputDecoration(
                  hintText: 'Role / Job',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.work),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (idCtrl.text.trim().isEmpty ||
                  firstNameCtrl.text.trim().isEmpty ||
                  lastNameCtrl.text.trim().isEmpty ||
                  roleCtrl.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please fill all fields')),
                );
                return;
              }

              final success = await context
                  .read<EmployeeProvider>()
                  .addEmployee(
                    idCtrl.text.trim(),
                    firstNameCtrl.text.trim(),
                    lastNameCtrl.text.trim(),
                    roleCtrl.text.trim(),
                  );

              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Employee added successfully')),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to add employee')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.turquoise,
              foregroundColor: AppColors.darkBlue,
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EmployeeProvider>();

    return Scaffold(
      resizeToAvoidBottomInset: true, // Pour gérer le clavier
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.turquoise,
        elevation: 0,
        toolbarHeight: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddEmployeeDialog(context),
        backgroundColor: AppColors.turquoise,
        child: const Icon(Icons.add, color: AppColors.darkBlue),
      ),
      body: Column(
        children: [
          // Header - fixe en haut
          Container(
            color: AppColors.turquoise,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Text(
                  'Employees',
                  style: TextStyle(
                    color: AppColors.darkBlue,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.lightGray,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => provider.search(v),
                    style: TextStyle(color: AppColors.darkBlue),
                    decoration: InputDecoration(
                      hintText: 'Search employees...',
                      hintStyle: TextStyle(
                        color: AppColors.darkBlue.withOpacity(0.4),
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: AppColors.darkBlue.withOpacity(0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Liste - avec padding ajusté
          Expanded(
            child: provider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : provider.employees.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people_outline,
                          size: 64,
                          color: AppColors.darkBlue.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No employees yet',
                          style: TextStyle(
                            color: AppColors.darkBlue.withOpacity(0.5),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap the + button to add',
                          style: TextStyle(
                            color: AppColors.darkBlue.withOpacity(0.3),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 16,
                      bottom: 80, // Plus d'espace en bas pour le clavier
                    ),
                    itemCount: provider.employees.length,
                    itemBuilder: (context, index) {
                      final emp = provider.employees[index];
                      return _EmployeeCard(
                        employee: emp,
                        onTap: () {
                          context.go('/employee/${emp.id}');
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.white,
        selectedItemColor: AppColors.turquoise,
        unselectedItemColor: AppColors.darkBlue.withOpacity(0.4),
        showSelectedLabels: false,
        showUnselectedLabels: false,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '/home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '/profil-admin',
          ),
        ],
        onTap: (index) {
          switch (index) {
            case 0:
              context.go('/home');
              break;
            case 1:
              context.go('/profil-admin');
              break;
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }
}

class _EmployeeCard extends StatelessWidget {
  final Employee employee;
  final VoidCallback onTap;

  const _EmployeeCard({required this.employee, required this.onTap});

  Color get _avatarColor {
    final colors = [
      AppColors.turquoise,
      const Color(0xFFA78BFA),
      const Color(0xFFFCD34D),
      const Color(0xFFF9A8D4),
      const Color(0xFF86EFAC),
    ];
    return colors[employee.fullName.hashCode % colors.length];
  }

  // couleur réelle depuis le backend
  Color get _statusColor {
    switch (employee.status) {
      case EmployeeStatus.online:
        return AppColors.green;
      case EmployeeStatus.away:
        return AppColors.yellow;
      case EmployeeStatus.offline:
        return AppColors.red;
    }
  }

  // label du statut
  String get _statusLabel {
    switch (employee.status) {
      case EmployeeStatus.online:
        return 'Online';
      case EmployeeStatus.away:
        return 'Away';
      case EmployeeStatus.offline:
        return 'Offline';
    }
  }

  // texte "Vu il y a X"
  String get _timeAgoText {
    final lastSeen = employee.lastSeen;
    if (lastSeen == null) return 'Never connected';

    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inSeconds < 60) {
      return 'Seen now';
    } else if (diff.inMinutes < 60) {
      return 'Seen ${diff.inMinutes} min ago';
    } else if (diff.inHours < 24) {
      return 'Seen ${diff.inHours} h ago';
    } else {
      final day = lastSeen.day.toString().padLeft(2, '0');
      final month = lastSeen.month.toString().padLeft(2, '0');
      final hour = lastSeen.hour.toString().padLeft(2, '0');
      final minute = lastSeen.minute.toString().padLeft(2, '0');
      return 'Vu le $day/$month à $hour:$minute';
    }
  }

  String get _initials {
    final parts = employee.fullName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return employee.fullName.substring(0, 2).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.lightGray,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: _avatarColor,
              child: Text(
                _initials,
                style: const TextStyle(
                  color: AppColors.darkBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    employee.fullName,
                    style: const TextStyle(
                      color: AppColors.darkBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),

                  Text(
                    employee.role,
                    style: TextStyle(
                      color: AppColors.darkBlue.withOpacity(0.5),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$_statusLabel · $_timeAgoText',
                        style: TextStyle(
                          color: AppColors.darkBlue.withOpacity(0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                print("Employee ID: '${employee.id}'");
                _showDeleteConfirmation(context, employee);
              },
              icon: Icon(Icons.delete_outline, color: Colors.red.shade300),
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, Employee employee) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Employee'),
        content: Text('Are you sure you want to delete ${employee.fullName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await context
                  .read<EmployeeProvider>()
                  .deleteEmployee(employee.id);
              if (success && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Employee deleted successfully'),
                  ),
                );
              } else if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Failed to delete employee')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
