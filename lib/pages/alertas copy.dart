import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

class AlertasScreen extends StatefulWidget {
  const AlertasScreen({super.key});

  @override
  AlertasScreenState createState() => AlertasScreenState();
}

class AlertasScreenState extends State<AlertasScreen> {
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
  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    cargarDispositivosExcluidos(); // Carga la lista de dispositivos excluidos
    fetchDevices(); // Carga la lista de dispositivos disponibles
    loadAlertas(); // Carga las alertas previas desde almacenamiento local
    loadSwitchState(); // Carga el estado de activación de las alertas
    initNotifications(); // Inicializa las notificaciones en el dispositivo
    cargarEstadosDeAlertas(); // Carga el estado de activación de cada tipo de alerta
    iniciarMonitorizacion(); // Inicia el monitoreo continuo
  }

  // -------------------------------
// Helper: parsea ISO UTC a DateTime local de forma segura
// -------------------------------
  DateTime _parseLocal(String? iso) {
    if (iso == null) return DateTime.now();
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return DateTime.now();
    }
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
  Future<void> initNotifications() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings);
    await flutterLocalNotificationsPlugin.initialize(initSettings);
  }

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

  /// Añade una alerta a la lista y la persiste en SharedPreferences
  Future<void> addAlerta(Map<String, dynamic> alerta) async {
    // 1) Normaliza last_hour_energy a String
    double energy = 0.0;
    if (alerta.containsKey('last_hour_energy')) {
      final raw = alerta['last_hour_energy'];
      if (raw is double) {
        energy = raw;
      } else if (raw is num) {
        energy = raw.toDouble();
      } else {
        energy = double.tryParse(raw?.toString() ?? '') ?? 0.0;
      }
    }
    // Guardamos siempre como String para evitar error de tipo
    alerta['last_hour_energy'] = energy.toStringAsFixed(2);

    // 2) Agrega la alerta en memoria **solo si el State aún está montado**
    if (mounted) {
      setState(() {
        alertas.add(alerta);
      });
    }

    // 3) Persiste en SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('alertas', json.encode(alertas));
  }

  /// Guarda la lista de alertas en SharedPreferences como JSON
  Future<void> saveAlertas() async {
    // 1) Obtiene la instancia de SharedPreferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    // 2) Convierte la lista de alertas a JSON String
    String encoded = json.encode(alertas);
    // 3) Almacena la cadena bajo la llave 'alertas'
    await prefs.setString('alertas', encoded);
  }

  /// Envía una notificación local cuando se detecta una alerta
  Future<void> sendNotification(
      String device, DateTime time, double energy) async {
    // 1) Configura detalles específicos para Android
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'channel_id', // ID del canal
      'Alertas de Consumo', // Nombre del canal
      importance: Importance.high, // Importancia alta para que salte la alerta
      priority: Priority.high, // Prioridad alta
    );
    // 2) Combina las configuraciones de Android (y de iOS si fuera necesario)
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    // 3) Construye el título y el cuerpo del mensaje
    String title = 'Alerta de Consumo';
    String body = 'Dispositivo: $device\n'
        'Fecha: ${DateFormat("yyyy-MM-dd HH:mm").format(time)}\n'
        'Consumo: ${energy.toStringAsFixed(2)} Wh';
    // 4) Muestra la notificación en el dispositivo
    await flutterLocalNotificationsPlugin.show(
      0, // ID de la notificación (puede ser dinámico)
      title, // Título
      body, // Cuerpo del mensaje
      details, // Detalles de plataforma
    );
  }

