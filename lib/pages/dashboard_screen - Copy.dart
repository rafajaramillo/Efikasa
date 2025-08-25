import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/standalone.dart' as tz;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';
//import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  _DashboardPageState createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  List<Map<String, dynamic>> consumoData = [];
  Timer? _timer;
  double maxY = 50;
  String selectedTime = "";
  double selectedConsumption = 0.0;
  String selectedDevice = "sensor.tv_radio_sala_power";
  List<String> devices = [];

  @override
  void initState() {
    super.initState();
    tz.initializeTimeZones();
    fetchDevices();
    fetchConsumptionData();
    _timer = Timer.periodic(
        Duration(minutes: 1), (Timer t) => fetchConsumptionData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> fetchDevices() async {
    final url = Uri.parse('${dotenv.env['HOME_ASSISTANT_URL']}/api/states');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}',
        'Content-Type': 'application/json',
      },
    );

    /*  Future<void> fetchDevices() async {
    final url = Uri.parse("http://192.168.0.121:8123/api/states");
    final response = await http.get(
      url,
      headers: {
        "Authorization":
            "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiIxZDY1ZTUyMmRiMDY0NWFjOWI5YjlmZDE3N2EzMzM2YyIsImlhdCI6MTczOTU4MDAzNywiZXhwIjoyMDU0OTQwMDM3fQ.SH_FZuWcuVc8jP3Ta81P4dJ0wqWicDtPGK23Cyb3954",
        "Content-Type": "application/json",
      },
    ); */

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      List<String> deviceList = data
          .where((entity) =>
              entity["entity_id"].startsWith("sensor.") &&
              entity["entity_id"].contains("_power") &&
              !entity["entity_id"].contains("_power_factor"))
          .map<String>((entity) => entity["entity_id"] as String)
          .toList();

      setState(() {
        devices = deviceList;
      });
    }
  }

  Future<void> fetchConsumptionData() async {
    final url = Uri.parse(
        "${dotenv.env['HOME_ASSISTANT_URL']}/api/history/period?filter_entity_id=$selectedDevice");
    final response = await http.get(
      url,
      headers: {
        "Authorization": "Bearer ${dotenv.env['HOME_ASSISTANT_TOKEN']}",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode == 200) {
      List<dynamic> data = json.decode(response.body);
      if (data.isNotEmpty) {
        List<Map<String, dynamic>> parsedData = [];
        tz.Location guayaquil = tz.getLocation('America/Guayaquil');
        DateTime now = tz.TZDateTime.now(guayaquil);
        String today = DateFormat('yyyy-MM-dd').format(now);

        for (var entry in data[0]) {
          DateTime timestamp = DateTime.parse(entry["last_changed"]).toLocal();
          String entryDate = DateFormat('yyyy-MM-dd').format(timestamp);
          if (entryDate == today && timestamp.isBefore(now)) {
            parsedData.add({
              "time": DateFormat('HH:mm:ss').format(timestamp),
              "power": double.tryParse(entry["state"]) ?? 0.0,
            });
          }
        }

        parsedData.sort((a, b) => a["time"].compareTo(b["time"]));

        setState(() {
          consumoData = parsedData;
          maxY = ((consumoData
                              .map((e) => e["power"])
                              .reduce((a, b) => a > b ? a : b) /
                          10)
                      .ceil() *
                  10)
              .toDouble();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Consumo KW - Hoy")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Center(
                  child: Text(
                    DateFormat('yyyy-MM-dd').format(DateTime.now()),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(height: 5),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: Colors.grey),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedDevice,
                      onChanged: (String? newValue) {
                        setState(() {
                          selectedDevice = newValue!;
                          fetchConsumptionData();
                        });
                      },
                      items:
                          devices.map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(
                            value.replaceAll("sensor.", ""),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 30.0, vertical: 8.0),
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 10,
                        getTitlesWidget: (value, meta) {
                          return Text("${value.toInt()}W",
                              style: TextStyle(fontSize: 7));
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(),
                    topTitles: AxisTitles(),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (consumoData.isNotEmpty) {
                            if (value.toInt() == 0 ||
                                value.toInt() == consumoData.length - 1) {
                              return Text(consumoData[value.toInt()]["time"]);
                            }
                          }
                          return Container();
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: consumoData
                          .asMap()
                          .entries
                          .map((e) => FlSpot(
                                e.key.toDouble(),
                                e.value["power"],
                              ))
                          .toList(),
                      isCurved: true,
                      barWidth: 3,
                      color: Colors.blue,
                      dotData: FlDotData(show: false),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  maxY: maxY,
                ),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: DataTable(
                columnSpacing: 20.0,
                columns: [
                  DataColumn(label: Text("Hora")),
                  DataColumn(
                      label: Text("Consumo (W)", textAlign: TextAlign.center)),
                  DataColumn(label: Icon(Icons.power, color: Colors.green)),
                ],
                rows: consumoData.map((item) {
                  return DataRow(cells: [
                    DataCell(Text(item['time'])),
                    DataCell(
                      Center(child: Text("${item['power']}")),
                    ),
                    DataCell(Icon(Icons.electric_bolt, color: Colors.orange)),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
