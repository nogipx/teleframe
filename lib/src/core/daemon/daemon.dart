/// Vendored daemon-process launcher.
///
/// Inlined from nogipx/rpc_dart `others/daemon_launcher` and stripped of its
/// rpc_dart dependency — its only coupling was `RpcLogger`, now replaced by
/// teleframe's own `log()`. This keeps teleframe free of any rpc_dart pin, so
/// it composes with a host workspace that pins a different rpc_dart revision.
library;

export 'daemon_launcher.dart';
export 'daemon_log.dart';
export 'pid_file_manager.dart';
export 'runtime_invocation.dart';