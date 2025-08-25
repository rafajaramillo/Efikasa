import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegistroUserPage extends StatefulWidget {
  const RegistroUserPage({super.key});

  @override
  State<RegistroUserPage> createState() => _RegistroUserPageState();
}

class _RegistroUserPageState extends State<RegistroUserPage> {
  final correoController = TextEditingController();
  final nombreController = TextEditingController();
  final apellidoController = TextEditingController();
  final passwordController = TextEditingController();
  final repetirPasswordController = TextEditingController();
  final telefonoController = TextEditingController();
  bool obsPassword = true;
  bool obsRepetirPassword = true;
  bool isLoading = false;

  // Lista de códigos de país
  final List<Map<String, String>> codigosPaises = [
    {'nombre': 'Ecuador', 'codigo': '+593'}, // Default
    {'nombre': 'Argentina', 'codigo': '+54'},
    {'nombre': 'Bolivia', 'codigo': '+591'},
    {'nombre': 'Brasil', 'codigo': '+55'},
    {'nombre': 'Chile', 'codigo': '+56'},
    {'nombre': 'Colombia', 'codigo': '+57'},
    {'nombre': 'Paraguay', 'codigo': '+595'},
    {'nombre': 'Perú', 'codigo': '+51'},
    {'nombre': 'Uruguay', 'codigo': '+598'},
    {'nombre': 'Venezuela', 'codigo': '+58'},
    {'nombre': 'México', 'codigo': '+52'},
    {'nombre': 'EE.UU.', 'codigo': '+1'},
    {'nombre': 'Canadá', 'codigo': '+1'},
    {'nombre': 'España', 'codigo': '+34'},
    {'nombre': 'Italia', 'codigo': '+39'},
    {'nombre': 'Francia', 'codigo': '+33'},
    {'nombre': 'Alemania', 'codigo': '+49'},
  ];

  // Código de país seleccionado (inicialmente Ecuador)
  String codigoPaisSeleccionado = '+593';

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

  Future<void> registrarUsuario() async {
    setState(() {
      isLoading = true;
    });

    // Validar si las contraseñas coinciden
    if (passwordController.text != repetirPasswordController.text) {
      mostrarPopup("Contraseñas NO coinciden!");
      setState(() {
        isLoading = false;
      });
      return;
    }

    // Validar longitud de la contraseña
    if (passwordController.text.length < 6) {
      mostrarPopup("Contraseña debe tener mínimo 6 caracteres!");
      setState(() {
        isLoading = false;
      });
      return;
    }

    // Unificar código de país con número de teléfono
    String telefonoCompleto =
        "$codigoPaisSeleccionado${telefonoController.text}";

    try {
      // Crear usuario en Firebase Authentication
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: correoController.text,
        password: passwordController.text,
      );

      // Obtener UID del usuario creado
      String uid = userCredential.user!.uid;

      // Guardar datos en Firestore
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).set({
        'correo': correoController.text,
        'nombre': nombreController.text,
        'apellido': apellidoController.text,
        'telefono': telefonoCompleto, // Se guarda con el código de país
        'fecha_registro': FieldValue.serverTimestamp(), // Hora del servidor
      });

      // Mostrar mensaje de éxito
      mostrarPopup("Registro exitoso!", esError: false);

