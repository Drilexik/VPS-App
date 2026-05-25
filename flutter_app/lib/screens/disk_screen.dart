import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class DiskScreen extends StatefulWidget {
  final ApiService api;
  const DiskScreen({super.key, required this.api});

  @override
  State<DiskScreen> createState() => _DiskScreenState();
}

class _DiskScreenState extends State<DiskScreen> {
  final List<String> _pathStack = ['/home'];
  List<DiskEntry> _entries = [];
  bool _loading = true;
  String? _error;

  String get _currentPath => _pathStack.last;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await widget.api.getDiskList(_currentPath);
      if (mounted) setState(() { _entries = data['entries'] as List<DiskEntry>; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _navigate(String path) {
    _pathStack.add(path);
    _load();
  }

  void _goBack() {
    if (_pathStack.length > 1) {
      _pathStack.removeLast();
      _load();
    }
  }

  Future<void> _newFolder() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Folder name'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      await widget.api.createDirectory('$_currentPath/${ctrl.text.trim()}');
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _delete(DiskEntry entry) async {
    bool recursive = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Delete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Delete "${entry.name}"?', style: const TextStyle(fontSize: 14)),
              if (entry.isDir) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: recursive,
                      onChanged: (v) => setS(() => recursive = v ?? false),
                      activeColor: AppColors.primary,
                    ),
                    const Text('Delete recursively', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.danger)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.deletePath(entry.path, recursive: recursive);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PathBar(
          path: _currentPath,
          canGoBack: _pathStack.length > 1,
          onBack: _goBack,
          onNewFolder: _newFolder,
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: AppColors.danger, size: 40),
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: AppColors.textDim, fontSize: 13)),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('Retry')),
                      ]),
                    )
                  : _entries.isEmpty
                      ? const Center(
                          child: Text('Empty folder', style: TextStyle(color: AppColors.textDim)),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          color: AppColors.primary,
                          child: ListView.builder(
                            itemCount: _entries.length,
                            itemBuilder: (ctx, i) => _EntryTile(
                              entry: _entries[i],
                              onTap: _entries[i].isDir ? () => _navigate(_entries[i].path) : null,
                              onDelete: () => _delete(_entries[i]),
                            ),
                          ),
                        ),
        ),
      ],
    );
  }
}

class _PathBar extends StatelessWidget {
  final String path;
  final bool canGoBack;
  final VoidCallback onBack;
  final VoidCallback onNewFolder;

  const _PathBar({
    required this.path,
    required this.canGoBack,
    required this.onBack,
    required this.onNewFolder,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (canGoBack)
            GestureDetector(
              onTap: onBack,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.text),
              ),
            ),
          if (canGoBack) const SizedBox(width: 10),
          Expanded(
            child: Text(
              path,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: AppColors.accent,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onNewFolder,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.create_new_folder_rounded, size: 18, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final DiskEntry entry;
  final VoidCallback? onTap;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(entry.path),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.danger.withOpacity(0.2),
        child: const Icon(Icons.delete_rounded, color: AppColors.danger),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: ListTile(
        leading: Icon(
          entry.isDir ? Icons.folder_rounded : _fileIcon(entry.name),
          color: entry.isDir ? AppColors.warning : AppColors.textDim,
          size: 22,
        ),
        title: Text(entry.name,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis),
        subtitle: !entry.isDir
            ? Text(fmtBytes(entry.size),
                style: const TextStyle(fontSize: 12, color: AppColors.textDim))
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (entry.isDir)
              const Icon(Icons.chevron_right_rounded, color: AppColors.textDim, size: 20),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger, size: 18),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Icons.movie_rounded;
      case 'mp3':
      case 'wav':
      case 'ogg':
        return Icons.music_note_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'tar':
      case 'gz':
      case 'bz2':
        return Icons.archive_rounded;
      case 'py':
      case 'js':
      case 'dart':
      case 'sh':
      case 'yaml':
      case 'json':
        return Icons.code_rounded;
      case 'txt':
      case 'log':
      case 'md':
        return Icons.article_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
