import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

/// Servicio de alertas para ejecución en background.
/// Contiene lógica pura (sin setState, sin widgets), accediendo a Home Assistant
/// y disparando notificaciones locales.
class AlertasService {
  // Plugin único de notificaciones
  static final FlutterLocalNotificationsPlugin _notifier =
      FlutterLocalNotificationsPlugin();

  // Snapshot estático de potencia y tiempo para Standby Prolongado
  static final Map<String, double> _snapshotPower = {};
  static final Map<String, DateTime> _snapshotTime = {};

  /// Guarda el instante en que cada dispositivo pasó a potencia > 0
  static final Map<String, DateTime> _encendidoStartTimes = {};

  /// Lista de dispositivos (puedes cargarla estáticamente o via método)
  static List<String> devices = [];

  /// Inicializa el plugin de notificaciones
  static Future<void> initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _notifier.initialize(
      InitializationSettings(android: android),
    );
  }

  /// Obtiene desde Home Assistant todos los sensores de potencia
  static Future<List<String>> fetchDevices() async {
    final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final res = await http.get(url, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) return [];
    final List<dynamic> raw = json.decode(res.body);
    return raw
        .map((e) => e['entity_id'] as String)
        .where((id) => id.startsWith('sensor.') && id.endsWith('_power'))
        .toList();
  }

  /// Obtiene estadísticas (media y desviación estándar) de Home Assistant
  static Future<Map<String, double>> obtenerEstadisticasHistoricasHA(
    String deviceId,
    int historyDays,
  ) async {
    final now = DateTime.now();
    final since = now.subtract(Duration(days: historyDays));

    // Formatea sin milisegundos para la API
    String iso(DateTime dt) =>
        dt.toUtc().toIso8601String().replaceFirst(RegExp(r'\.\d+Z$'), 'Z');

    final uri = Uri.parse(
      '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/${iso(since)}'
      '?filter_entity_id=$deviceId',
    );
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) {
      return {'media': 0.0, 'stddev': 0.0};
    }

    final decoded = json.decode(res.body) as List<dynamic>;
    final series = (decoded.isNotEmpty && decoded[0] is List)
        ? List<Map<String, dynamic>>.from(decoded[0])
        : <Map<String, dynamic>>[];

    final consumos = <double>[];
    for (var point in series) {
      final p = double.tryParse(point['state']?.toString() ?? '') ?? 0.0;
      consumos.add(p);
    }
    if (consumos.isEmpty) {
      return {'media': 0.0, 'stddev': 0.0};
    }

    final media = consumos.reduce((a, b) => a + b) / consumos.length;
    final sumSq = consumos.fold(0.0, (s, v) => s + pow(v - media, 2));
    final stddev = sqrt(sumSq / consumos.length);

    return {'media': media, 'stddev': stddev};
  }

  /// Check Picos Anómalos: detecta picos mayores a media+1.5*stddev
  static Future<void> checkPicosAnomalos(DateTime now) async {
    // final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    final devices = await fetchDevices();
    final prefs = await SharedPreferences.getInstance();
    final activos = prefs.getBool('picos_anomalos_activo') ?? true;
    if (!activos) return;

    for (final device in devices) {
      final uri = Uri.parse(
          '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device');
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;

      final data = json.decode(res.body) as List<dynamic>;
      double lastHourEnergyWh = 0.0;
      if (data.isNotEmpty && data[0] is List) {
        final oneHourAgo = now.subtract(Duration(hours: 1));
        for (var entry in data[0]) {
          final ts = DateTime.parse(entry['last_changed'] as String).toLocal();
          if (ts.isAfter(oneHourAgo)) {
            lastHourEnergyWh +=
                (double.tryParse(entry['state']?.toString() ?? '') ?? 0.0) /
                    60.0;
          }
        }
      }

      // Estadísticas históricas
      final stats = await obtenerEstadisticasHistoricasHA(
        device,
        int.parse(dotenv.env['HA_ALERT_HISTORY_DAYS'] ?? '7'),
      );
      final umbral = (stats['media'] ?? 0.0) + 1.5 * (stats['stddev'] ?? 0.0);

      if (lastHourEnergyWh > umbral) {
        final stored = prefs.getString('alertas');
        final alertas = stored != null
            ? List<Map<String, dynamic>>.from(json.decode(stored))
            : <Map<String, dynamic>>[];
        final exists = alertas
            .any((a) => a['device'] == device && a['tipo'] == 'picos_anomalos');
        if (!exists) {
          final alerta = {
            'device': device,
            'time': now.toUtc().toIso8601String(),
            'last_hour_energy': lastHourEnergyWh,
            'media_hist': stats['media'],
            'stddev_hist': stats['stddev'],
            'tipo': 'picos_anomalos',
          };
          alertas.add(alerta);
          await prefs.setString('alertas', json.encode(alertas));
          await _notifier.show(
            now.millisecondsSinceEpoch ~/ 1000 % 100000,
            'Picos Anómalos',
            '$device: ${lastHourEnergyWh.toStringAsFixed(2)} Wh último hora',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'canal_picos',
                'Picos Anómalos',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    }
  }

  /// Check Standby Prolongado: dispara alerta si un dispositivo está ON
  /// por al menos [UMBRAL_STANDBY_MIN] minutos.
  static Future<void> checkStandbyProlongado(DateTime now) async {
    final int umbralMin = int.parse(dotenv.env['UMBRAL_STANDBY_MIN'] ?? '35');

    // Carga lista de dispositivos
    final devices = await fetchDevices();
    final prefs = await SharedPreferences.getInstance();
    final activos = prefs.getBool('standby_prolongado_activo') ?? true;
    if (!activos) return;

    for (final device in devices) {
      // Ignora excluidos
      final excluidos = prefs.getStringList('dispositivos_excluidos') ?? [];
      if (excluidos.contains(device)) continue;

      // Leer estado actual
      final uriState =
          Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states/$device');
      final resState = await http.get(uriState, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (resState.statusCode != 200) continue;
      final data = json.decode(resState.body) as Map<String, dynamic>;
      final power = double.tryParse(data['state']?.toString() ?? '') ?? 0;
      final changed = DateTime.parse(
        data['last_changed'] ?? data['last_updated'],
      ).toLocal();

      if (power > 0) {
        // Inicializar snapshot si es primera vez
        _snapshotTime.putIfAbsent(device, () => changed);
        _snapshotPower.putIfAbsent(device, () => power);
        final start = _snapshotTime[device]!;
        final duration = now.difference(start).inMinutes;
        if (duration >= umbralMin) {
          // Calcular consumo última hora
          double lastHourEnergy = 0;
          final oneHourAgo = now.subtract(Duration(hours: 1));
          final today = DateFormat('yyyy-MM-dd').format(now);
          final uriHist = Uri.parse(
              '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today?filter_entity_id=$device');
          final resHist = await http.get(uriHist, headers: {
            'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
            'Content-Type': 'application/json',
          });
          if (resHist.statusCode == 200) {
            final raw = json.decode(resHist.body) as List<dynamic>;
            if (raw.isNotEmpty && raw[0] is List) {
              for (var entry in raw[0]) {
                DateTime ts;
                try {
                  ts = DateTime.parse(entry['last_changed']).toLocal();
                } catch (_) {
                  continue;
                }
                if (ts.isAfter(oneHourAgo)) {
                  final p =
                      double.tryParse(entry['state']?.toString() ?? '') ?? 0;
                  lastHourEnergy += p / 60;
                }
              }
            }
          }

          // Persistir alerta si no existe
          final stored = prefs.getString('alertas');
          List<Map<String, dynamic>> alertas = stored != null
              ? List<Map<String, dynamic>>.from(json.decode(stored))
              : [];
          final exists = alertas.any((a) =>
              a['device'] == device && a['tipo'] == 'standby_prolongado');
          if (!exists) {
            final alerta = {
              'device': device,
              'standby_inicio': start.toIso8601String(),
              'time': now.toIso8601String(),
              'duration_min': duration,
              'last_hour_energy': lastHourEnergy,
              'tipo': 'standby_prolongado',
            };
            alertas.add(alerta);
            await prefs.setString('alertas', json.encode(alertas));

            // Disparar notificación
            await _notifier.show(
              now.millisecondsSinceEpoch ~/ 1000 % 100000,
              'Standby Prolongado',
              '$device: $duration min, consumo: ${lastHourEnergy.toStringAsFixed(2)} Wh',
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'canal_standby',
                  'Standby Prolongado',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
              ),
            );
          }
        }
      } else {
        // Reiniciar snapshot si se apaga
        _snapshotTime.remove(device);
        _snapshotPower.remove(device);
      }
    }
  }

  /// Check Ausencia de Datos: dispara si no hay actualización en X min
  static Future<void> checkAusenciaDatos(DateTime now) async {
    // 1) Umbral de ausencia en minutos desde .env
    final int umbralMinutos =
        int.parse(dotenv.env['UMBRAL_AUSENCIA_DATOS_MINUTOS'] ?? '15');

    // 2) Verifica si está activada la alerta
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('ausencia_datos_activo') ?? true)) return;

    // 3) Obtiene todos los estados
    final uri = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) return;
    final allStates = json.decode(res.body) as List<dynamic>;

    // 4) Recorre solo sensores de potencia
    for (var entity in allStates) {
      final String id = entity['entity_id'] as String? ?? '';
      if (!id.startsWith('sensor.') || !id.endsWith('_power')) continue;
      final excl = prefs.getStringList('dispositivos_excluidos') ?? [];
      if (excl.contains(id)) continue;

      // 5) Parsear marca de tiempo
      String? rawTime = entity['last_updated'] as String?;
      rawTime ??= entity['last_changed'] as String?;
      if (rawTime == null) continue;
      DateTime lastLocal;
      try {
        lastLocal = DateTime.parse(rawTime).toLocal();
      } catch (_) {
        continue;
      }

      // 6) Diferencia con ahora
      final diff = now.difference(lastLocal);
      if (diff.inMinutes < umbralMinutos) continue;

      // 7) Solo crea alerta si no existe
      final stored = prefs.getString('alertas');
      final alertas = stored != null
          ? List<Map<String, dynamic>>.from(json.decode(stored))
          : <Map<String, dynamic>>[];
      final existe = alertas
          .any((a) => a['device'] == id && a['tipo'] == 'ausencia_datos');
      if (!existe) {
        final alerta = {
          'device': id,
          'time': lastLocal.toIso8601String(),
          'tipo': 'ausencia_datos',
        };
        alertas.add(alerta);
        await prefs.setString('alertas', json.encode(alertas));

        // 8) Notificación local
        await _notifier.show(
          now.millisecondsSinceEpoch ~/ 1000 % 100000,
          'Ausencia de Datos',
          'Dispositivo: $id'
              'Último reporte: ${DateFormat('yyyy-MM-dd HH:mm').format(lastLocal)}'
              'Hace: ${diff.inMinutes} min (umbral: \$umbralMinutos min)',
          NotificationDetails(
            android: AndroidNotificationDetails(
              'canal_ausencia',
              'Ausencia de Datos',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
    }
  }

  /// Check Consumo Diario Alto: detecta consumo de hoy superior a media+1.5*stddev
  static Future<void> checkConsumoDiarioAlto(DateTime now) async {
    // 1) Inicio del día actual (00:00 local)
    final DateTime todayStart = DateTime(now.year, now.month, now.day);

    // 2) Recorre cada dispositivo de potencia
    final devices = await fetchDevices();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('consumo_diario_activo') ?? true)) return;

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
        DateTime t1 =
            DateTime.parse(series[i - 1]['last_changed'] as String).toLocal();
        DateTime t2 =
            DateTime.parse(series[i]['last_changed'] as String).toLocal();
        if (t1.isBefore(todayStart)) continue;
        double p1 =
            double.tryParse(series[i - 1]['state']?.toString() ?? '') ?? 0.0;
        double p2 =
            double.tryParse(series[i]['state']?.toString() ?? '') ?? 0.0;
        int dt = t2.difference(t1).inSeconds;
        consumoTodayWh += ((p1 + p2) / 2.0) * dt / 3600.0;
      }

      // 4) Obtiene estadísticas históricas diarias
      final int historyDays =
          int.tryParse(dotenv.env['HA_ALERT_HISTORY_DAYS'] ?? '7') ?? 7;
      final Map<String, double> stats =
          await obtenerEstadisticasHistoricasHA(device, historyDays);
      final double media = stats['media'] ?? 0.0;
      final double stddev = stats['stddev'] ?? 0.0;
      final double umbral = media + 1.5 * stddev;

      // 5) Genera alerta si supera umbral
      if (consumoTodayWh > umbral) {
        final stored = prefs.getString('alertas');
        final alertas = stored != null
            ? List<Map<String, dynamic>>.from(json.decode(stored))
            : <Map<String, dynamic>>[];
        if (!alertas.any((a) =>
            a['device'] == device && a['tipo'] == 'consumo_diario_alto')) {
          final alerta = {
            'device': device,
            'time': now.toIso8601String(),
            'consumo_diario': consumoTodayWh,
            'media_hist_diario': media,
            'stddev_hist_diario': stddev,
            'tipo': 'consumo_diario_alto',
          };
          alertas.add(alerta);
          await prefs.setString('alertas', json.encode(alertas));
          await _notifier.show(
            now.millisecondsSinceEpoch ~/ 1000 % 100000,
            'Consumo Diario Alto',
            '$device consumió ${consumoTodayWh.toStringAsFixed(2)} Wh hoy\nUmbral: ${umbral.toStringAsFixed(2)} Wh',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'canal_consumo_diario',
                'Consumo Diario Alto',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    }
  }

  static Future<void> checkEncendidoProlongado(DateTime now) async {
    // 1) Límite de horas permitidas desde .env (por defecto 8)
    final int maxHoras =
        int.tryParse(dotenv.env['MAX_HORAS_ENCENDIDO'] ?? '8') ?? 8;

    // 2) Lee todos los estados
    final uri = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final res = await http.get(uri, headers: {
      'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
      'Content-Type': 'application/json',
    });
    if (res.statusCode != 200) return;

    final List<dynamic> allStates = json.decode(res.body);

    // 3) Recorre solo sensores de potencia
    for (var entity in allStates) {
      final String id = entity['entity_id'] as String? ?? '';
      if (!id.startsWith('sensor.') || !id.endsWith('_power')) continue;
      if (!(dotenv.env['CHECK_ENCENDIDO_PROLONGADO'] == 'true')) continue;
      // Puedes usar alertasActivas si lo expones aquí también.

      // 4) Interpreta potencia
      final double power =
          double.tryParse(entity['state']?.toString() ?? '') ?? 0.0;

      if (power > 0) {
        // 5) Si recién empieza, registra timestamp
        _encendidoStartTimes.putIfAbsent(id, () => now);
        final DateTime inicio = _encendidoStartTimes[id]!;

        // 6) Si supera el umbral, genera alerta y reinicia el contador
        if (now.difference(inicio).inHours >= maxHoras) {
          // Evita duplicados
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('alertas') ?? '[]';
          final List<dynamic> alertas = json.decode(raw) as List<dynamic>;
          final existe = alertas.any(
              (a) => a['device'] == id && a['tipo'] == 'encendido_prolongado');
          if (!existe) {
            final alerta = {
              'device': id,
              'inicio_encendido': inicio.toUtc().toIso8601String(),
              'time': now.toUtc().toIso8601String(),
              'tipo': 'encendido_prolongado',
            };
            // Guarda alerta y notifica
            alertas.add(alerta);
            await prefs.setString('alertas', json.encode(alertas));
            await _notifier.show(
              now.millisecondsSinceEpoch ~/ 1000 % 100000,
              'Alerta: Encendido Prolongado',
              'Dispositivo $id lleva más de $maxHoras horas ON.',
              NotificationDetails(
                android: AndroidNotificationDetails(
                  'canal_encendido',
                  'Encendido Prolongado',
                  importance: Importance.high,
                  priority: Priority.high,
                ),
              ),
            );
          }
          // Reinicia el contador para no volver a notificar inmediatamente
          _encendidoStartTimes[id] = now;
        }
      } else {
        // 7) Si está apagado, borra el registro
        _encendidoStartTimes.remove(id);
      }
    }
  }

  /// Comprueba el consumo nocturno en la última hora.
  /// Comprueba consumo nocturno (entre HORA_INICIO_NOCTURNO y HORA_FIN_NOCTURNO)
  /// en la última hora para cada dispositivo y genera alertas si hubo consumo.
  static Future<void> checkConsumoNocturno(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('consumo_nocturno_activo') ?? true)) return;
    final excluidos = prefs.getStringList('dispositivos_excluidos') ?? [];

    // Lista de dispositivos activos
    final devices = prefs.getStringList('dispositivos_activos') ?? [];
    if (devices.isEmpty) return;

    // Horas nocturnas desde .env (inicio inclusivo, fin exclusivo)
    final horaInicio = int.parse(dotenv.env['HORA_INICIO_NOCTURNO'] ?? '22');
    final horaFin = int.parse(dotenv.env['HORA_FIN_NOCTURNO'] ?? '6');

    // Rango de la última hora en UTC para la consulta
    final DateTime endTime = now.toUtc();
    final DateTime oneHourAgo = endTime.subtract(const Duration(hours: 1));

    final String baseUrl = dotenv.env['HOME_ASSISTANT_URL']?.trim() ?? '';
    final String token = dotenv.env['HOME_ASSISTANT_TOKEN']?.trim() ?? '';
    if (baseUrl.isEmpty || token.isEmpty) return;

    for (final device in devices) {
      if (excluidos.contains(device)) continue;

      // URI de consulta con rango de tiempo
      final uri = Uri.parse(
        '\$baseUrl/api/history/period'
        '?filter_entity_id=\$device'
        '&start_time=\${oneHourAgo.toIso8601String()}'
        '&end_time=\${endTime.toIso8601String()}',
      );

      http.Response res;
      try {
        res = await http.get(uri, headers: {
          'Authorization': 'Bearer \$token',
          'Content-Type': 'application/json',
        });
      } catch (e) {
        debugPrint('Error HTTP consumo nocturno: \$e');
        continue;
      }
      if (res.statusCode != 200) continue;

      final raw = json.decode(res.body);
      if (raw is! List || raw.isEmpty || raw[0] is! List) continue;
      final entries = raw[0] as List<dynamic>;

      double nocturnalWh = 0.0;
      for (final entry in entries) {
        final tsRaw = entry['last_changed'] as String?;
        if (tsRaw == null) continue;
        DateTime ts;
        try {
          ts = DateTime.parse(tsRaw).toLocal();
        } catch (_) {
          continue;
        }

        // Filtrar dentro del último rango de una hora
        final tsUtc = ts.toUtc();
        if (tsUtc.isBefore(oneHourAgo) || tsUtc.isAfter(endTime)) continue;

        // Comprobar si hora local corresponde a horario nocturno
        final int h = ts.hour;
        final bool isNocturno = (horaInicio <= horaFin)
            ? (h >= horaInicio && h < horaFin)
            : (h >= horaInicio || h < horaFin);
        if (!isNocturno) continue;

        final state = entry['state']?.toString() ?? '0';
        final double p = double.tryParse(state) ?? 0.0;
        // Asumir medición por minuto: convertir potencia a energía Wh
        nocturnalWh += p / 60.0;
      }

      if (nocturnalWh > 0) {
        final rawAlertas = prefs.getString('alertas') ?? '[]';
        final List<dynamic> alertas = json.decode(rawAlertas);
        final existe = alertas.any(
          (a) => a['device'] == device && a['tipo'] == 'consumo_nocturno',
        );
        if (!existe) {
          alertas.add({
            'device': device,
            'time': now.toIso8601String(),
            'last_hour_energy': nocturnalWh,
            'tipo': 'consumo_nocturno',
          });
          await prefs.setString('alertas', json.encode(alertas));

          // Notificación local
          await _notifier.show(
            now.millisecondsSinceEpoch ~/ 1000 % 100000,
            'Consumo Nocturno Detectado',
            'Dispositivo \$device consumió \${nocturnalWh.toStringAsFixed(2)} Wh en la última hora nocturna.',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'canal_nocturno',
                'Consumo Nocturno',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    }
  }

  static Future<void> checkExcesoCO2(DateTime now) async {
    // 1) Factor de emisión (kg CO₂ por kWh)
    const double factorCO2 = 0.5;
    // 2) Umbral desde .env
    final double umbralCO2 =
        double.tryParse(dotenv.env['UMBRAL_CO2_KG'] ?? '1.0') ?? 1.0;

    // 3) Fecha de hoy para histórico
    final String today = DateFormat('yyyy-MM-dd').format(now.toLocal());

    // 4) Obtén alertas actuales
    final prefs = await SharedPreferences.getInstance();
    final rawAlertas = prefs.getString('alertas') ?? '[]';
    final List<dynamic> alertas = json.decode(rawAlertas) as List<dynamic>;

    // 5) Procesa cada dispositivo
    for (final device in devices) {
      // Consulta histórico de hoy
      final uri = Uri.parse(
        '${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period/$today'
        '?filter_entity_id=$device',
      );
      final res = await http.get(uri, headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      });
      if (res.statusCode != 200) continue;
      final data = json.decode(res.body) as List<dynamic>;
      if (data.isEmpty || data[0] is! List) continue;

      // 6) Sumar Wh de la última hora
      final DateTime oneHourAgo = now.subtract(Duration(hours: 1));
      double wh = 0.0;
      for (var entry in data[0] as List<dynamic>) {
        DateTime ts;
        try {
          ts = DateTime.parse(entry['last_changed'] as String).toLocal();
        } catch (_) {
          continue;
        }
        if (ts.isAfter(oneHourAgo)) {
          final double p =
              double.tryParse(entry['state']?.toString() ?? '') ?? 0.0;
          wh += p / 60.0;
        }
      }

      // 7) Convertir a kg CO₂
      final double kwh = wh / 1000.0;
      final double co2kg = kwh * factorCO2;

      // 8) Verificar umbral y duplicados
      if (co2kg > umbralCO2) {
        final bool existe = alertas.any(
          (a) => a['device'] == device && a['tipo'] == 'exceso_co2',
        );
        if (!existe) {
          // 9) Crear y persistir alerta
          final alerta = {
            'device': device,
            'time': now.toUtc().toIso8601String(),
            'co2_kg': co2kg,
            'tipo': 'exceso_co2',
          };
          alertas.add(alerta);
          await prefs.setString('alertas', json.encode(alertas));

          // 10) Disparar notificación local
          await _notifier.show(
            now.millisecondsSinceEpoch ~/ 1000 % 100000,
            'Alerta Exceso de CO₂',
            'Dispositivo: $device\nEmisión: ${co2kg.toStringAsFixed(2)} kg CO₂',
            NotificationDetails(
              android: AndroidNotificationDetails(
                'canal_co2',
                'Exceso de CO₂',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      }
    }
  }
}
