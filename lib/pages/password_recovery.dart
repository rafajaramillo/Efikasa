import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final TextEditingController emailController = TextEditingController();
  bool isLoading = false;

  // Función para mostrar mensajes en un Popup
  void mostrarPopup(String mensaje, {bool esError = true}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          esError ? "Error" : "Éxito",
          style: TextStyle(color: esError ? Colors.red : Colors.green),
        ),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Aceptar"),
          ),
        ],
      ),
    );
  }

  // Función para enviar el email de recuperación
  Future<void> enviarCorreoRecuperacion() async {
    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance
          .sendPasswordResetEmail(email: emailController.text.trim());

      mostrarPopup(
        "Si el correo está registrado, recibirás un enlace de recuperación.",
        esError: false,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        mostrarPopup("No existe una cuenta con este correo.");
      } else if (e.code == 'invalid-email') {
        mostrarPopup("El formato del correo electrónico no es válido.");
      } else {
        mostrarPopup("Error: ${e.message}");
      }
    } catch (e) {
      mostrarPopup("Error inesperado: ${e.toString()}");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color.fromARGB(255, 34, 108, 112), // Fondo verde oscuro
      appBar: AppBar(
        title: const Text(
          "Recuperar Contraseña",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xff142047),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.lock_reset, size: 100, color: Colors.white),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white.withOpacity(0.9),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Ingresa tu correo electrónico",
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: "email@example.com",
                        ),
                      ),
                      const SizedBox(height: 20),
                      isLoading
                          ? const Center(
                              child:
                                  CircularProgressIndicator()) // Indicador de carga
                          : SizedBox(
                              width: double.infinity,
                              height: 50,
                              child: ElevatedButton(
                                onPressed: enviarCorreoRecuperacion,
                                style: ButtonStyle(
                                  backgroundColor:
                                      WidgetStateProperty.all<Color>(
                                          const Color(0xff142047)),
                                ),
                                child: const Text(
                                  'Enviar enlace',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "Volver al inicio de sesión",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
