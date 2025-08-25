import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class EditUserScreen extends StatefulWidget {
  const EditUserScreen({super.key});

  @override
  _EditUserScreenState createState() => _EditUserScreenState();
}

class _EditUserScreenState extends State<EditUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  File? _profileImage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// Carga el nombre completo y correo consultando el email en Firestore
  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final authEmail = user.email;
    String fullName = '';
    String email = authEmail ?? '';
    if (authEmail != null && authEmail.isNotEmpty) {
      try {
        final query = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: authEmail)
            .limit(1)
            .get();
        if (query.docs.isNotEmpty) {
          final data = query.docs.first.data();
          final firstName = data['firstName'] as String? ?? '';
          final lastName = data['lastName'] as String? ?? '';
          final dbEmail = data['email'] as String? ?? authEmail;
          fullName = '$firstName $lastName'.trim();
          email = dbEmail;
        }
      } catch (e) {
        // En caso de error, usar displayName como respaldo
        fullName = user.displayName ?? '';
      }
    }
    setState(() {
      _nameController.text = fullName;
      _emailController.text = email;
    });
  }

  Future<void> _pickImage() async {
    final imageFile =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (imageFile != null) {
      setState(() {
        _profileImage = File(imageFile.path);
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final newEmail = _emailController.text.trim();
    final newPassword = _passwordController.text;
    bool passwordChanged = false;
    try {
      // Actualizar correo en Auth si cambió
      if (newEmail.isNotEmpty && newEmail != user.email) {
        await user.updateEmail(newEmail);
      }
      // Actualizar contraseña en Auth si proporcionada
      if (newPassword.isNotEmpty) {
        await user.updatePassword(newPassword);
        passwordChanged = true;
      }
      // Actualizar email en Firestore si existe documento con UID
      try {
        final docRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        await docRef.update({'email': newEmail});
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Perfil actualizado exitosamente')));

      // Si la contraseña se cambió, cerrar sesión y volver a login
      if (passwordChanged) {
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al actualizar: $e')));
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacementNamed(context, "/categorias");
          },
        ),
        title: const Text('Editar Perfil'),
        actions: [
          IconButton(
            icon: _loading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.save),
            onPressed: _loading ? null : _saveProfile,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: GestureDetector(
                  onTap: _pickImage,
                  child: CircleAvatar(
                    radius: 50,
                    backgroundImage: _profileImage != null
                        ? FileImage(_profileImage!)
                        : null,
                    child: _profileImage == null
                        ? const Icon(Icons.person, size: 50)
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Nombre completo (no editable)
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nombre completo',
                  border: OutlineInputBorder(),
                ),
                readOnly: true,
              ),
              const SizedBox(height: 15),
              // Correo electrónico (editable)
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Ingresa un correo';
                  if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(v))
                    return 'Correo inválido';
                  return null;
                },
              ),
              const SizedBox(height: 15),
              // Nueva contraseña
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                validator: (v) {
                  if (v != null && v.isNotEmpty && v.length < 6) {
                    return 'La contraseña debe tener al menos 6 caracteres';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
