import 'package:flutter/material.dart';
import 'dart:io';

class CategoriasScreen extends StatelessWidget {
  final int selectedIndex;

  const CategoriasScreen({super.key, this.selectedIndex = 0});

  void _onItemTapped(BuildContext context, int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacementNamed(context, "/dashboard");
        break;
      case 1:
        Navigator.pushReplacementNamed(context, "/editprofile");
        break;
      case 2:
        Navigator.pushReplacementNamed(context, "/about");
        break;
    }
  }

  void _cerrarAplicacion() {
    exit(0); // Cierra la aplicación por completo
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          appBar: AppBar(
            title: Text("Categories",
                style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: PopupMenuButton<String>(
              icon: Icon(Icons.menu, color: Colors.black),
              onSelected: (value) {
                if (value == "compartir") {
                  Navigator.pushNamed(context, "/compartir");
                } else if (value == "cerrar") {
                  _cerrarAplicacion();
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem(
                  value: "compartir",
                  child: ListTile(
                    leading: Icon(Icons.share, color: Colors.black),
                    title: Text("Compartir aplicación"),
                  ),
                ),
                PopupMenuItem(
                  value: "cerrar",
                  child: ListTile(
                    leading: Icon(Icons.exit_to_app, color: Colors.red),
                    title: Text("Cerrar aplicación"),
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: Icon(Icons.search, color: Colors.black),
                onPressed: () {}, // Funcionalidad de búsqueda
              ),
            ],
          ),
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: [
                _buildCategoryItem(context, "Consumo KW",
                    "assets/icons/consumo.png", "/dashboard"),
                _buildCategoryItem(context, "Dispositivos",
                    "assets/icons/dispositivos.png", "/dispositivos"),
                _buildCategoryItem(context, "Historico Consumo",
                    "assets/icons/historico.png", "/historico"),
                _buildCategoryItem(
                    context, "Alertas", "assets/icons/alertas.png", "/alertas"),
                _buildCategoryItem(context, "Predicciones",
                    "assets/icons/prediccion.png", "/PrediccionConsumo"),
                _buildCategoryItem(context, "Estadísticas",
                    "assets/icons/estadisticas.png", "/estadisticas"),
                _buildCategoryItem(
                    context, "Tarifas", "assets/icons/tarifas.png", "/tarifas"),
                _buildCategoryItem(context, "Consejos de Ahorro",
                    "assets/icons/consejos.png", "/consejos"),
              ],
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex:
                selectedIndex, // Mantiene el estado del icono seleccionado
            onTap: (index) =>
                _onItemTapped(context, index), // Llama al método al hacer clic

            items: [
              BottomNavigationBarItem(
                  icon: Icon(Icons.home,
                      color: selectedIndex == 0 ? Colors.green : Colors.grey),
                  label: "Inicio"),
              BottomNavigationBarItem(
                  icon: Icon(Icons.person,
                      color: selectedIndex == 1 ? Colors.green : Colors.grey),
                  label: "Perfil"),
              BottomNavigationBarItem(
                  icon: Icon(Icons.add_card,
                      color: selectedIndex == 2 ? Colors.green : Colors.grey),
                  label: "Acerca"),
            ],
            selectedFontSize: 12,
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.bold),
          ),
        ));
  }

  Widget _buildCategoryItem(
      BuildContext context, String title, String iconPath, String route) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(context, route);
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black12, blurRadius: 5, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(iconPath, height: 60),
            SizedBox(height: 10),
            Text(
              title.toUpperCase(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
