import 'package:flutter/material.dart';

Widget buildStatCard(String title, String value) {
  return Card(
    margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    child: ListTile(
      title: Text(title),
      trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}
