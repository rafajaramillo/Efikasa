import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
//import 'package:flutter_background_service_android/flutter_background_service_android.dart';

@pragma('vm:entry-point')

/// Inicializa y lanza el servicio en background
Future<void> initializeService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: true,
      isForegroundMode: true,
      initialNotificationTitle: 'Efikasa Alertas',
      initialNotificationContent: 'Verificando alertas...',
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onServiceStart,
      onBackground: onIosBackground,
    ),
  );
  service.startService();
}

/// Punto de arranque del servicio (Android e iOS foreground)
@pragma('vm:entry-point')
Future<bool> onServiceStart(ServiceInstance service) async {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Efikasa Alertas',
      content: 'Servicio de alertas activo',
    );
  }

  Timer.periodic(
    Duration(minutes: int.parse(dotenv.env['CHECK_INTERVAL_MIN'] ?? '3')),
    (_) {
      // Sólo llamamos si el State ya existió y asignó el puntero:
      if (_bgServiceState != null) {
        _bgServiceState!.fetchConsumptionData();
      }
    },
  );

  return true;
}

/// Callback para iOS (no necesita hacer nada extra)
Future<bool> onIosBackground(ServiceInstance service) async {
  // Nada especial, sólo devolvemos true
  return true;
}

_AlertasScreenState? _bgServiceState;

class AlertasScreen extends StatefulWidget {
  const AlertasScreen({super.key});

  @override
  _AlertasScreenState createState() => _AlertasScreenState();
}

