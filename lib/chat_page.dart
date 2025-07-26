import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'widgets/custom_app_bar.dart';

class ChatPage extends StatefulWidget {
  final String technicianId;
  final String technicianName;
  final String clientId;

  const ChatPage({
    Key? key,
    required this.technicianId,
    required this.technicianName,
    required this.clientId,
  }) : super(key: key);

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  String get chatId {
    List<String> ids = [widget.clientId, widget.technicianId]..sort();
    return "${ids[0]}_${ids[1]}";
  }

  @override
  void initState() {
    super.initState();
    _markMessagesAsRead();
  }

  void _markMessagesAsRead() async {
    final chatRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages');
    final snapshot = await chatRef
        .where('senderId', isEqualTo: widget.technicianId)
        .where('seenByClient', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      await doc.reference.update({'seenByClient': true});
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Send the new message
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
          'text': text,
          'senderId': widget.clientId,
          'senderType': 'client',
          'timestamp': FieldValue.serverTimestamp(),
          'seenByClient': true,
          'seenByTechnician': false,
        });

    // Mark all previous messages from technician as read by client
    final chatRef = FirebaseFirestore.instance
        .collection('chats')
        .doc(chatId)
        .collection('messages');
    final snapshot = await chatRef
        .where('senderId', isEqualTo: widget.technicianId)
        .where('seenByClient', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      await doc.reference.update({'seenByClient': true});
    }

    _controller.clear();
    _scrollController.animateTo(
      0.0,
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: CustomAppBar(
        title: '${widget.technicianName}',
        showBackButton: true,
        showImage: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatId)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Erreur: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final isMe = data['senderId'] == widget.clientId;
                    return Align(
                      alignment: isMe
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.symmetric(
                          vertical: 4,
                          horizontal: 12,
                        ),
                        padding: EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: isMe ? Color(0xFFE30713) : Colors.grey[200],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          data['text'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                            fontFamily: 'Poppins',
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Écrivez un message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: Color(0xFFE30713)),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
