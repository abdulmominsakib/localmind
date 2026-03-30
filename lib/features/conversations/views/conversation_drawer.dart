import 'package:flutter/material.dart';
import 'conversation_sidebar.dart';

class ConversationDrawer extends StatelessWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Drawer(
      child: ConversationSidebar(),
    );
  }
}