// Método para obtener los datos históricos de consumo desde Home Assistant
  // Este método carga datos como consumo, media y desviación estándar para cada dispositivo
  Future<void> fetchConsumptionData() async {
    // Verifica si las alertas están activadas antes de proceder
    if (!alertasActivadas) return;
    // Obtiene la fecha actual para filtrar los datos del día
    DateTime now = DateTime.now();
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

  /// Paso 3: Método para detectar Picos Anómalos en segundo plano
  /// Compara el consumo de la última hora vs. umbral histórico (μ + 1.5·σ)
// -------------------------------
// _checkPicosAnomalos corregido
// -------------------------------
  Future<void> checkPicosAnomalos() async {
    DateTime now = DateTime.now();
    String today = DateFormat('yyyy-MM-dd').format(now);

    for (String device in devices) {
      final url = Uri.parse(
          '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device');
      final res = await http.get(url, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;

      final data = json.decode(res.body) as List<dynamic>;
      double lastHourEnergyWh = 0.0;
      if (data.isNotEmpty) {
        DateTime oneHourAgo = now.subtract(Duration(hours: 1));
        for (var entry in data[0]) {
          DateTime ts = DateTime.parse(entry['last_changed']).toLocal();
          if (ts.isAfter(oneHourAgo)) {
            lastHourEnergyWh += (double.tryParse(entry['state']) ?? 0.0) / 60.0;
          }
        }
      }

      // sacar media y desviación estadística
      var stats = await obtenerEstadisticasHistoricasHA(
          device, int.parse(dotenv.env['HA_ALERT_HISTORY_DAYS'] ?? '7'));
      double umbral = (stats['media'] ?? 0.0) + 1.5 * (stats['stddev'] ?? 0.0);

      if (lastHourEnergyWh > umbral) {
        bool existe = alertas
            .any((a) => a['device'] == device && a['tipo'] == 'picos_anomalos');
        if (!existe) {
          final alerta = {
            'device': device,
            // Guardamos siempre en UTC para luego parsear localmente
            'time': now.toUtc().toIso8601String(),
            'last_hour_energy': lastHourEnergyWh,
            'media_hist': stats['media'],
            'stddev_hist': stats['stddev'],
            'tipo': 'picos_anomalos',
          };
          await addAlerta(alerta);
        }
      }
    }
  }

  // Mapa que almacena, para cada dispositivo, cuándo empezó a estar encendido
  final Map<String, DateTime> encendidoStartTimes = {};

  /// Paso 4: Chequeo de Encendido Prolongado en segundo plano
  /// Dispara alerta si un dispositivo ha estado encendido más tiempo del permitido
  Future<void> checkEncendidoProlongado() async {
    // 1) Límite de horas permitidas desde .env (por defecto 8 horas)
    final int maxHoras =
        int.tryParse(dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8') ?? 8;
    final DateTime now = DateTime.now();

    // 2) Consulta todos los estados de sensores
    final Uri uri = Uri.parse(
      '${dotenv.env['HOME_ASSISTANT_URL']}/api/states',
    );
    final http.Response res = await http.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      },
    );
    if (res.statusCode != 200) return;
    final List<dynamic> allStates = json.decode(res.body);

    // 3) Recorre solo sensores de potencia
    for (var entity in allStates) {
      final String id = entity['entity_id'] as String? ?? '';
      if (!id.startsWith('sensor.') || !id.endsWith('_power')) continue;

      // 4) Interpreta estado como potencia en W
      final double power =
          double.tryParse(entity['state']?.toString() ?? '') ?? 0.0;

      if (power > 0) {
        // 5) Si recién empieza, registra timestamp
        encendidoStartTimes.putIfAbsent(id, () => now);
        final DateTime inicio = encendidoStartTimes[id]!;

        // 6) Si supera el umbral, genera alerta y reinicia contador
        if (now.difference(inicio).inHours >= maxHoras) {
          final alerta = {
            'device': id,
            'inicio_encendido': inicio.toIso8601String(),
            'time': now.toIso8601String(),
            'tipo': 'encendido_prolongado',
          };
          await addAlerta(alerta);
          encendidoStartTimes[id] = now;
        }
      } else {
        // 7) Si está apagado, borra registro
        encendidoStartTimes.remove(id);
      }
    }
  }

  /// Obtiene media y desviación estándar de consumo histórico de un dispositivo
  /// usando el endpoint /api/history/period de Home Assistant (Nabu Casa).
  Future<Map<String, double>> obtenerEstadisticasHistoricasHA(
      String deviceId, int historyDays) async {
    // 1) Cálculo de fechas para el rango histórico
    final now = DateTime.now();
    final since = now.subtract(Duration(days: historyDays));
    // Función auxiliar para formatear ISO sin milisegundos
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z\$'), 'Z');

    // 2) Construcción de URI para la API de History
    final uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/${iso(since)}'
        '?filter_entity_id=$deviceId');

    // 3) Llamada HTTP con Bearer token
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) {
      throw Exception('Error histórico HA: ${res.statusCode}');
    }

    // 4) Decodificación de la respuesta JSON
    final decoded = json.decode(res.body) as List<dynamic>;
    // Tomamos la primera serie (deviceId) o lista vacía
    final series = (decoded.isNotEmpty && decoded[0] is List)
        ? List<Map<String, dynamic>>.from(decoded[0])
        : <Map<String, dynamic>>[];

    // 5) Recopilación de valores numéricos de potencia
    List<double> consumos = [];
    for (var point in series) {
      double p = double.tryParse(point['state']?.toString() ?? '') ?? 0.0;
      consumos.add(p);
    }

    // 6) Si no hay datos, retorna 0
    if (consumos.isEmpty) return {'media': 0.0, 'stddev': 0.0};

    // 7) Cálculo de media
    final media = consumos.reduce((a, b) => a + b) / consumos.length;
    // 8) Cálculo de desviación estándar
    final sumSq = consumos.fold(0.0, (s, v) => s + pow(v - media, 2));
    final stddev = sqrt(sumSq / consumos.length);

    return {'media': media, 'stddev': stddev};
  }

  /// Helper: estadísticas de consumo diario (Wh) de los últimos [historyDays] días
  Future<Map<String, double>> _statsConsumoDiarioHA(
      String deviceId, int historyDays) async {
    final now = DateTime.now();
    final since = now.subtract(Duration(days: historyDays));
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z\$'), 'Z');

    final uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/${iso(since)}'
        '?filter_entity_id=$deviceId');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) return {'media': 0.0, 'stddev': 0.0};

    final decoded = json.decode(res.body) as List<dynamic>;
    final series = (decoded.isNotEmpty && decoded[0] is List)
        ? List<Map<String, dynamic>>.from(decoded[0])
        : <Map<String, dynamic>>[];

    // Agrupa por fecha (YYYY-MM-DD)
    Map<String, List<Map<String, dynamic>>> porDia = {};
    for (var pt in series) {
      final timeStr = pt['last_changed'] as String?;
      if (timeStr == null) continue;
      final ts = DateTime.parse(timeStr);
      final diaKey = ts.toIso8601String().substring(0, 10);
      porDia.putIfAbsent(diaKey, () => []).add(pt);
    }

    // Calcula energía diaria (Wh) por trapezoidal
    List<double> diarios = [];
    porDia.forEach((dia, puntos) {
      puntos.sort((a, b) =>
          (a['last_changed'] as String).compareTo(b['last_changed'] as String));
      double totalWh = 0.0;
      for (int i = 1; i < puntos.length; i++) {
        final prev = puntos[i - 1];
        final curr = puntos[i];
        final t1 = DateTime.parse(prev['last_changed'] as String);
        final t2 = DateTime.parse(curr['last_changed'] as String);
        final dt = t2.difference(t1).inSeconds;
        final p1 = double.tryParse(prev['state']?.toString() ?? '') ?? 0.0;
        final p2 = double.tryParse(curr['state']?.toString() ?? '') ?? 0.0;
        totalWh += ((p1 + p2) / 2.0) * dt / 3600.0;
      }
      if (totalWh > 0) diarios.add(totalWh);
    });

    if (diarios.isEmpty) return {'media': 0.0, 'stddev': 0.0};
    final media = diarios.reduce((a, b) => a + b) / diarios.length;
    final sumSq = diarios.fold(0.0, (s, v) => s + pow(v - media, 2));
    final stddev = sqrt(sumSq / diarios.length);
    return {'media': media, 'stddev': stddev};
  }

  /// Paso 5: Chequeo de Consumo Diario Alto
  /// Dispara alerta si consumo del día supera μ_hist_diario + 1.5·σ_hist_diario
  Future<void> checkConsumoDiarioAlto() async {
    // 1) Inicio del día actual (00:00 local)
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);

    // 2) Recorre cada dispositivo de potencia
    for (String device in devices) {
      // 2.1) Llama al endpoint HA History para obtener datos de hoy
      final Uri uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/${todayStart.toIso8601String()}'
        '?filter_entity_id=$device',
      );
      final http.Response res = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
          'Content-Type': 'application/json',
        },
      );
      if (res.statusCode != 200) continue;

      // 2.2) Decodifica la serie de hoy para este device
      final List<dynamic> data = json.decode(res.body) as List<dynamic>;
      final List<Map<String, dynamic>> series =
          data.isNotEmpty && data[0] is List
              ? List<Map<String, dynamic>>.from(data[0])
              : <Map<String, dynamic>>[];

      // 3) Cálculo de energía diaria (Wh) usando trapezoidal
      double consumoTodayWh = 0.0;
      for (int i = 1; i < series.length; i++) {
        // Parseo seguro de timestamps y potencia
        DateTime t1 =
            DateTime.parse(series[i - 1]['last_changed'] as String).toLocal();
        DateTime t2 =
            DateTime.parse(series[i]['last_changed'] as String).toLocal();
        if (t1.isBefore(todayStart)) continue; // sólo a partir de las 00:00
        double p1 =
            double.tryParse(series[i - 1]['state']?.toString() ?? '') ?? 0.0;
        double p2 =
            double.tryParse(series[i]['state']?.toString() ?? '') ?? 0.0;
        int dt = t2.difference(t1).inSeconds;
        // Energía Wh = promedio(P1,P2)·dt[s] / 3600
        consumoTodayWh += ((p1 + p2) / 2.0) * dt / 3600.0;
      }

      // 4) Obtiene estadísticas históricas diarias (media y stddev)
      final int historyDays =
          int.tryParse(dotenv.env['HA_ALERT_HISTORY_DAYS'] ?? '7') ?? 7;
      final Map<String, double> stats =
          await _statsConsumoDiarioHA(device, historyDays);
      final double media = stats['media'] ?? 0.0;
      final double stddev = stats['stddev'] ?? 0.0;
      final double umbral = media + 1.5 * stddev;

      // 5) Genera alerta si supera umbral
      if (consumoTodayWh > umbral) {
        final alerta = {
          'device': device,
          'time': now.toIso8601String(),
          'consumo_diario': consumoTodayWh,
          'media_hist_diario': media,
          'stddev_hist_diario': stddev,
          'tipo': 'consumo_diario_alto',
        };
        await addAlerta(alerta);
      }
    }
  }

  /// Paso 6: Chequeo de Consumo Nocturno en segundo plano
  /// Dispara alerta si hay consumo (>0 Wh) durante el horario nocturno (entre HORA_INICIO_NOCTURNO y HORA_FIN_NOCTURNO)
  Future<void> checkConsumoNocturno() async {
    // 1) Lee horas nocturnas desde .env (start inclusive, end exclusive)
    final int horaInicio =
        int.parse(dotenv.env['HORA_INICIO_NOCTURNO'] ?? '22');
    final int horaFin = int.parse(dotenv.env['HORA_FIN_NOCTURNO'] ?? '6');
    final DateTime now = DateTime.now();
    final DateTime oneHourAgo = now.subtract(Duration(hours: 1));
    final String today = DateFormat('yyyy-MM-dd').format(now);

    // 2) Para cada dispositivo, consulta histórico de hoy
    for (String device in devices) {
      final Uri uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device',
      );
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;
      final List<dynamic> data = json.decode(res.body) as List<dynamic>;
      if (data.isEmpty || data[0] is! List) continue;

      // 3) Suma Wh de los puntos dentro de la última hora y en horario nocturno
      double nocturnalWh = 0.0;
      for (var entry in data[0]) {
        final String rawTs = entry['last_changed']?.toString() ?? '';
        DateTime ts;
        try {
          ts = DateTime.parse(rawTs).toLocal();
        } catch (_) {
          continue;
        }
        if (ts.isAfter(oneHourAgo) && ts.isBefore(now)) {
          final int h = ts.hour;
          final bool isNocturno = (horaInicio <= horaFin)
              ? (h >= horaInicio && h < horaFin)
              : (h >= horaInicio || h < horaFin);
          if (isNocturno) {
            final double p =
                double.tryParse(entry['state']?.toString() ?? '') ?? 0.0;
            nocturnalWh += p / 60.0; // convierte W·min -> Wh
          }
        }
      }

      // 4) Si hubo consumo nocturno, dispara alerta
      if (nocturnalWh > 0.0) {
        final alerta = {
          'device': device,
          'time': now.toLocal().toIso8601String(),
          'last_hour_energy': nocturnalWh,
          'tipo': 'consumo_nocturno',
        };
        await addAlerta(alerta);
      }
    }
  }

  /// Paso 7: Chequeo de Standby Prolongado
  /// Dispara alerta si un dispositivo registra consumo muy bajo (0 < Wh < umbral) en la última hora
  Future<void> checkStandbyProlongado(DateTime now) async {
    // Umbral máximo de consumo en standby (Wh) desde .env
    final double umbralStandby =
        double.tryParse(dotenv.env['UMBRAL_STANDBY_PROLONGADO_WH'] ?? '1') ??
            1.0;

    // Fecha de hoy en formato YYYY-MM-DD (local) para la consulta al History API
    String today = DateFormat('yyyy-MM-dd').format(now.toLocal());

    // Encabezados HTTP para autenticación Bearer en Home Assistant
    final headers = {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    };

    // Recorre cada dispositivo registrado
    for (String device in devices) {
      // Si la alerta está desactivada o el dispositivo está excluido, continua
      if (!(alertasActivas['standby_prolongado'] ?? true) ||
          dispositivosExcluidos.contains(device)) {
        continue;
      }

      // Construye URL History para la fecha de hoy y el dispositivo
      final uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today'
        '?filter_entity_id=$device',
      );
      final res = await http.get(uri, headers: headers);
      if (res.statusCode != 200) continue; // ignora errores de conexión

      // Decodifica la respuesta como lista de series de datos
      final data = json.decode(res.body) as List<dynamic>;
      double lastHourEnergy = 0.0;

      // Si hay datos, recorre los puntos de la última hora
      if (data.isNotEmpty && data[0] is List) {
        DateTime oneHourAgo = now.subtract(Duration(hours: 1));
        for (var entry in data[0]) {
          // Parseo seguro de la marca de tiempo y conversión a hora local
          DateTime ts;
          try {
            ts = DateTime.parse(entry['last_changed'] as String).toLocal();
          } catch (_) {
            continue;
          }
          // Si el punto está dentro de la última hora, acumula energía
          if (ts.isAfter(oneHourAgo)) {
            double p = double.tryParse(entry['state']?.toString() ?? '') ?? 0.0;
            // Convierto W·min a Wh
            lastHourEnergy += p / 60.0;
          }
        }
      }

      // Si el consumo está entre 0 y el umbral, genera la alerta
      if (lastHourEnergy > 0.0 && lastHourEnergy < umbralStandby) {
        bool existe = alertas.any(
            (a) => a['device'] == device && a['tipo'] == 'standby_prolongado');
        if (!existe) {
          final alerta = {
            'device': device,
            'standby_inicio': DateFormat('yyyy-MM-dd HH:mm')
                .format(now.toLocal()), // momento en que se disparó
            'time': DateFormat('yyyy-MM-dd HH:mm')
                .format(now.toLocal()), // para mostrar en UI
            'last_hour_energy': lastHourEnergy,
            'tipo': 'standby_prolongado',
          };
          await addAlerta(alerta);

          // También dispara notificación local
          const androidDetails = AndroidNotificationDetails(
            'canal_standby',
            'Standby Prolongado',
            importance: Importance.high,
            priority: Priority.high,
          );
          const notificationDetails =
              NotificationDetails(android: androidDetails);
          await flutterLocalNotificationsPlugin.show(
            2,
            'Alerta Standby Prolongado',
            'Dispositivo: $device\n'
                'Consumo última hora: ${lastHourEnergy.toStringAsFixed(2)} Wh',
            notificationDetails,
          );
        }
      }
    }
  }

  /// Paso 8: Chequeo de Caída Repentina
  /// Dispara alerta si el consumo de la última hora cae más del 50% vs la hora anterior
  Future<void> checkCaidaRepentina(DateTime now) async {
    // 1) Define los límites de las dos ventanas de 5 minutos:
    //    [now - 10min, now - 5min)  y  [now - 5min, now)
    DateTime tenMinAgo = now.subtract(Duration(minutes: 5));
    DateTime fiveMinAgo = now.subtract(Duration(minutes: 3));

    // 2) Recorre cada dispositivo si la alerta está activa y no excluido
    for (String device in devices) {
      if (!(alertasActivas['caida_repentina'] ?? true) ||
          dispositivosExcluidos.contains(device)) continue;

      // 3) Consulta histórico desde tenMinAgo
      String iso(DateTime dt) =>
          dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');
      final uri = Uri.parse(
          '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/${iso(tenMinAgo)}'
          '?filter_entity_id=$device');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;

      final data = json.decode(res.body) as List<dynamic>;
      final series = (data.isNotEmpty && data[0] is List)
          ? List<Map<String, dynamic>>.from(data[0])
          : <Map<String, dynamic>>[];

      double prevWindowWh = 0.0;
      double lastWindowWh = 0.0;

      // 4) Integra por trapecios, asignando a cada ventana
      for (int i = 1; i < series.length; i++) {
        final prev = series[i - 1];
        final curr = series[i];

        DateTime t1 = DateTime.parse(prev['last_changed'] as String);
        DateTime t2 = DateTime.parse(curr['last_changed'] as String);
        double p1 = double.tryParse(prev['state']?.toString() ?? '') ?? 0.0;
        double p2 = double.tryParse(curr['state']?.toString() ?? '') ?? 0.0;
        double avgP = (p1 + p2) / 2.0;
        int dtSec = t2.difference(t1).inSeconds;
        if (dtSec <= 0) continue;

        // 4a) Todo intervalo en la ventana previa (10–5 min)
        if (t2.isBefore(fiveMinAgo)) {
          prevWindowWh += avgP * dtSec / 3600.0;
        }
        // 4b) Todo en la última ventana (5–0 min)
        else if (t1.isAfter(fiveMinAgo) || t1.isAtSameMomentAs(fiveMinAgo)) {
          lastWindowWh += avgP * dtSec / 3600.0;
        }
        // 4c) Si cruza el límite, parte en ambas ventanas
        else {
          // de t1 a fiveMinAgo
          int secPrev = fiveMinAgo.difference(t1).inSeconds;
          prevWindowWh += avgP * secPrev / 3600.0;
          // de fiveMinAgo a t2
          int secLast = t2.difference(fiveMinAgo).inSeconds;
          lastWindowWh += avgP * secLast / 3600.0;
        }
      }

      // 5) Si la caída supera el 50%, agrega alerta y notifica
      if (prevWindowWh > 0 && (lastWindowWh / prevWindowWh) < 0.5) {
        bool existe = alertas.any(
            (a) => a['device'] == device && a['tipo'] == 'caida_repentina');
        if (!existe) {
          final alerta = {
            'device': device,
            'time': DateFormat('yyyy-MM-dd HH:mm').format(now),
            'prev_hour_energy': prevWindowWh,
            'last_hour_energy': lastWindowWh,
            'tipo': 'caida_repentina',
          };
          await addAlerta(alerta);

          // Notificación local
          const androidDetails = AndroidNotificationDetails(
            'canal_caida',
            'Caída Repentina',
            importance: Importance.high,
            priority: Priority.high,
          );
          const notificationDetails =
              NotificationDetails(android: androidDetails);
          await flutterLocalNotificationsPlugin.show(
            3,
            'Alerta de Caída Repentina',
            'Dispositivo: $device\n'
                'Previo (10–5 min): ${prevWindowWh.toStringAsFixed(2)} Wh\n'
                'Último (5–0 min): ${lastWindowWh.toStringAsFixed(2)} Wh',
            notificationDetails,
          );
        }
      }
    }
  }

  /// Paso 9: Chequeo de Ausencia de Datos
  /// Dispara alerta si no recibimos datos de un dispositivo en [umbralMinutos]
  Future<void> checkAusenciaDatos(DateTime now) async {
    // 1) Umbral de ausencia en minutos desde .env
    final int umbralMinutos =
        int.parse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15');

    // 2) Consulta el estado actual de todos los sensores
    final uri = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) return;
    final List<dynamic> allStates = json.decode(res.body);

    // 3) Recorre solo sensores de potencia
    for (var entity in allStates) {
      String id = entity['entity_id'] as String? ?? '';
      if (!id.startsWith('sensor.') || !id.endsWith('_power')) continue;
      if (dispositivosExcluidos.contains(id)) continue;
      if (!(alertasActivas['ausencia_datos'] ?? true)) continue;

      // 4) Parsea primero 'last_updated', si no existe, cae a 'last_changed'
      String? rawTime = entity['last_updated'] as String?;
      rawTime ??= entity['last_changed'] as String?;
      if (rawTime == null) continue;

      DateTime lastUtc;
      try {
        lastUtc = DateTime.parse(rawTime);
      } catch (_) {
        continue;
      }
      // Convierte UTC a local
      DateTime lastLocal = lastUtc.toLocal();

      // 5) Calcula diferencia con ahora (ambos en local)
      final diff = now.difference(lastLocal);

      // 6) Si supera el umbral, genera alerta
      if (diff.inMinutes >= umbralMinutos) {
        bool existe = alertas
            .any((a) => a['device'] == id && a['tipo'] == 'ausencia_datos');
        if (!existe) {
          final alerta = {
            'device': id,
            'time': lastLocal.toIso8601String(),
            'tipo': 'ausencia_datos',
          };
          await addAlerta(alerta);

          // 7) Notificación local
          const androidDetails = AndroidNotificationDetails(
            'canal_ausencia',
            'Ausencia de Datos',
            importance: Importance.high,
            priority: Priority.high,
          );
          const notificationDetails =
              NotificationDetails(android: androidDetails);
          await flutterLocalNotificationsPlugin.show(
            6,
            'Alerta Ausencia de Datos',
            'Dispositivo: $id\n'
                'Último reporte: ${DateFormat('yyyy-MM-dd HH:mm').format(lastLocal)}\n'
                'Hace: ${diff.inMinutes} minutos (umbral: $umbralMinutos min)',
            notificationDetails,
          );
        }
      }
    }
  }

  /// Paso 10: Chequeo de Exceso de CO₂
  /// Dispara alerta si la emisión de CO₂ en la última hora supera un umbral (kg)
  Future<void> checkExcesoCO2(DateTime now) async {
    // 1) Factor de emisión: kg CO₂ por kWh
    const double factorCO2 = 0.5; // 0.5 kg CO₂ / kWh
    // 2) Umbral de CO₂ en kg desde .env
    final double umbralCO2 = double.parse(dotenv.env['UMBRAL_CO2_KG'] ?? '1.0');

    // 3) Consulta histórico de la última hora para cada dispositivo
    String today = DateFormat('yyyy-MM-dd').format(now);
    for (String device in devices) {
      if (!(alertasActivas['exceso_co2'] ?? true) ||
          dispositivosExcluidos.contains(device)) continue;

      final uri = Uri.parse(
          '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today'
          '?filter_entity_id=$device');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;
      final data = json.decode(res.body) as List<dynamic>;
      if (data.isEmpty) continue;

      // 4) Sumar Wh de la última hora
      DateTime oneHourAgo = now.subtract(Duration(hours: 1));
      double wh = 0.0;
      for (var entry in data[0]) {
        DateTime ts = DateTime.parse(entry['last_changed']);
        if (ts.isAfter(oneHourAgo)) {
          wh += (double.tryParse(entry['state']) ?? 0.0) / 60.0;
        }
      }
      // 5) Convertir a kg CO₂
      double kwh = wh / 1000.0;
      double co2kg = kwh * factorCO2;

      // 6) Si supera el umbral, alerta y notificación
      if (co2kg > umbralCO2) {
        bool existe = alertas
            .any((a) => a['device'] == device && a['tipo'] == 'exceso_co2');
        if (!existe) {
          final alerta = {
            'device': device,
            'time': DateFormat('yyyy-MM-dd HH:mm').format(now),
            'co2_kg': co2kg,
            'tipo': 'exceso_co2',
          };
          await addAlerta(alerta);
          // Notificación
          const androidDetails = AndroidNotificationDetails(
            'canal_co2',
            'Exceso de CO₂',
            importance: Importance.high,
            priority: Priority.high,
          );
          const notificationDetails =
              NotificationDetails(android: androidDetails);
          await flutterLocalNotificationsPlugin.show(
            7,
            'Alerta Exceso de CO₂',
            'Dispositivo: $device\nEmisión: ${co2kg.toStringAsFixed(2)} kg CO₂',
            notificationDetails,
          );
        }
      }
    }
  }

  /// Paso 11: Chequeo de Sobreconsumo Dinámico
  /// Dispara alerta si el consumo de la última hora supera μ_hist + 1.5·σ_hist
  Future<void> checkSobreconsumo(DateTime now) async {
    // Número de días históricos usados en el cálculo
    int historyDays = int.parse(dotenv.env['HA_ALERT_HISTORY_DAYS'] ?? '7');
    // Fecha de hoy en formato YYYY-MM-DD
    String today = DateFormat('yyyy-MM-dd').format(now);

    for (String device in devices) {
      // Omite si no está activa o dispositivo excluido
      if (!(alertasActivas['sobreconsumo'] ?? true) ||
          dispositivosExcluidos.contains(device)) continue;

      // 1) Consulta histórico de la última hora
      final uri = Uri.parse(
          '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today'
          '?filter_entity_id=$device');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;

      final data = json.decode(res.body) as List<dynamic>;
      if (data.isEmpty) continue;

      DateTime oneHourAgo = now.subtract(Duration(hours: 1));
      double lastHourWh = 0.0;
      for (var entry in data[0]) {
        DateTime ts = _parseLocal(entry['last_changed'] as String);
        if (ts.isAfter(oneHourAgo)) {
          double p = double.tryParse(entry['state']?.toString() ?? '') ?? 0.0;
          lastHourWh += p / 60.0;
        }
      }

      // 2) Obtiene estadísticas históricas (μ y σ)
      var stats = await obtenerEstadisticasHistoricasHA(device, historyDays);
      double umbral = stats['media']! + 1.5 * stats['stddev']!;

      // 3) Si supera el umbral, crea alerta
      if (lastHourWh > umbral) {
        bool existe = alertas
            .any((a) => a['device'] == device && a['tipo'] == 'sobreconsumo');
        if (!existe) {
          final alerta = {
            'device': device,
            // Guardamos ISO para parsear más tarde
            'time': now.toUtc().toIso8601String(),
            'last_hour_energy': lastHourWh,
            'media_hist': stats['media'],
            'stddev_hist': stats['stddev'],
            'tipo': 'sobreconsumo',
          };
          await addAlerta(alerta);
          // Opcional: enviar notificación local
          const androidDetails = AndroidNotificationDetails(
            'canal_sobreconsumo',
            'Sobreconsumo',
            importance: Importance.high,
            priority: Priority.high,
          );
          const notificationDetails =
              NotificationDetails(android: androidDetails);
          await flutterLocalNotificationsPlugin.show(
            8,
            'Alerta de Sobreconsumo',
            'Dispositivo: $device\nConsumo: ${lastHourWh.toStringAsFixed(2)} Wh',
            notificationDetails,
          );
        }
      }
    }
  }

