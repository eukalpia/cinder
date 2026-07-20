import 'package:cinder/cinder.dart';

void main() {
  runApp(const InfiniteListBrowserAdapter());
}

class InfiniteListBrowserAdapter extends StatelessWidget {
  const InfiniteListBrowserAdapter({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.magenta)),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text(
                ' INFINITE LIST / WEB ADAPTER ',
                style: TextStyle(
                  color: Colors.magenta,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text('LAZY BUILDER', style: TextStyle(color: Colors.green)),
            ],
          ),
          const SizedBox(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: 1000000,
              itemExtent: 1,
              lazy: true,
              cacheExtent: 12,
              keyboardScrollable: true,
              itemBuilder: (context, index) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('item ${(index + 1).toString().padLeft(7, '0')}'),
                    Text(
                      index.isEven ? 'EVEN' : 'ODD',
                      style: TextStyle(
                        color: index.isEven ? Colors.cyan : Colors.yellow,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 1),
          const Text(
            'Arrow keys, Page Up/Down, Home/End, and the mouse wheel scroll only visible rows.',
            style: TextStyle(color: Colors.gray),
          ),
        ],
      ),
    );
  }
}
