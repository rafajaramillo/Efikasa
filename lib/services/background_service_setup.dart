import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'alertas_service.dart'; // Importa el servicio puro

const String BACKGROUND_TASK = "check_alertas";

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // 1) Carga .env
    await dotenv.load(fileName: ".env");
    // 2) Inicializa notificaciones
    await AlertasService.initNotifications();
    // 3) Pobla lista de dispositivos
    AlertasService.devices = await AlertasService.fetchDevices();
    // 4) Mismo timestamp para todas las comprobaciones
    final now = DateTime.now();
    // 5) Ejecuta todos los checks
    await AlertasService.checkPicosAnomalos(now);
    await AlertasService.checkEncendidoProlongado(now);
    await AlertasService.checkConsumoDiarioAlto(now);
    await AlertasService.checkConsumoNocturno(now);
    await AlertasService.checkStandbyProlongado(now);
    await AlertasService.checkAusenciaDatos(now);
    await AlertasService.checkExcesoCO2(now);
    return Future.value(true);
  });
}

Future<void> initializeBackgroundService() async {
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false,
  );
  Workmanager().registerPeriodicTask(
    "1",
    BACKGROUND_TASK,
    frequency: const Duration(minutes: 15),
    initialDelay: const Duration(seconds: 10),
  );
}
