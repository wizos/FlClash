import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'detail.dart';

class ActivityItemWidget extends ConsumerWidget {
  final ActivityItem activityItem;
  final Function(String)? onClickKeyword;
  final Widget? trailing;

  const ActivityItemWidget({
    super.key,
    required this.activityItem,
    this.onClickKeyword,
    this.trailing,
  });

  static double get subTitleHeight {
    return globalState.measure.bodySmallHeight + 20;
  }

  Future<ImageProvider?> _getPackageIcon(TrackerInfo connection) async {
    return await app?.getPackageIcon(connection.metadata.process);
  }

  String _getSourceText(TrackerInfo trackerInfo, ActivityStatus status) {
    final progress = trackerInfo.progressText.isNotEmpty
        ? '${trackerInfo.progressText} · '
        : '';
    final traffic = Traffic(up: trackerInfo.upload, down: trackerInfo.download);
    final rule = trackerInfo.rule.isNotEmpty
        ? ' · ${trackerInfo.rulePayload.isNotEmpty ? '${trackerInfo.rule}(${trackerInfo.rulePayload})' : trackerInfo.rule}'
        : '';
    // For failed requests, show error summary from dnsTrace
    String errorSummary = '';
    if (status == ActivityStatus.failed) {
      final dnsTrace = trackerInfo.dnsTrace;
      if (dnsTrace != null) {
        for (final stage in dnsTrace.stages) {
          if (stage.error.isNotEmpty) {
            errorSummary = ' · ${stage.error}';
            break;
          }
        }
      }
      if (errorSummary.isEmpty) {
        errorSummary = ' · 连接失败';
      }
    }
    return '${trackerInfo.start.lastUpdateTimeDesc}$rule$progress · ${traffic.desc}$errorSummary';
  }

  Color _getStatusColor(ActivityStatus status, ColorScheme colorScheme) {
    return switch (status) {
      ActivityStatus.ongoing => colorScheme.primary,
      ActivityStatus.success => const Color(0xFF81C784),
      ActivityStatus.failed => colorScheme.error,
      ActivityStatus.rejected => Colors.orangeAccent,
    };
  }

  Widget _buildStatusBadge(ActivityStatus status, ColorScheme colorScheme) {
    final color = _getStatusColor(status, colorScheme);
    final icon = switch (status) {
      ActivityStatus.ongoing => Icons.sync,
      ActivityStatus.success => Icons.check,
      ActivityStatus.failed => Icons.close,
      ActivityStatus.rejected => Icons.block,
    };
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }

  @override
  Widget build(BuildContext context, ref) {
    final trackerInfo = activityItem.trackerInfo;
    final status = activityItem.status;
    final colorScheme = context.colorScheme;
    final statusColor = _getStatusColor(status, colorScheme);

    final value = ref.watch(
      patchClashConfigProvider.select(
        (state) =>
            state.findProcessMode == FindProcessMode.always && system.isAndroid,
      ),
    );

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(trackerInfo.desc, style: context.textTheme.bodyLarge),
        const SizedBox(height: 6),
        Text(
          _getSourceText(trackerInfo, status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textTheme.bodyMedium?.copyWith(
            color: context.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    final subTitle = SizedBox(
      height: subTitleHeight,
      child: Row(
        spacing: 8,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: ListView.separated(
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              padding: EdgeInsets.zero,
              scrollDirection: Axis.horizontal,
              itemCount: trackerInfo.chains.length,
              itemBuilder: (_, index) {
                final chain = trackerInfo.chains[index];
                return CommonChip(
                  label: chain,
                  labelStyle: context.textTheme.bodySmall?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    if (onClickKeyword == null) return;
                    onClickKeyword!(chain);
                  },
                );
              },
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    final icon = value
        ? GestureDetector(
            onTap: () {
              if (onClickKeyword == null) return;
              final process = trackerInfo.metadata.process;
              if (process.isEmpty) return;
              onClickKeyword!(process);
            },
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              width: 42,
              height: 42,
              child: FutureBuilder<ImageProvider?>(
                future: _getPackageIcon(trackerInfo),
                builder: (_, snapshot) {
                  if (!snapshot.hasData && snapshot.data == null) {
                    return Container();
                  } else {
                    return Image(
                      image: snapshot.data!,
                      gaplessPlayback: true,
                      width: 42,
                      height: 42,
                    );
                  }
                },
              ),
            ),
          )
        : null;

    return Row(
      children: [
        // Left status indicator bar
        Container(
          width: 3,
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: ListItem(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            onTap: () {
              showExtend(
                context,
                builder: (_, type) {
                  return AdaptiveSheetScaffold(
                    type: type,
                    body: ActivityDetailView(activityItem: activityItem),
                    title: '活动详情',
                  );
                },
              );
            },
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  spacing: 8,
                  children: [
                    _buildStatusBadge(status, colorScheme),
                    if (icon != null) icon,
                    Flexible(child: title),
                  ],
                ),
                const SizedBox(height: 8),
                subTitle,
              ],
            ),
          ),
        ),
      ],
    );
  }
}
