import 'package:cinder/cinder.dart';

void main() {
  runApp(
    const CinderApp(
      child: Center(
        child: IconTheme(
          data: IconThemeData(renderMode: IconRenderMode.unicode),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TerminalIcons.home),
              SizedBox(width: 2),
              Icon(TerminalIcons.search),
              SizedBox(width: 2),
              Icon(TerminalIcons.warning),
            ],
          ),
        ),
      ),
    ),
  );
}
