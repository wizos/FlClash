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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildChip(context, null, '全部'),
          const SizedBox(width: 8),
          _buildChip(context, ActivityStatus.ongoing, '进行中'),
          const SizedBox(width: 8),
          _buildChip(context, ActivityStatus.success, '已连接'),
          const SizedBox(width: 8),
          _buildChip(context, ActivityStatus.failed, '失败'),
          const SizedBox(width: 8),
          _buildChip(context, ActivityStatus.rejected, '已拒绝'),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, ActivityStatus? status, String label) {
    final isActive = currentFilter == status;
    return FilterChip(
      selected: isActive,
      label: Text(label),
      onSelected: (_) => onFilterChanged(isActive ? null : status),
    );
  }
}
