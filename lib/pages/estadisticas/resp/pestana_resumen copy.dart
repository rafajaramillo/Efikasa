import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:efikasa/pages/global_tarifa.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Esta clase representa la pestaña de resumen general de consumo energético.
class PestanaResumen extends StatelessWidget {
  const PestanaResumen({super.key});

  Future<Map<String, dynamic>> obtenerResumenGeneral() async {
    // Obtiene las credenciales de autenticación básica desde el archivo .env (usuario:contraseña)
    final influxAuth = dotenv.env['INFLUXDB_AUTH']!;

    // Obtiene la URL base de InfluxDB desde el archivo .env
    final influxUrl = dotenv.env['INFLUXDB_URL']!;

    // Obtiene el nombre de la base de datos desde el archivo .env
    final influxDBName = dotenv.env['INFLUXDB_DB']!;

    final auth = base64Encode(utf8.encode(influxAuth));
    final headers = {'Authorization': 'Basic $auth'};

    Future<double> calcularConsumoEnergetico(String rango) async {
      final query = Uri.parse('$influxUrl/query?q='
          'SELECT "value", time FROM "W" WHERE time >= now() - $rango AND "entity_id" =~ /.*_power/'
          '&db=$influxDBName&epoch=ms');

      final res = await http.get(query, headers: headers);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final series = decoded['results']?[0]['series'];

        if (series == null || series.isEmpty) return 0.0;

        double totalKwh = 0.0;
        for (var serie in series) {
          final values = serie['values'];
          for (int i = 1; i < values.length; i++) {
            final anterior = values[i - 1];
            final actual = values[i];
            final potencia = anterior[1];
            final t1 = DateTime.fromMillisecondsSinceEpoch(anterior[0]);
            final t2 = DateTime.fromMillisecondsSinceEpoch(actual[0]);
            final duracionSeg = t2.difference(t1).inSeconds;
            if (potencia != null) {
              final energia = (potencia * duracionSeg) / 3600000;
              totalKwh += energia;
            }
          }
        }
        return totalKwh;
      } else {
        throw Exception('Error en cálculo de energía para $rango');
      }
    }

    final dia = await calcularConsumoEnergetico('1d');
    final semana = await calcularConsumoEnergetico('7d');
    final mes = await calcularConsumoEnergetico('30d');
    final anio = await calcularConsumoEnergetico('365d');

    return {
      "dia": dia.toStringAsFixed(2),
      "semana": semana.toStringAsFixed(2),
      "mes": mes.toStringAsFixed(2),
      "anio": anio.toStringAsFixed(2),
      "promedio": (semana / 7).toStringAsFixed(2),
    };
  }

  String formatoDolares(double valor) {
    final formatter = NumberFormat.simpleCurrency(decimalDigits: 2);
    return formatter.format(valor);
  }

  Color getColorPorNivel(double kwh) {
    if (kwh < 5) return Colors.green.shade100;
    if (kwh < 20) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  Widget buildStatCardMoneda(
      String titulo, String kwhStr, IconData iconKwh, IconData iconUsd) {
    final double kwh = double.tryParse(kwhStr) ?? 0.0;
    final double totalUSD = kwh * tarifaKwHGlobal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: getColorPorNivel(kwh),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200,
              blurRadius: 4,
              offset: const Offset(0, 2),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                children: [
                  Icon(iconKwh, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconKwh, size: 16, color: Colors.black54),
                    const SizedBox(width: 4),
                    Text(
                      '$kwhStr kWh',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(iconUsd, size: 16, color: Colors.black45),
                    const SizedBox(width: 4),
                    Text(
                      formatoDolares(totalUSD),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void exportarResumenPDF(Map<String, dynamic> data) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text("Resumen de Consumo Energético",
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            ...data.entries.map((e) => pw.Text(
                "${e.key.toUpperCase()}: ${e.value} kWh | \$${(double.parse(e.value) * tarifaKwHGlobal).toStringAsFixed(2)}")),
          ],
        ),
      ),
    );
    await Printing.layoutPdf(
      onLayout: (format) => doc.save(),
      name: 'Resumen de Consumo Energético',
      usePrinterSettings: true,
      dynamicLayout: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: FutureBuilder<Map<String, dynamic>>(
        future: obtenerResumenGeneral(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),
            );
          } else if (snapshot.hasError) {
            return const Center(child: Text('Error al cargar resumen'));
          } else {
            final data = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildStatCardMoneda('Consumo total diario', data["dia"],
                    Icons.calendar_today, Icons.attach_money),
                buildStatCardMoneda('Consumo total semanal', data["semana"],
                    Icons.date_range, Icons.money),
                buildStatCardMoneda('Consumo total mensual', data["mes"],
                    Icons.calendar_view_month, Icons.monetization_on),
                buildStatCardMoneda('Consumo total anual', data["anio"],
                    Icons.event, Icons.euro),
                buildStatCardMoneda('Promedio diario (ultimos 7 dias)',
                    data["promedio"], Icons.show_chart, Icons.price_change),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton.icon(
                    onPressed: () => exportarResumenPDF(data),
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text("Exportar Resumen a PDF"),
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }
}
