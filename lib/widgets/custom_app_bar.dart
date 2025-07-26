import 'package:flutter/material.dart';
import '../profil_client.dart';
import '../client_home.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showBackButton;
  final bool showImage;

  const CustomAppBar({
    super.key,
    required this.title,
    this.showBackButton = false,
    this.showImage = true,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      centerTitle: true,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      title: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFe30713),
              fontFamily: 'Poppins',
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            width: title.length * 12.0,
            height: 2.0,
            color: Colors.black,
          ),
        ],
      ),
      actions: [
        if (showImage)
          Padding(
            padding: const EdgeInsets.only(right: 10.0),
            child: GestureDetector(
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ClientHomePage(),
                  ),
                  (route) => false,
                );
              },
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    height: 40,
                    width: 40,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
