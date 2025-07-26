import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_client.dart';
import 'client_home.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _animationController.forward();

    // Navigate to appropriate screen after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      _navigateToNextScreen();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _navigateToNextScreen() async {
    final user = FirebaseAuth.instance.currentUser;

    if (mounted) {
      if (user != null) {
        // User is logged in, go to client home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ClientHomePage()),
        );
      } else {
        // User is not logged in, go to login
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginClientPage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App Logo (no white square)
                    Image.asset(
                      'assets/images/logo.png',
                      width: 280,
                      height: 280,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.car_repair,
                          size: 140,
                          color: Color(0xFFE30713),
                        );
                      },
                    ),
                    const SizedBox(height: 40),

                    // App Name
                    const Text(
                      'SOS Auto',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE30713),
                        fontFamily: 'Poppins',
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Tagline
                    const Text(
                      'Assistance automobile rapide et fiable',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontFamily: 'Poppins',
                      ),
                    ),

                    const SizedBox(height: 60),

                    // Loading indicator
                    const CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFFE30713),
                      ),
                      strokeWidth: 3,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
