from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

# Main Matrix client owns its default Dio but must not close an injected/shared
# transport. dispose() clears only in-memory state; persisted auth remains intact.
client_path = Path('lib/services/matrix_client_service.dart')
client = client_path.read_text()
client = replace_once(
    client,
    "  }) : _dio = dio ?? Dio(),\n"
    "       _secureStorage = secureStorage ?? const FlutterSecureStorage();\n",
    "  }) : _dio = dio ?? Dio(),\n"
    "       _ownsDio = dio == null,\n"
    "       _secureStorage = secureStorage ?? const FlutterSecureStorage();\n",
    'client ownership initializer',
)
client = replace_once(
    client,
    "  final Dio _dio;\n  final FlutterSecureStorage _secureStorage;\n",
    "  final Dio _dio;\n  final bool _ownsDio;\n  final FlutterSecureStorage _secureStorage;\n",
    'client ownership field',
)
client = replace_once(
    client,
    "  Future<void> _persistSession(MatrixSession session) async {\n",
    "  void dispose() {\n"
    "    _session = null;\n"
    "    _resetSyncState();\n"
    "    if (_ownsDio) {\n"
    "      _dio.close(force: true);\n"
    "    }\n"
    "  }\n\n"
    "  Future<void> _persistSession(MatrixSession session) async {\n",
    'client dispose',
)
client_path.write_text(client)

# SSO companion follows the same ownership rule.
sso_path = Path('lib/services/messaging/matrix_sso_service.dart')
sso = sso_path.read_text()
sso = replace_once(
    sso,
    "class MatrixSsoService {\n"
    "  MatrixSsoService({Dio? dio}) : _dio = dio ?? Dio();\n\n"
    "  final Dio _dio;\n",
    "class MatrixSsoService {\n"
    "  MatrixSsoService({Dio? dio})\n"
    "    : _dio = dio ?? Dio(),\n"
    "      _ownsDio = dio == null;\n\n"
    "  final Dio _dio;\n"
    "  final bool _ownsDio;\n",
    'sso ownership',
)
sso = replace_once(
    sso,
    "  static String _normalizeBaseUrl(String value) {\n",
    "  void dispose() {\n"
    "    if (_ownsDio) {\n"
    "      _dio.close(force: true);\n"
    "    }\n"
    "  }\n\n"
    "  static String _normalizeBaseUrl(String value) {\n",
    'sso dispose',
)
sso_path.write_text(sso)

# Discovery currently converts Dio into a closure and loses the handle. Keep an
# owned handle only for internally-created transports; withTransport remains a
# no-op disposable test seam.
discovery_path = Path('lib/services/messaging/matrix_homeserver_discovery.dart')
discovery = discovery_path.read_text()
discovery = replace_once(
    discovery,
    "class MatrixHomeserverDiscoveryService {\n"
    "  MatrixHomeserverDiscoveryService({Dio? dio})\n"
    "    : _get = _dioTransport(dio ?? Dio());\n\n"
    "  MatrixHomeserverDiscoveryService.withTransport(MatrixDiscoveryGet transport)\n"
    "    : _get = transport;\n\n"
    "  final MatrixDiscoveryGet _get;\n",
    "class MatrixHomeserverDiscoveryService {\n"
    "  MatrixHomeserverDiscoveryService({Dio? dio})\n"
    "    : this._withDio(dio ?? Dio(), ownsDio: dio == null);\n\n"
    "  MatrixHomeserverDiscoveryService._withDio(\n"
    "    Dio dio, {\n"
    "    required bool ownsDio,\n"
    "  }) : _get = _dioTransport(dio),\n"
    "       _ownedDio = ownsDio ? dio : null;\n\n"
    "  MatrixHomeserverDiscoveryService.withTransport(MatrixDiscoveryGet transport)\n"
    "    : _get = transport,\n"
    "      _ownedDio = null;\n\n"
    "  final MatrixDiscoveryGet _get;\n"
    "  final Dio? _ownedDio;\n",
    'discovery ownership',
)
discovery = replace_once(
    discovery,
    "  static String? serverNameFromInput(String input) {\n",
    "  void dispose() {\n"
    "    _ownedDio?.close(force: true);\n"
    "  }\n\n"
    "  static String? serverNameFromInput(String input) {\n",
    'discovery dispose',
)
discovery_path.write_text(discovery)

# The page owns all three default services and closes them with its route. This
# does not log the user out; MatrixClientService.dispose leaves secure storage.
page_path = Path('lib/pages/chat/matrix_chat_page.dart')
page = page_path.read_text()
page = replace_once(
    page,
    "  void dispose() {\n"
    "    _homeserverController.dispose();\n",
    "  void dispose() {\n"
    "    _client.dispose();\n"
    "    _discovery.dispose();\n"
    "    _sso.dispose();\n"
    "    _homeserverController.dispose();\n",
    'page service disposal',
)
page_path.write_text(page)

print('Matrix transport lifecycle cleanup staged successfully')
