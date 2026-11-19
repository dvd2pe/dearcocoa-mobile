import 'package:flutter/material.dart';
import 'package:dearcocoa/utils/result.dart';
import 'package:dearcocoa/utils/toast_helper.dart';
import 'package:dearcocoa/data/repositories/memex_router.dart';
import 'package:dearcocoa/ui/knowledge/widgets/knowledge/knowledge_file_card.dart';
import 'package:dearcocoa/ui/core/widgets/agent_logo_loading.dart';
import 'package:dearcocoa/ui/core/widgets/back_button.dart';
import 'package:dearcocoa/utils/user_storage.dart';

class KnowledgeDirectoryPage extends StatefulWidget {
  final String path;

  const KnowledgeDirectoryPage({
    super.key,
    required this.path,
  });

  @override
  State<KnowledgeDirectoryPage> createState() => _KnowledgeDirectoryPageState();
}

class _KnowledgeDirectoryPageState extends State<KnowledgeDirectoryPage> {
  final MemexRouter _memexRouter = MemexRouter();
  bool _isLoading = true;
  List<Map<String, dynamic>> _files = [];
  List<Map<String, dynamic>> _folders = [];

  @override
  void initState() {
    super.initState();
    _fetchResult();
  }

  Future<void> _fetchResult() async {
    setState(() => _isLoading = true);
    final dataResult = await _memexRouter.listPkmDirectory(path: widget.path);
    final data = dataResult.when(
        onOk: (d) => d, onError: (_, __) => <String, dynamic>{});
    if (data.isEmpty && dataResult.isError) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    {
      final items = data['items'] as List<dynamic>? ?? [];
      final List<Map<String, dynamic>> files = [];
      final List<Map<String, dynamic>> folders = [];

      for (final item in items) {
        if (item is Map<String, dynamic>) {
          final isDirectory = item['is_directory'] == true;
          if (isDirectory) {
            folders.add(item);
          } else {
            files.add(item);
          }
        }
      }

      // Fetch counts for folders
      if (folders.isNotEmpty) {
        final folderPaths = folders.map((f) => f['path'] as String).toList();
        final countResult = await _memexRouter.countPkmItems(folderPaths);
        final counts = countResult.when(
            onOk: (c) => c, onError: (_, __) => <String, int>{});
        for (var f in folders) {
          f['item_count'] = counts[f['path']] ?? 0;
        }
      }

      if (mounted) {
        setState(() {
          _files = files;
          _folders = folders;
          _isLoading = false;
        });
      }
    }
    if (dataResult.isError && mounted) {
      setState(() => _isLoading = false);
    }
  }

  // ------------------------------------------------------------------
  // PARA CRUD (DearCocoa): create / delete / move without AI.
  // ------------------------------------------------------------------

  String _errorText(Object error) {
    final text = error.toString();
    if (text.startsWith('Exception: ')) {
      return text.substring('Exception: '.length);
    }
    return text;
  }

