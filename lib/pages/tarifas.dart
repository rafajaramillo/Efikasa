import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'global_tarifa.dart';

class TarifasScreen extends StatefulWidget {
  const TarifasScreen({super.key});

  @override
  State<TarifasScreen> createState() => _TarifasScreenState();
}

class _TarifasScreenState extends State<TarifasScreen> {
  @override
  void initState() {
    super.initState();
    _leerTarifaDesdeArchivo();
  }

  Future<void> _leerTarifaDesdeArchivo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/tarifas.dat');

      if (await file.exists()) {
        final contenido = await file.readAsString();
        setState(() {
          tarifaKwHGlobal = double.tryParse(contenido) ?? tarifaKwHGlobal;
        });
      }
    } catch (e) {
      // Si hay error, se conserva el valor por defecto
    }
  }

  Future<void> _guardarTarifaEnArchivo(double tarifa) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/tarifas.dat');
      await file.writeAsString(tarifa.toStringAsFixed(4));
    } catch (e) {
      // Manejo de errores si es necesario
    }
  }

  void editarTarifa() {
    final controller =
        TextEditingController(text: tarifaKwHGlobal.toStringAsFixed(4));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Tarifa Kw/h'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            hintText: 'Ingrese tarifa en dólares (ej: 0.0920)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nuevaTarifa = double.tryParse(controller.text);
              if (nuevaTarifa != null) {
                setState(() {
                  tarifaKwHGlobal = nuevaTarifa;
                });
                await _guardarTarifaEnArchivo(nuevaTarifa);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tarifa Eléctrica Residencial'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Tarifa Actual ${DateTime.now().year}:\n\$${tarifaKwHGlobal.toStringAsFixed(4)} por Kw/h',
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              ElevatedButton.icon(
                onPressed: editarTarifa,
                icon: const Icon(Icons.edit),
                label: const Text('Editar Tarifa'),
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
