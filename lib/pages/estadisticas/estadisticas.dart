import 'package:flutter/material.dart';
import 'pestana_resumen.dart';
import 'pestana_mas_consumo.dart';
import 'pestana_menos_consumo.dart';
import 'pordispositivo.dart';
//import 'pestana_eficiencia.dart';

class EstadisticasScreen extends StatefulWidget {
  const EstadisticasScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _EstadisticasScreenState createState() => _EstadisticasScreenState();
}

class _EstadisticasScreenState extends State<EstadisticasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Tab> _tabs = [
    Tab(text: 'Resumen'),
    Tab(text: 'Más consumo'),
    Tab(text: 'Menos consumo'),
    Tab(text: 'Por dispositivo'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget buildStatCard(String title, String value) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: ListTile(
        title: Text(title),
        trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Estadísticas de Consumo'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // PESTAÑAS DE LA PANTALLA ESTADÍSTICAS
          PestanaResumen(),
          PestanaMasConsumo(),
          PestanaMenosConsumo(),
          PorDispositivo(),
          //PestanaEficiencia(),
        ],
      ),
    );
  }
}
