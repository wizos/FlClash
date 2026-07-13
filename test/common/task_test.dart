import 'package:fl_clash/common/task.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('toGroupsTask preserves group proxy current node', () async {
    final groups = await toGroupsTask(
      ComputeGroupsState(
        proxiesData: ProxiesData(
          all: const ['Root', 'A', 'node-a'],
          proxies: {
            'Root': {
              'name': 'Root',
              'type': GroupType.Selector.name,
              'all': ['A'],
            },
            'A': {
              'name': 'A',
              'type': GroupType.URLTest.name,
              'now': 'node-a',
              'all': ['node-a'],
            },
            'node-a': {'name': 'node-a', 'type': 'ss'},
          },
        ),
        sortType: ProxiesSortType.none,
        delayMap: const {},
        selectedMap: const {},
        defaultTestUrl: '',
      ),
    );

    expect(groups.getGroup('A')?.now, 'node-a');
    expect(groups.getGroup('Root')?.all.single.now, 'node-a');
    expect(groups.getGroup('A')?.all.single.name, 'node-a');
    expect(groups.getGroup('A')?.all.single.type, 'ss');
  });
}
