import 'package:flutter/material.dart';

import '../widgets/mini_player.dart';
import 'discover_screen.dart';
import 'library_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [DiscoverScreen(), SearchScreen(), LibraryScreen(), ProfileScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            // Offstage tabs in the IndexedStack keep their focus; drop it so the search field's keyboard
            // doesn't pop up over another tab.
            FocusManager.instance.primaryFocus?.unfocus();
            setState(() => _index = i);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore), label: 'Keşfet'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Ara'),
            NavigationDestination(
                icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Kitaplık'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil'),
          ],
        ),
      ]),
    );
  }
}
