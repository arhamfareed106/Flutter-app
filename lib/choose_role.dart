import 'package:flutter/material.dart';
import 'login_client.dart';

class ChooseRolePage extends StatelessWidget {
  const ChooseRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F4FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFD63D33), // Rouge SOS AUTO
        title: const Text(
          'Bienvenue sur SOS AUTO',
          style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset('assets/images/logo.png', height: 150),
            const SizedBox(height: 30),
            const Text(
              'Bienvenue !',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
                color: Color(0xFFD63D33),
              ),
            ),
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.0),
              child: Text(
                'Nous sommes là pour vous aider en cas de besoin sur la route',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontFamily: 'Poppins',
                  color: Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person),
                    label: const Text('Je suis Client'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD63D33),
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LoginClientPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
