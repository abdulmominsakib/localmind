import 'package:flutter/material.dart';
import 'sidebar_widget.dart';

class ConversationDrawer extends StatelessWidget {
  const ConversationDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Drawer(child: SidebarWidget());
  }
}
