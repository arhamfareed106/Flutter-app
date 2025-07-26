import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'client_home.dart';
import 'register_client.dart';
import 'widgets/custom_app_bar.dart';

class LoginClientPage extends StatefulWidget {
  const LoginClientPage({super.key});

  @override
  State<LoginClientPage> createState() => _LoginClientPageState();
}

class _LoginClientPageState extends State<LoginClientPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _rememberMe = false;
  final _auth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _rememberMe = prefs.getBool('rememberMe') ?? false;
        if (_rememberMe) {
          _emailController.text = prefs.getString('email') ?? '';
          _passwordController.text = prefs.getString('password') ?? '';
        }
      });
    } catch (e) {
      print('Error loading saved credentials: $e');
    }
  }

  Future<void> _saveCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setBool('rememberMe', true);
        await prefs.setString('email', _emailController.text);
        await prefs.setString('password', _passwordController.text);
      } else {
        await prefs.clear();
      }
    } catch (e) {
      print('Error saving credentials: $e');
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (userCredential.user != null) {
        await _saveCredentials();
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const ClientHomePage()),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      String message = 'Erreur lors de la connexion';
      if (e.code == 'user-not-found') {
        message = 'Aucun utilisateur trouvé avec cet email.';
      } else if (e.code == 'wrong-password') {
        message = 'Mot de passe incorrect.';
      } else if (e.code == 'invalid-email') {
        message = 'Format d\'email invalide.';
      } else if (e.code == 'user-disabled') {
        message = 'Ce compte a été désactivé.';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Color(0xFFe30713)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Une erreur est survenue. Veuillez réessayer.'),
            backgroundColor: Color(0xFFe30713),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const redColor = Color(0xFFe30713);
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final width = mediaQuery.size.width;
    final height = mediaQuery.size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth = constraints.maxWidth;
          final maxHeight = constraints.maxHeight;
          final horizontalPadding = maxWidth * 0.06;
          final logoHeight = isPortrait ? maxHeight * 0.22 : maxHeight * 0.35;
          final verticalSpacing = maxHeight * 0.03;

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalSpacing,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: maxHeight * 0.06),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: logoHeight,
                    ),
                  ),
                  SizedBox(height: maxHeight * 0.04),
                  const Text(
                    'Bienvenue cher Client !',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Poppins',
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: maxHeight * 0.012),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
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
                  SizedBox(height: maxHeight * 0.04),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre email';
                      }
                      if (!value.contains('@')) {
                        return 'Veuillez entrer un email valide';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: maxHeight * 0.025),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Mot de passe',
                      prefixIcon: Icon(Icons.lock),
                      border: OutlineInputBorder(),
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Veuillez entrer votre mot de passe';
                      }
                      if (value.length < 6) {
                        return 'Le mot de passe doit contenir au moins 6 caractères';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: maxHeight * 0.012),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberMe,
                        onChanged: (value) {
                          setState(() {
                            _rememberMe = value ?? false;
                          });
                        },
                        activeColor: redColor,
                      ),
                      const Text('Se souvenir de moi'),
                    ],
                  ),
                  SizedBox(height: maxHeight * 0.04),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          horizontal: maxWidth * 0.1,
                          vertical: maxHeight * 0.018,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Se connecter',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(height: maxHeight * 0.025),
                  GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const RegisterClientPage(),
                      ),
                    ),
                    child: const Text(
                      'Pas encore de compte ? S\'inscrire',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(height: maxHeight * 0.02),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
