import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/backup_record.dart';
import 'backup_service.dart';

class BackupApiException implements Exception {
  final String message;
  final int? statusCode;

  BackupApiException(this.message, {this.statusCode});

  @override
  String toString() => 'BackupApiException($statusCode): $message';
}

/// Local Dart backup facade.
///
/// The public methods are intentionally kept compatible with the previous
/// service so the UI can keep using one backup facade.
class BackupApiService {
  String? _backupDir;

  BackupApiService({String? baseUrl});

  Future<bool> checkHealth() async => true;

  Future<BackupRecord> createBackup({
    required String projectPath,
    String? destination,
    void Function(int processed, int total)? onProgress,
  }) async {
    final targetDestination = destination ?? _backupDir;
    if (targetDestination == null || targetDestination.isEmpty) {
      throw BackupApiException('No backup destination configured');
    }

    try {
      return await BackupService.createBackup(
        projectPath: projectPath,
        destination: targetDestination,
        onProgress: onProgress,
      );
    } catch (e) {
      throw BackupApiException('Backup failed: $e');
    }
  }

  Future<Map<String, dynamic>> getProjectInfo(String projectPath) async {
    final dir = Directory(projectPath);
    var sizeBytes = 0;
    var fileCount = 0;
    var excludedCount = 0;

    if (!dir.existsSync()) {
      throw BackupApiException('Project path does not exist: $projectPath');
    }

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      final relativePath = p.relative(entity.path, from: projectPath).replaceAll('\\', '/');
      if (BackupService.shouldExclude(relativePath)) {
        excludedCount++;
        continue;
      }

      if (entity is File) {
        try {
          final stat = await entity.stat();
          sizeBytes += stat.size;
          fileCount++;
        } catch (_) {}
      }
    }

    final appInfo = BackupService.getAppInfo(projectPath);
    final splitInfo = _splitAppInfo(appInfo);

    return {
      'name': p.basename(projectPath),
      'path': dir.absolute.path,
      'app_name': splitInfo.$1,
      'version': splitInfo.$2,
      'size_bytes': sizeBytes,
      'file_count': fileCount,
      'excluded_count': excludedCount,
    };
  }

  Future<List<BackupRecord>> listBackups({int limit = 50}) async {
    final destination = _backupDir;
    if (destination == null || destination.isEmpty) {
      return BackupService.history(limit: limit);
    }

    final dir = Directory(destination);
    if (!dir.existsSync()) {
      return BackupService.history(limit: limit);
    }

    final backups = <BackupRecord>[...BackupService.history(limit: limit)];
    final knownPaths = backups.map((record) => record.backupPath).toSet();

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File || p.extension(entity.path).toLowerCase() != '.zip') {
        continue;
      }
      if (knownPaths.contains(entity.path)) {
        continue;
      }

      try {
        final stat = await entity.stat();
        backups.add(BackupRecord(
          projectName: p.basenameWithoutExtension(entity.path),
          backupPath: entity.path,
          timestamp: stat.modified,
          sizeInBytes: stat.size,
        ));
      } catch (_) {}
    }

    backups.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return backups.take(limit).toList();
  }

  Future<File> downloadBackup(String backupPath) async {
    final file = File(backupPath);
    if (!file.existsSync()) {
      throw BackupApiException('Backup file not found');
    }
    return file;
  }

  Future<void> deleteBackup(String backupPath) async {
    final file = File(backupPath);
    if (!file.existsSync()) {
      throw BackupApiException('Backup file not found');
    }

    try {
      await file.delete();
      BackupService.removeHistoryPath(backupPath);
    } catch (e) {
      throw BackupApiException('Failed to delete backup: $e');
    }
  }

  Future<List<String>> getExclusions() async => BackupService.excludePaths;

  Future<String> setBackupDestination(String destination) async {
    final dir = Directory(destination);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _backupDir = dir.absolute.path;
    return _backupDir!;
  }

  Future<bool> testExclusion(String path) async {
    return BackupService.shouldExclude(path);
  }

  (String?, String?) _splitAppInfo(String? appInfo) {
    if (appInfo == null) {
      return (null, null);
    }

    final versionMatch = RegExp(r'^(.*) v([^ ]+)$').firstMatch(appInfo);
    if (versionMatch == null) {
      return (appInfo, null);
    }

    return (versionMatch.group(1), versionMatch.group(2));
  }
}
