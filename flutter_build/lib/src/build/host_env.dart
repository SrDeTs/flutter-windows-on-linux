//
//
//   lld: error: unable to find library -lepoxy
//

const Set<String> kHostBuildFlagVars = {
  'CFLAGS',
  'CXXFLAGS',
  'CPPFLAGS',
  'LDFLAGS',
  'CPATH',
  'C_INCLUDE_PATH',
  'CPLUS_INCLUDE_PATH',
  'OBJC_INCLUDE_PATH',
  'LIBRARY_PATH',
  'PKG_CONFIG_PATH',
  'PKG_CONFIG_LIBDIR',
  'PKG_CONFIG_SYSROOT_DIR',
  'CMAKE_PREFIX_PATH',
};

///
Map<String, String> sanitizedCrossBuildEnv(
  Map<String, String> base, {
  Map<String, String>? overrides,
}) {
  final env = <String, String>{
    for (final entry in base.entries)
      if (!kHostBuildFlagVars.contains(entry.key)) entry.key: entry.value,
  };
  if (overrides != null) env.addAll(overrides);
  return env;
}
