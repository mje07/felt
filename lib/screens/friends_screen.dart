import 'dart:async';
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:poker_engine/poker_engine.dart';

import '../app/controller.dart';
import '../app/history_store.dart';
import '../app/settings.dart';
import '../app/theme.dart';
import '../net/client.dart';
import '../net/host.dart';
import '../net/protocol.dart';
import '../net/relay_link.dart';
import '../widgets/common.dart';
import '../widgets/controls.dart';
import 'lesson_screen.dart';
import 'table_screen.dart';

const _stakes = [(5, 10), (25, 50), (100, 200), (500, 1000)];

/// The table config a home game plays with (the same on every PC).
TableConfig homeGameConfig(HomeGameSettings s) => TableConfig(
      homeGame: true,
      mode: s.tournament ? GameMode.sitAndGo : GameMode.cash,
      seats: s.seats,
      smallBlind: s.smallBlind,
      bigBlind: s.bigBlind,
      sngBuyIn: 0,
      speed: s.speed,
      startingStack: StartingStack.values.firstWhere((x) => x.chips == s.startingStack, orElse: () => StartingStack.standard),
      difficulty: Difficulty.standard,
      eventName: s.name,
    );

/// Play with friends: host a table on this PC, or join one on the network.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.history});
  final HistoryStore history;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  var _hosting = true;

  // Host form.
  late final _gameName = TextEditingController(text: 'Home game');
  var _seats = 6;
  var _tournament = false;
  var _stake = 0;
  var _speed = BlindSpeed.turbo;
  var _bots = true;
  var _seconds = 30;

  // Join form.
  final _address = TextEditingController();
  final _code = TextEditingController();
  late final _relay = TextEditingController(text: SettingsScope.of(context).relayUrl);
  String? _relayError;
  final _discovery = LanDiscovery();
  StreamSubscription<List<LanGame>>? _lanSub;
  List<LanGame> _lan = const [];

  // A table being set up (hosting) or waited on (joined).
  HomeGameHost? _host;
  HomeGameClient? _client;
  List<String> _addresses = const [];
  String? _error;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    _discovery.start();
    _lanSub = _discovery.games.listen((g) {
      if (mounted) setState(() => _lan = g);
    });
  }

  @override
  void dispose() {
    _lanSub?.cancel();
    _discovery.stop();
    _host?.close();
    _client?.leave();
    _gameName.dispose();
    _address.dispose();
    _code.dispose();
    _relay.dispose();
    super.dispose();
  }

  String get _playerName => SettingsScope.of(context).playerName;

  Future<void> _openTable() async {
    final (sb, bb) = _stakes[_stake];
    final settings = HomeGameSettings(
      name: _gameName.text.trim().isEmpty ? 'Home game' : _gameName.text.trim(),
      seats: _seats,
      tournament: _tournament,
      smallBlind: _tournament ? 10 : sb,
      bigBlind: _tournament ? 20 : bb,
      speed: _speed,
      // A Sit & Go needs every seat taken; bots fill the gaps.
      fillWithBots: _tournament || _bots,
      actionSeconds: _seconds,
    );
    final host = HomeGameHost(settings, hostName: _playerName);
    final relayUrl = SettingsScope.of(context).relayUrl;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await host.listen();
    } on SocketException {
      try {
        await host.listen(port: 0);
      } on SocketException catch (e) {
        setState(() {
          _busy = false;
          _error = 'Couldn\'t open a table on this PC (${e.osError?.message ?? e.message}).';
        });
        return;
      }
    }
    _relayError = null;
    final relay = relayBase(relayUrl);
    if (relay != null) {
      try {
        await host.openRelay(relay);
      } catch (_) {
        _relayError = 'Couldn\'t reach the invite-code server at ${relay.host}, so there\'s no code this time. '
            'Friends can still join on your network or by address.';
      }
    }
    final addresses = await localAddresses();
    if (!mounted) {
      unawaited(host.close());
      return;
    }
    host.addListener(_changed);
    setState(() {
      _host = host;
      _addresses = addresses;
      _busy = false;
    });
  }

  void _changed() {
    if (mounted) setState(() {});
    final c = _client;
    if (c != null && c.started && ModalRoute.of(context)?.isCurrent == true) _sitAtFriendsTable(c);
  }

  Future<void> _join(Uri uri) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = HomeGameClient(await SocketChannel.connect(uri), name: _playerName);
      await client.join();
      client.addListener(_changed);
      setState(() {
        _client = client;
        _busy = false;
      });
      if (client.started) _sitAtFriendsTable(client);
    } on StateError catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      setState(() {
        _busy = false;
        _error = 'Couldn\'t reach a Felt table at ${uri.host}:${uri.port}.';
      });
    }
  }

  Uri? _parseAddress(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^\[?([^\]\s]+?)\]?(?::(\d{1,5}))?$').firstMatch(t);
    if (m == null) return null;
    return Uri(scheme: 'ws', host: m[1], port: int.tryParse(m[2] ?? '') ?? defaultGamePort, path: '/felt');
  }

  void _startGame() {
    final host = _host!;
    host.markStarted();
    host.removeListener(_changed);
    _host = null;
    Navigator.of(context)
        .push(CupertinoPageRoute<void>(
          builder: (_) => TableScreen(config: homeGameConfig(host.settings), history: widget.history, host: host),
        ))
        .then((_) => host.close());
    setState(() {});
  }

  void _sitAtFriendsTable(HomeGameClient client) {
    client.removeListener(_changed);
    _client = null;
    Navigator.of(context)
        .push(CupertinoPageRoute<void>(
          builder: (_) => TableScreen(config: homeGameConfig(client.settings), history: widget.history, client: client),
        ))
        .then((_) => client.leave());
    setState(() {});
  }

  Future<void> _cancel() async {
    final h = _host, c = _client;
    setState(() {
      _host = null;
      _client = null;
    });
    await h?.close();
    await c?.leave();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final Widget body;
    if (_host != null) {
      body = _hostLobby(p, _host!);
    } else if (_client != null) {
      body = _joinedLobby(p, _client!);
    } else {
      body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Play with friends', style: Typo.largeTitle(p.label)),
        const SizedBox(height: Space.s),
        Text(
          'Host a table on this PC and friends join from theirs, on the same network or by address. '
          'Your PC deals and runs the game; each player only ever receives their own cards. '
          'Home games are for play chips and never touch your bankroll.',
          style: Typo.body(p.secondaryLabel).copyWith(fontSize: 17, height: 1.5),
        ),
        const SizedBox(height: Space.xl),
        ChoiceChips<bool>(
          value: _hosting,
          options: const {true: 'Host a game', false: 'Join a game'},
          onChanged: (v) => setState(() {
            _hosting = v;
            _error = null;
          }),
        ),
        const SizedBox(height: Space.l),
        if (_hosting) _hostForm(p) else _joinForm(p),
        if (_error != null) ...[
          const SizedBox(height: Space.m),
          Text(_error!, style: Typo.callout(p.destructive)),
        ],
      ]);
    }
    return CupertinoPageScaffold(
      backgroundColor: p.isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
      child: SafeArea(
        child: Column(children: [
          backRow(context),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.xxl, Space.xxl),
              child: Center(
                child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: body),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _hostForm(Palette p) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SettingsCard(title: 'Your table', icon: CupertinoIcons.person_3_fill, children: [
          SettingRow(label: 'Name', trailing: FeltTextField(controller: _gameName, maxLength: 24, width: 220)),
          SettingRow(
            label: 'Game',
            trailing: ChoiceChips<bool>(
              value: _tournament,
              options: const {false: 'Cash', true: 'Sit & Go'},
              onChanged: (v) => setState(() => _tournament = v),
            ),
          ),
          SettingRow(
            label: 'Seats',
            trailing: ChoiceChips<int>(
              value: _seats,
              options: const {2: '2', 4: '4', 6: '6', 9: '9'},
              onChanged: (v) => setState(() => _seats = v),
            ),
          ),
          if (_tournament)
            SettingRow(
              label: 'Blinds',
              detail: 'Starts at 10/20 with 1,500 chips each.',
              trailing: ChoiceChips<BlindSpeed>(
                value: _speed,
                options: {for (final s in BlindSpeed.values) s: s.label},
                onChanged: (v) => setState(() => _speed = v),
              ),
            )
          else
            SettingRow(
              label: 'Stakes',
              detail: 'Everyone starts with 100 big blinds and rebuys for free.',
              trailing: ChoiceChips<int>(
                value: _stake,
                options: {
                  for (var i = 0; i < _stakes.length; i++) i: '${formatChips(_stakes[i].$1)}/${formatChips(_stakes[i].$2)}',
                },
                onChanged: (v) => setState(() => _stake = v),
              ),
            ),
          SettingRow(
            label: 'Fill empty seats with bots',
            detail: _tournament ? 'Always on for a Sit & Go.' : null,
            trailing: FeltToggle(value: _tournament || _bots, onChanged: _tournament ? null : (v) => setState(() => _bots = v)),
          ),
          SettingRow(
            label: 'Time to act',
            detail: 'Out of time: check if possible, otherwise fold.',
            trailing: ChoiceChips<int>(
              value: _seconds,
              options: const {15: '15s', 30: '30s', 60: '60s'},
              onChanged: (v) => setState(() => _seconds = v),
            ),
          ),
        ]),
        const SizedBox(height: Space.xl),
        PillButton(label: 'Open table', style: PillStyle.filled, minWidth: 220, onPressed: _busy ? null : _openTable),
        const SizedBox(height: Space.xxl),
        _relayCard(p),
      ]);

  Widget _joinForm(Palette p) {
    final typed = _parseAddress(_address.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SettingsCard(title: 'On your network', icon: CupertinoIcons.wifi, children: [
        if (_lan.isEmpty)
          const SettingRow(label: 'Looking for games…', detail: 'Tables hosted on this network appear here.')
        else
          for (final g in _lan)
            SettingRow(
              label: g.name,
              detail: '${g.players} of ${g.seats} seats · ${g.host}',
              trailing: PillButton(label: 'Join', minWidth: 0, height: 32, onPressed: _busy ? null : () => _join(g.uri)),
            ),
      ]),
      const SizedBox(height: Space.l),
      SettingsCard(title: 'Invite code', icon: CupertinoIcons.globe, children: [
        if (relayBase(SettingsScope.of(context).relayUrl) == null)
          const SettingRow(
            label: 'Invite codes are off',
            detail: 'Set an invite-code server below to join friends anywhere with a 6-letter code.',
          )
        else
          SettingRow(
            label: 'Code from the host',
            trailing: FeltTextField(
              controller: _code,
              placeholder: 'K7QH2M',
              maxLength: inviteCodeLength,
              width: 160,
              onChanged: (_) => setState(() {}),
            ),
            below: Padding(
              padding: const EdgeInsets.only(top: Space.s),
              child: PillButton(
                label: 'Join with code',
                minWidth: 0,
                height: 32,
                onPressed: _busy || _code.text.trim().length != inviteCodeLength
                    ? null
                    : () => _join(relayJoinUri(relayBase(SettingsScope.of(context).relayUrl)!, _code.text)),
              ),
            ),
          ),
      ]),
      const SizedBox(height: Space.l),
      SettingsCard(title: 'By address', icon: CupertinoIcons.link, children: [
        SettingRow(
          label: 'Host address',
          detail: 'The address the host sees, like 192.168.1.20 or 192.168.1.20:$defaultGamePort.',
          trailing: FeltTextField(
            controller: _address,
            placeholder: '192.168.1.20',
            width: 220,
            onChanged: (_) => setState(() {}),
          ),
        ),
      ]),
      const SizedBox(height: Space.xl),
      PillButton(
        label: _busy ? 'Joining…' : 'Join by address',
        style: PillStyle.filled,
        minWidth: 220,
        onPressed: _busy || typed == null ? null : () => _join(typed),
      ),
      const SizedBox(height: Space.xxl),
      _relayCard(p),
    ]);
  }

  /// Where invite codes come from: a relay the player (or a friend) runs.
  Widget _relayCard(Palette p) => SettingsCard(
        title: 'Invite-code server',
        icon: CupertinoIcons.cloud,
        children: [
          SettingRow(
            label: 'Server address',
            detail: 'For games over the internet. Felt includes a small relay you can deploy for free (see the '
                'README); everyone at the table uses the same address. Leave empty to play on your network only.',
            trailing: FeltTextField(
              controller: _relay,
              placeholder: 'felt-relay.fly.dev',
              width: 220,
              onChanged: (v) {
                final s = SettingsScope.of(context);
                s.update((s) => s.relayUrl = v.trim());
                setState(() {});
              },
            ),
          ),
        ],
      );
  Widget _seatList(Palette p, List<(String, bool)> players, int seats) => SettingsCard(
        title: 'At the table · ${players.length} of $seats',
        icon: CupertinoIcons.person_2_fill,
        children: [
          for (final (name, on) in players)
            SettingRow(
              label: name,
              trailing: Text(on ? 'Connected' : 'Reconnecting…', style: Typo.callout(on ? p.positive : p.secondaryLabel)),
            ),
        ],
      );

  Widget _hostLobby(Palette p, HomeGameHost host) {
    final port = host.port ?? defaultGamePort;
    final where = _addresses.isEmpty
        ? 'this PC\'s address'
        : _addresses.map((a) => port == defaultGamePort ? a : '$a:$port').join(' or ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(host.settings.name, style: Typo.largeTitle(p.label)),
      const SizedBox(height: Space.s),
      Text(
        'Friends on this network see the table under "Join a game". From elsewhere they can join at $where '
        '(port $port has to be reachable, for example with port forwarding or a VPN like Tailscale).',
        style: Typo.body(p.secondaryLabel).copyWith(height: 1.5),
      ),
      const SizedBox(height: Space.xl),
      if (host.inviteCode != null) ...[
        _InviteCode(code: host.inviteCode!),
        const SizedBox(height: Space.l),
      ] else if (_relayError != null) ...[
        Text(_relayError!, style: Typo.callout(p.secondaryLabel)),
        const SizedBox(height: Space.l),
      ],
      _seatList(p, [(host.hostName, true), for (final f in host.players) (f.name, f.connected)], host.settings.seats),
      const SizedBox(height: Space.xl),
      Wrap(spacing: Space.s, runSpacing: Space.s, children: [
        PillButton(
          label: 'Start game',
          sublabel: host.players.isEmpty
              ? (host.settings.fillWithBots ? 'Just you and the bots so far' : 'Waiting for friends')
              : '${host.players.length} friend${host.players.length == 1 ? '' : 's'} joined',
          style: PillStyle.filled,
          minWidth: 240,
          onPressed: host.players.isEmpty && !host.settings.fillWithBots ? null : _startGame,
        ),
        PillButton(label: 'Close table', onPressed: _cancel),
      ]),
    ]);
  }

  Widget _joinedLobby(Palette p, HomeGameClient c) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(c.settings.name, style: Typo.largeTitle(p.label)),
        const SizedBox(height: Space.s),
        Text(
          c.ended ?? 'You\'re in. ${c.hostName} starts the game when everyone has arrived.',
          style: Typo.body(c.ended != null ? p.destructive : p.secondaryLabel).copyWith(height: 1.5),
        ),
        const SizedBox(height: Space.xl),
        _seatList(p, [for (final (name, _, on) in c.lobby) (name, on)], c.settings.seats),
        const SizedBox(height: Space.xl),
        PillButton(label: 'Leave', onPressed: _cancel),
      ]);
}

/// The invite code, big and easy to read out over a call.
class _InviteCode extends StatelessWidget {
  const _InviteCode({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return GlassPanel(
      radius: Radii.l,
      padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.l),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('INVITE CODE', style: Typo.caption(p.secondaryLabel).copyWith(letterSpacing: 0.8)),
            const SizedBox(height: 4),
            Text(code, style: Typo.number(p.label, size: 34, weight: FontWeight.w700).copyWith(letterSpacing: 6)),
            const SizedBox(height: 4),
            Text('Friends enter this under Join a game, from anywhere.', style: Typo.callout(p.secondaryLabel)),
          ]),
        ),
        PillButton(
          label: 'Copy',
          minWidth: 0,
          onPressed: () => Clipboard.setData(ClipboardData(text: code)),
        ),
      ]),
    );
  }
}