class _AlertasScreenState extends State<AlertasScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Alertas Energéticas")),
      body: Column(
        children: [
          // Barra superior de iconos para seleccionar tipo de alerta
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                    icon: Icon(Icons.flash_on,
                        color: alertasActivas['picos_anomalos'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(0)),
                IconButton(
                    icon: Icon(Icons.access_time,
                        color: alertasActivas['encendido_prolongado'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(1)),
                IconButton(
                    icon: Icon(Icons.today,
                        color: alertasActivas['consumo_diario_alto'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(2)),
                IconButton(
                    icon: Icon(Icons.nightlight_round,
                        color: alertasActivas['consumo_nocturno'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(3)),
                IconButton(
                    icon: Icon(Icons.power,
                        color: alertasActivas['standby_prolongado'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(4)),
                IconButton(
                    icon: Icon(Icons.show_chart,
                        color: alertasActivas['caida_repentina'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(5)),
                IconButton(
                    icon: Icon(Icons.signal_wifi_off,
                        color: alertasActivas['ausencia_datos'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(6)),
                IconButton(
                    icon: Icon(Icons.eco,
                        color: alertasActivas['exceso_co2'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(7)),
                IconButton(
                    icon: Icon(Icons.warning_amber_rounded,
                        color: alertasActivas['sobreconsumo'] == true
                            ? Colors.green
                            : Colors.grey),
                    onPressed: () => setAlert(8)),
                IconButton(
                    icon: Icon(Icons.block, color: Colors.green),
                    onPressed: () => setAlert(9)),
              ],
            ),
          ),
          // Contenedor para el widget dinámico seleccionado
          Expanded(
            child: buildSelectedAlertWidget(selectedAlertIndex),
          ),
        ],
      ),
    );
  }

  // Método para actualizar el índice del widget seleccionado
  void setAlert(int index) {
    setState(() {
      selectedAlertIndex = index;
    });
  }

  // Método para devolver el widget correspondiente según el índice seleccionado
  Widget buildSelectedAlertWidget(int index) {
    switch (index) {
      case 0:
        return buildPicosAnomalosWidget();
      case 1:
        return buildEncendidoProlongadoWidget();
      case 2:
        return buildConsumoDiarioAltowidget();
      case 3:
        return buildConsumoNocturnoWidget();
      case 4:
        return buildStandbyProlongadoWidget();
      case 5:
        return buildCaidaRepentinaWidget();
      case 6:
        return buildAusenciaDatosWidget();
      case 7:
        return buildExcesoCO2Widget();
      case 8:
        return buildSobreConsumoWidget();
      case 9:
        return buildExclusionWidget();
      default:
        return Center(child: Text("Seleccione una alerta"));
    }
  }

  int selectedAlertIndex = 0;
  List<Map<String, dynamic>> alertas = [];
  List<String> devices = [];
  List<String> dispositivosExcluidos = [];
  bool alertasActivadas = false;
  Map<String, bool> alertasActivas = {};
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _bgServiceState = this;
    initializeService(); // <— Arranca el background service
    cargarDispositivosExcluidos(); // Carga la lista de dispositivos excluidos
    fetchDevices(); // Carga la lista de dispositivos disponibles
    loadAlertas(); // Carga las alertas previas desde almacenamiento local
    loadSwitchState(); // Carga el estado de activación de las alertas
    initNotifications(); // Inicializa las notificaciones en el dispositivo
    cargarEstadosDeAlertas(); // Carga el estado de activación de cada tipo de alerta
    iniciarMonitorizacion(); // Inicia el monitoreo continuo
    fetchConsumptionData(); // primera comprobación
    fetchConsumptionData(); // <— También en foreground
    _timer = Timer.periodic(
      Duration(
        minutes: int.parse(dotenv.env['CHECK_INTERVAL_MIN'] ?? '3'),
      ),
      (Timer t) => fetchConsumptionData(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> initNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(settings);
  }

  // Eliminar una alerta individual y persistir el cambio
  Future<void> removeAlerta(Map<String, dynamic> alerta) async {
    setState(() {
      alertas.remove(alerta);
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('alertas', json.encode(alertas));
  }

  // Método para guardar la lista de dispositivos excluidos de forma persistente
  void guardarDispositivosExcluidos(List<String> excluidos) async {
    setState(() {
      dispositivosExcluidos = excluidos;
    });
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dispositivos_excluidos', excluidos);
  }

  // Método para cargar el estado de activación general de alertas (alertasActivadas)
  Future<void> loadSwitchState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      alertasActivadas = prefs.getBool('alertas_activadas') ?? false;
    });
  }

  // Método para inicializar el plugin de notificaciones locales
/*   Future<void> initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  } */

  // Método para cargar las alertas previas desde almacenamiento local
  Future<void> loadAlertas() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? storedAlertas = prefs.getString('alertas');
    if (storedAlertas != null) {
      var decoded = json.decode(storedAlertas);
      if (decoded is List) {
        alertas = List<Map<String, dynamic>>.from(decoded);
      } else if (decoded is Map) {
        alertas = [Map<String, dynamic>.from(decoded)];
      }
    }
  }

  // Método para cargar la lista de dispositivos excluidos desde almacenamiento persistente
  void cargarDispositivosExcluidos() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      dispositivosExcluidos =
          prefs.getStringList('dispositivos_excluidos') ?? [];
    });
  }

// Método para cargar el estado de activación de cada tipo de alerta desde almacenamiento persistente
  void cargarEstadosDeAlertas() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      // Carga el estado de cada alerta, si no está definido, activa por defecto
      alertasActivas['picos_anomalos'] =
          prefs.getBool('picos_anomalos_activo') ?? true;
      alertasActivas['sobreconsumo'] =
          prefs.getBool('sobreconsumo_activo') ?? true;
      alertasActivas['picos_voltaje'] =
          prefs.getBool('picos_voltaje_activo') ?? true;
      alertasActivas['encendido_prolongado'] =
          prefs.getBool('encendido_prolongado_activo') ?? true;
      alertasActivas['consumo_nocturno'] =
          prefs.getBool('consumo_nocturno_activo') ?? true;
      alertasActivas['ausencia_datos'] =
          prefs.getBool('ausencia_datos_activo') ?? true;
      alertasActivas['standby_prolongado'] =
          prefs.getBool('standby_prolongado_activo') ?? true;
      alertasActivas['consumo_diario_alto'] =
          prefs.getBool('consumo_diario_alto_activo') ?? true;
      // Carga el estado para Caída Repentina de Consumo
      alertasActivas['caida_repentina'] =
          prefs.getBool('caida_repentina_activo') ?? true;
      // Carga el estado para Exceso de CO₂
      alertasActivas['exceso_co2'] = prefs.getBool('exceso_co2_activo') ?? true;
    });
  }

  // Método para cargar la lista de dispositivos desde Home Assistant
  Future<List<String>> fetchDevices() async {
    try {
      // Construye la URL para obtener todos los estados desde Home Assistant
      final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });

      // Verifica si la solicitud fue exitosa
      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        // Filtra solo los dispositivos tipo sensor con mediciones de energía
        return data
            .where((entity) =>
                entity["entity_id"].startsWith("sensor.") &&
                entity["entity_id"].contains("_power") &&
                !entity["entity_id"].contains("_power_factor"))
            .map<String>((entity) => entity["entity_id"] as String)
            .toList();
      }
    } catch (e) {
      //print("Error al cargar dispositivos: $e");
    }

    // Retorna una lista vacía en caso de error
    return [];
  }

