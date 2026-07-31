// screens/profil_admin_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../utils/constants.dart';

class ProfilAdminScreen extends StatefulWidget {
  const ProfilAdminScreen({super.key});

  @override
  State<ProfilAdminScreen> createState() => _ProfilAdminScreenState();
}

class _ProfilAdminScreenState extends State<ProfilAdminScreen> {
  bool _isEditingEmail = false;
  bool _isEditingName = false;
  bool _isLoading = false;
  final _emailCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _emailCtrl.text = auth.user?.mail ?? '';
    _nameCtrl.text = auth.user?.fullName ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      resizeToAvoidBottomInset: true, // pour gérer le clavier
      backgroundColor: AppColors.white,
      appBar: AppBar(
        backgroundColor: AppColors.turquoise,
        elevation: 0,
        title: const Text(
          'Mon Profil',
          style: TextStyle(
            color: AppColors.darkBlue,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.darkBlue),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // Avatar
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.turquoise,
                      child: const Icon(
                        Icons.person_outline,
                        size: 40,
                        color: AppColors.darkBlue,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              // ─── Full Name ───
              _buildLabel('Complete name'),
              const SizedBox(height: 8),
              _isEditingName
                  ? _buildEditField(
                      _nameCtrl,
                      'Your name',
                      Icons.person_outline,
                    )
                  : _buildDisplayField(auth.user?.fullName ?? 'Not defined'),
              const SizedBox(height: 8),
              _buildEditButton(
                isEditing: _isEditingName,
                onEdit: () => setState(() {
                  _isEditingName = true;
                  _isEditingEmail = false;
                  _error = null;
                }),
                onSave: () => _saveField('name', _nameCtrl.text.trim()),
              ),
              const SizedBox(height: 24),
              // ─── Email ───
              _buildLabel('Email address'),
              const SizedBox(height: 8),
              _isEditingEmail
                  ? _buildEditField(
                      _emailCtrl,
                      'new@email.com',
                      Icons.email_outlined,
                    )
                  : _buildDisplayField(auth.user?.mail ?? 'Not defined'),
              const SizedBox(height: 8),
              _buildEditButton(
                isEditing: _isEditingEmail,
                onEdit: () => setState(() {
                  _isEditingEmail = true;
                  _isEditingName = false;
                  _error = null;
                }),
                onSave: () => _saveField('email', _emailCtrl.text.trim()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.red, fontSize: 13),
                ),
              ],
              const SizedBox(height: 32), // Espace avant le bouton
              // Déconnexion
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    await auth.logout();
                    if (mounted) {
                      context.go('/login');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.red,
                    foregroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'DÉCONNEXION',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40), // Espace en bas pour le scroll
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: AppColors.darkBlue.withOpacity(0.5),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildDisplayField(String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: AppColors.darkBlue,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEditField(
    TextEditingController ctrl,
    String hint,
    IconData icon,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: AppColors.darkBlue, fontSize: 16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.darkBlue.withOpacity(0.4)),
          prefixIcon: Icon(icon, color: AppColors.darkBlue.withOpacity(0.4)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildEditButton({
    required bool isEditing,
    required VoidCallback onEdit,
    required VoidCallback onSave,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: _isLoading ? null : (isEditing ? onSave : onEdit),
        child: _isLoading && isEditing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                isEditing ? 'Save' : 'Edit',
                style: TextStyle(
                  color: AppColors.turquoise,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
      ),
    );
  }

  Future<void> _saveField(String field, String value) async {
    if (value.isEmpty) {
      setState(() => _error = 'Required field');
      return;
    }
    if (field == 'mail' && (!value.contains('@') || !value.contains('.'))) {
      setState(() => _error = 'Invalid email');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final success = await auth.updateProfile(
      fullName: field == 'name' ? value : null,
      mail: field == 'mail' ? value : null,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        if (success) {
          _isEditingName = false;
          _isEditingEmail = false;
        } else {
          _error = auth.error ?? 'Error updating profile';
        }
      });
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }
}
