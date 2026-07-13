import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ActivityDetailView extends ConsumerStatefulWidget {
  final ActivityItem activityItem;

  const ActivityDetailView({super.key, required this.activityItem});

  @override
  ConsumerState<ActivityDetailView> createState() => _ActivityDetailViewState();
}

class _ActivityDetailViewState extends ConsumerState<ActivityDetailView> {
  late TrackerInfo _trackerInfo;
  late ActivityStatus _status;
  Timer? _refreshTimer;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _trackerInfo = widget.activityItem.trackerInfo;
    _status = widget.activityItem.status;
    _startRefreshIfNeeded();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshIfNeeded() {
    if (_status != ActivityStatus.ongoing || _refreshTimer != null) return;
    _refreshTimer = Timer(const Duration(seconds: 2), _refreshConnection);
  }

  Future<void> _refreshConnection() async {
    _refreshTimer = null;
    if (!mounted || _status != ActivityStatus.ongoing || _isRefreshing) return;
    _isRefreshing = true;
    try {
      final connections = await coreController.getConnections();
      final match = connections.where((c) => c.id == _trackerInfo.id);
      if (match.isNotEmpty) {
        final updated = match.first;
        if (mounted) {
          setState(() {
            _trackerInfo = updated;
          });
        }
      } else if (mounted) {
        setState(() {
          if (_trackerInfo.upload > 0 || _trackerInfo.download > 0) {
            _status = ActivityStatus.success;
          } else {
            _status = ActivityStatus.failed;
          }
        });
      }
    } catch (_) {
    } finally {
      _isRefreshing = false;
      if (mounted && _status == ActivityStatus.ongoing) {
        _startRefreshIfNeeded();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logsProvider).list;
    final trackerInfo = _trackerInfo;
    final relatedLogs = _filterRelatedLogs(logs, trackerInfo);

    final items = <Widget>[
      _buildTimelineHeader(context),
      _buildTimeline(context),
      const Divider(),
      ..._buildMetadataItems(context),
      if (relatedLogs.isNotEmpty) ...[
        const Divider(),
        _buildRelatedLogsSection(context, relatedLogs),
      ],
    ];

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: items.length,
        itemBuilder: (_, index) => items[index],
      ),
    );
  }

  Widget _buildTimelineHeader(BuildContext context) {
    return ListItem(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '请求链路',
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant.opacity80,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: '复制诊断信息',
            onPressed: () {
              final text = _buildDiagnosticText();
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _buildDiagnosticText() {
    final trackerInfo = _trackerInfo;
    final metadata = trackerInfo.metadata;
    final dnsTrace = trackerInfo.dnsTrace;
    final buf = StringBuffer();

    buf.writeln('=== 请求诊断信息 ===');
    buf.writeln('Host: ${metadata.host}');
    buf.writeln('目标: ${metadata.destinationIP}:${metadata.destinationPort}');
    buf.writeln('进程: ${metadata.process}');
    buf.writeln(
      '规则: ${trackerInfo.rule}${trackerInfo.rulePayload.isNotEmpty ? '(${trackerInfo.rulePayload})' : ''}',
    );
    buf.writeln('代理链: ${trackerInfo.chains.join(' → ')}');
    buf.writeln('上传: ${trackerInfo.upload}  下载: ${trackerInfo.download}');
    buf.writeln();

    buf.writeln('--- DNS Trace ---');
    if (dnsTrace != null && dnsTrace.stages.isNotEmpty) {
      for (final stage in dnsTrace.stages) {
        buf.write('[${stage.name}] ');
        if (stage.name == 'hosts') {
          buf.write(stage.matched ? '命中' : '未命中');
        } else if (stage.name == 'resolve') {
          buf.write('server=${stage.server} ');
          if (stage.policyKey.isNotEmpty) {
            buf.write('policy=${stage.policyKey} ');
          }
          buf.write('cache=${stage.cacheHit} ');
          buf.write('duration=${stage.duration}ms');
        }
        if (stage.error.isNotEmpty) {
          buf.write(' ERROR: ${stage.error}');
        }
        buf.writeln();
      }
    } else {
      buf.writeln('(无 DNS trace 数据)');
    }

    return buf.toString();
  }

  Widget _buildTimeline(BuildContext context) {
    final trackerInfo = _trackerInfo;
    final status = _status;
    final metadata = trackerInfo.metadata;
    final dnsTrace = trackerInfo.dnsTrace;

    final stages = <_TimelineStage>[];

    // Stage 1: Intercept
    stages.add(
      _TimelineStage(
        name: '拦截',
        status: _StageStatus.done,
        detail: metadata.process.isNotEmpty
            ? '进程 ${metadata.process}${metadata.uid != 0 ? ' (${metadata.uid})' : ''}'
            : '系统代理',
      ),
    );

    // Stage 2: DNS Resolve (skip for REJECT)
    if (status != ActivityStatus.rejected) {
      final host = metadata.host;
      final destIP = metadata.destinationIP;

      if (dnsTrace != null && dnsTrace.stages.isNotEmpty) {
        // Use real DNS trace data from Go core
        for (final dnsStage in dnsTrace.stages) {
          final stageName = switch (dnsStage.name) {
            'hosts' => 'Hosts 查找',
            'fakeip' => 'FakeIP 分配',
            'resolve' => 'DNS 解析',
            _ => 'DNS ${dnsStage.name}',
          };

          final stageStatus = dnsStage.error.isNotEmpty
              ? _StageStatus.fail
              : dnsStage.matched
              ? _StageStatus.done
              : _StageStatus.done;

          final detailParts = <String>[];
          if (dnsStage.name == 'hosts') {
            detailParts.add(dnsStage.matched ? '命中' : '未命中');
          } else if (dnsStage.name == 'fakeip') {
            if (host.isNotEmpty && destIP.isNotEmpty) {
              detailParts.add('$host → $destIP');
            }
          } else if (dnsStage.name == 'resolve') {
            if (host.isNotEmpty) {
              detailParts.add(destIP.isNotEmpty ? '$host → $destIP' : host);
            }
            if (dnsStage.server.isNotEmpty) {
              detailParts.add('nameserver: ${dnsStage.server}');
            }
            if (dnsStage.policyKey.isNotEmpty) {
              detailParts.add('policy: ${dnsStage.policyKey}');
            }
            if (dnsStage.cacheHit) {
              detailParts.add('缓存命中');
            }
            if (dnsStage.duration > 0) {
              detailParts.add('耗时: ${dnsStage.duration}ms');
            }
          }

          stages.add(
            _TimelineStage(
              name: stageName,
              status: stageStatus,
              detail: detailParts.join(' · '),
              error: dnsStage.error.isNotEmpty ? dnsStage.error : null,
            ),
          );
        }
      } else if (host.isNotEmpty) {
        // Fallback: no dnsTrace, use inferred DNS info
        final dnsMode = metadata.dnsMode;
        final dnsDetail = dnsMode != null
            ? '$host → $destIP (${dnsMode.name})'
            : '$host → $destIP';
        stages.add(
          _TimelineStage(
            name: 'DNS 解析',
            status: status == ActivityStatus.failed && destIP.isEmpty
                ? _StageStatus.fail
                : _StageStatus.done,
            detail: dnsDetail,
            error: status == ActivityStatus.failed && destIP.isEmpty
                ? 'DNS 解析失败'
                : null,
          ),
        );
      }
    }

    // Stage 3: Rule Match
    final rule = trackerInfo.rule;
    final rulePayload = trackerInfo.rulePayload;
    if (rule.isNotEmpty) {
      final ruleText = rulePayload.isNotEmpty ? '$rule($rulePayload)' : rule;
      stages.add(
        _TimelineStage(
          name: '规则匹配',
          status: _StageStatus.done,
          detail: ruleText,
        ),
      );
    }

    // Stage 4: Proxy Select (skip for REJECT/DIRECT)
    if (status != ActivityStatus.rejected) {
      final chains = trackerInfo.chains;
      if (chains.isNotEmpty && !chains.contains('DIRECT')) {
        stages.add(
          _TimelineStage(
            name: '代理选择',
            status: _StageStatus.done,
            detail: chains.join(' → '),
          ),
        );
      }
    }

    // Stage 5: Connection / Rejected
    if (status == ActivityStatus.rejected) {
      stages.add(
        const _TimelineStage(
          name: '已拒绝',
          status: _StageStatus.fail,
          detail: '规则命中拒绝',
        ),
      );
    } else if (status == ActivityStatus.ongoing) {
      stages.add(
        _TimelineStage(
          name: '连接建立',
          status: _StageStatus.active,
          detail: trackerInfo.chains.isNotEmpty
              ? '${trackerInfo.chains.last}:${metadata.destinationPort}'
              : '连接中...',
        ),
      );
    } else if (status == ActivityStatus.success) {
      stages.add(
        _TimelineStage(
          name: '连接建立',
          status: _StageStatus.done,
          detail: trackerInfo.chains.isNotEmpty
              ? '${trackerInfo.chains.last}:${metadata.destinationPort}'
              : '已建立',
        ),
      );
    } else if (status == ActivityStatus.failed) {
      stages.add(
        const _TimelineStage(
          name: '连接建立',
          status: _StageStatus.fail,
          detail: '连接失败',
          error: '超时或连接被拒绝',
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: stages
            .map((stage) => _buildStageItem(context, stage))
            .toList(),
      ),
    );
  }

  Widget _buildStageItem(BuildContext context, _TimelineStage stage) {
    final colorScheme = context.colorScheme;
    final Color dotColor;
    switch (stage.status) {
      case _StageStatus.done:
        dotColor = const Color(0xFF81C784);
        break;
      case _StageStatus.fail:
        dotColor = colorScheme.error;
        break;
      case _StageStatus.active:
        dotColor = colorScheme.primary;
        break;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + dot
          SizedBox(
            width: 20,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Container(width: 2, color: colorScheme.outlineVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stage.name,
                    style: context.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stage.detail,
                    style: context.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (stage.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          stage.error!,
                          style: context.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMetadataItems(BuildContext context) {
    final trackerInfo = _trackerInfo;
    final metadata = trackerInfo.metadata;

    String getRuleText() {
      final rule = trackerInfo.rule;
      final rulePayload = trackerInfo.rulePayload;
      if (rulePayload.isNotEmpty) return '$rule($rulePayload)';
      return rule;
    }

    String getProcessText() {
      final process = metadata.process;
      final uid = metadata.uid;
      if (uid != 0) return '$process($uid)';
      return process;
    }

    String getSourceText() {
      final sourceIP = metadata.sourceIP;
      if (sourceIP.isEmpty) return '';
      final sourcePort = metadata.sourcePort;
      if (sourcePort.isNotEmpty) return '$sourceIP:$sourcePort';
      return sourceIP;
    }

    String getDestinationText() {
      final destinationIP = metadata.destinationIP;
      if (destinationIP.isEmpty) return '';
      final destinationPort = metadata.destinationPort;
      if (destinationPort.isNotEmpty) return '$destinationIP:$destinationPort';
      return destinationIP;
    }

    Widget buildItem({required String title, required String desc}) {
      return ListItem(
        title: Row(
          spacing: 16,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Flexible(child: Text(desc, textAlign: TextAlign.end)),
          ],
        ),
      );
    }

    Widget buildChains() {
      final chains = Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.end,
        children: [
          for (final chain in trackerInfo.chains)
            CommonChip(label: chain, onPressed: () {}),
        ],
      );
      return ListItem(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 20,
          children: [
            const Text('代理链'),
            Flexible(child: chains),
          ],
        ),
      );
    }

    return [
      buildItem(title: '创建时间', desc: trackerInfo.start.showFull),
      if (getProcessText().isNotEmpty)
        buildItem(title: '进程', desc: getProcessText()),
      buildItem(title: '网络类型', desc: metadata.network),
      buildItem(title: '规则', desc: getRuleText()),
      if (metadata.host.isNotEmpty) buildItem(title: '主机', desc: metadata.host),
      if (getSourceText().isNotEmpty)
        buildItem(title: '来源', desc: getSourceText()),
      if (getDestinationText().isNotEmpty)
        buildItem(title: '目标地址', desc: getDestinationText()),
      buildItem(title: '上传', desc: trackerInfo.upload.traffic.show),
      buildItem(title: '下载', desc: trackerInfo.download.traffic.show),
      if (metadata.destinationGeoIP.isNotEmpty)
        buildItem(title: '目标地理定位', desc: metadata.destinationGeoIP.join(' ')),
      if (metadata.destinationIPASN.isNotEmpty)
        buildItem(title: '目标IP ASN', desc: metadata.destinationIPASN),
      if (metadata.dnsMode != null)
        buildItem(title: 'DNS模式', desc: metadata.dnsMode!.name),
      if (metadata.specialProxy.isNotEmpty)
        buildItem(title: '特殊代理', desc: metadata.specialProxy),
      if (metadata.specialRules.isNotEmpty)
        buildItem(title: '特殊规则', desc: metadata.specialRules),
      if (metadata.remoteDestination.isNotEmpty)
        buildItem(title: '远程目标', desc: metadata.remoteDestination),
      buildChains(),
    ];
  }

  List<Log> _filterRelatedLogs(List<Log> logs, TrackerInfo info) {
    final host = info.metadata.host;
    final id = info.id;
    if (host.isEmpty) return [];
    return logs
        .where((log) => log.payload.contains(host) || log.payload.contains(id))
        .take(20)
        .toList();
  }

  Widget _buildRelatedLogsSection(BuildContext context, List<Log> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListItem(
          title: Text(
            '相关日志',
            style: context.textTheme.labelLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant.opacity80,
            ),
          ),
        ),
        for (final log in logs)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  margin: const EdgeInsets.only(right: 6, top: 2),
                  decoration: BoxDecoration(
                    color: _getLogLevelColor(
                      log.logLevel,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    log.logLevel.name.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _getLogLevelColor(log.logLevel),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    log.payload,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Color _getLogLevelColor(LogLevel level) {
    return switch (level) {
      LogLevel.silent => Colors.grey.shade700,
      LogLevel.debug => Colors.grey.shade400,
      LogLevel.info => const Color(0xFF90CAF9),
      LogLevel.warning => Colors.orangeAccent,
      LogLevel.error => Colors.redAccent,
    };
  }
}

enum _StageStatus { done, fail, active }

class _TimelineStage {
  final String name;
  final _StageStatus status;
  final String detail;
  final String? error;

  const _TimelineStage({
    required this.name,
    required this.status,
    required this.detail,
    this.error,
  });
}
