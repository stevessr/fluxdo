from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, got {count}')
    return text.replace(old, new, 1)

# ChatHub: do not construct inactive protocol surfaces until the user actually
# selects them (or they are restored from preferences). Once activated, keep the
# same IndexedStack slot alive so login/scroll state is preserved.
hub_path = Path('lib/pages/chat/chat_hub_page.dart')
hub = hub_path.read_text()
hub = replace_once(
    hub,
    "  ChatProtocol _selected = ChatProtocol.discourse;\n",
    "  ChatProtocol _selected = ChatProtocol.discourse;\n"
    "  final Set<ChatProtocol> _activated = <ChatProtocol>{};\n"
    "  bool _selectionReady = false;\n"
    "  bool _selectionTouched = false;\n",
    'hub lazy state',
)
hub = replace_once(
    hub,
    "  Future<void> _restoreSelection() async {\n"
    "    final preferences = await SharedPreferences.getInstance();\n"
    "    final restored = chatProtocolFromStorage(\n"
    "      preferences.getString(_selectedProtocolKey),\n"
    "    );\n"
    "    if (!mounted || restored == _selected) return;\n"
    "    setState(() => _selected = restored);\n"
    "  }\n",
    "  Future<void> _restoreSelection() async {\n"
    "    ChatProtocol restored = ChatProtocol.discourse;\n"
    "    try {\n"
    "      final preferences = await SharedPreferences.getInstance();\n"
    "      restored = chatProtocolFromStorage(\n"
    "        preferences.getString(_selectedProtocolKey),\n"
    "      );\n"
    "    } catch (_) {\n"
    "      // Preferences are an optimization. Fall back to Discourse if the\n"
    "      // platform store is temporarily unavailable.\n"
    "    }\n"
    "    if (!mounted) return;\n"
    "    setState(() {\n"
    "      if (!_selectionTouched) {\n"
    "        _selected = restored;\n"
    "      }\n"
    "      _activated.add(_selected);\n"
    "      _selectionReady = true;\n"
    "    });\n"
    "  }\n",
    'hub restore lazily',
)
hub = replace_once(
    hub,
    "  Future<void> _selectProtocol(ChatProtocol protocol) async {\n"
    "    if (_selected != protocol && mounted) {\n"
    "      setState(() => _selected = protocol);\n"
    "    }\n"
    "    final preferences = await SharedPreferences.getInstance();\n"
    "    await preferences.setString(_selectedProtocolKey, protocol.storageValue);\n"
    "  }\n",
    "  Future<void> _selectProtocol(ChatProtocol protocol) async {\n"
    "    if (mounted) {\n"
    "      setState(() {\n"
    "        _selectionTouched = true;\n"
    "        _selectionReady = true;\n"
    "        _selected = protocol;\n"
    "        _activated.add(protocol);\n"
    "      });\n"
    "    }\n"
    "    try {\n"
    "      final preferences = await SharedPreferences.getInstance();\n"
    "      await preferences.setString(\n"
    "        _selectedProtocolKey,\n"
    "        protocol.storageValue,\n"
    "      );\n"
    "    } catch (_) {\n"
    "      // The visible protocol switch should still succeed if persistence\n"
    "      // fails; the next launch will simply use the fallback.\n"
    "    }\n"
    "  }\n\n"
    "  Widget _pageFor(ChatProtocol protocol) {\n"
    "    if (!_activated.contains(protocol)) {\n"
    "      if (!_selectionReady && protocol == _selected) {\n"
    "        return const Center(child: CircularProgressIndicator());\n"
    "      }\n"
    "      return const SizedBox.shrink();\n"
    "    }\n"
    "    return switch (protocol) {\n"
    "      ChatProtocol.discourse => const ChatPage(),\n"
    "      ChatProtocol.matrix => const MatrixChatPage(),\n"
    "      ChatProtocol.telegram => const TelegramChatPage(),\n"
    "    };\n"
    "  }\n",
    'hub selection and builder',
)
hub = replace_once(
    hub,
    "          child: IndexedStack(\n"
    "            index: selectedIndex < 0 ? 0 : selectedIndex,\n"
    "            children: const <Widget>[\n"
    "              ChatPage(),\n"
    "              MatrixChatPage(),\n"
    "              TelegramChatPage(),\n"
    "            ],\n"
    "          ),\n",
    "          child: IndexedStack(\n"
    "            index: selectedIndex < 0 ? 0 : selectedIndex,\n"
    "            children: chatProtocolOrder\n"
    "                .map(_pageFor)\n"
    "                .toList(growable: false),\n"
    "          ),\n",
    'hub lazy indexed stack',
)
hub_path.write_text(hub)

