//
//   - isAot: debug=false, profile/release=true

import 'package:flutter_build/src/engine_artifacts.dart';
import 'package:test/test.dart';

void main() {
  group('group_case_991', () {
    test('test_case_992', () {
      expect(WindowsFlavor.debug.isAot, isFalse);
    });

    test('test_case_996', () {
      expect(WindowsFlavor.profile.isAot, isTrue);
    });

    test('test_case_1000', () {
      expect(WindowsFlavor.release.isAot, isTrue);
    });

    test('test_case_1004', () {
      expect(WindowsFlavor.release.isProduct, isTrue);
      expect(WindowsFlavor.profile.isProduct, isFalse);
      expect(WindowsFlavor.debug.isProduct, isFalse);
    });

    test('test_case_1010', () {
      expect(WindowsFlavor.debug.cliName, 'debug');
      expect(WindowsFlavor.profile.cliName, 'profile');
      expect(WindowsFlavor.release.cliName, 'release');
    });

    test('test_case_1016', () {
      expect(WindowsFlavor.release.kernelModeDefines,
          containsAll(['dart.vm.product=true', 'dart.vm.profile=false']));
      expect(WindowsFlavor.profile.kernelModeDefines,
          containsAll(['dart.vm.product=false', 'dart.vm.profile=true']));
      expect(WindowsFlavor.debug.kernelModeDefines,
          containsAll(['dart.vm.product=false', 'dart.vm.profile=false']));
    });
  });
}
