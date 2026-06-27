import 'dart:async';
import 'dart:io' show SocketException;

import 'package:dartssh2/dartssh2.dart';

import '../core/app_error.dart';
import 'host_key_store.dart';

/// Opens a host-key-pinned SSH client as `<user>@host`, runs [body] against it,
/// and tears the connection down — the single place the connect / auth /
/// host-key-verify / teardown lifecycle lives. Shared by the buffered command
/// runner ([SshRunner]), the bootstrap mint, and (M3) the interactive PTY, so the
/// lifecycle is written and fixed once.
///
/// Never logs anything; [body] decides what (if anything) is safe to surface.
Future<T> withSshClient<T>({
  required String host,
  required int port,
  required String user,
  required List<SSHKeyPair> identities,
  required HostKeyStore hostKeys,
  required Duration timeout,
  required Future<T> Function(SSHClient client) body,
}) async {
  final socket = await SSHSocket.connect(host, port, timeout: timeout);
  SSHClient? client;
  try {
    client = SSHClient(
      socket,
      username: user,
      identities: identities,
      onVerifyHostKey: hostKeys.verifier('$host:$port'),
    );
    return await body(client);
  } finally {
    // SSHClient.close() owns the socket; if construction threw, close it directly.
    if (client != null) {
      client.close();
    } else {
      socket.destroy();
    }
  }
}

/// Map a dartssh2 transport failure to a typed [AppError], or null if [e] is not
/// a transport error this layer recognizes (the caller rethrows). The analogue of
/// the orchestrator's `classifySSHError` — here we match dartssh2's typed
/// exceptions instead of scraping stderr. Messages are generic and never echo the
/// exception detail (which could carry sensitive material). Shared so RC, mint,
/// and the M3 PTY classify transport failures identically.
AppError? classifySshException(Object e) {
  // SSHAuthError / SSHHostkeyError both implement SSHError, so check them first.
  if (e is SSHAuthError) {
    return AppError('SSH_AUTH_DENIED', 'SSH authentication denied', 401);
  }
  if (e is SSHHostkeyError) return AppError.hostKeyMismatch();
  if (e is SSHError) {
    return AppError('SSH_UNREACHABLE', 'SSH connection failed', 502);
  }
  if (e is SocketException) {
    return AppError('SSH_UNREACHABLE', 'SSH connection failed', 502);
  }
  if (e is TimeoutException) {
    return AppError('SSH_UNREACHABLE', 'SSH connection timed out', 502);
  }
  return null;
}
