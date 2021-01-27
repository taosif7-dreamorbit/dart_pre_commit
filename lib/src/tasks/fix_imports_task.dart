import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart'; // ignore: import_of_legacy_library_into_null_safe
import 'package:crypto/crypto.dart'; // ignore: import_of_legacy_library_into_null_safe
import 'package:path/path.dart';
import 'package:yaml/yaml.dart';

import '../repo_entry.dart';
import '../task_base.dart';
import '../util/logger.dart';

/// A task that scans dart files for unclean imports and fixes them.
///
/// This task consists of two steps, wich are run on all staged dart files:
/// 1. Make absolute package imports relative
/// 2. Organize imports
///
/// The first step simply checks if any library imports another library from the
/// same package via an absolute package import. If that is the case, the import
/// is simply replaced by a relative one.
///
/// The second step collects all imports of the file and the sorts them. They
/// are grouped into dart imports, package imports and relative imports, each
/// group seperated by a newline and the internally sorted alphabetically.
///
/// If any of these steps had to modify the file, it saves the changes to the
/// file and returns a [TaskResult.modified] result.
///
/// {@category tasks}
class FixImportsTask implements FileTask {
  /// The name if the package that is beeing scanned.
  ///
  /// Must be the same as declared in the `pubspec.yaml`.
  final String packageName;

  /// The path to the lib folder in this package.
  ///
  /// This is almost always simply `'lib'`.
  final Directory libDir;

  /// The [TaskLogger] instance used by this task.
  final TaskLogger logger;

  /// Default Constructor.
  ///
  /// See [FixImportsTask.current()] for a simply instanciation.
  const FixImportsTask({
    required this.packageName,
    required this.libDir,
    required this.logger,
  });

  /// Creates a [FixImportsTask] based on the current repository.
  ///
  /// This method looks and the `pubspec.yaml` in the current directory and uses
  /// it to figure out the [packageName] and [libDir]. The [logger] is passed to
  /// [this.logger].
  static Future<FixImportsTask> current({
    required TaskLogger logger,
  }) async {
    final pubspecFile = File('pubspec.yaml');
    final yamlData = loadYamlDocument(
      await pubspecFile.readAsString(),
      sourceUrl: pubspecFile.uri,
    ).contents as YamlMap;

    return FixImportsTask(
      libDir: Directory('lib'),
      packageName: yamlData.value['name'] as String,
      logger: logger,
    );
  }

  @override
  String get taskName => 'fix-imports';

  @override
  Pattern get filePattern => RegExp(r'^.*\.dart$');

  @override
  Future<TaskResult> call(RepoEntry entry) async {
    final inDigest = AccumulatorSink<Digest>();
    final outDigest = AccumulatorSink<Digest>();
    final result = await Stream.fromFuture(entry.file.readAsString())
        .transform(const LineSplitter())
        .shaSum(inDigest)
        .relativize(
          packageName: packageName,
          file: entry.file,
          libDir: libDir,
          logger: logger,
        )
        .organizeImports(logger)
        .shaSum(outDigest)
        .withNewlines()
        .join();

    if (inDigest.events.single != outDigest.events.single) {
      logger.debug('File has been modified, writing changes...');
      await entry.file.writeAsString(result);
      logger.debug('Write successful');
      return TaskResult.modified;
    } else {
      logger.debug('No imports modified, keeping file as is');
      return TaskResult.accepted;
    }
  }
}

extension _ImportFixExtensions on Stream<String> {
  Stream<String> shaSum(AccumulatorSink<Digest> sink) async* {
    final input = sha512.startChunkedConversion(sink);
    try {
      await for (final part in this) {
        input.add(utf8.encode(part));
        yield part;
      }
    } finally {
      input.close();
    }
  }

  Stream<String> relativize({
    required String packageName,
    required File file,
    required Directory libDir,
    required TaskLogger logger,
  }) async* {
    if (!isWithin(libDir.path, file.path)) {
      yield* this;
      return;
    }

    final regexp = RegExp(
        """^\\s*import\\s*(['"])package:$packageName\\/([^'"]*)['"]([^;]*);\\s*(\\/\\/.*)?\$""");

    await for (final line in this) {
      final trimmedLine = line.trim();
      final match = regexp.firstMatch(trimmedLine);
      if (match != null) {
        logger.debug('Relativizing $trimmedLine');
        final quote = match[1];
        final importPath = match[2];
        final postfix = match[3];
        final comment = match[4] != null ? ' ${match[4]}' : '';
        final relativeImport = relative(
          join('lib', importPath),
          from: file.parent.path,
        ).replaceAll('\\', '/');

        yield 'import $quote$relativeImport$quote$postfix;$comment';
      } else {
        yield line;
      }
    }
  }

  Stream<String> organizeImports(TaskLogger logger) async* {
    final dartRegexp = RegExp(
      r"""^\s*import\s+(?:"|')dart:[^;]+;\s*(?:\/\/.*)?$""",
    );
    final packageRegexp = RegExp(
      r"""^\s*import\s+(?:"|')package:[^;]+;\s*(?:\/\/.*)?$""",
    );
    final relativeRegexp = RegExp(
      r"""^\s*import\s+(?:"|')(?!package:|dart:)[^;]+;\s*(?:\/\/.*)?$""",
    );

    final prefixCode = <String>[];
    final dartImports = <String>[];
    final packageImports = <String>[];
    final relativeImports = <String>[];
    final code = <String>[];

    // split into import types and code
    await for (final line in this) {
      if (dartRegexp.hasMatch(line)) {
        dartImports.add(line.trim());
      } else if (packageRegexp.hasMatch(line)) {
        packageImports.add(line.trim());
      } else if (relativeRegexp.hasMatch(line)) {
        relativeImports.add(line.trim());
      } else if (dartImports.isEmpty &&
          packageImports.isEmpty &&
          relativeImports.isEmpty) {
        prefixCode.add(line);
      } else {
        code.add(line);
      }
    }

    // remove leading/trailing empty lines
    while (code.isNotEmpty && code.first.trim().isEmpty) {
      code.removeAt(0);
    }
    while (code.isNotEmpty && code.last.trim().isEmpty) {
      code.removeLast();
    }

    // sort individual imports
    logger.debug('Sorting imports...');
    dartImports.sort((a, b) => a.compareTo(b));
    packageImports.sort((a, b) => a.compareTo(b));
    relativeImports.sort((a, b) => a.compareTo(b));

    // yield into result
    yield* Stream.fromIterable(prefixCode);
    if (dartImports.isNotEmpty) {
      yield* Stream.fromIterable(dartImports);
      yield '';
    }
    if (packageImports.isNotEmpty) {
      yield* Stream.fromIterable(packageImports);
      yield '';
    }
    if (relativeImports.isNotEmpty) {
      yield* Stream.fromIterable(relativeImports);
      yield '';
    }
    yield* Stream.fromIterable(code);
  }

  Stream<String> withNewlines() async* {
    await for (final line in this) {
      yield '$line\n';
    }
  }
}
