import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/material.dart';

class ActivityFilterBar extends StatelessWidget {
  final ActivityStatus? currentFilter;
  final Function(ActivityStatus?) onFilterChanged;

  const ActivityFilterBar({
    super.key,
    this.currentFilter,
    required this.onFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final appLocalizations = context.appLocalizations;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildChip(context, null, appLocalizations.activityAll),
          const SizedBox(width: 8),
          _buildChip(
            context,
            ActivityStatus.ongoing,
            appLocalizations.activityOngoing,
          ),
          const SizedBox(width: 8),
          _buildChip(
            context,
            ActivityStatus.success,
            appLocalizations.connected,
          ),
          const SizedBox(width: 8),
          _buildChip(
            context,
            ActivityStatus.failed,
            appLocalizations.activityFailed,
          ),
          const SizedBox(width: 8),
          _buildChip(
            context,
            ActivityStatus.rejected,
            appLocalizations.activityRejected,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(
    BuildContext context,
    ActivityStatus? status,
    String label,
  ) {
    final isActive = currentFilter == status;
    return FilterChip(
      selected: isActive,
      label: Text(label),
      onSelected: (_) => onFilterChanged(isActive ? null : status),
    );
  }
}
