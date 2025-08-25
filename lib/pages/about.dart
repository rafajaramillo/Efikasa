import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacementNamed(context, "/categorias");
          },
        ),
        title: const Text(
          "Acerca de...",
          style: TextStyle(color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 30),
            // Icono circular
            CircleAvatar(
              radius: 50,
              backgroundImage: AssetImage("assets/icons/efikasa_about.png"),
              backgroundColor: Colors.transparent,
            ),
            const SizedBox(height: 20),

            // Título de la App
            const Text(
              "EFIKASA APP INFO",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),

            // Versión de la App
            const Text(
              "ver. 1.0.0",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            // Opciones de la pantalla
            _buildOption(
                "Envíenos sus comentarios", "Ayúdenos a mejorar la APP"),
            _buildOption("Califique esta APP", "¡Su opinión nos importa!"),
            _buildOption("Visite nuestra Web", "Descubra más"),
            _buildOption("Licencia", "Detalles de Licencia"),

            const SizedBox(height: 30),

            // Copyright
            const Text(
              "Copyright Efikasa 2025",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // Widget para las opciones
  Widget _buildOption(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const Divider(),
        ],
      ),
    );
  }
}