// Método para obtener los datos históricos de consumo desde Home Assistant
  // Este método carga datos como consumo, media y desviación estándar para cada dispositivo
  Future<void> fetchConsumptionData() async {
    // Verifica si las alertas están activadas antes de proceder
    if (!alertasActivadas) return;
    // Obtiene la fecha actual para filtrar los datos del día
    DateTime now = DateTime.now();

    // → NUEVO paso A: comprueba ausencias de datos
    await _checkAusenciaDatos(now);

    // Formatea la fecha actual en el formato requerido por Home Assistant
    String today = DateFormat('yyyy-MM-dd').format(now);

    for (String device in devices) {
      // Omite los dispositivos que están en la lista de exclusión
      if (dispositivosExcluidos.contains(device)) continue;

      // Construye la URL para obtener los datos históricos de consumo
      final url = Uri.parse(
          "${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device");
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        List<dynamic> data = json.decode(response.body);
        // Lista para almacenar los consumos históricos para calcular la media y la desviación estándar
        List<double> consumos = [];
        // Variable para acumular el consumo de la última hora
        double lastHourEnergyWh = 0.0;
        double prevHourEnergyWh = 0.0;
        // Marca el inicio de encendido (primer valor >0)
        DateTime? inicioEncendido;
        // Calcula el tiempo hace una hora para filtrar los datos
        DateTime oneHourAgo = now.subtract(Duration(hours: 1));
        DateTime twoHoursAgo = now.subtract(Duration(hours: 2));

        // Procesa los datos si la respuesta no está vacía
        if (data.isNotEmpty) {
          for (var entry in data[0]) {
            // Convierte la fecha del estado a un objeto DateTime
            DateTime timestamp = DateTime.parse(entry["last_changed"]);
            // Solo considera los datos de la última hora
            // Convierte el estado a un valor numérico (W)
            double power = double.tryParse(entry["state"]) ?? 0.0;
            // Registra momento de encendido la primera vez que supera 0 W
            if (power > 0 && inicioEncendido == null) {
              inicioEncendido = timestamp;
            }
            if (timestamp.isAfter(oneHourAgo)) {
              // Acumula consumo para última hora (W·h)
              lastHourEnergyWh += power / 60;
              // Guarda muestra para cálculo de estadística
              consumos.add(power);
            } else if (timestamp.isAfter(twoHoursAgo)) {
              // Acumula consumo de la hora previa
              prevHourEnergyWh += power / 60;
            }
          }
        }

        // Calcula la media histórica y la desviación estándar
        // Calcula la media histórica del consumo
        double media = consumos.isNotEmpty
            ? consumos.reduce((a, b) => a + b) / consumos.length
            : 0.0;
        // Calcula la suma de las diferencias cuadradas para la desviación estándar
        double sumSquaredDiffs =
            consumos.fold(0.0, (sum, value) => sum + pow(value - media, 2));
        // Calcula la desviación estándar del consumo
        double desviacionEstandar =
            consumos.isNotEmpty ? sqrt(sumSquaredDiffs / consumos.length) : 0.0;
        // Guarda los datos históricos para usar en las alertas
        alertas.add({
          "device": device,
          "time": DateFormat('yyyy-MM-dd HH:mm').format(now),
          "last_hour_energy": lastHourEnergyWh,
          "prev_hour_energy": prevHourEnergyWh,
          "media_hist": media,
          "stddev_hist": desviacionEstandar,
          "inicio_encendido": (inicioEncendido ?? now).toIso8601String()
        });
      }
    }
  }

  /// 4. NUEVO MÉTODO para detección de AUSENCIA
  Future<void> _checkAusenciaDatos(DateTime now) async {
    int umbral = int.parse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15');

    for (String device in devices) {
      final url =
          Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states/$device');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json'
      });
      if (res.statusCode != 200) continue;

      final decoded = json.decode(res.body);
      DateTime lastChanged = DateTime.parse(decoded['last_changed']);
      int diffMin = now.difference(lastChanged).inMinutes;

      if (diffMin >= umbral) {
        // evita duplicados de ausencia
        bool existe = alertas
            .any((a) => a['device'] == device && a['tipo'] == 'ausencia');
        if (!existe) {
          final alerta = {
            'device': device,
            'time': DateFormat('yyyy-MM-dd HH:mm').format(lastChanged),
            'tipo': 'ausencia' // marcamos tipo ausencia
          };
          addAlerta(alerta);
          sendNotificationAusencia(device, lastChanged);
        }
      }
    }
  }

  /// 9. Limpia todo
  void clearAlertas() async {
    setState(() => alertas.clear());
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove('alertas');
  }

  /// 5. MODIFICADO: ahora addAlerta ya no filtra por energía,
  ///    recibe *cualquier* alerta (pico o ausencia)
  Future<void> addAlerta(Map<String, dynamic> alerta) async {
    setState(() => alertas.add(alerta));
    await saveAlertas();
  }

  Future<void> saveAlertas() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('alertas', json.encode(alertas));
  }

  /// 6. NOTIFICACIÓN IGUAL PARA PICOS
  Future<void> sendNotification(
      String device, DateTime time, double energy) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'canal_picos',
      'Alertas de Consumo',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Alerta de Consumo',
      'Dispositivo: $device\nFecha: '
          '${DateFormat('yyyy-MM-dd HH:mm').format(time)}\n'
          'Consumo: ${energy.toStringAsFixed(2)} Wh',
      notificationDetails,
    );
  }

  /// 7. NUEVO: notificación específica de ausencia
  Future<void> sendNotificationAusencia(
      String device, DateTime lastChanged) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'canal_ausencia',
      'Ausencia de Datos',
      importance: Importance.high,
      priority: Priority.high,
    );
    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      1,
      'Ausencia de Datos',
      'Dispositivo $device no reporta desde '
          '${DateFormat('yyyy-MM-dd HH:mm').format(lastChanged)}',
      notificationDetails,
    );
  }

  /// 8. Estadísticas históricas (sin cambios)
  Future<Map<String, double>> obtenerEstadisticasHistoricas(
      String deviceId) async {
    final influxUrl = dotenv.env['INFLUXDB_URL']!;
    final influxDB = dotenv.env['INFLUXDB_DB']!;
    final auth = base64Encode(utf8.encode(dotenv.env['INFLUXDB_AUTH']!));
    final days = int.parse(dotenv.env['INFLUXDB_ALERT_HISTORY_DAYS']!);
    DateTime now = DateTime.now();
    String since = now.subtract(Duration(days: days)).toUtc().toIso8601String();
    String query = "SELECT mean(\"value\") as avg_power FROM \"W\" "
        "WHERE (\"entity_id\" = '$deviceId') AND "
        "time >= '$since' GROUP BY time(1h)";
    final uri = Uri.parse(
        '$influxUrl/query?db=$influxDB&q=${Uri.encodeComponent(query)}');
    final res = await http.get(uri, headers: {'Authorization': 'Basic $auth'});
    if (res.statusCode != 200) {
      throw Exception('Error al obtener datos históricos');
    }
    final values = json.decode(res.body)['results'][0]['series'][0]['values']
        as List<dynamic>;
    List<double> hist = values
        .map((e) => double.tryParse(e[1].toString()) ?? 0.0)
        .where((v) => v > 0.0)
        .toList();
    if (hist.isEmpty) return {'media': 0.0, 'stddev': 0.0};
    double media = hist.reduce((a, b) => a + b) / hist.length;
    double varSum = hist.fold(0.0, (sum, v) => sum + pow(v - media, 2));
    double stddev = sqrt(varSum / hist.length);
    return {'media': media, 'stddev': stddev};
  }

  /// Mismo cuerpo de fetchConsumptionData pero sin setState ni acceso a UI

