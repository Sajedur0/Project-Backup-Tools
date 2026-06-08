import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;

import '../models/backup_record.dart';
import '../models/project_info.dart';
import '../utils/backup_service.dart';
import '../utils/backup_api_service.dart';
import '../widgets/backup_progress_dialog.dart';

class BackupToolHome extends StatefulWidget {
  const BackupToolHome({super.key});

  @override
  State<BackupToolHome> createState() => _BackupToolHomeState();
}

class _BackupToolHomeState extends State<BackupToolHome> {
  String basePath = r"C:\Users\Zero\AndroidStudioProjects";
  String backupDest = "";
  String status = "Ready — select a project and backup destination.";
  List<ProjectInfo> projects = [];
  ProjectInfo? selectedProject;
  bool isBackingUp = false;
  List<BackupRecord> backupHistory = [];
  bool showHistory = false;

  late BackupApiService _apiService;

  @override
  void initState() {
    super.initState();
    _apiService = BackupApiService();
    loadProjects();
    loadBackupHistory();
  }

  Future<void> loadProjects() async {
    final dir = Directory(basePath);
    if (!dir.existsSync()) {
      setState(() {
        status = "Error: Path not found: $basePath";
        projects = [];
      });
      return;
    }

    final projectList = <ProjectInfo>[];
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = path.basename(entity.path);
          if (name.startsWith('.') || name.startsWith('\$')) continue;

          final markers = [
            'pubspec.yaml',
            'android',
            'ios',
            'lib',
            'build.gradle',
            'build.gradle.kts',
            'package.json',
            'src',
          ];

          final hasMarker = markers.any(
            (m) =>
                File('${entity.path}${Platform.pathSeparator}$m').existsSync() ||
                Directory('${entity.path}${Platform.pathSeparator}$m')
                    .existsSync(),
          );

          if (hasMarker) {
            final info = BackupService.getAppInfo(entity.path) ??
                'Flutter Project';
            projectList.add(ProjectInfo(name, info, entity.path));
          }
        }
      }
      projectList.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      setState(() {
        status = "Error loading projects: $e";
      });
      return;
    }

    setState(() {
      projects = projectList;
      status =
          '✅ Found ${projectList.length} project${projectList.length != 1 ? 's' : ''}.';
    });
  }

  Future<void> changeBasePath() async {
    String? selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Projects Folder',
      initialDirectory: basePath,
    );
    if (selected != null) {
      setState(() {
        basePath = selected;
        selectedProject = null;
      });
      await loadProjects();
    }
  }

  Future<void> selectBackupDestination() async {
    String? selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Backup Destination',
    );
    if (selected != null) {
      setState(() {
        backupDest = selected;
      });
      loadBackupHistory();
    }
  }

  Future<void> loadBackupHistory() async {
    if (backupDest.isEmpty) return;

    try {
      await _apiService.setBackupDestination(backupDest);
      final localBackups = await _apiService.listBackups(limit: 100);
      setState(() {
        backupHistory = localBackups;
      });
    } catch (e) {
      debugPrint('Failed to load backup history: $e');
    }
  }

  void _openBackupLocation(BackupRecord backup) {
    final file = File(backup.backupPath);
    if (file.existsSync()) {
      Process.run('explorer', [path.dirname(backup.backupPath)]);
    }
  }

  Future<void> startBackup() async {
    if (selectedProject == null) {
      _showMessage('Warning', 'Please select a project!');
      return;
    }

    if (backupDest.isEmpty) {
      String? selected = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Backup Destination',
      );
      if (selected == null) return;
      setState(() {
        backupDest = selected;
      });
    }

    setState(() {
      isBackingUp = true;
      status = 'Creating backup with Dart...';
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const BackupProgressDialog(),
    );

    try {
      final projectPath = selectedProject!.path;
      final backupDestDir = Directory(backupDest);

      if (!backupDestDir.existsSync()) {
        await backupDestDir.create(recursive: true);
      }

      if (FileSystemEntity.typeSync(backupDest) !=
          FileSystemEntityType.directory) {
        throw Exception('Backup destination must be a folder.');
      }

      final record = await _apiService.createBackup(
        projectPath: projectPath,
        destination: backupDest,
      );

      if (!backupHistory.any((r) => r.backupPath == record.backupPath)) {
        backupHistory.insert(0, BackupRecord(
          projectName: record.projectName,
          backupPath: record.backupPath,
          timestamp: record.timestamp,
          sizeInBytes: record.sizeInBytes,
        ));
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      setState(() {
        status = '✅ Backup Completed Successfully!';
        isBackingUp = false;
      });

      _showMessage('Success',
          'Project "${selectedProject!.name}" has been backed up to:\n${path.basename(record.backupPath)}');
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(() {
        status = '❌ Backup failed: $e';
        isBackingUp = false;
      });
      _showMessage('Error', 'Backup failed: $e');
    }
  }

  Future<void> deleteBackup(BackupRecord backup) async {
    try {
      await _apiService.deleteBackup(backup.backupPath);
      setState(() {
        backupHistory.remove(backup);
      });
      _showMessage('Success', 'Backup deleted successfully.');
    } catch (e) {
      _showMessage('Error', 'Failed to delete backup: $e');
    }
  }

  void _showMessage(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Flutter Project Backup Tool'),
        backgroundColor: const Color(0xFF6750A4),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(showHistory ? Icons.folder : Icons.history),
            tooltip: showHistory ? 'Show Projects' : 'Show History',
            onPressed: () {
              setState(() {
                showHistory = !showHistory;
              });
            },
          ),
        ],
      ),
      body: showHistory ? _buildHistoryView() : _buildProjectsView(),
    );
  }

  Widget _buildProjectsView() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Projects folder card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.folder, color: Color(0xFF6750A4)),
                          SizedBox(width: 8),
                          Text(
                            'Projects Folder',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6750A4),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                basePath,
                                style: const TextStyle(fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: isBackingUp ? null : changeBasePath,
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: const Text('Change'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6750A4),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.backup, color: Color(0xFF6750A4)),
                          SizedBox(width: 8),
                          Text(
                            'Backup Destination',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6750A4),
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                backupDest.isEmpty
                                    ? 'Not selected'
                                    : backupDest,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: backupDest.isEmpty
                                      ? Colors.grey
                                      : Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: isBackingUp ? null : selectBackupDestination,
                            icon: const Icon(Icons.save, size: 16),
                            label: const Text('Select'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2E7D32),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Projects list card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.apps, color: Color(0xFF6750A4)),
                              SizedBox(width: 8),
                              Text(
                                'Available Projects',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6750A4),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${projects.length} found',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (projects.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              children: [
                                Icon(Icons.folder_open,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                Text(
                                  'No projects found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: projects.length,
                            separatorBuilder: (context, index) =>
                                Divider(
                                    height: 1,
                                    color: Colors.grey.shade200),
                            itemBuilder: (context, index) {
                              final project = projects[index];
                              final isSelected = selectedProject == project;
                              return ListTile(
                                leading: Icon(
                                  Icons.folder,
                                  color: isSelected
                                      ? const Color(0xFF6750A4)
                                      : Colors.grey.shade600,
                                ),
                                title: Text(project.name),
                                subtitle: Text(
                                  project.appInfo,
                                  style: TextStyle(
                                    color: project.appInfo == '—'
                                        ? Colors.grey
                                        : Colors.green.shade700,
                                  ),
                                ),
                                tileColor: isSelected
                                    ? Colors.purple.shade50
                                    : index.isEven
                                        ? const Color(0xFFFCFCFC)
                                        : const Color(0xFFF7F7F7),
                                onTap: isBackingUp
                                    ? null
                                    : () {
                                        setState(() {
                                          selectedProject = project;
                                        });
                                      },
                                selected: isSelected,
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle,
                                        color: Color(0xFF6750A4))
                                    : null,
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Action buttons
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: isBackingUp ? null : loadProjects,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Refresh'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF6750A4),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: isBackingUp ? null : startBackup,
                        icon: const Icon(Icons.backup),
                        label: const Text('Start Backup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Status card
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        status.contains('✅')
                            ? Icons.check_circle
                            : status.contains('❌')
                                ? Icons.error
                                : Icons.info,
                        color: status.contains('✅')
                            ? Colors.green
                            : status.contains('❌')
                                ? Colors.red
                                : Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Exclusions info
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Excluded from backup (${BackupService.excludePaths.length} items):',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Only matching folder names are excluded. Files with these names are preserved.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: BackupService.excludePaths.map((folder) {
                          return Chip(
                            label: Text(folder, style: const TextStyle(fontSize: 11)),
                            backgroundColor: Colors.grey.shade200,
                            padding: EdgeInsets.zero,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryView() {
    return Column(
      children: [
        Container(
          color: const Color(0xFF6750A4),
          padding: const EdgeInsets.all(24),
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backup History',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'View and manage your previous backups.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: backupHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history,
                          size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        'No backups yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Backups will appear here once created.',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: backupHistory.length,
                  itemBuilder: (context, index) {
                    final backup = backupHistory[index];
                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.archive,
                              color: Color(0xFF6750A4)),
                        ),
                        title: Text(
                          backup.projectName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(backup.formattedDate),
                            Text(
                              'Size: ${backup.formattedSize}',
                              style: TextStyle(color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Backup'),
                                content: Text(
                                    'Are you sure you want to delete this backup?\n${backup.projectName}'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      deleteBackup(backup);
                                    },
                                    child: const Text('Delete',
                                        style: TextStyle(color: Colors.red)),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        onTap: () async {
                          _openBackupLocation(backup);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
