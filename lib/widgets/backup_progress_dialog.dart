import 'package:flutter/material.dart';

class BackupProgressDialog extends StatelessWidget {
  const BackupProgressDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Backup in progress'),
        ],
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Please wait while the backup is being created...'),
          SizedBox(height: 16),
          LinearProgressIndicator(
            backgroundColor: Colors.grey,
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6750A4)),
          ),
        ],
      ),
    );
  }
}