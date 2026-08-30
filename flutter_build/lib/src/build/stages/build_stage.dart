//
//

import '../../logger.dart';
import '../../process_runner.dart';
import '../build_context.dart';

///
abstract class BuildStage {
  BuildStage({Logger? logger, ProcessRunner? runner})
      : log = logger ?? Logger.instance,
        runner = runner ?? ProcessRunner(logger: logger ?? Logger.instance);

  final Logger log;

  final ProcessRunner runner;

  String get name;

  bool shouldRun(BuildContext ctx) => true;

  Future<void> run(BuildContext ctx);
}
