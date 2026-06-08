import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';
import '../extensions/string_extension.dart';
import '../models/backup_record.dart';

class BackupService {
  // Exclude common build folders, dependency folders, and cache from the archive.
  // All other files and directories in the project are included.
  //
  // Supports exact folder names and wildcard patterns:
  //   'name'       - excludes any folder/file named 'name' at any depth
  //   '*.ext'      - excludes files/folders matching the extension pattern
  //   '.prefix*'   - excludes items starting with a dot prefix
  static final List<String> excludePaths = [
    // Flutter / Dart
    'build',
    '.dart_tool',
    '.flutter-plugins',
    '.flutter-plugins-dependencies',

    // Node.js
    'node_modules',
    '.next',
    '.nuxt',

    // Python
    '__pycache__',
    'venv',
    '.venv',
    '*.egg-info',

    // Android (Java/Kotlin)
    '.gradle',
    '.idea',

    // iOS
    'Pods',
    'DerivedData',

    // General / VCS
    '.git',
    '.svn',
    '.hg',

    // IDE / Editor
    '.vscode',
    '.idea',
    '.vs',

    // OS metadata
    '.DS_Store',
    'Thumbs.db',
    'desktop.ini',

    // Rust
    'target',

    // Java / Gradle
    '.gradle',

    // Temporary / Cache
    '.tmp',
    '.cache',
  ];

  /// Get the exclusion patterns as a Set for quick lookup
  static Set<String> get exclusionSet => Set<String>.from(excludePaths);

  static final List<BackupRecord> _history = [];

