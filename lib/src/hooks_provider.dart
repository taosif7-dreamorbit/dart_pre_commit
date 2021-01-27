import 'dart:io';

import 'package:dart_pre_commit/dart_pre_commit.dart';
import 'package:riverpod/all.dart'; // ignore: import_of_legacy_library_into_null_safe

import 'hooks.dart';
import 'tasks/analyze_task.dart';
import 'tasks/fix_imports_task.dart';
import 'tasks/format_task.dart';
import 'tasks/pull_up_dependencies_task.dart';
import 'util/file_resolver.dart';
import 'util/logger.dart';
import 'util/logging/console_logger.dart';
import 'util/logging/simple_logger.dart';
import 'util/program_runner.dart';

/// The configuration to create dependency-injected [Hooks] via [HooksProvider].
class HooksConfig {
  /// Specifies, whether the [FixImportsTask] should be enabled.
  final bool fixImports;

  /// Specifies, whether the [FormatTask] should be enabled.
  final bool format;

  /// Specifies, whether the [AnalyzeTask] should be enabled.
  final bool analyze;

  /// Specifies, whether the [PullUpDependenciesTask] should be enabled.
  final bool pullUpDependencies;

  /// Sets [Hooks.continueOnRejected].
  final bool continueOnRejected;

  /// A list of additional tasks to be added to the hook.
  ///
  /// These are added in addition to the four primary tasks. They are always
  /// added last to the hook, so they will also run last. If you need more
  /// control over the order, instanciate the primary tasks by hand, using
  /// [HooksProviderInternal]
  final List<TaskBase>? extraTasks;

  /// Default constructor.
  const HooksConfig({
    this.fixImports = false,
    this.format = false,
    this.analyze = false,
    this.pullUpDependencies = false,
    this.continueOnRejected = false,
    this.extraTasks,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! HooksConfig) {
      return false;
    }
    return fixImports == other.fixImports &&
        format == other.format &&
        analyze == other.analyze &&
        pullUpDependencies == other.pullUpDependencies &&
        continueOnRejected == other.continueOnRejected &&
        extraTasks == other.extraTasks;
  }

  @override
  int get hashCode =>
      runtimeType.hashCode ^
      fixImports.hashCode ^
      format.hashCode ^
      analyze.hashCode ^
      pullUpDependencies.hashCode ^
      continueOnRejected.hashCode ^
      extraTasks.hashCode;
}

/// A static class to give scope to [hookProvider].
///
/// If you need access to all the internal providers, use
/// [HooksProviderInternal].
abstract class HooksProvider {
  const HooksProvider._();

  /// Returns a riverpod provider family to create [Hooks].
  ///
  /// This provider uses the dependency injection of riverpod. You have to pass
  /// a [HooksConfig] to the provider to create a corresponding hooks instance.
  ///
  /// Makes use of [HooksProviderInternal] to get all the required parameters
  /// and tasks for the hooks instance.
  static final hookProvider = FutureProvider.family(
    (ref, HooksConfig param) async => Hooks(
      logger: ref.watch(HooksProviderInternal.loggerProvider),
      fileResolver: ref.watch(HooksProviderInternal.fileResolverProvider),
      programRunner: ref.watch(HooksProviderInternal.programRunnerProvider),
      continueOnRejected: param.continueOnRejected,
      tasks: [
        if (param.fixImports)
          await ref.watch(HooksProviderInternal.fixImportsProvider.future),
        if (param.format) ref.watch(HooksProviderInternal.formatProvider),
        if (param.analyze) ref.watch(HooksProviderInternal.analyzeProvider),
        if (param.pullUpDependencies)
          ref.watch(HooksProviderInternal.pullUpDependenciesProvider),
        if (param.extraTasks != null) ...param.extraTasks!,
      ],
    ),
  );
}

/// A static class that contains all internally used providers.
abstract class HooksProviderInternal {
  const HooksProviderInternal._();

  /// A simple provider for [ConsoleLogger] as [Logger]
  static final consoleLoggerProvider = Provider<Logger>(
    (ref) => ConsoleLogger(),
  );

  /// A simple provider for [SimpleLogger] as [Logger]
  static final simpleLoggerProvider = Provider<Logger>(
    (ref) => SimpleLogger(),
  );

  static Provider<Logger> get loggerProvider =>
      stdout.hasTerminal && stdout.supportsAnsiEscapes
          ? consoleLoggerProvider
          : simpleLoggerProvider;

  /// A simple provider for [TaskLogger]
  ///
  /// This is simply [loggerProvider], but as a [TaskLogger] view.
  static final taskLoggerProvider = Provider<TaskLogger>(
    (ref) => ref.watch(loggerProvider),
  );

  /// A simple provider for [FileResolver].
  static final fileResolverProvider = Provider(
    (ref) => FileResolver(),
  );

  /// A simple provider for [ProgramRunner].
  ///
  /// Uses [taskLoggerProvider].
  static final programRunnerProvider = Provider(
    (ref) => ProgramRunner(
      logger: ref.watch(taskLoggerProvider),
    ),
  );

  /// A simple provider for [FixImportsTask].
  ///
  /// Uses [taskLoggerProvider].
  static final fixImportsProvider = FutureProvider(
    (ref) => FixImportsTask.current(
      logger: ref.watch(taskLoggerProvider),
    ),
  );

  /// A simple provider for [FormatTask].
  ///
  /// Uses [programRunnerProvider].
  static final formatProvider = Provider(
    (ref) => FormatTask(
      programRunner: ref.watch(programRunnerProvider),
    ),
  );

  /// A simple provider for [AnalyzeTask].
  ///
  /// Uses [fileResolverProvider], [programRunnerProvider] and
  /// [taskLoggerProvider].
  static final analyzeProvider = Provider(
    (ref) => AnalyzeTask(
      fileResolver: ref.watch(fileResolverProvider),
      programRunner: ref.watch(programRunnerProvider),
      logger: ref.watch(taskLoggerProvider),
    ),
  );

  /// A simple provider for [PullUpDependenciesTask].
  ///
  /// Uses [fileResolverProvider], [programRunnerProvider] and
  /// [taskLoggerProvider].
  static final pullUpDependenciesProvider = Provider(
    (ref) => PullUpDependenciesTask(
      fileResolver: ref.watch(fileResolverProvider),
      programRunner: ref.watch(programRunnerProvider),
      logger: ref.watch(taskLoggerProvider),
    ),
  );
}
