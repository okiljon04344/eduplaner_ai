import '../../school/models/school.dart';

/// Parsing strategy used by the backend timetable import engine.
enum ParseMethod {
  schoolMatrix('school_matrix'),
  headerMapper('header_mapper'),
  ocrGrid('ocr_grid'),
  ai('ai');

  final String wireName;
  const ParseMethod(this.wireName);

  static ParseMethod fromWire(String? s) {
    switch (s) {
      case 'school_matrix':
        return ParseMethod.schoolMatrix;
      case 'header_mapper':
        return ParseMethod.headerMapper;
      case 'ocr_grid':
        return ParseMethod.ocrGrid;
      case 'ai':
        return ParseMethod.ai;
      default:
        return ParseMethod.schoolMatrix;
    }
  }
}

/// Kind of change for a single diff preview row.
enum DiffKind {
  added,
  changed,
  removed,
  unchanged;

  static DiffKind fromWire(String? s) {
    switch (s) {
      case 'added':
        return DiffKind.added;
      case 'changed':
      case 'updated':
        return DiffKind.changed;
      case 'removed':
        return DiffKind.removed;
      default:
        return DiffKind.unchanged;
    }
  }
}

/// Numerical counts of changes in the import diff.
class ImportDiffSummary {
  final int added;
  final int changed;
  final int removed;
  final int unchanged;

  const ImportDiffSummary({
    this.added = 0,
    this.changed = 0,
    this.removed = 0,
    this.unchanged = 0,
  });

  int get total => added + changed + removed + unchanged;
  int get totalMutations => added + changed + removed;

  factory ImportDiffSummary.fromMap(Map? m) {
    if (m == null) return const ImportDiffSummary();
    int toInt(Object? v) => v is num ? v.toInt() : 0;
    return ImportDiffSummary(
      added: toInt(m['added']),
      changed: toInt(m['changed'] ?? m['updated']),
      removed: toInt(m['removed']),
      unchanged: toInt(m['unchanged']),
    );
  }

  Map<String, dynamic> toMap() => {
        'added': added,
        'changed': changed,
        'removed': removed,
        'unchanged': unchanged,
      };
}

/// A single lesson slot modification preview.
class ImportDiffItem {
  final String dayId;
  final String date;
  final String weekday;
  final String period;
  final DiffKind kind;
  final SchoolSlot? before;
  final SchoolSlot? after;

  const ImportDiffItem({
    this.dayId = '',
    required this.date,
    this.weekday = '',
    required this.period,
    required this.kind,
    this.before,
    this.after,
  });

  factory ImportDiffItem.fromMap(Map m) {
    return ImportDiffItem(
      dayId: (m['dayId'] ?? '').toString(),
      date: (m['date'] ?? '').toString(),
      weekday: (m['weekday'] ?? '').toString(),
      period: (m['period'] ?? '').toString(),
      kind: DiffKind.fromWire((m['kind'] ?? m['changeType'])?.toString()),
      before: m['before'] is Map ? SchoolSlot.fromMap(m['before'] as Map) : null,
      after: m['after'] is Map ? SchoolSlot.fromMap(m['after'] as Map) : null,
    );
  }
}

/// Complete import diff containing counts and preview items.
class ImportDiff {
  final ImportDiffSummary summary;
  final List<ImportDiffItem> preview;

  const ImportDiff({
    this.summary = const ImportDiffSummary(),
    this.preview = const [],
  });

  int get added => summary.added;
  int get changed => summary.changed;
  int get removed => summary.removed;
  int get unchanged => summary.unchanged;
  int get total => summary.total;
  int get totalMutations => summary.totalMutations;

  factory ImportDiff.fromServer({Map? summaryMap, List? previewList}) {
    return ImportDiff(
      summary: ImportDiffSummary.fromMap(summaryMap),
      preview: previewList is List
          ? previewList.whereType<Map>().map(ImportDiffItem.fromMap).toList()
          : const [],
    );
  }
}

/// Reason why a specific date was omitted from the import range.
enum ExcludedDateReason {
  holiday('national_holiday'),
  closedDateRange('closed_range'),
  nonSchoolDay('non_school_day'),
  manual('manual'),
  unknown('unknown');

  final String wireName;
  const ExcludedDateReason(this.wireName);

  static ExcludedDateReason fromWire(String? s) {
    switch (s) {
      case 'national_holiday':
      case 'holiday':
        return ExcludedDateReason.holiday;
      case 'closed_range':
      case 'closed_date_range':
        return ExcludedDateReason.closedDateRange;
      case 'non_school_day':
        return ExcludedDateReason.nonSchoolDay;
      case 'manual':
        return ExcludedDateReason.manual;
      default:
        return ExcludedDateReason.unknown;
    }
  }
}

