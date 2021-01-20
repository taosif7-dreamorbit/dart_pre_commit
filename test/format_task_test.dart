import 'package:dart_pre_commit/src/format_task.dart';
import 'package:dart_pre_commit/src/program_runner.dart';
import 'package:dart_pre_commit/src/task_base.dart';
import 'package:dart_pre_commit/src/task_exception.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:tuple/tuple.dart'; // ignore: import_of_legacy_library_into_null_safe

import 'format_task_test.mocks.dart';
import 'global_mocks.dart';
import 'test_with_data.dart';

@GenerateMocks([
  ProgramRunner,
])
void main() {
  final fakeEntry = FakeEntry('mock.dart');

  final mockRunner = MockProgramRunner();

  late FormatTask sut;

  setUp(() {
    reset(mockRunner);

    when(mockRunner.run(any, any)).thenAnswer((_) async => 0);

    sut = FormatTask(
      programRunner: mockRunner,
    );
  });

  test('task metadata is correct', () {
    expect(sut.taskName, 'format');
  });

  testWithData<Tuple2<String, bool>>(
    'matches only dart/pubspec.yaml files',
    const [
      Tuple2('test1.dart', true),
      Tuple2('test/path2.dart', true),
      Tuple2('test3.g.dart', true),
      Tuple2('test4.dart.g', false),
      Tuple2('test5_dart', false),
      Tuple2('test6.dat', false),
    ],
    (fixture) {
      expect(
        sut.filePattern.matchAsPrefix(fixture.item1),
        fixture.item2 ? isNotNull : isNull,
      );
    },
  );

  test('calls dart format with correct arguments', () async {
    final res = await sut(fakeEntry);
    expect(res, TaskResult.accepted);
    verify(mockRunner.run(
      'dart',
      const [
        'format',
        '--fix',
        '--set-exit-if-changed',
        'mock.dart',
      ],
    ));
  });

  test('returns true if dart format returns 1', () async {
    when(mockRunner.run(any, any)).thenAnswer((_) async => 1);
    final res = await sut(fakeEntry);
    expect(res, TaskResult.modified);
  });

  test('throws exception if dart format returns >1', () async {
    when(mockRunner.run(any, any)).thenAnswer((_) async => 42);
    expect(() => sut(fakeEntry), throwsA(isA<TaskException>()));
  });
}