# Room: the underlying route remains mounted when a Thread is pushed. Stop its
# 20-second polling timer while the Thread route is visible, then resume and do
# one latest refresh when returning.
room_path = Path('lib/pages/chat/matrix_room_page.dart')
room = room_path.read_text()
room = replace_once(
    room,
    "    final mediaService = _mediaFor(session);\n"
    "    await Navigator.of(context).push<void>(\n"
    "      MaterialPageRoute<void>(\n"
    "        builder: (_) => thread_ui.MatrixThreadPage(\n"
    "          client: widget.client,\n"
    "          room: widget.room,\n"
    "          root: root,\n"
    "          mediaService: mediaService,\n"
    "        ),\n"
    "      ),\n"
    "    );\n"
    "    if (mounted) {\n"
    "      await _loadLatest(\n"
    "        showSpinner: false,\n"
    "        scrollToBottom: false,\n"
    "        preservePaginationCursor: true,\n"
    "      );\n"
    "    }\n",
    "    final mediaService = _mediaFor(session);\n"
    "    _stopForegroundRefresh();\n"
    "    try {\n"
    "      await Navigator.of(context).push<void>(\n"
    "        MaterialPageRoute<void>(\n"
    "          builder: (_) => thread_ui.MatrixThreadPage(\n"
    "            client: widget.client,\n"
    "            room: widget.room,\n"
    "            root: root,\n"
    "            mediaService: mediaService,\n"
    "          ),\n"
    "        ),\n"
    "      );\n"
    "    } finally {\n"
    "      if (mounted) {\n"
    "        _startForegroundRefresh();\n"
    "        await _loadLatest(\n"
    "          showSpinner: false,\n"
    "          scrollToBottom: false,\n"
    "          preservePaginationCursor: true,\n"
    "        );\n"
    "      }\n"
    "    }\n",
    'pause room refresh behind thread',
)
room_path.write_text(room)

# Telegram: migrate to the 6.2 onDownloadStarting API, let blob/data downloads
# stay inside the WebView engine, and reduce parent rebuilds from progress ticks.
telegram_path = Path('lib/pages/chat/telegram_chat_page.dart')
telegram = telegram_path.read_text()
telegram = replace_once(
    telegram,
    "      return launchUrl(externalUri, mode: LaunchMode.externalApplication);\n",
    "      return await launchUrl(\n"
    "        externalUri,\n"
    "        mode: LaunchMode.externalApplication,\n"
    "      );\n",
    'telegram awaited launch',
)
telegram = replace_once(
    telegram,
    "                onProgressChanged: (controller, progress) {\n"
    "                  if (!mounted) return;\n"
    "                  setState(() => _progress = progress / 100);\n"
    "                },\n",
    "                onProgressChanged: (controller, progress) {\n"
    "                  if (!mounted) return;\n"
    "                  final next = progress / 100;\n"
    "                  if (next < 1 && (next - _progress).abs() < 0.02) return;\n"
    "                  setState(() => _progress = next);\n"
    "                },\n",
    'telegram progress throttling',
)
telegram = replace_once(
    telegram,
    "                onDownloadStartRequest: (controller, request) async {\n"
    "                  final launched = await _launchExternalUri(request.url);\n"
    "                  if (!launched && mounted) {\n"
    "                    setState(() {\n"
    "                      _error = '无法交给系统下载：${request.url}';\n"
    "                    });\n"
    "                  }\n"
    "                },\n",
    "                onDownloadStarting: (controller, request) async {\n"
    "                  final parsed = Uri.tryParse(request.url.toString());\n"
    "                  if (parsed != null &&\n"
    "                      TelegramWebPolicy.shouldUseWebViewDownload(parsed)) {\n"
    "                    return DownloadStartResponse(handled: false);\n"
    "                  }\n"
    "                  final launched = await _launchExternalUri(request.url);\n"
    "                  if (!launched && mounted) {\n"
    "                    setState(() {\n"
    "                      _error = '无法交给系统下载：${request.url}';\n"
    "                    });\n"
    "                  }\n"
    "                  return DownloadStartResponse(handled: true);\n"
    "                },\n",
    'telegram download API',
)
telegram_path.write_text(telegram)

policy_path = Path('lib/services/messaging/telegram_web_policy.dart')
policy = policy_path.read_text()
policy = replace_once(
    policy,
    "  static TelegramWebNavigationDisposition classify(\n",
    "  /// Blob/data downloads are generated by the already-trusted Telegram\n"
    "  /// document and cannot be handed to an external browser meaningfully.\n"
    "  static bool shouldUseWebViewDownload(Uri uri) {\n"
    "    final scheme = uri.scheme.toLowerCase();\n"
    "    return scheme == 'blob' || scheme == 'data';\n"
    "  }\n\n"
    "  static TelegramWebNavigationDisposition classify(\n",
    'telegram download policy helper',
)
policy_path.write_text(policy)

# Keep Matrix timeline parsing and transport validation aligned.
reducer_path = Path('lib/services/messaging/matrix_timeline_reducer.dart')
reducer = reducer_path.read_text()
reducer = replace_once(
    reducer,
    "    if (uri == null || uri.scheme != 'mxc' || uri.authority.isEmpty) return null;\n",
    "    if (uri == null ||\n"
    "        uri.scheme != 'mxc' ||\n"
    "        uri.authority.isEmpty ||\n"
    "        uri.userInfo.isNotEmpty) {\n"
    "      return null;\n"
    "    }\n",
    'mxc userinfo validation',
)
reducer_path.write_text(reducer)

print('Lazy multi-protocol performance wave staged successfully')