      // Redirigir a la pantalla de inicio de sesión después de 2 segundos
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pushReplacementNamed(context, '/login');
      });
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        mostrarPopup("Usuario ya existe!");
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
        title: const Text("Registro de Usuario",
            style: TextStyle(color: Colors.white)),
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
                const Icon(Icons.person_add, size: 100, color: Colors.white),
                const SizedBox(height: 20),
                RegistroForm(
                  correoController: correoController,
                  nombreController: nombreController,
                  apellidoController: apellidoController,
                  passwordController: passwordController,
                  repetirPasswordController: repetirPasswordController,
                  telefonoController: telefonoController,
                  obsPassword: obsPassword,
                  obsRepetirPassword: obsRepetirPassword,
                  togglePasswordVisibility: () {
                    setState(() {
                      obsPassword = !obsPassword;
                    });
                  },
                  toggleRepetirPasswordVisibility: () {
                    setState(() {
                      obsRepetirPassword = !obsRepetirPassword;
                    });
                  },
                  codigoPaisSeleccionado: codigoPaisSeleccionado,
                  onCodigoPaisChanged: (nuevoCodigo) {
                    setState(() {
                      codigoPaisSeleccionado = nuevoCodigo;
                    });
                  },
                ),
                const SizedBox(height: 20),
                isLoading
                    ? const CircularProgressIndicator()
                    : SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: registrarUsuario,
                          style: ButtonStyle(
                            backgroundColor: WidgetStateProperty.all<Color>(
                                const Color(0xff142047)),
                          ),
                          child: const Text(
                            'Registrar',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text(
                    "¿Ya tienes cuenta? Iniciar sesión",
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

class RegistroForm extends StatelessWidget {
  final TextEditingController correoController;
  final TextEditingController nombreController;
  final TextEditingController apellidoController;
  final TextEditingController passwordController;
  final TextEditingController repetirPasswordController;
  final TextEditingController telefonoController;
  final bool obsPassword;
  final bool obsRepetirPassword;
  final VoidCallback togglePasswordVisibility;
  final VoidCallback toggleRepetirPasswordVisibility;
  final String codigoPaisSeleccionado;
  final Function(String) onCodigoPaisChanged;

  const RegistroForm({
    super.key,
    required this.correoController,
    required this.nombreController,
    required this.apellidoController,
    required this.passwordController,
    required this.repetirPasswordController,
    required this.telefonoController,
    required this.obsPassword,
    required this.obsRepetirPassword,
    required this.togglePasswordVisibility,
    required this.toggleRepetirPasswordVisibility,
    required this.codigoPaisSeleccionado,
    required this.onCodigoPaisChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withOpacity(0.9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildTextField(
              "Correo", correoController, TextInputType.emailAddress, 50),
          buildTextField("Nombre", nombreController, TextInputType.text, 20),
          buildTextField(
              "Apellido", apellidoController, TextInputType.text, 20),

          // Contraseña
          buildPasswordField("Contraseña", passwordController, obsPassword,
              togglePasswordVisibility),

          // Repetir Contraseña
          buildPasswordField("Repetir Contraseña", repetirPasswordController,
              obsRepetirPassword, toggleRepetirPasswordVisibility),

          // Selector de Código de País + Teléfono
          const SizedBox(height: 10),
          const Text(
            "Teléfono",
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              // Dropdown para seleccionar código de país con banderas
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: codigoPaisSeleccionado,
                  onChanged: (String? nuevoCodigo) {
                    if (nuevoCodigo != null) {
                      onCodigoPaisChanged(nuevoCodigo);
                    }
                  },
                  items: [
                    {'bandera': '🇪🇨', 'codigo': '+593'}, // Ecuador (Default)
                    {'bandera': '🇦🇷', 'codigo': '+54'}, // Argentina
                    {'bandera': '🇧🇴', 'codigo': '+591'}, // Bolivia
                    {'bandera': '🇧🇷', 'codigo': '+55'}, // Brasil
                    {'bandera': '🇨🇱', 'codigo': '+56'}, // Chile
                    {'bandera': '🇨🇴', 'codigo': '+57'}, // Colombia
                    {'bandera': '🇵🇾', 'codigo': '+595'}, // Paraguay
                    {'bandera': '🇵🇪', 'codigo': '+51'}, // Perú
                    {'bandera': '🇺🇾', 'codigo': '+598'}, // Uruguay
                    {'bandera': '🇻🇪', 'codigo': '+58'}, // Venezuela
                    {'bandera': '🇲🇽', 'codigo': '+52'}, // México
                    {'bandera': '🇺🇸', 'codigo': '+1'}, // EE.UU.
                    {'bandera': '🇨🇦', 'codigo': '+1'}, // Canadá
                    {'bandera': '🇪🇸', 'codigo': '+34'}, // España
                    {'bandera': '🇮🇹', 'codigo': '+39'}, // Italia
                    {'bandera': '🇫🇷', 'codigo': '+33'}, // Francia
                    {'bandera': '🇩🇪', 'codigo': '+49'}, // Alemania
                  ].map<DropdownMenuItem<String>>((Map<String, String> pais) {
                    return DropdownMenuItem<String>(
                      value: pais['codigo'],
                      child: Row(
                        children: [
                          Text(pais['bandera'] ?? ''), // Muestra la bandera
                          const SizedBox(width: 10),
                          Text(pais['codigo'] ??
                              ''), // Muestra el código de país
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(width: 10),

              // Campo de texto para el número de teléfono
              Expanded(
                child: TextFormField(
                  controller: telefonoController,
                  keyboardType: TextInputType.phone,
                  maxLength: 15,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    counterText: "",
                    hintText: "Número de teléfono",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  // Método para construir los campos de texto
  Widget buildTextField(String label, TextEditingController controller,
      TextInputType inputType, int maxLength) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          keyboardType: inputType,
          maxLength: maxLength,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            counterText: "", // Oculta el contador de caracteres
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  // Método para construir los campos de contraseña
  Widget buildPasswordField(String label, TextEditingController controller,
      bool obscureText, VoidCallback toggleVisibility) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 5),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          maxLength: 60,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            counterText: "",
            suffixIcon: IconButton(
              icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
              onPressed: toggleVisibility,
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
