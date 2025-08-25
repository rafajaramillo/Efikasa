import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:intl/intl.dart';
import '../services/alertas_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'dart:async';

class AlertasScreen extends StatefulWidget {
  const AlertasScreen({Key? key}) : super(key: key);

  @override
  AlertasScreenState createState() => AlertasScreenState();
}

class AlertasScreenState extends State<AlertasScreen> {
  int selectedAlertIndex = 0;
  List<Map<String, dynamic>> alertas = [];
  List<String> dispositivosExcluidos = [];
  Map<String, bool> alertasActivas = {};
  List<String> devices = [];
  bool alertasActivadas = false;

  late FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _initializeAlertas();
  }

  void iniciarMonitorizacion() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(
        minutes: int.parse(dotenv.env['CHECK_INTERVAL_MIN'] ?? '5'),
      ),
      (Timer _) async {
        final now = DateTime.now();
        // 1) Ejecuta todas las comprobaciones de background
        await AlertasService.checkPicosAnomalos(now);
        await AlertasService.checkEncendidoProlongado(now);
        await AlertasService.checkConsumoDiarioAlto(now);
        await AlertasService.checkConsumoNocturno(now);
        await AlertasService.checkStandbyProlongado(now);
        await AlertasService.checkAusenciaDatos(now);
        await AlertasService.checkExcesoCO2(now);

        // 2) Luego recarga desde SharedPreferences y refresca la UI
        await _loadAlertas();
      },
    );
  }

  Future<void> _loadAll() async {
    // Ya cargó .env en main.dart
    await _loadAlertas();
    await _loadDispositivosExcluidos();
    await _loadEstadosDeAlertas();
    setState(() {});
  }

  Future<void> _loadAlertas() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('alertas') ?? '[]';
    final List<dynamic> stored = json.decode(raw);
    if (!mounted) return;
    setState(() {
      alertas = List<Map<String, dynamic>>.from(stored);
    });
  }

  Future<void> _loadDispositivosExcluidos() async {
    final prefs = await SharedPreferences.getInstance();
    dispositivosExcluidos = prefs.getStringList('dispositivos_excluidos') ?? [];
  }

  Future<void> _loadEstadosDeAlertas() async {
    final prefs = await SharedPreferences.getInstance();
    const keys = [
      'picos_anomalos_activo',
      'encendido_prolongado_activo',
      'consumo_diario_alto_activo',
      'consumo_nocturno_activo',
      'standby_prolongado_activo',
      'ausencia_datos_activo',
      'exceso_co2_activo',
    ];
    for (var key in keys) {
      final tipo = key.replaceAll('_activo', '');
      alertasActivas[tipo] = prefs.getBool(key) ?? true;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text("Alertas Energéticas")),
        body: Column(
          children: [
            _buildIconBar(),
            Expanded(child: _buildSelectedAlertWidget()),
          ],
        ),
      );

  Widget _buildIconBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _iconButton(Icons.flash_on, 'picos_anomalos', 0),
            _iconButton(Icons.access_time, 'encendido_prolongado', 1),
            _iconButton(Icons.today, 'consumo_diario_alto', 2),
            _iconButton(Icons.nightlight_round, 'consumo_nocturno', 3),
            _iconButton(Icons.power, 'standby_prolongado', 4),
            _iconButton(Icons.signal_wifi_off, 'ausencia_datos', 5),
            _iconButton(Icons.eco, 'exceso_co2', 6),
            _iconButton(Icons.block, 'exclusion', 7),
          ],
        ),
      );

  Widget _iconButton(IconData icon, String tipo, int index) {
    final activo = alertasActivas[tipo] ?? true;
    return IconButton(
      icon: Icon(
        icon,
        color: activo ? Colors.green : Colors.grey,
      ),
      onPressed: () => setState(() => selectedAlertIndex = index),
    );
  }

  Widget _buildSelectedAlertWidget() {
    switch (selectedAlertIndex) {
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
        return buildAusenciaDatosWidget();
      case 6:
        return buildExcesoCO2Widget();
      case 7:
        return buildExclusionWidget();
      default:
        return Center(child: Text("Seleccione una alerta"));
    }
  }

  DateTime _parseLocal(String? iso) {
    if (iso == null) return DateTime.now();
    try {
      return DateTime.parse(iso).toLocal();
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<void> removeAlerta(Map<String, dynamic> alerta) async {
    setState(() {
      alertas.removeWhere((a) =>
          a['device'] == alerta['device'] && a['tipo'] == alerta['tipo']);
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alertas', json.encode(alertas));
  }

  Future<void> guardarDispositivosExcluidos(List<String> ids) async {
    setState(() => dispositivosExcluidos = ids);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('dispositivos_excluidos', ids);
  }

  Future<void> guardarEstadoAlerta(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    final tipo = key.replaceAll('_activo', '');
    setState(() {
      alertasActivas[tipo] = value;
    });
  }

  Future<void> _initializeAlertas() async {
    // Carga variables de entorno
    await dotenv.load(fileName: ".env");
    // print('✅ .env cargado: ${dotenv.env}');

    // Carga lista de dispositivos excluidos
    _loadDispositivosExcluidos();

    // Obtiene sensores de potencia
    devices = await fetchDevices();
    print('[init] Dispositivos cargados: $devices');

    // Carga las alertas previas y el estado de los switches
    await loadAlertas();
    loadSwitchState();
    _loadEstadosDeAlertas();
    // Inicializa notificaciones locales
    initNotifications();
    // Inicia el timer de monitoreo
    // Inicia el timer de monitoreo periódico de alertas
    iniciarMonitorizacion();
  }

  // --- Widgets de cada alerta ---

  Widget buildPicosAnomalosWidget() {
    final lista = alertas.where((a) {
      return a['tipo'] == 'picos_anomalos' &&
          !dispositivosExcluidos.contains(a['device']) &&
          (double.tryParse(a['last_hour_energy']?.toString() ?? '') ?? 0) > 0;
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Picos Anómalos"),
        value: alertasActivas['picos_anomalos'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('picos_anomalos_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final ts = _parseLocal(a['time']?.toString());
          final energy =
              double.tryParse(a['last_hour_energy']?.toString() ?? '') ?? 0;
          final media = double.tryParse(a['media_hist']?.toString() ?? '') ?? 0;
          final stddev =
              double.tryParse(a['stddev_hist']?.toString() ?? '') ?? 0;
          final umbral = media + 1.5 * stddev;
          return Card(
              color: Colors.red[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle:
                    Text("Hora: ${DateFormat('yyyy-MM-dd HH:mm').format(ts)}\n"
                        "Última hora: ${energy.toStringAsFixed(2)} Wh\n"
                        "Umbral: ${umbral.toStringAsFixed(2)} Wh"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildEncendidoProlongadoWidget() {
    final maxH = int.tryParse(dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8') ?? 8;
    final now = DateTime.now();
    final lista = alertas.where((a) {
      if (a['tipo'] != 'encendido_prolongado') return false;
      final inicio = _parseLocal(a['inicio_encendido']?.toString());
      return now.difference(inicio).inHours >= maxH &&
          !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Encendido Prolongado"),
        value: alertasActivas['encendido_prolongado'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('encendido_prolongado_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final inicio = _parseLocal(a['inicio_encendido']?.toString());
          final horas = now.difference(inicio).inHours;
          return Card(
              color: Colors.blue[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle: Text(
                    "Inicio: ${DateFormat('yyyy-MM-dd HH:mm').format(inicio)}\n"
                    "Duración: $horas h (límite $maxH h)"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildConsumoDiarioAltowidget() {
    final lista = alertas.where((a) {
      return a['tipo'] == 'consumo_diario_alto' &&
          !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Consumo Diario Alto"),
        value: alertasActivas['consumo_diario_alto'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('consumo_diario_alto_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final consumo =
              double.tryParse(a['consumo_diario']?.toString() ?? '') ?? 0;
          final media =
              double.tryParse(a['media_hist_diario']?.toString() ?? '') ?? 0;
          final stddev =
              double.tryParse(a['stddev_hist_diario']?.toString() ?? '') ?? 0;
          final umbral = media + 1.5 * stddev;
          final ts = _parseLocal(a['time']?.toString());
          return Card(
              color: Colors.yellow[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle: Text("Fecha: ${DateFormat('yyyy-MM-dd').format(ts)}\n"
                    "Consumo: ${consumo.toStringAsFixed(2)} Wh\n"
                    "Umbral: ${umbral.toStringAsFixed(2)} Wh"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildConsumoNocturnoWidget() {
    final hi = int.tryParse(dotenv.env['HORA_INICIO_NOCTURNO'] ?? '22') ?? 22;
    final hf = int.tryParse(dotenv.env['HORA_FIN_NOCTURNO'] ?? '6') ?? 6;
    final lista = alertas.where((a) {
      if (a['tipo'] != 'consumo_nocturno') return false;
      final ts = _parseLocal(a['time']?.toString());
      final h = ts.hour;
      final noct = hi < hf ? (h >= hi && h < hf) : (h >= hi || h < hf);
      final e = double.tryParse(a['last_hour_energy']?.toString() ?? '') ?? 0;
      return noct && e > 0 && !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Consumo Nocturno"),
        value: alertasActivas['consumo_nocturno'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('consumo_nocturno_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final ts = _parseLocal(a['time']?.toString());
          final e =
              double.tryParse(a['last_hour_energy']?.toString() ?? '') ?? 0;
          return Card(
              color: Colors.indigo[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle:
                    Text("Hora: ${DateFormat('yyyy-MM-dd HH:mm').format(ts)}\n"
                        "Consumo: ${e.toStringAsFixed(2)} Wh"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildStandbyProlongadoWidget() {
    final um = int.tryParse(dotenv.env['UMBRAL_STANDBY_MIN'] ?? '35') ?? 30;
    final now = DateTime.now();
    final lista = alertas.where((a) {
      if (a['tipo'] != 'standby_prolongado') return false;
      final inicio = _parseLocal(a['standby_inicio']?.toString());
      final m = now.difference(inicio).inMinutes;
      return m >= um && !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Standby Prolongado"),
        value: alertasActivas['standby_prolongado'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('standby_prolongado_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final inicio = _parseLocal(a['standby_inicio']?.toString());
          final dur = now.difference(inicio).inMinutes;
          final e =
              double.tryParse(a['last_hour_energy']?.toString() ?? '') ?? 0;
          return Card(
              color: Colors.grey[200],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle: Text(
                    "Inicio: ${DateFormat('yyyy-MM-dd HH:mm').format(inicio)}\n"
                    "Duración: $dur min (umbral $um min)\n"
                    "Consumo: ${e.toStringAsFixed(2)} Wh"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildAusenciaDatosWidget() {
    final um =
        int.tryParse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15') ?? 15;
    final now = DateTime.now();
    final lista = alertas.where((a) {
      if (a['tipo'] != 'ausencia_datos') return false;
      final ts = _parseLocal(a['time']?.toString());
      final diff = now.difference(ts).inMinutes;
      return diff >= um && !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Ausencia de Datos"),
        value: alertasActivas['ausencia_datos'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('ausencia_datos_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final ts = _parseLocal(a['time']?.toString());
          final diff = DateTime.now().difference(ts).inMinutes;
          return Card(
              color: Colors.teal[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle: Text(
                    "Último reporte: ${DateFormat('yyyy-MM-dd HH:mm').format(ts)}\n"
                    "Hace: $diff min (umbral $um min)"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildExcesoCO2Widget() {
    final um = double.tryParse(dotenv.env['UMBRAL_CO2_KG'] ?? '1.0') ?? 1.0;
    final lista = alertas.where((a) {
      if (a['tipo'] != 'exceso_co2') return false;
      final e = double.tryParse(a['co2_kg']?.toString() ?? '') ?? 0;
      return e > um && !dispositivosExcluidos.contains(a['device']);
    }).toList();

    return Column(children: [
      SwitchListTile(
        title: Text("Exceso de CO₂"),
        value: alertasActivas['exceso_co2'] ?? true,
        onChanged: (v) => guardarEstadoAlerta('exceso_co2_activo', v),
      ),
      Expanded(
          child: ListView.builder(
        itemCount: lista.length,
        itemBuilder: (c, i) {
          final a = lista[i];
          final e = double.tryParse(a['co2_kg']?.toString() ?? '') ?? 0;
          return Card(
              color: Colors.green[100],
              child: ListTile(
                title: Text(a['device'] ?? ''),
                subtitle: Text("Emisión: ${e.toStringAsFixed(2)} kg CO₂"),
                trailing: IconButton(
                  icon: Icon(Icons.delete),
                  onPressed: () => removeAlerta(a),
                ),
              ));
        },
      )),
    ]);
  }

  Widget buildExclusionWidget() {
    return FutureBuilder<List<String>>(
      future: AlertasService.fetchDevices(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        } else if (snap.hasError) {
          return Center(child: Text("Error cargando dispositivos"));
        }
        final lista = snap.data ?? [];
        return ListView.builder(
          itemCount: lista.length,
          itemBuilder: (c, i) {
            final id = lista[i];
            final excl = dispositivosExcluidos.contains(id);
            return CheckboxListTile(
              title: Text(id),
              value: excl,
              onChanged: (v) {
                final nuevos = List<String>.from(dispositivosExcluidos);
                if (v == true)
                  nuevos.add(id);
                else
                  nuevos.remove(id);
                guardarDispositivosExcluidos(nuevos);
              },
            );
          },
        );
      },
    );
  }

  // Método para cargar la lista de dispositivos desde Home Assistant
  Future<List<String>> fetchDevices() async {
    final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    print('[fetchDevices] Llamando a $url');
    try {
      final response = await http.get(url, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      print('[fetchDevices] Status code: ${response.statusCode}');
      if (response.statusCode == 200) {
        final List<dynamic> raw = json.decode(response.body);
        print('[fetchDevices] Total estados: ${raw.length}');
        print(
            '[fetchDevices] Primeros IDs: ${raw.take(5).map((e) => e["entity_id"]).toList()}');
        // Filtrar solo los sensores que terminan en '_power'
        final devices = raw
            .map((e) => e['entity_id'] as String)
            .where((id) => id.startsWith('sensor.') && id.endsWith('_power'))
            .toList();
        print('[fetchDevices] Sensores filtrados: $devices');
        return devices;
      } else {
        print('[fetchDevices] Error HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print('[fetchDevices] Excepción: $e');
    }
    return []; // No sensors found
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
}