  /// Check if a relative path should be excluded (local fallback version)
  static bool shouldExclude(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');
    final segments = normalizedPath.split('/');

    for (final exclude in excludePaths) {
      final normalizedExclude = exclude.replaceAll('\\', '/');

      // 1. Wildcard pattern: *.suffix (e.g., '*.egg-info')
      if (normalizedExclude.startsWith('*.')) {
        final suffix = normalizedExclude.substring(1); // e.g., '.egg-info'
        for (final segment in segments) {
          if (segment.endsWith(suffix)) {
            return true;
          }
        }
        continue;
      }

      // 2. Dot-prefix wildcard: .prefix* (e.g., '.flutter-plugins*')
      if (normalizedExclude.startsWith('.') && normalizedExclude.endsWith('*')) {
        final prefix = normalizedExclude.substring(0, normalizedExclude.length - 1);
        for (final segment in segments) {
          if (segment.startsWith(prefix)) {
            return true;
          }
        }
        continue;
      }

      // 3. Known file patterns (files that should be excluded by name at any depth)
      const knownFilePatterns = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};
      if (knownFilePatterns.contains(normalizedExclude)) {
        for (final segment in segments) {
          if (segment == normalizedExclude) {
            return true;
          }
        }
        continue;
      }

      // 4. Exact segment match for folder names (e.g., 'build', 'node_modules')
      // Only match against directory segments, not the filename itself
      if (segments.length > 1) {
        for (int i = 0; i < segments.length - 1; i++) {
          if (segments[i] == normalizedExclude) {
            return true;
          }
        }
      }

      // 5. For single-segment paths (root-level items), match both files and folders
      if (segments.length == 1 && segments[0] == normalizedExclude) {
        return true;
      }
    }
    return false;
  }

  // Get app info from AndroidManifest.xml and pubspec.yaml
  static String? getAppInfo(String projectPath) {
    String? appName;
    String? versionName;

    // Try AndroidManifest.xml first
    final manifestPath = '$projectPath/android/app/src/main/AndroidManifest.xml';
    if (File(manifestPath).existsSync()) {
      try {
        final content = File(manifestPath).readAsStringSync();
        final xml = XmlDocument.parse(content);
        final elements = xml.findAllElements('application');
        if (elements.isNotEmpty) {
          final application = elements.first;
          final label = application.getAttribute('android:label');
          if (label != null && label.isNotEmpty) {
            appName = label;
          }
        }
      } catch (_) {}
    }

    // Get version from pubspec.yaml
    final pubspecPath = '$projectPath/pubspec.yaml';
    if (File(pubspecPath).existsSync()) {
      try {
        final content = File(pubspecPath).readAsStringSync();
        final yaml = loadYaml(content);
        if (appName == null && yaml['name'] != null) {
          final name = yaml['name'];
          if (name is String) {
            appName = name.replaceAll('_', ' ').toTitleCase();
          }
        }
        if (yaml['version'] != null) {
          final version = yaml['version'];
          if (version is String) {
            versionName = version.split('+').first;
          }
        }
      } catch (_) {}
    }

    if (appName != null) {
      if (versionName != null) {
        return '$appName v$versionName';
      }
      return appName;
    }
    return null;
  }

  static Future<BackupRecord> createBackup({
    required String projectPath,
    required String destination,
    void Function(int processed, int total)? onProgress,
  }) async {
    final sourceDir = Directory(projectPath);
    if (!sourceDir.existsSync()) {
      throw Exception('Project path does not exist: $projectPath');
    }

    final destinationDir = Directory(destination);
    if (!destinationDir.existsSync()) {
      await destinationDir.create(recursive: true);
    }

    if (FileSystemEntity.typeSync(destination) != FileSystemEntityType.directory) {
      throw Exception('Backup destination must be a folder.');
    }

    final backupName = getAppInfo(projectPath) ?? p.basename(projectPath);
    final safeName = sanitizeFilename(backupName);
    final zipPath = _uniqueZipPath(destination, safeName);
    final sourceBytes = await createZip(
      projectPath,
      zipPath,
      onProgress: onProgress,
    );

    final record = BackupRecord(
      projectName: p.basename(projectPath),
      backupPath: zipPath,
      timestamp: DateTime.now(),
      sizeInBytes: sourceBytes,
    );
    _history.insert(0, record);
    return record;
  }

  static List<BackupRecord> history({int limit = 50}) {
    final sorted = [..._history]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(limit).toList();
  }

  static void removeHistoryPath(String backupPath) {
    _history.removeWhere((record) => record.backupPath == backupPath);
  }

  static String sanitizeFilename(String name) {
    final sanitized = name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), '')
        .replaceFirst(RegExp(r'[ .]+$'), '');
    return sanitized.isEmpty ? 'backup' : sanitized;
  }

  static String _uniqueZipPath(String destination, String safeName) {
    final basePath = p.join(destination, '$safeName.zip');
    var zipPath = basePath;
    var counter = 1;

    while (File(zipPath).existsSync()) {
      zipPath = p.join(destination, '${safeName}_$counter.zip');
      counter++;
    }

    return zipPath;
  }

  // Create ZIP archive with exclusions. Returns the total source bytes included.
  static Future<int> createZip(
    String sourcePath,
    String zipPath, {
    void Function(int processed, int total)? onProgress,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);

    final sourceDir = Directory(sourcePath);
    final files = await _collectIncludedFiles(sourceDir, sourcePath);
    var processed = 0;
    var sourceBytes = 0;

    for (final file in files) {
      final relativePath = p.relative(file.path, from: sourcePath).replaceAll('\\', '/');
      try {
        final stat = await file.stat();
        encoder.addFile(file, relativePath);
        sourceBytes += stat.size;
      } catch (_) {}
      processed++;
      onProgress?.call(processed, files.length);
    }

    encoder.close();
    return sourceBytes;
  }

  static Future<List<File>> _collectIncludedFiles(
      Directory dir, String basePath) async {
    final files = <File>[];

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      final relativePath = p.relative(entity.path, from: basePath).replaceAll('\\', '/');

      if (_shouldExclude(relativePath)) {
        continue;
      }

      if (entity is File) {
        files.add(entity);
      } else if (entity is Directory) {
        files.addAll(await _collectIncludedFiles(entity, basePath));
      }
    }

    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
  }

  static bool _shouldExclude(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');
    final segments = normalizedPath.split('/');

    for (final exclude in excludePaths) {
      final normalizedExclude = exclude.replaceAll('\\', '/');

      // 1. Wildcard pattern: *.suffix (e.g., '*.egg-info')
      if (normalizedExclude.startsWith('*.')) {
        final suffix = normalizedExclude.substring(1); // e.g., '.egg-info'
        for (final segment in segments) {
          if (segment.endsWith(suffix)) {
            return true;
          }
        }
        continue;
      }

      // 2. Dot-prefix wildcard: .prefix* (e.g., '.flutter-plugins*')
      if (normalizedExclude.startsWith('.') && normalizedExclude.endsWith('*')) {
        final prefix = normalizedExclude.substring(0, normalizedExclude.length - 1);
        for (final segment in segments) {
          if (segment.startsWith(prefix)) {
            return true;
          }
        }
        continue;
      }

      // 3. Known file patterns (files that should be excluded by name at any depth)
      // These are specific OS/IDE metadata files, not generic folder names
      const knownFilePatterns = {'.DS_Store', 'Thumbs.db', 'desktop.ini'};
      if (knownFilePatterns.contains(normalizedExclude)) {
        for (final segment in segments) {
          if (segment == normalizedExclude) {
            return true;
          }
        }
        continue;
      }

      // 4. Exact segment match for folder names (e.g., 'build', 'node_modules')
      // Only match against directory segments, not the filename itself
      // This prevents a file named 'build.dart' from being excluded
      if (segments.length > 1) {
        // Check all segments except the last one (which is the filename)
        for (int i = 0; i < segments.length - 1; i++) {
          if (segments[i] == normalizedExclude) {
            return true;
          }
        }
      }

      // 5. For single-segment paths (root-level items), match both files and folders
      if (segments.length == 1 && segments[0] == normalizedExclude) {
        return true;
      }
    }
    return false;
  }
}
