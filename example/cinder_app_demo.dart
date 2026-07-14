import 'package:cinder/cinder.dart';

/// Demo showcasing the CinderApp widget and its ability to set terminal window titles
///
/// This example demonstrates:
/// - Setting a window title declaratively using CinderApp
/// - Setting both window title and icon name separately
/// - Dynamically updating the title based on user interaction
///
/// The window title will appear in your terminal emulator's title bar
void main() async {
  await runApp(const CinderAppDemoApp());
}

class CinderAppDemoApp extends StatefulWidget {
  const CinderAppDemoApp({super.key});

  @override
  State<CinderAppDemoApp> createState() => _CinderAppDemoAppState();
}

class _CinderAppDemoAppState extends State<CinderAppDemoApp> {
  int _counter = 0;
  String _currentTitle = 'CinderApp Demo';

  @override
  Widget build(BuildContext context) {
    return CinderApp(
      // The title parameter sets the terminal window title
      // This appears in your terminal emulator's title bar
      title: _currentTitle,

      // The iconName parameter sets the icon name (primarily used in X11)
      iconName: 'CinderDemo',

      child: Focusable(
        focused: true,
        onKeyEvent: (event) {
          if (event.character == ' ') {
            setState(() {
              _counter++;
              _currentTitle = 'CinderApp Demo - Count: $_counter';
            });
            return true;
          } else if (event.character?.toLowerCase() == 'r') {
            setState(() {
              _counter = 0;
              _currentTitle = 'CinderApp Demo';
            });
            return true;
          } else if (event.character?.toLowerCase() == 'q') {
            shutdownApp();
            return true;
          }
          return false;
        },
        child: Center(
          child: Container(
            decoration: BoxDecoration(
              border: BoxBorder.all(style: BoxBorderStyle.rounded),
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      'CinderApp Demo',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(''),
                  Text(
                      'This demo showcases the CinderApp widget, which provides'),
                  Text('a declarative way to set terminal window titles.'),
                  Text(''),
                  const Divider(),
                  Text(''),
                  Text('Current window title: "$_currentTitle"'),
                  Text('Icon name: "CinderDemo"'),
                  Text(''),
                  const Divider(),
                  Text(''),
                  Center(
                    child: Text(
                      'Counter: $_counter',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(''),
                  const Divider(),
                  Text(''),
                  Text('Controls:'),
                  Text('  [Space] - Increment counter (updates window title)'),
                  Text('  [R]     - Reset counter'),
                  Text('  [Q]     - Quit'),
                  Text(''),
                  Center(
                    child: Text(
                      'Look at your terminal window title bar!',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        color: Color.fromRGB(100, 200, 255),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
