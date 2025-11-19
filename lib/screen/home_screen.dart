import 'package:flutter/material.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {

  Object? salom = "Assalomu alaykum";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          makeSnack("$salom", context);
        },
        child: Icon(Icons.add),
      ),
      backgroundColor: Colors.green,
      appBar: AppBar(
        title: Text("Salom  dunyo"),
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        backgroundColor: Colors.teal,
        leading: IconButton(
          icon: Icon(Icons.menu, color: Colors.blue),
          onPressed: () {
            makeSnack("Menu ezildi", context);
          },
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: Colors.deepOrange),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.save, color: Colors.purpleAccent),
            onPressed: () {},
          ),
        ],

        leadingWidth: 30,

        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.red, Colors.purpleAccent, Colors.pink],
            ),
          ),
        ),

        centerTitle: false,
      ),
    );
  }

  static void makeSnack(String a, context) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$a")));
  }
}
