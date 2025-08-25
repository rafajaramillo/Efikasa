import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
//import 'package:flutter_dotenv/flutter_dotenv.dart';

class ConsejosScreen extends StatefulWidget {
  const ConsejosScreen({super.key});

  @override
  _ConsejosScreenState createState() => _ConsejosScreenState();
}

class _ConsejosScreenState extends State<ConsejosScreen> {
  // API Key de YouTube Data API v3 (REEMPLAZA ESTO CON TU API KEY)
  final String _apiKey = "AIzaSyBj8oaEAY_4DSFNavLH0wBMNpU1qw2UcwE";
  //final String _apiKey = '${dotenv.env['YOUTUBE_API_KEY']}';

  // Lista de IDs de videos de YouTube
  final List<String> _videoIds = [
    "2feoyVpXfCg",
    "LyK3F7PLzAg",
    "pT0Z6NffUx8",
    "sZouYaWX0SY",
    "qT3M8MxCE8c"
  ];

  // Mapa para almacenar los títulos de los videos
  final Map<String, String> _videoTitles = {};

  @override
  void initState() {
    super.initState();
    _obtenerTitulos();
  }

  // Función para obtener los títulos de los videos usando la YouTube Data API
  Future<void> _obtenerTitulos() async {
    for (var videoId in _videoIds) {
      try {
        final url =
            "https://www.googleapis.com/youtube/v3/videos?part=snippet&id=$videoId&key=$_apiKey";
        final response = await http.get(Uri.parse(url));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final title = data['items'][0]['snippet']['title'];
          setState(() {
            _videoTitles[videoId] = title;
          });
        } else {
          setState(() {
            _videoTitles[videoId] = "Título no disponible";
          });
        }
      } catch (e) {
        setState(() {
          _videoTitles[videoId] = "Error al cargar título";
        });
      }
    }
  }

  // Función para abrir enlaces de YouTube
  void _abrirEnlace(String url) async {
    final uri = Uri.parse(url);

    // Intentamos primero con canLaunchUrl y, si falla, forzamos el launch
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Como no lo detectó, lo lanzamos a la fuerza (debería funcionar si AndroidManifest está bien)
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.black),
          onPressed: () {
            Navigator.pushReplacementNamed(context, "/categorias");
          },
        ),
        title: Text(
          "Consejos para Ahorrar energía",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: _videoIds.map((videoId) {
              return _buildCard(
                context,
                videoId,
                "https://www.youtube.com/watch?v=$videoId",
                "https://img.youtube.com/vi/$videoId/maxresdefault.jpg",
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  // Widget para construir cada tarjeta de video
  Widget _buildCard(
      BuildContext context, String videoId, String url, String imageUrl) {
    return GestureDetector(
      onTap: () => _abrirEnlace(url),
      child: Card(
        margin: EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(15), topRight: Radius.circular(15)),
              child: Image.network(
                imageUrl,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Mostrar título o indicador de carga si aún no está listo
                  Expanded(
                    child: Text(
                      _videoTitles[videoId] ?? "Cargando...",
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Icon(Icons.arrow_forward, color: Colors.grey),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
