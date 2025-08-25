import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import './pages/login.dart';
import './pages/singup.dart';
import './pages/categorias.dart';
import './pages/dashboard_screen.dart';
import './pages/editprofile.dart';
import './pages/consejos.dart';
import './pages/about.dart';
import './pages/dispositivos.dart';
import './pages/registro_user.dart';
import './pages/password_recovery.dart';
import 'pages/historico_consumo.dart';
import 'pages/diario.dart';
import 'pages/alertas.dart';
import 'pages/tarifas.dart';
import 'pages/prediccion.dart';
import 'services/background_service_setup.dart';
import 'pages/estadisticas/estadisticas.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cargamos el archivo .env antes de correr la app
  try {
    await dotenv.load(fileName: ".env");
    print('✅ .env cargado: ${dotenv.env}');
  } catch (e) {
    print('❌ Error cargando .env: $e');
  }

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Aquí arrancamos y configuramos el servicio en segundo plano
  await initializeBackgroundService(); // función que vive en background_service_setup.dart

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      routes: {
        "/login": (context) => LoginPage(),
        "/singup": (context) => SingupPage(),
        "/categorias": (context) => CategoriasScreen(),
        "/dashboard": (context) => DashboardPage(),
        "/editprofile": (context) => EditUserScreen(),
        "/consejos": (context) => ConsejosScreen(),
        "/about": (context) => AboutScreen(),
        "/dispositivos": (context) => DispositivosScreen(),
        '/registro_user': (context) => RegistroUserPage(),
        '/recovery_pass': (context) => PasswordRecoveryPage(),
        '/historico': (context) => HistoricoConsumo(),
        '/diario': (context) => OnOffScreen(),
        '/alertas': (context) => AlertasScreen(),
        '/tarifas': (context) => TarifasScreen(),
        '/PrediccionConsumo': (context) => PrediccionConsumo(),
        '/estadisticas': (context) => EstadisticasScreen(),

        // (route) => false,
      },
      initialRoute: '/login',
    );
  }
}
