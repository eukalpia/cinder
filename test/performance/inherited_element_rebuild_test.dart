import 'package:cinder/cinder.dart';
import 'package:test/test.dart';

class BuildTracker extends StatelessWidget {
  final VoidCallback onBuild;
  const BuildTracker({required this.onBuild, super.key});

  @override
  Widget build(BuildContext context) {
    onBuild();
    return const SizedBox();
  }
}

class MyDataWidget extends InheritedWidget {
  final int value;

  const MyDataWidget({
    required this.value,
    required super.child,
  });

  @override
  bool updateShouldNotify(MyDataWidget old) => value != old.value;
}

void main() {
  test('Standard InheritedWidget triggers redundant builds', () {
    int builds = 0;
    final tracker = BuildTracker(onBuild: () => builds++);

    // Initial Mount
    final first = MyDataWidget(value: 100, child: tracker);
    final element = first.createElement();
    element.mount(null, null);

    builds = 0; // Reset after initial mount

    // Update with identical data.. NO REBUILD NEEDED
    final second = MyDataWidget(value: 100, child: tracker);
    element.update(second);

    expect(
      builds,
      0,
      reason: 'Subtree should not rebuild if updateShouldNotify is false',
    );
  });
}