  Future<void> _showCreateSheet() async {
    final l10n = UserStorage.l10n;
    final isFolder = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined,
                  color: Color(0xFF3B82F6)),
              title: Text(l10n.pkmNewFolder),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined,
                  color: Color(0xFF10B981)),
              title: Text(l10n.pkmNewNote),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (isFolder == null || !mounted) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(isFolder ? l10n.pkmNewFolder : l10n.pkmNewNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: l10n.pkmNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(UserStorage.l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.pkmCreate),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final result = await _memexRouter.createPkmEntry(
      parentPath: widget.path,
      name: name,
      isFolder: isFolder,
    );
    result.when(
      onOk: (_) {
        ToastHelper.showSuccess(context, l10n.pkmEntryCreated);
        _fetchResult();
      },
      onError: (error, _) =>
          ToastHelper.showError(context, _errorText(error)),
    );
  }

  Future<void> _showEntryActions(Map<String, dynamic> item) async {
    final l10n = UserStorage.l10n;
    final isFolder = item['is_directory'] == true;
    final entryPath = item['path'] as String;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final root in pkmParaRoots)
              if (root != widget.path.split('/').first)
                ListTile(
                  leading: Icon(
                    Icons.drive_file_move_outline,
                    color: isFolder
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFF10B981),
                  ),
                  title: Text('${l10n.pkmMoveTo} $root'),
                  onTap: () => Navigator.pop(context, 'move:$root'),
                ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
              title: Text(l10n.pkmDelete,
                  style: const TextStyle(color: Color(0xFFEF4444))),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text(l10n.pkmDelete),
          content: Text(l10n.pkmDeleteConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(UserStorage.l10n.cancel),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.pkmDelete),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await _memexRouter.deletePkmEntry(entryPath: entryPath);
      result.when(
        onOk: (_) {
          ToastHelper.showSuccess(context, l10n.pkmEntryDeleted);
          _fetchResult();
        },
        onError: (error, _) =>
            ToastHelper.showError(context, _errorText(error)),
      );
      return;
    }

    if (action.startsWith('move:')) {
      final target = action.substring('move:'.length);
      final result = await _memexRouter.movePkmEntry(
        entryPath: entryPath,
        newParentPath: target,
      );
      result.when(
        onOk: (_) {
          ToastHelper.showSuccess(context, '${l10n.pkmMoveTo} $target');
          _fetchResult();
        },
        onError: (error, _) =>
            ToastHelper.showError(context, _errorText(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = UserStorage.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(widget.path,
            style: const TextStyle(
                color: Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        centerTitle: false,
        backgroundColor: const Color(0xFFF7F8FA),
        elevation: 0,
        leading: const AppBackButton(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: const Color(0xFF5B6CFF),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(l10n.pkmAdd,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      body: _isLoading
          ? Center(child: AgentLogoLoading())
          : KnowledgeDirectoryBody(
              folders: _folders,
              files: _files,
              folderBuilder: _buildFolderCard,
              fileBuilder: _buildFileCard,
            ),
    );
  }

  Widget _buildFolderCard(Map<String, dynamic> item) {
    return GestureDetector(
      onLongPress: () => _showEntryActions(item),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => KnowledgeDirectoryPage(path: item['path']),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: const Color(0xFF64748B).withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF), // Blue 50
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.folder_rounded,
                  color: Color(0xFF3B82F6), size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['name'] ?? '',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B))),
                  const SizedBox(height: 4),
                  Text('${item['item_count'] ?? 0} items',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(Map<String, dynamic> item) {
    return GestureDetector(
      onLongPress: () => _showEntryActions(item),
      child: KnowledgeFileCard(item: item),
    );
  }
}

/// The four PARA root folders (kept in sync with lib/data/repositories/pkm.dart).
const pkmParaRoots = <String>['Projects', 'Areas', 'Resources', 'Archives'];

class KnowledgeDirectoryBody extends StatelessWidget {
  const KnowledgeDirectoryBody({
    super.key,
    required this.folders,
    required this.files,
    required this.folderBuilder,
    this.fileBuilder,
  });

  final List<Map<String, dynamic>> folders;
  final List<Map<String, dynamic>> files;
  final Widget Function(Map<String, dynamic> item) folderBuilder;
  final Widget Function(Map<String, dynamic> item)? fileBuilder;

  @override
  Widget build(BuildContext context) {
    if (folders.isEmpty && files.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(40),
            alignment: Alignment.center,
            child: Text(UserStorage.l10n.emptyFolder,
                style: const TextStyle(color: Color(0xFFCBD5E1))),
          ),
        ],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: folders.length + files.length,
      itemBuilder: (context, index) {
        if (index < folders.length) {
          return folderBuilder(folders[index]);
        }
        final file = files[index - folders.length];
        final builder = fileBuilder;
        if (builder != null) return builder(file);
        return KnowledgeFileCard(item: file);
      },
    );
  }
}
