import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'item.dart';

class ConnectionsView extends ConsumerStatefulWidget {
  const ConnectionsView({super.key});

  @override
  ConsumerState<ConnectionsView> createState() => _ConnectionsViewState();
}

class _ConnectionsViewState extends ConsumerState<ConnectionsView> {
  final _connectionsStateNotifier = ValueNotifier<TrackerInfosState>(
    const TrackerInfosState(),
  );
  final ScrollController _scrollController = ScrollController();

  Timer? timer;
  bool _isUpdatingConnections = false;

  List<Widget> _buildActions() {
    return [
      IconButton(
        onPressed: () async {
          coreController.closeConnections();
          await _updateConnections();
        },
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  void _onSearch(String value) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      query: value,
    );
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      keywords: keywords,
    );
  }

  Future<void> _updateConnectionsTask() async {
    if (_isUpdatingConnections || timer != null) return;
    _isUpdatingConnections = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted &&
            ref.read(currentPageLabelProvider) == PageLabel.connections) {
          await _updateConnections();
          if (!mounted ||
              ref.read(currentPageLabelProvider) != PageLabel.connections) {
            _stopPolling();
            return;
          }
          timer = Timer(const Duration(seconds: 1), () {
            timer = null;
            _updateConnectionsTask();
          });
        } else {
          _stopPolling();
        }
      } finally {
        _isUpdatingConnections = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(currentPageLabelProvider, (_, next) {
      if (next == PageLabel.connections) {
        _updateConnectionsTask();
      } else {
        _stopPolling();
      }
    });
    if (ref.read(currentPageLabelProvider) == PageLabel.connections) {
      _updateConnectionsTask();
    }
  }

  Future<void> _updateConnections() async {
    _connectionsStateNotifier.value = _connectionsStateNotifier.value.copyWith(
      trackerInfos: await coreController.getConnections(),
    );
  }

  Future<void> _handleBlockConnection(String id) async {
    await coreController.closeConnection(id);
    await _updateConnections();
  }

  @override
  void dispose() {
    _stopPolling();
    _connectionsStateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _stopPolling() {
    timer?.cancel();
    timer = null;
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.connections,
      onKeywordsUpdate: _onKeywordsUpdate,
      searchState: AppBarSearchState(onSearch: _onSearch),
      actions: _buildActions(),
      body: ValueListenableBuilder<TrackerInfosState>(
        valueListenable: _connectionsStateNotifier,
        builder: (context, state, _) {
          final connections = state.list;
          if (connections.isEmpty) {
            return NullStatus(
              label: appLocalizations.nullTip(appLocalizations.connections),
              illustration: const ConnectionEmptyIllustration(),
            );
          }
          return SuperListView.builder(
            controller: _scrollController,
            itemBuilder: (context, index) {
              if (index.isOdd) {
                return const Divider(height: 0);
              }
              final trackerInfo = connections[index ~/ 2];
              return TrackerInfoItem(
                key: Key(trackerInfo.id),
                trackerInfo: trackerInfo,
                onClickKeyword: (value) {
                  context.commonScaffoldState?.addKeyword(value);
                },
                trailing: IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(minimumSize: Size.zero),
                  icon: const Icon(Icons.block),
                  onPressed: () {
                    _handleBlockConnection(trackerInfo.id);
                  },
                ),
                detailTitle: appLocalizations.details(
                  appLocalizations.connection,
                ),
              );
            },
            itemCount: connections.length * 2 - 1,
          );
        },
      ),
    );
  }
}
