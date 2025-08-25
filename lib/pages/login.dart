import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    verificarSesion();
  }

  Future<void> verificarSesion() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? emailGuardado = prefs.getString('email');
    String? passwordGuardado = prefs.getString('password');

    if (emailGuardado != null && passwordGuardado != null) {
      await login(emailGuardado, passwordGuardado, true);
    }
  }

  Future<void> login(String email, String password, bool autoLogin) async {
    setState(() {
      isLoading = true;
    });

    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      SharedPreferences prefs = await SharedPreferences.getInstance();
      if (!autoLogin) {
        bool recordar = prefs.getBool('recordar') ?? false;
        if (recordar) {
          await prefs.setString('email', email);
          await prefs.setString('password', password);
        } else {
          await prefs.remove('email');
          await prefs.remove('password');
        }
      }

      // ignore: use_build_context_synchronously
      Navigator.pushReplacementNamed(context, '/categorias');
    } catch (e) {
      mostrarPopup("Usuario o Contraseña no válidos! \n Intente nuevamente!");
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void mostrarPopup(String mensaje) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Error", style: TextStyle(color: Colors.red)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 34, 108, 112),
      body: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Fondo(),
                const SizedBox(height: 20),
                Datos(onLogin: login),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class Datos extends StatefulWidget {
  final Function(String, String, bool) onLogin;

  const Datos({super.key, required this.onLogin});

  @override
  State<Datos> createState() => _DatosState();
}

class _DatosState extends State<Datos> {
  bool obs = true;
  bool recordar = false;
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;

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
          const Text(
            'Correo electrónico',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 5),
          TextFormField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Ingrese su correo',
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Contraseña',
            style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 5),
          TextFormField(
            controller: passwordController,
            obscureText: obs,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: 'Ingrese su contraseña',
              suffixIcon: IconButton(
                icon: Icon(obs ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  setState(() {
                    obs = !obs;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: recordar,
                onChanged: (value) async {
                  setState(() {
                    recordar = value!;
                  });
                  SharedPreferences prefs =
                      await SharedPreferences.getInstance();
                  prefs.setBool('recordar', recordar);
                },
              ),
              const Text("Recordarme", style: TextStyle(fontSize: 14)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, '/recovery_pass');
                },
                child: const Text(
                  "Olvidé mi contraseña",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.blue,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          isLoading
              ? const Center(child: CircularProgressIndicator())
              : SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onLogin(
                          emailController.text, passwordController.text, false);
                    },
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.all<Color>(
                          const Color(0xff142047)),
                    ),
                    child: const Text(
                      'Iniciar Sesión',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pushNamed(context, '/registro_user');
              },
              child: const Text(
                "¿No tienes cuenta? Regístrate!",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Fondo extends StatelessWidget {
  const Fondo({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        height: 200,
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/login.png"),
          ),
        ),
      ),
    );
  }
}