/// Information about a skipped calendar date.
class ExcludedDate {
  final String date;
  final ExcludedDateReason reason;
  final String label;
  final bool provisional;

  const ExcludedDate({
    required this.date,
    required this.reason,
    required this.label,
    this.provisional = false,
  });

  factory ExcludedDate.fromMap(Map m) {
    return ExcludedDate(
      date: (m['date'] ?? '').toString(),
      reason: ExcludedDateReason.fromWire(m['reason']?.toString()),
      label: (m['label'] ?? '').toString(),
      provisional: m['provisional'] == true,
    );
  }
}

/// An unparseable or rejected raw line/row from the imported source.
class InvalidRow {
  final int rowNumber;
  final String rawText;
  final String reason;

  const InvalidRow({
    required this.rowNumber,
    this.rawText = '',
    required this.reason,
  });

  factory InvalidRow.fromMap(Map m) {
    final row = m['row'] ?? m['rowNumber'];
    return InvalidRow(
      rowNumber: row is num ? row.toInt() : 0,
      rawText: (m['raw'] ?? m['rawText'] ?? '').toString(),
      reason: (m['reason'] ?? '').toString(),
    );
  }
}

/// Full timetable import preview returned by `previewTimetableImport`.
class TimetableImportPreview {
  final String draftId;
  final DateTime? expiresAt;
  final String mode;
  final int? grade;
  final String? course;
  final ImportDiff diff;
  final int changedDaysCount;
  final List<ExcludedDate> excludedDates;
  final List<InvalidRow> invalidRows;
  final ParseMethod parseMethod;
  final bool usedAi;
  final String? maskedPreviewText;
  final bool notifyStudentsDefault;

  const TimetableImportPreview({
    required this.draftId,
    this.expiresAt,
    this.mode = 'merge',
    this.grade,
    this.course,
    required this.diff,
    required this.changedDaysCount,
    this.excludedDates = const [],
    this.invalidRows = const [],
    this.parseMethod = ParseMethod.schoolMatrix,
    this.usedAi = false,
    this.maskedPreviewText,
    this.notifyStudentsDefault = false,
  });

  factory TimetableImportPreview.fromMap(Map m) {
    final rawExpires = m['expiresAt'];
    return TimetableImportPreview(
      draftId: (m['draftId'] ?? '').toString(),
      expiresAt: rawExpires is String ? DateTime.tryParse(rawExpires) : null,
      mode: (m['mode'] ?? 'merge').toString(),
      grade: m['grade'] is num ? (m['grade'] as num).toInt() : null,
      course: m['course'] as String?,
      diff: ImportDiff.fromServer(
        summaryMap: (m['summary'] ?? m['diffSummary']) as Map?,
        previewList: m['diffPreview'] as List?,
      ),
      changedDaysCount: m['changedDaysCount'] is num
          ? (m['changedDaysCount'] as num).toInt()
          : 0,
      excludedDates: m['excludedDates'] is List
          ? (m['excludedDates'] as List)
              .whereType<Map>()
              .map(ExcludedDate.fromMap)
              .toList()
          : const [],
      invalidRows: m['invalidRows'] is List
          ? (m['invalidRows'] as List)
              .whereType<Map>()
              .map(InvalidRow.fromMap)
              .toList()
          : const [],
      parseMethod: ParseMethod.fromWire(m['parseMethod']?.toString()),
      usedAi: m['usedAi'] == true,
      maskedPreviewText: m['maskedPreviewText'] as String?,
      notifyStudentsDefault: m['notifyStudentsDefault'] == true,
    );
  }
}

/// Result returned after confirming an import draft (`confirmTimetableImport`).
class ImportResult {
  final bool ok;
  final String? importId;
  final int appliedDays;
  final int pushedCount;

  const ImportResult({
    this.ok = true,
    this.importId,
    required this.appliedDays,
    this.pushedCount = 0,
  });

  factory ImportResult.fromMap(Map m) {
    final days = m['appliedDays'] ?? m['updatedDaysCount'];
    return ImportResult(
      ok: m['ok'] != false,
      importId: m['importId']?.toString(),
      appliedDays: days is num ? days.toInt() : 0,
      pushedCount: m['pushed'] is num ? (m['pushed'] as num).toInt() : 0,
    );
  }
}

/// Result returned after reverting a past timetable import (`revertTimetableImport`).
class RevertResult {
  final bool success;
  final int restoredDaysCount;

  const RevertResult({
    required this.success,
    required this.restoredDaysCount,
  });

  factory RevertResult.fromMap(Map m) {
    final days = m['revertedDays'] ?? m['restoredDaysCount'];
    return RevertResult(
      success: m['ok'] == true || m['success'] == true,
      restoredDaysCount: days is num ? days.toInt() : 0,
    );
  }
}