// Método para iniciar el monitoreo continuo de las alertas
  void iniciarMonitorizacion() {
    // Si ya hay un temporizador activo, lo cancela para evitar duplicados
    _timer?.cancel();

    // Inicia un nuevo temporizador para verificar las alertas cada 3 minutos
    _timer = Timer.periodic(Duration(minutes: 3), (timer) {
      //print("Verificando alertas...");
      // Aquí puedes verificar cada tipo de alerta individualmente
      buildPicosAnomalosWidget();
      buildEncendidoProlongadoWidget();
      buildSobreConsumoWidget();
      buildConsumoDiarioAltowidget();
      buildConsumoNocturnoWidget();
      buildStandbyProlongadoWidget();
      buildCaidaRepentinaWidget();
      buildAusenciaDatosWidget();
    });
  }

// Método para guardar el estado de activación de cada tipo de alerta de forma persistente
// prefKey: clave usada en SharedPreferences (por ejemplo, 'picos_anomalos_activo')
// estado: nuevo valor de activación (true=activada, false=desactivada)
  Future<void> guardarEstadoAlerta(String prefKey, bool estado) async {
    // Determina la clave interna para controlar el switch en memoria
    String stateKey = prefKey.endsWith('_activo')
        ? prefKey.substring(0, prefKey.length - 7)
        : prefKey;

    // Guarda el estado en almacenamiento persistente
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(prefKey, estado);

    // Actualiza el estado en memoria y refresca la UI inmediatamente
    setState(() {
      alertasActivas[stateKey] = estado;
    });
  }

  Color getAlertaColor(String tipoAlerta) {
    return alertasActivas[tipoAlerta] ?? true ? Colors.green : Colors.grey;
  }

  // Widget para mostrar las alertas de Picos Anómalos
