import 'package:flutter/material.dart';

class SingupPage extends StatelessWidget {
  const SingupPage({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color.fromARGB(255, 23, 248, 143),
          body: Center(
            child: Text(
              "SINGUP",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ));
  }
}
