//

import '../build_context.dart';
import '../msvc_flag_translator.dart';
import 'build_stage.dart';

class TranslateFlagsStage extends BuildStage {
  TranslateFlagsStage({super.logger, super.runner});

  @override
  String get name => 'translate MSVC flags';

  @override
  Future<void> run(BuildContext ctx) async {
    await MsvcFlagTranslator(logger: log).transformTree(ctx.windowsStageDir);
  }
}
