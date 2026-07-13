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

import 'filter_bar.dart';
import 'item.dart';

class ActivityView extends ConsumerStatefulWidget {
  const ActivityView({super.key});

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

class _ActivityViewState extends ConsumerState<ActivityView> {
  final _stateNotifier = ValueNotifier<ActivityState>(const ActivityState());
  List<TrackerInfo> _requests = [];
  Set<String> _activeConnectionIds = {};
  late final ScrollController _scrollController;
  Timer? _connectionTimer;
  bool _isPollingConnections = false;

  void _onSearch(String value) {
    _stateNotifier.value = _stateNotifier.value.copyWith(query: value);
  }

  void _onKeywordsUpdate(List<String> keywords) {
    _stateNotifier.value = _stateNotifier.value.copyWith(keywords: keywords);
  }

  @override
  void initState() {
    super.initState();
    _requests = ref.read(requestsProvider).list;
    _scrollController = ScrollController(initialScrollOffset: double.maxFinite);
    _refreshActivities();
    ref.listenManual(requestsProvider.select((state) => state.list), (
      prev,
      next,
    ) {
      _requests = next;
      _updateActivitiesThrottler();
    });
    ref.listenManual(currentPageLabelProvider, (_, next) {
      if (next == PageLabel.activity) {
        _startConnectionPolling();
      } else {
        _stopConnectionPolling();
      }
    });
    if (ref.read(currentPageLabelProvider) == PageLabel.activity) {
      _startConnectionPolling();
    }
  }

  void _startConnectionPolling() {
    if (_connectionTimer != null || _isPollingConnections) return;
    _pollConnections();
  }

  void _stopConnectionPolling() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  Future<void> _pollConnections() async {
    if (!mounted || ref.read(currentPageLabelProvider) != PageLabel.activity) {
      _stopConnectionPolling();
      return;
    }
    _isPollingConnections = true;
    try {
      final connections = await coreController.getConnections();
      _activeConnectionIds = connections.map((c) => c.id).toSet();
      _updateActivitiesThrottler();
    } catch (_) {}
    _isPollingConnections = false;
    if (!mounted || ref.read(currentPageLabelProvider) != PageLabel.activity) {
      _stopConnectionPolling();
      return;
    }
    _connectionTimer = Timer(const Duration(seconds: 1), () {
      _connectionTimer = null;
      _pollConnections();
    });
  }

  void _updateActivitiesThrottler() {
    throttler.call(FunctionTag.requests, () {
      if (!mounted) return;
      _refreshActivities();
    }, duration: commonDuration);
  }

  void _refreshActivities() {
    final items = _requests
        .map(
          (info) => ActivityItem(
            trackerInfo: info,
            status: inferStatus(info, _activeConnectionIds),
          ),
        )
        .toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _stateNotifier.value = _stateNotifier.value.copyWith(items: items);
      }
    });
  }

  Future<void> _handleBlockConnection(String id) async {
    coreController.closeConnection(id);
  }

  @override
  void dispose() {
    _stopConnectionPolling();
    _stateNotifier.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      IconButton(
        onPressed: () async {
          ref.read(requestsProvider.notifier).clear();
        },
        tooltip: context.appLocalizations.clearActivity,
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return CommonScaffold(
      title: appLocalizations.activity,
      searchState: AppBarSearchState(onSearch: _onSearch),
      onKeywordsUpdate: _onKeywordsUpdate,
      actions: _buildActions(context),
      floatingActionButton: ValueListenableBuilder(
        valueListenable: _stateNotifier,
        builder: (_, state, _) {
          final autoScrollToEnd = state.autoScrollToEnd;
          return FadeRotationScaleBox(
            child: FloatingActionButton(
              key: ValueKey(autoScrollToEnd),
              onPressed: () {
                _stateNotifier.value = _stateNotifier.value.copyWith(
                  autoScrollToEnd: !_stateNotifier.value.autoScrollToEnd,
                );
              },
              child: autoScrollToEnd
                  ? const Icon(Icons.keyboard_arrow_down)
                  : const Icon(Icons.push_pin),
            ),
          );
        },
      ),
      body: ValueListenableBuilder<ActivityState>(
        valueListenable: _stateNotifier,
        builder: (context, state, _) {
          final items = state.filteredList;
          if (items.isEmpty) {
            return NullStatus(label: appLocalizations.activityEmpty);
          }
          return Column(
            children: [
              ActivityFilterBar(
                currentFilter: state.filterStatus,
                onFilterChanged: (status) {
                  _stateNotifier.value = _stateNotifier.value.copyWith(
                    filterStatus: () => status,
                  );
                },
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: CommonScrollBar(
                    trackVisibility: false,
                    controller: _scrollController,
                    child: ScrollToEndBox(
                      controller: _scrollController,
                      dataSource: items,
                      enable: state.autoScrollToEnd,
                      onCancelToEnd: () {
                        _stateNotifier.value = _stateNotifier.value.copyWith(
                          autoScrollToEnd: false,
                        );
                      },
                      child: SuperListView.builder(
                        reverse: true,
                        shrinkWrap: true,
                        physics: const NextClampingScrollPhysics(),
                        controller: _scrollController,
                        itemBuilder: (_, index) {
                          if (index.isOdd) {
                            return const Divider(height: 0);
                          }
                          final activityItem = items[index ~/ 2];
                          return ActivityItemWidget(
                            key: Key(activityItem.trackerInfo.id),
                            activityItem: activityItem,
                            onClickKeyword: (value) {
                              context.commonScaffoldState?.addKeyword(value);
                            },
                            trailing:
                                activityItem.status == ActivityStatus.ongoing
                                ? IconButton(
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    style: IconButton.styleFrom(
                                      minimumSize: Size.zero,
                                    ),
                                    icon: const Icon(Icons.block),
                                    onPressed: () {
                                      _handleBlockConnection(
                                        activityItem.trackerInfo.id,
                                      );
                                    },
                                  )
                                : null,
                          );
                        },
                        itemCount: items.length * 2 - 1,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