// Aplicando la fórmula: W_actual > μ_hist + 1.5σ
// Aplicando la fórmula: W_actual > μ_hist + 2σ (más sensible a cambios rápidos)
  Widget buildPicosAnomalosWidget() {
    List<Map<String, dynamic>> picosAnomalosAlertas = alertas.where((alerta) {
      // Verifica si el dispositivo está excluido
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Obtiene el consumo en la última hora
      double last = alerta['last_hour_energy'] ?? 0.0;
      double mu = alerta['media_hist'] ?? 0.0;
      double sd = alerta['stddev_hist'] ?? 0.0;
      double threshold = mu + 1.5 * sd; // μ + 1.5·σ

      return last > threshold; // filtrado correcto
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar las alertas de picos anómalos
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Picos Anómalos"),
          value: alertasActivas['picos_anomalos'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('picos_anomalos_activo', value);
          },
        ),
        // Lista de alertas de picos anómalos
        Expanded(
          child: ListView.builder(
            itemCount: picosAnomalosAlertas.length,
            itemBuilder: (context, index) {
              var alerta = picosAnomalosAlertas[index];
              double media = alerta['media_hist'] ?? 0.0;
              double stddev = alerta['stddev_hist'] ?? 0.0;
              double umbralHist = media + 1.5 * stddev;

              return Card(
                color: Colors.red[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    "Fecha y hora: ${alerta['time']}\n"
                    "Consumo última hora: ${alerta['last_hour_energy'].toStringAsFixed(2)} Wh\n"
                    "Media histórica: ${media.toStringAsFixed(2)} Wh\n"
                    "Desviación estándar: ${stddev.toStringAsFixed(2)} Wh\n"
                    "Umbral dinámico: ${umbralHist.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Sobreconsumo
  Widget buildSobreConsumoWidget() {
    List<Map<String, dynamic>> sobreConsumoAlertas = alertas.where((alerta) {
      // Verifica si el dispositivo está excluido
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Obtiene el consumo en la última hora
      double lastHourEnergy = alerta['last_hour_energy'] ?? 0.0;
      // Obtiene la media histórica del consumo

      // Retorna true solo si el consumo actual supera el umbral dinámico
      return lastHourEnergy > 0.0;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar las alertas de sobreconsumo
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Sobreconsumo"),
          value: alertasActivas['sobreconsumo'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('sobreconsumo_activo', value);
          },
        ),
        // Lista de alertas de sobreconsumo
        Expanded(
          child: ListView.builder(
            itemCount: sobreConsumoAlertas.length,
            itemBuilder: (context, index) {
              var alerta = sobreConsumoAlertas[index];
              double media = alerta['media_hist'] ?? 0.0;
              // Calcula la desviación estándar usando los datos históricos
              double desviacionEstandar = alerta['stddev_hist'] ?? 0.0;
              // Calcula el umbral dinámico para detectar sobreconsumo
              double umbralDinamico = media + (1.5 * desviacionEstandar);
              return Card(
                color: Colors.orange[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    "Fecha y hora: ${alerta['time']}"
                    '\n'
                    "Media histórica: ${alerta['media_hist']?.toStringAsFixed(2)} Wh"
                    '\n'
                    "Desviación estándar: ${alerta['stddev_hist']?.toStringAsFixed(2)} Wh"
                    '\n'
                    "Umbral dinámico: ${umbralDinamico.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para gestionar la exclusión de dispositivos
  Widget buildExclusionWidget() {
    return FutureBuilder<List<String>>(
      future: fetchDevices(), // Carga la lista de dispositivos disponibles
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Muestra un indicador de carga mientras se obtienen los dispositivos
          return Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          // Muestra un mensaje de error si no se pueden cargar los dispositivos
          return Center(child: Text("Error al cargar dispositivos"));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          // Muestra un mensaje si no se encontraron dispositivos
          return Center(child: Text("No se encontraron dispositivos"));
        } else {
          // Muestra la lista de dispositivos con casillas de verificación para exclusión
          List<String> dispositivos = snapshot.data!;
          return ListView.builder(
            itemCount: dispositivos.length,
            itemBuilder: (context, index) {
              String dispositivo = dispositivos[index];
              bool excluido = dispositivosExcluidos.contains(dispositivo);
              return CheckboxListTile(
                title: Text(dispositivo),
                value: excluido,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      dispositivosExcluidos.add(dispositivo);
                    } else {
                      dispositivosExcluidos.remove(dispositivo);
                    }
                    // Guarda la lista actualizada de dispositivos excluidos
                    guardarDispositivosExcluidos(dispositivosExcluidos);
                  });
                },
              );
            },
          );
        }
      },
    );
  }

  // Widget para mostrar las alertas de Consumo Nocturno
  Widget buildConsumoNocturnoWidget() {
    // Define las horas nocturnas desde .env
    int horaInicio = int.parse(dotenv.env['HORA_INICIO_NOCTURNO'] ?? '22');
    int horaFin = int.parse(dotenv.env['HORA_FIN_NOCTURNO'] ?? '6');
    DateTime now = DateTime.now();

    // Filtra alertas con consumo en horas nocturnas
    List<Map<String, dynamic>> consumoNocturnoAlertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Fecha de la medición
      DateTime time = DateTime.parse(alerta['time'] ?? now.toIso8601String());
      int hora = time.hour;
      bool esNocturno = (horaInicio <= hora || hora < horaFin);

      // Consumo en la última hora
      double lastHourEnergy = alerta['last_hour_energy'] ?? 0.0;
      return esNocturno && lastHourEnergy > 0.0;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar alertas de consumo nocturno
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Consumo Nocturno"),
          value: alertasActivas['consumo_nocturno'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('consumo_nocturno_activo', value);
          },
        ),
        // Lista de dispositivos con consumo nocturno
        Expanded(
          child: ListView.builder(
            itemCount: consumoNocturnoAlertas.length,
            itemBuilder: (context, index) {
              var alerta = consumoNocturnoAlertas[index];
              DateTime time = DateTime.parse(alerta['time']!);
              double energy = alerta['last_hour_energy'] ?? 0.0;

              return Card(
                color: Colors.indigo[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    "Fecha y hora: ${DateFormat('yyyy-MM-dd HH:mm').format(time)}"
                    '\n'
                    "Consumo última hora: ${energy.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Encendido Prolongado
// Detecta dispositivos que han estado encendidos por más tiempo del permitido
  Widget buildEncendidoProlongadoWidget() {
    // Filtra las alertas que cumplen con el criterio de encendido prolongado
    List<Map<String, dynamic>> encendidoProlongadoAlertas =
        alertas.where((alerta) {
      // Verifica si el dispositivo está excluido
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) {
        // Si el dispositivo está excluido, omite esta alerta
        return false;
      }

      // Verifica el tiempo total encendido del dispositivo
      DateTime inicioEncendido = DateTime.parse(
          alerta['inicio_encendido'] ?? DateTime.now().toString());
      Duration tiempoEncendido = DateTime.now().difference(inicioEncendido);
      // Definir el tiempo máximo permitido (8 horas por defecto)
      int maxHoras = int.parse(dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8');
      // Retorna true solo si el dispositivo ha estado encendido más tiempo del permitido
      return tiempoEncendido.inHours >= maxHoras;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar las alertas de encendido prolongado
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Encendido Prolongado"),
          value: alertasActivas['encendido_prolongado'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('encendido_prolongado_activo', value);
          },
        ),
        // Lista de alertas de encendido prolongado
        Expanded(
          child: ListView.builder(
            itemCount: encendidoProlongadoAlertas.length,
            itemBuilder: (context, index) {
              var alerta = encendidoProlongadoAlertas[index];
              return Card(
                color: Colors.blue[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    // Muestra detalles de la alerta
                    "Fecha de inicio: ${alerta['inicio_encendido']}"
                    '\n'
                    "Duración encendido: ${DateTime.now().difference(DateTime.parse(alerta['inicio_encendido'] ?? DateTime.now().toString())).inHours} horas"
                    '\n'
                    "Tiempo máximo permitido: ${dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8'} horas",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Consumo Diario Alto
  Widget buildConsumoDiarioAltowidget() {
    // Filtra las alertas de consumo diario alto
    List<Map<String, dynamic>> consumoDiarioAlertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      // Omite dispositivos excluidos
      if (dispositivosExcluidos.contains(deviceId)) return false;
      // Obtiene consumo diario registrado
      double consumoDiario = alerta['consumo_diario'] ?? 0.0;
      // Obtiene media histórica diaria o usa media_hist si no existe
      double media = alerta['media_hist_diario'] ?? alerta['media_hist'] ?? 0.0;
      // Obtiene desviación estándar diaria o usa stddev_hist si no existe
      double desviacionEstandar =
          alerta['stddev_hist_diario'] ?? alerta['stddev_hist'] ?? 0.0;
      // Calcula umbral dinámico: W_diario > μ_hist + 1.5σ
      double umbralDinamico = media + (1.5 * desviacionEstandar);
      return consumoDiario > umbralDinamico;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar alertas de consumo diario alto
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Consumo Diario Alto"),
          value: alertasActivas['consumo_diario_alto'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('consumo_diario_alto_activo', value);
          },
        ),
        // Lista de dispositivos con consumo diario alto
        Expanded(
          child: ListView.builder(
            itemCount: consumoDiarioAlertas.length,
            itemBuilder: (context, index) {
              var alerta = consumoDiarioAlertas[index];
              double consumoDiario = alerta['consumo_diario'] ?? 0.0;
              double media =
                  alerta['media_hist_diario'] ?? alerta['media_hist'] ?? 0.0;
              double desviacionEstandar =
                  alerta['stddev_hist_diario'] ?? alerta['stddev_hist'] ?? 0.0;
              double umbralDinamico = media + (1.5 * desviacionEstandar);

              return Card(
                color: Colors.yellow[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    "Consumo diario: ${consumoDiario.toStringAsFixed(2)} Wh"
                    '\n'
                    "Media histórica diaria: ${media.toStringAsFixed(2)} Wh"
                    '\n'
                    "Desviación estándar diaria: ${desviacionEstandar.toStringAsFixed(2)} Wh"
                    '\n'
                    "Umbral dinámico: ${umbralDinamico.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Caída Repentina de Consumo
  Widget buildCaidaRepentinaWidget() {
    // Filtra alertas donde el consumo actual cae más del 50% respecto al anterior
    List<Map<String, dynamic>> caidaAlertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Consumos horas consecutivas
      double current = alerta['last_hour_energy'] ?? 0.0;
      double previous = alerta['prev_hour_energy'] ?? 0.0;
      // Solo valida si hay un valor previo y la caída supera el 50%
      return previous > 0.0 && (current / previous) < 0.5;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar alertas de caída repentina
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Caída Repentina"),
          value: alertasActivas['caida_repentina'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('caida_repentina_activo', value);
          },
        ),
        // Lista de dispositivos con caída repentina
        Expanded(
          child: ListView.builder(
            itemCount: caidaAlertas.length,
            itemBuilder: (context, index) {
              var alerta = caidaAlertas[index];
              double current = alerta['last_hour_energy'] ?? 0.0;
              double previous = alerta['prev_hour_energy'] ?? 0.0;
              double percentage =
                  previous > 0.0 ? (current / previous) * 100 : 0.0;

              return Card(
                color: Colors.blueGrey[100],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "Previo: ${previous.toStringAsFixed(2)} Wh"
                    '\n'
                    "Actual: ${current.toStringAsFixed(2)} Wh"
                    '\n'
                    "Caída: ${percentage.toStringAsFixed(1)}%",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

// Widget para mostrar las alertas de Ausencia de Datos usando umbral en minutos
  Widget buildAusenciaDatosWidget() {
    // Lee umbral de ausencia en minutos desde .env, por defecto 15 minutos
    int umbralMinutos =
        int.parse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15');

    // Filtra solo los dispositivos cuya última lectura exceda el umbral de ausencia en minutos
    List<Map<String, dynamic>> ausenciaAlertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      // Omite dispositivos excluidos
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Parsea el timestamp del último reporte
      DateTime lastTime =
          DateTime.parse(alerta['time'] ?? DateTime.now().toIso8601String());
      // Calcula la diferencia en minutos desde la última lectura
      Duration diff = DateTime.now().difference(lastTime);
      // Marca alerta si la diferencia en minutos es mayor o igual al umbral
      return diff.inMinutes >= umbralMinutos;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar alertas de ausencia de datos
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Ausencia de Datos"),
          value: alertasActivas['ausencia_datos'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('ausencia_datos_activo', value);
          },
        ),
        // Lista de tarjetas para cada dispositivo sin datos recientes
        Expanded(
          child: ListView.builder(
            itemCount: ausenciaAlertas.length,
            itemBuilder: (context, index) {
              var alerta = ausenciaAlertas[index];
              // Parsea y calcula la diferencia de minutos nuevamente
              DateTime lastTime = DateTime.parse(alerta['time']);
              Duration diff = DateTime.now().difference(lastTime);

              return Card(
                color: Colors.teal[100],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "Último reporte: ${DateFormat('yyyy-MM-dd HH:mm').format(lastTime)}" +
                        "Hace: ${diff.inMinutes} minutos (umbral: $umbralMinutos min)",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Exceso de CO₂
// Detecta dispositivos cuyo consumo está correlacionado con un aumento de CO₂ estimado
  Widget buildExcesoCO2Widget() {
    // Lee umbral de CO₂ desde .env (ppm), valor por defecto 1000 ppm
    int umbralCO2 = int.parse(dotenv.env['UMBRAL_EXCESO_CO2_PPM'] ?? '1000');

    // Filtra las alertas que exceden el umbral de CO₂ estimado basado en consumo
    List<Map<String, dynamic>> co2Alertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      // Omite dispositivos excluidos
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Obtiene consumo de última hora (Wh)
      double energyWh = alerta['last_hour_energy'] ?? 0.0;
      // Estima CO₂ emitido: asume 0.5 gramos CO₂ por Wh
      double co2Grams = energyWh * 0.5;
      // Convierte gramos a ppm aproximado (simplificado): ppm = (co2Grams / 1_000_000) * 1_000_000
      double co2Ppm = co2Grams; // en este ejemplo directo en ppm equivalente

      // Retorna true si el ppm estimado supera el umbral
      return co2Ppm >= umbralCO2;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar alertas de exceso de CO₂
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Exceso de CO₂"),
          value: alertasActivas['exceso_co2'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('exceso_co2_activo', value);
          },
        ),
        // Lista de dispositivos con exceso de CO₂ estimado
        Expanded(
          child: ListView.builder(
            itemCount: co2Alertas.length,
            itemBuilder: (context, index) {
              var alerta = co2Alertas[index];
              String device = alerta['device'] ?? "Desconocido";
              double energyWh = alerta['last_hour_energy'] ?? 0.0;
              double co2Grams = energyWh * 0.5;

              return Card(
                color: Colors.green[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(device),
                  subtitle: Text(
                    "Consumo última hora: ${energyWh.toStringAsFixed(2)} Wh" +
                        "CO₂ estimado: ${co2Grams.toStringAsFixed(1)} ppm (umbral: $umbralCO2 ppm)",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Widget para mostrar las alertas de Standby Prolongado
// Detecta dispositivos que han estado consumiendo muy poco (0 < Wh < 1) en la última hora
  Widget buildStandbyProlongadoWidget() {
    // Filtra solo las alertas que cumplen con el criterio de “standby prolongado”
    List<Map<String, dynamic>> standbyAlertas = alertas.where((alerta) {
      // Obtiene el ID del dispositivo
      String deviceId = alerta['device'] ?? "";
      // Omite los dispositivos que el usuario haya excluido
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Toma el consumo total de la última hora (en Wh)
      double energy = alerta['last_hour_energy'] ?? 0.0;
      // “Standby” significa consumo pequeño pero no nulo: entre 0 y 1 Wh
      return energy > 0.0 && energy < 1.0;
    }).toList();

    return Column(
      children: [
        // Un switch para activar o desactivar estas alertas
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Standby Prolongado"),
          // Lee el estado guardado (o true por defecto)
          value: alertasActivas['standby_prolongado'] ?? true,
          onChanged: (value) {
            // Guarda el nuevo estado en memoria y en SharedPreferences
            guardarEstadoAlerta('standby_prolongado_activo', value);
          },
        ),

        // Muestra la lista de dispositivos en standby prolongado
        Expanded(
          child: ListView.builder(
            itemCount: standbyAlertas.length,
            itemBuilder: (context, index) {
              var alerta = standbyAlertas[index];
              double energy = alerta['last_hour_energy'] ?? 0.0;

              return Card(
                color: Colors.grey[300], // Color suave para standby
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  // Nombre del dispositivo (ID)
                  title: Text(alerta['device'] ?? "Desconocido"),
                  // Detalles de consumo y umbral
                  subtitle: Text(
                    "Consumo última hora: ${energy.toStringAsFixed(2)} Wh\n"
                    "Umbral standby (max 1 Wh)",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
