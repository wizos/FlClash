import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/common.dart';

class DnsStage {
  final String name;
  final bool matched;
  final String server;
  final String policyKey;
  final bool cacheHit;
  final int duration;
  final String error;

  const DnsStage({
    this.name = '',
    this.matched = false,
    this.server = '',
    this.policyKey = '',
    this.cacheHit = false,
    this.duration = 0,
    this.error = '',
  });

  factory DnsStage.fromJson(Map<String, dynamic> json) => DnsStage(
    name: json['name'] ?? '',
    matched: json['matched'] ?? false,
    server: json['server'] ?? '',
    policyKey: json['policyKey'] ?? '',
    cacheHit: json['cacheHit'] ?? false,
    duration: json['duration'] ?? 0,
    error: json['error'] ?? '',
  );
}

class DnsTrace {
  final List<DnsStage> stages;

  const DnsTrace({this.stages = const []});

  factory DnsTrace.fromJson(Map<String, dynamic> json) => DnsTrace(
    stages:
        (json['stages'] as List?)
            ?.map((e) => DnsStage.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

class ActivityItem {
  final TrackerInfo trackerInfo;
  final ActivityStatus status;

  const ActivityItem({
    required this.trackerInfo,
    this.status = ActivityStatus.ongoing,
  });

  ActivityItem copyWith({TrackerInfo? trackerInfo, ActivityStatus? status}) {
    return ActivityItem(
      trackerInfo: trackerInfo ?? this.trackerInfo,
      status: status ?? this.status,
    );
  }
}

ActivityStatus inferStatus(TrackerInfo info, Set<String> activeConnectionIds) {
  if (info.chains.contains('REJECT')) return ActivityStatus.rejected;
  // If any DNS trace stage has an error, mark as failed
  final dnsTrace = info.dnsTrace;
  if (dnsTrace != null &&
      dnsTrace.stages.any((stage) => stage.error.isNotEmpty)) {
    return ActivityStatus.failed;
  }
  if (activeConnectionIds.contains(info.id)) return ActivityStatus.ongoing;
  if (info.upload > 0 || info.download > 0) return ActivityStatus.success;
  return ActivityStatus.failed;
}

class ActivityState {
  final List<ActivityItem> items;
  final List<String> keywords;
  final String query;
  final bool autoScrollToEnd;
  final ActivityStatus? filterStatus;

  const ActivityState({
    this.items = const [],
    this.keywords = const [],
    this.query = '',
    this.autoScrollToEnd = true,
    this.filterStatus,
  });

  ActivityState copyWith({
    List<ActivityItem>? items,
    List<String>? keywords,
    String? query,
    bool? autoScrollToEnd,
    ActivityStatus? Function()? filterStatus,
  }) {
    return ActivityState(
      items: items ?? this.items,
      keywords: keywords ?? this.keywords,
      query: query ?? this.query,
      autoScrollToEnd: autoScrollToEnd ?? this.autoScrollToEnd,
      filterStatus: filterStatus != null ? filterStatus() : this.filterStatus,
    );
  }

  List<ActivityItem> get filteredList {
    var result = items;
    if (filterStatus != null) {
      result = result.where((a) => a.status == filterStatus).toList();
    }
    for (final keyword in keywords.map((k) => k.toLowerCase().trim())) {
      if (keyword.isEmpty) continue;
      result = result.where((a) => _matchesText(a, keyword)).toList();
    }
    final lowerQuery = query.toLowerCase().trim();
    if (lowerQuery.isNotEmpty) {
      // Support field-specific search: rule:DIRECT, chain:Proxy, host:google
      const rulePrefix = 'rule:';
      const chainPrefix = 'chain:';
      const hostPrefix = 'host:';
      if (lowerQuery.startsWith(rulePrefix)) {
        final ruleQuery = lowerQuery.substring(rulePrefix.length);
        result = result.where((a) {
          final rule = a.trackerInfo.rule.toLowerCase();
          final rulePayload = a.trackerInfo.rulePayload.toLowerCase();
          return rule.contains(ruleQuery) || rulePayload.contains(ruleQuery);
        }).toList();
      } else if (lowerQuery.startsWith(chainPrefix)) {
        final chainQuery = lowerQuery.substring(chainPrefix.length);
        result = result.where((a) {
          return a.trackerInfo.chains.any(
            (c) => c.toLowerCase().contains(chainQuery),
          );
        }).toList();
      } else if (lowerQuery.startsWith(hostPrefix)) {
        final hostQuery = lowerQuery.substring(hostPrefix.length);
        result = result.where((a) {
          return a.trackerInfo.metadata.host.toLowerCase().contains(hostQuery);
        }).toList();
      } else {
        // Default: match host, process, chains, destinationIP, rule
        result = result.where((a) => _matchesText(a, lowerQuery)).toList();
      }
    }
    return result;
  }

  bool _matchesText(ActivityItem item, String query) {
    final info = item.trackerInfo;
    return info.metadata.host.toLowerCase().contains(query) ||
        info.metadata.process.toLowerCase().contains(query) ||
        info.chains.join('').toLowerCase().contains(query) ||
        info.metadata.destinationIP.toLowerCase().contains(query) ||
        info.rule.toLowerCase().contains(query) ||
        info.rulePayload.toLowerCase().contains(query);
  }
}