// Método para iniciar el monitoreo continuo de las alertas
  void iniciarMonitorizacion() {
    // Si ya hay un temporizador activo, lo cancela para evitar duplicados
    _timer?.cancel();

    // Inicia un nuevo temporizador para verificar las alertas cada 3 minutos
    _timer = Timer.periodic(
        Duration(
          minutes: int.parse(dotenv.env['CHECK_INTERVAL_MIN'] ?? '3'),
        ), (Timer t) async {
      //print("Verificando alertas...");
      // Aquí puedes verificar cada tipo de alerta individualmente
      await fetchConsumptionData(); // Picos, caídas, etc.
      await checkPicosAnomalos(); // 1️⃣ Picos Anómalos
      await checkEncendidoProlongado(); // 2️⃣ Encendido Prolongado
      await checkConsumoDiarioAlto(); // 3️⃣ Consumo Diario Alto
      await checkConsumoNocturno(); // 4️⃣ Consumo Nocturno
      await checkStandbyProlongado(DateTime.now()); // 5️⃣ Standby Prolongado
      await checkCaidaRepentina(DateTime.now()); // 6️⃣ Caída Repentina
      await checkAusenciaDatos(DateTime.now()); // 7️⃣ Ausencia de Datos
      await checkExcesoCO2(DateTime.now()); // 8️⃣ Exceso de CO₂
      await checkSobreconsumo(DateTime.now()); // 9️⃣ Sobreconsumo
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

  /// Actualización de buildPicosAnomalosWidget con parseo seguro
  Widget buildPicosAnomalosWidget() {
    // Filtra alertas de picos anómalos
    final List<Map<String, dynamic>> picosAnomalosAlertas =
        alertas.where((alerta) {
      final String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;
      // Parseo seguro de last_hour_energy
      final rawEnergy = alerta['last_hour_energy'];
      double lastHourEnergy;
      if (rawEnergy is num) {
        lastHourEnergy = rawEnergy.toDouble();
      } else {
        lastHourEnergy = double.tryParse(rawEnergy?.toString() ?? '') ?? 0.0;
      }
      return lastHourEnergy > 0.0;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Picos Anómalos"),
          value: alertasActivas['picos_anomalos'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('picos_anomalos_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: picosAnomalosAlertas.length,
            itemBuilder: (context, index) {
              final alerta = picosAnomalosAlertas[index];

              // Parseo seguro de time y cálculos numéricos
              final DateTime timeLocal =
                  _parseLocal(alerta['time']?.toString());
              final String timeStr =
                  DateFormat('yyyy-MM-dd HH:mm').format(timeLocal);
              final rawEnergy = alerta['last_hour_energy'];
              final double lastHourEnergy = rawEnergy is num
                  ? rawEnergy.toDouble()
                  : double.tryParse(rawEnergy?.toString() ?? '') ?? 0.0;
              final double media =
                  double.tryParse(alerta['media_hist']?.toString() ?? '') ??
                      0.0;
              final double stddev =
                  double.tryParse(alerta['stddev_hist']?.toString() ?? '') ??
                      0.0;
              final double umbral = media + 2 * stddev;

              return Card(
                color: Colors.red[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device']?.toString() ??
                      "Dispositivo desconocido"),
                  subtitle: Text(
                    'Fecha y hora: $timeStr'
                    'Última hora: ${lastHourEnergy.toStringAsFixed(2)} Wh'
                    'Media histórica: ${media.toStringAsFixed(2)} Wh'
                    'Desviación estándar: ${stddev.toStringAsFixed(2)} Wh'
                    'Umbral dinámico: ${umbral.toStringAsFixed(2)} Wh',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Widget para mostrar las alertas de Sobreconsumo
  /// Actualización de buildSobreConsumoWidget con parseo seguro
  Widget buildSobreConsumoWidget() {
    // Filtra solo alertas pendientes de sobreconsumo
    List<Map<String, dynamic>> sobreConsumoAlertas = alertas.where((alerta) {
      String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      double lastHourEnergy =
          double.tryParse(alerta['last_hour_energy']?.toString() ?? '') ?? 0.0;
      double media =
          double.tryParse(alerta['media_hist']?.toString() ?? '') ?? 0.0;
      double desviacionEstandar =
          double.tryParse(alerta['stddev_hist']?.toString() ?? '') ?? 0.0;

      double umbralDinamico = media + (1.5 * desviacionEstandar);
      return lastHourEnergy > umbralDinamico;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Sobreconsumo"),
          value: alertasActivas['sobreconsumo'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('sobreconsumo_activo', value);
          },
        ),
        // Listado de alertas
        Expanded(
          child: ListView.builder(
            itemCount: sobreConsumoAlertas.length,
            itemBuilder: (context, index) {
              var alerta = sobreConsumoAlertas[index];
              DateTime time = _parseLocal(alerta['time']?.toString() ?? '');
              // Formatea la hora local
              String horaLocal = DateFormat('yyyy-MM-dd HH:mm').format(time);

              double lastHourEnergy = double.tryParse(
                      alerta['last_hour_energy']?.toString() ?? '') ??
                  0.0;
              double media =
                  double.tryParse(alerta['media_hist']?.toString() ?? '') ??
                      0.0;
              double desviacionEstandar =
                  double.tryParse(alerta['stddev_hist']?.toString() ?? '') ??
                      0.0;
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
                    "Fecha y hora: $horaLocal"
                    "\nConsumo última hora: ${lastHourEnergy.toStringAsFixed(2)} Wh"
                    "\nMedia histórica: ${media.toStringAsFixed(2)} Wh"
                    "\nDesviación estándar: ${desviacionEstandar.toStringAsFixed(2)} Wh"
                    "\nUmbral dinámico: ${umbralDinamico.toStringAsFixed(2)} Wh",
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

  /// Actualización de buildConsumoNocturnoWidget con parseo seguro
  Widget buildConsumoNocturnoWidget() {
    // Define las horas nocturnas desde .env
    final int horaInicio =
        int.parse(dotenv.env['HORA_INICIO_NOCTURNO'] ?? '22');
    final int horaFin = int.parse(dotenv.env['HORA_FIN_NOCTURNO'] ?? '6');
    final DateTime now = DateTime.now();

    // Filtra alertas con consumo en horas nocturnas
    final List<Map<String, dynamic>> consumoNocturnoAlertas =
        alertas.where((alerta) {
      final String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Parsea fecha/hora local de la alerta
      DateTime time;
      try {
        time = DateTime.parse(alerta['time']?.toString() ?? '').toLocal();
      } catch (_) {
        time = now;
      }
      final int h = time.hour;
      final bool esNocturno = (horaInicio <= horaFin)
          ? (h >= horaInicio && h < horaFin)
          : (h >= horaInicio || h < horaFin);

      // Parsea consumo última hora de forma segura
      final String rawEnergy = alerta['last_hour_energy']?.toString() ?? '';
      final double energy = double.tryParse(rawEnergy) ?? 0.0;

      return esNocturno && energy > 0.0;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Consumo Nocturno"),
          value: alertasActivas['consumo_nocturno'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('consumo_nocturno_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: consumoNocturnoAlertas.length,
            itemBuilder: (context, index) {
              final alerta = consumoNocturnoAlertas[index];
              DateTime time;
              try {
                time =
                    DateTime.parse(alerta['time']?.toString() ?? '').toLocal();
              } catch (_) {
                time = now;
              }
              final String rawEnergy =
                  alerta['last_hour_energy']?.toString() ?? '';
              final double energy = double.tryParse(rawEnergy) ?? 0.0;

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
                    "\nConsumo última hora: ${energy.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Actualización de buildEncendidoProlongadoWidget con parseo seguro
  Widget buildEncendidoProlongadoWidget() {
    final int maxHoras =
        int.tryParse(dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8') ?? 8;
    final DateTime now = DateTime.now();

    // Filtra las alertas de encendido prolongado
    List<Map<String, dynamic>> encendidoProlongadoAlertas =
        alertas.where((alerta) {
      String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      DateTime inicio;
      try {
        inicio = DateTime.parse(
                alerta['inicio_encendido']?.toString() ?? now.toIso8601String())
            .toLocal();
      } catch (_) {
        inicio = now;
      }
      final int horasEnc = now.difference(inicio).inHours;
      return horasEnc >= maxHoras;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Encendido Prolongado"),
          value: alertasActivas['encendido_prolongado'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('encendido_prolongado_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: encendidoProlongadoAlertas.length,
            itemBuilder: (context, index) {
              final alerta = encendidoProlongadoAlertas[index];
              DateTime inicio;
              try {
                inicio = DateTime.parse(
                        alerta['inicio_encendido']?.toString() ??
                            now.toIso8601String())
                    .toLocal();
              } catch (_) {
                inicio = now;
              }
              final int horasEnc = now.difference(inicio).inHours;

              return Card(
                color: Colors.blue[200],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Dispositivo desconocido"),
                  subtitle: Text(
                    "Fecha de inicio: ${DateFormat('yyyy-MM-dd HH:mm').format(inicio)}\n"
                    "Duración: $horasEnc h\n"
                    "Límite: $maxHoras h",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Actualización de buildConsumoDiarioAltowidget con parseo seguro
  Widget buildConsumoDiarioAltowidget() {
    // Filtra alerts por consumo diario alto
    final List<Map<String, dynamic>> consumoDiarioAlertas =
        alertas.where((alerta) {
      final String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Parseo seguro de consumo diario y stats
      final double consumoDiario =
          double.tryParse(alerta['consumo_diario']?.toString() ?? '') ?? 0.0;
      final double media =
          double.tryParse(alerta['media_hist_diario']?.toString() ?? '') ??
              double.tryParse(alerta['media_hist']?.toString() ?? '') ??
              0.0;
      final double stddev =
          double.tryParse(alerta['stddev_hist_diario']?.toString() ?? '') ??
              double.tryParse(alerta['stddev_hist']?.toString() ?? '') ??
              0.0;
      final double umbral = media + 1.5 * stddev;

      return consumoDiario > umbral;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Consumo Diario Alto"),
          value: alertasActivas['consumo_diario_alto'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('consumo_diario_alto_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: consumoDiarioAlertas.length,
            itemBuilder: (context, index) {
              final alerta = consumoDiarioAlertas[index];
              final double consumoDiario =
                  double.tryParse(alerta['consumo_diario']?.toString() ?? '') ??
                      0.0;
              final double media = double.tryParse(
                      alerta['media_hist_diario']?.toString() ?? '') ??
                  double.tryParse(alerta['media_hist']?.toString() ?? '') ??
                  0.0;
              final double stddev = double.tryParse(
                      alerta['stddev_hist_diario']?.toString() ?? '') ??
                  double.tryParse(alerta['stddev_hist']?.toString() ?? '') ??
                  0.0;
              final double umbral = media + 1.5 * stddev;

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
                    "\nMedia histórica diaria: ${media.toStringAsFixed(2)} Wh"
                    "\nDesviación estándar diaria: ${stddev.toStringAsFixed(2)} Wh"
                    "\nUmbral dinámico: ${umbral.toStringAsFixed(2)} Wh",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Actualización de buildCaidaRepentinaWidget con parseo seguro
  Widget buildCaidaRepentinaWidget() {
    List<Map<String, dynamic>> caidaAlertas = alertas.where((alerta) {
      String deviceId = alerta['device'] ?? "";
      if (dispositivosExcluidos.contains(deviceId)) return false;
      double prev = (alerta['prev_hour_energy'] is num)
          ? (alerta['prev_hour_energy'] as num).toDouble()
          : double.tryParse(alerta['prev_hour_energy']?.toString() ?? '') ??
              0.0;
      double last = (alerta['last_hour_energy'] is num)
          ? (alerta['last_hour_energy'] as num).toDouble()
          : double.tryParse(alerta['last_hour_energy']?.toString() ?? '') ??
              0.0;
      return prev > 0.0 && (last / prev) < 0.5;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Caída Repentina"),
          value: alertasActivas['caida_repentina'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('caida_repentina_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: caidaAlertas.length,
            itemBuilder: (context, index) {
              var alerta = caidaAlertas[index];
              double prev = double.tryParse(
                      alerta['prev_hour_energy']?.toString() ?? '') ??
                  0.0;
              double last = double.tryParse(
                      alerta['last_hour_energy']?.toString() ?? '') ??
                  0.0;
              double percent = prev > 0 ? (last / prev) * 100 : 0.0;
              return Card(
                color: Colors.blueGrey[100],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "Previo (10–5 min): ${prev.toStringAsFixed(2)} Wh\n"
                    "Último (5–0 min): ${last.toStringAsFixed(2)} Wh\n"
                    "Caída: ${percent.toStringAsFixed(1)}%",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Actualización de buildAusenciaDatosWidget con parseo seguro de time
  Widget buildAusenciaDatosWidget() {
    // 1) Umbral de ausencia en minutos desde .env
    int umbralMinutos =
        int.parse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15');

    // 2) Filtra solo las alertas cuya diferencia supere el umbral
    List<Map<String, dynamic>> ausenciaAlertas = alertas.where((alerta) {
      String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // 3) Parsea el 'time' guardado (ya convertido a local al guardarlo)
      DateTime lastLocal;
      try {
        // atent@ a toLocal() si tu addAlerta guardó en UTC
        lastLocal = DateTime.parse(alerta['time'].toString()).toLocal();
      } catch (_) {
        lastLocal = DateTime.now();
      }

      // 4) Calcula diferencia con AHORA
      final diff = DateTime.now().difference(lastLocal);

      // 5) Solo deja las que superan el umbral
      return diff.inMinutes >= umbralMinutos;
    }).toList();

    return Column(
      children: [
        // 6) Switch de activación
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Ausencia de Datos"),
          value: alertasActivas['ausencia_datos'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('ausencia_datos_activo', value);
          },
        ),
        // 7) Lista de tarjetas con la info ya en local
        Expanded(
          child: ListView.builder(
            itemCount: ausenciaAlertas.length,
            itemBuilder: (context, index) {
              var alerta = ausenciaAlertas[index];

              // 8) Volvemos a parsear la fecha para mostrar
              DateTime lastLocal;
              try {
                lastLocal = DateTime.parse(alerta['time'].toString()).toLocal();
              } catch (_) {
                lastLocal = DateTime.now();
              }

              // 9) Recalcula minutos
              final minutos = DateTime.now().difference(lastLocal).inMinutes;

              return Card(
                color: Colors.teal[100],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "Último reporte: ${DateFormat('yyyy-MM-dd HH:mm').format(lastLocal)}\n"
                    "Hace: $minutos minutos (umbral: $umbralMinutos min)",
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
    List<Map<String, dynamic>> co2Alertas = alertas.where((alerta) {
      String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      double co2 = double.tryParse(alerta['co2']?.toString() ?? '') ?? 0.0;
      double umbralCo2 =
          double.tryParse(dotenv.env['UMBRAL_CO2_PPM'] ?? '1000') ?? 1000;
      return co2 > umbralCo2;
    }).toList();

    return Column(
      children: [
        SwitchListTile(
          title: Text("Activar/Desactivar Alertas de Exceso de CO₂"),
          value: alertasActivas['exceso_co2'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('exceso_co2_activo', value);
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: co2Alertas.length,
            itemBuilder: (context, index) {
              var alerta = co2Alertas[index];
              double co2 =
                  double.tryParse(alerta['co2']?.toString() ?? '') ?? 0.0;

              return Card(
                color: Colors.green[100],
                child: ListTile(
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "CO₂: ${co2.toStringAsFixed(1)} ppm",
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Actualización de buildStandbyProlongadoWidget con parseo seguro
  Widget buildStandbyProlongadoWidget() {
    // Filtra la lista de alertas para este tipo
    List<Map<String, dynamic>> standbyAlertas = alertas.where((alerta) {
      String deviceId = alerta['device']?.toString() ?? '';
      if (dispositivosExcluidos.contains(deviceId)) return false;

      // Parseo seguro de cuándo empezó el standby
      DateTime start;
      try {
        start = DateTime.parse(alerta['standby_inicio']?.toString() ?? '')
            .toLocal();
      } catch (_) {
        start = DateTime.now().toLocal();
      }

      // Calcula cuánto tiempo lleva en standby
      Duration standbyDur = DateTime.now().toLocal().difference(start);

      // Umbral mínimo en minutos (por defecto 30) desde .env
      int umbralMin =
          int.tryParse(dotenv.env['UMBRAL_STANDBY_MIN'] ?? '30') ?? 30;

      return standbyDur.inMinutes >= umbralMin;
    }).toList();

    return Column(
      children: [
        // Switch para activar/desactivar esta alerta
        SwitchListTile(
          title: const Text("Activar/Desactivar Alertas de Standby Prolongado"),
          value: alertasActivas['standby_prolongado'] ?? true,
          onChanged: (value) {
            guardarEstadoAlerta('standby_prolongado_activo', value);
          },
        ),
        // Lista de las alertas filtradas
        Expanded(
          child: ListView.builder(
            itemCount: standbyAlertas.length,
            itemBuilder: (context, index) {
              var alerta = standbyAlertas[index];
              DateTime start;
              try {
                start =
                    DateTime.parse(alerta['standby_inicio']?.toString() ?? '')
                        .toLocal();
              } catch (_) {
                start = DateTime.now().toLocal();
              }
              int mins = DateTime.now().toLocal().difference(start).inMinutes;
              int umbralMin =
                  int.tryParse(dotenv.env['UMBRAL_STANDBY_MIN'] ?? '30') ?? 30;

              return Card(
                color: Colors.grey[300],
                child: ListTile(
                  trailing: IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => removeAlerta(alerta),
                  ),
                  title: Text(alerta['device'] ?? "Desconocido"),
                  subtitle: Text(
                    "Inicio standby: ${DateFormat('yyyy-MM-dd HH:mm').format(start)}\n"
                    "Duración: $mins min (umbral: $umbralMin min)",
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
