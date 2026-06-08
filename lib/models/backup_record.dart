class BackupRecord {
  final String projectName;
  final String backupPath;
  final DateTime timestamp;
  final int sizeInBytes;

  BackupRecord({
    required this.projectName,
    required this.backupPath,
    required this.timestamp,
    required this.sizeInBytes,
  });

  String get formattedSize {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    if (sizeInBytes < 1024 * 1024 * 1024) return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(sizeInBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String get formattedDate {
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')} '
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
  }
}