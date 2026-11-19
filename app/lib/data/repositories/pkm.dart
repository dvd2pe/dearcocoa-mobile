import 'dart:io';
import 'dart:convert';
import 'package:dearcocoa/utils/logger.dart';
import 'package:dearcocoa/utils/user_storage.dart';
import 'package:dearcocoa/data/services/file_system_service.dart';
import 'package:dearcocoa/data/services/api_exception.dart';
import 'package:path/path.dart' as p;

final _logger = getLogger('PkmEndpoint');
FileSystemService get _fileSystemService => FileSystemService.instance;

/// English → Chinese mapping for PARA root categories.
const _paraCategoryMapping = <String, String>{
  'Projects': '项目',
  'Areas': '领域',
  'Resources': '资源',
  'Archives': '归档',
};

/// Check if [dirPath] is a PARA root category path (e.g. "Projects", "Areas").
bool _isParaRootCategory(String dirPath) {
  // Only top-level paths like "Projects", not "Projects/Foo"
  return _paraCategoryMapping.containsKey(dirPath);
}

/// Migrate Chinese PARA root directory contents into the English directory.
///
/// Moves all files/subdirectories from the Chinese-named directory into the
/// English-named one, then removes the now-empty Chinese directory.
/// Silently skips if either directory is missing or if individual items
/// already exist in the target (no overwrite).
Future<void> _migrateChineseToEnglish(
    String pkmRoot, String englishName, String chineseName) async {
  final englishDir = Directory(p.join(pkmRoot, englishName));
  final chineseDir = Directory(p.join(pkmRoot, chineseName));

  if (!await chineseDir.exists()) return;
  if (!await englishDir.exists()) return; // nothing to migrate into

  try {
    await for (final entity in chineseDir.list()) {
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;

      final targetPath = p.join(englishDir.path, name);
      if (await FileSystemEntity.isDirectory(targetPath) ||
          await FileSystemEntity.isFile(targetPath)) {
        // Already exists in target, skip
        continue;
      }
      await entity.rename(targetPath);
    }

    // Remove Chinese dir if empty
    final remaining = await chineseDir.list().toList();
    final nonHidden =
        remaining.where((e) => !p.basename(e.path).startsWith('.')).toList();
    if (nonHidden.isEmpty) {
      await chineseDir.delete(recursive: false);
      _logger.info(
          'Migrated PARA category $chineseName → $englishName and removed empty dir');
    }
  } catch (e) {
    _logger.warning('Failed to migrate PARA category $chineseName: $e');
  }
}

/// List PKM directory contents
///
/// Args:
///   path: path relative to PKM root (e.g. "Projects/MyProject"), empty = root
///
/// Returns:
///   Map with items and current_path
///     - items: list of { name, path, is_directory, size }
///     - current_path: current path string
Future<Map<String, dynamic>> listPkmDirectory({String? path}) async {
  _logger.info('listPkmDirectory called: path=$path');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw ApiException('User not logged in, cannot access PKM directory');
    }

    // DearCocoa: always make sure the four PARA roots exist so the Library
    // grid shows usable folders even on a fresh install.
    await ensureParaRoots();

    // Get PKM root
    final pkmRoot = _fileSystemService.getPkmPath(userId);
    final pkmRootDir = Directory(pkmRoot);

    // If PKM dir does not exist, return empty list
    if (!await pkmRootDir.exists()) {
      _logger.info('PKM directory does not exist: $pkmRoot');
      return {
        'items': <Map<String, dynamic>>[],
        'current_path': '',
      };
    }

    // Build target path
    Directory targetDir;
    final dirPath = path;
    if (dirPath != null && dirPath.isNotEmpty) {
      // Prevent path traversal
      final targetPath = p.normalize(p.join(pkmRoot, dirPath));
      final resolvedTarget = p.absolute(targetPath);
      final resolvedRoot = p.absolute(pkmRoot);

      if (!resolvedTarget.startsWith(resolvedRoot)) {
        throw ApiException('Invalid path: path is not safe');
      }

      targetDir = Directory(targetPath);

      // For PARA root categories: migrate Chinese dirs into English and merge listing
      if (_isParaRootCategory(dirPath)) {
        final chineseName = _paraCategoryMapping[dirPath]!;

        // Auto-migrate: move contents from Chinese dir into English dir
        await _migrateChineseToEnglish(pkmRoot, dirPath, chineseName);

        // If English dir doesn't exist but Chinese does, use Chinese as fallback
        if (!await targetDir.exists()) {
          final chineseDir = Directory(p.join(pkmRoot, chineseName));
          if (await chineseDir.exists()) {
            targetDir = chineseDir;
          }
        }
      }
    } else {
      targetDir = pkmRootDir;
    }

    if (!await targetDir.exists()) {
      _logger.info('PKM directory not found: $dirPath, returning empty list');
      return {
        'items': <Map<String, dynamic>>[],
        'current_path': dirPath ?? '',
      };
    }

    // List directory contents
    final items = <Map<String, dynamic>>[];
    final seenNames = <String>{};
    try {
      await for (final entity in targetDir.list()) {
        // Skip hidden files
        final entityPath = entity.path;
        final name = p.basename(entityPath);
        if (name.startsWith('.')) {
          continue;
        }

        seenNames.add(name);
        final isDirectory = await FileSystemEntity.isDirectory(entityPath);
        final item = <String, dynamic>{
          'name': name,
          'path': p.relative(entityPath, from: pkmRoot),
          'is_directory': isDirectory,
        };

        if (!isDirectory) {
          final file = File(entityPath);
          if (await file.exists()) {
            final stat = await file.stat();
            item['size'] = stat.size;
          }
        }

        items.add(item);
      }

      // For PARA root categories: if Chinese dir still exists (has leftover
      // duplicates that couldn't be moved), merge its items into the listing
      // with deduplication by name.
      if (dirPath != null &&
          dirPath.isNotEmpty &&
          _isParaRootCategory(dirPath)) {
        final chineseName = _paraCategoryMapping[dirPath]!;
        final chineseDir = Directory(p.join(pkmRoot, chineseName));
        if (await chineseDir.exists()) {
          await for (final entity in chineseDir.list()) {
            final name = p.basename(entity.path);
            if (name.startsWith('.')) continue;
            if (seenNames.contains(name)) continue;

            seenNames.add(name);
            final isDirectory = await FileSystemEntity.isDirectory(entity.path);
            final item = <String, dynamic>{
              'name': name,
              'path': p.relative(entity.path, from: pkmRoot),
              'is_directory': isDirectory,
            };

            if (!isDirectory) {
              final file = File(entity.path);
              if (await file.exists()) {
                final stat = await file.stat();
                item['size'] = stat.size;
              }
            }

            items.add(item);
          }
        }
      }
    } catch (e) {
      _logger.severe('Error listing directory ${targetDir.path}: $e');
      throw ApiException('Failed to list directory: $e');
    }

    // Compute relative path
    final currentPath = targetDir.path != pkmRoot
        ? p.relative(targetDir.path, from: pkmRoot)
        : '';

    return {
      'items': items,
      'current_path': currentPath,
    };
  } catch (e) {
    _logger.severe('Failed to list PKM directory: $e');
    rethrow;
  }
}

/// Read PKM file content
///
/// Args:
///   filePath: path relative to PKM root (e.g. "Projects/MyProject/readme.md")
///
/// Returns:
///   Map with path, content, is_binary
///     - path: file path
///     - content: text or base64 for binary
///     - is_binary: bool
Future<Map<String, dynamic>> readPkmFileEndpoint(String filePath) async {
  _logger.info('readPkmFile called: filePath=$filePath');

  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) {
      throw ApiException('User not logged in, cannot read PKM file');
    }

    if (filePath.isEmpty) {
      throw ApiException('File path from root cannot be empty');
    }

    // Get PKM root
    final pkmRoot = _fileSystemService.getPkmPath(userId);

    // Build target file path
    final normalizedPath = p.normalize(p.join(pkmRoot, filePath));
    final resolvedTarget = p.absolute(normalizedPath);
    final resolvedRoot = p.absolute(pkmRoot);

    // Prevent path traversal
    if (!resolvedTarget.startsWith(resolvedRoot)) {
      throw ApiException('Invalid path: path is not safe');
    }

    final targetFile = File(resolvedTarget);

    if (!await targetFile.exists()) {
      throw ApiException('File not found: $filePath');
    }

    // Check file size (max 10MB)
    final stat = await targetFile.stat();
    if (stat.size > 10 * 1024 * 1024) {
      throw ApiException('File too large (max 10MB)');
    }

    // Read file content
    try {
      // Try read as text
      String content;
      bool isBinary = false;

      try {
        content = await targetFile.readAsString(
            encoding: const Utf8Codec(allowMalformed: true));
        // Check for invalid UTF-8
        if (content.contains('\uFFFD')) {
          // Replacement char present, likely binary
          throw FormatException('Binary file detected');
        }
        isBinary = false;
      } catch (e) {
        // If binary, return base64
        final bytes = await targetFile.readAsBytes();
        content = base64Encode(bytes);
        isBinary = true;
      }

      final relativePath = p.relative(targetFile.path, from: pkmRoot);

      return {
        'path': relativePath,
        'content': content,
        'is_binary': isBinary,
      };
    } catch (e) {
      _logger.severe('Error reading file ${targetFile.path}: $e');
      throw ApiException('Failed to read file: $e');
    }
  } catch (e) {
    _logger.severe('Failed to read PKM file $filePath: $e');
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// PARA CRUD (DearCocoa v0.3.3): create / delete / move, usable without AI.
// ---------------------------------------------------------------------------

/// The four PARA root folders.
const pkmParaRoots = <String>['Projects', 'Areas', 'Resources', 'Archives'];

/// Validate a single path segment: no separators, traversal or hidden files.
bool _isValidSegment(String name) {
  final n = name.trim();
  return n.isNotEmpty &&
      n != '.' &&
      n != '..' &&
      !n.contains('/') &&
      !n.contains('\\') &&
      !n.startsWith('.');
}

/// Resolve [relPath] under [pkmRoot], refusing traversal outside the PKM root.
String _resolveSafePkmPath(String pkmRoot, String relPath) {
  final targetPath = p.normalize(p.join(pkmRoot, relPath));
  final resolvedTarget = p.absolute(targetPath);
  final resolvedRoot = p.absolute(pkmRoot);
  if (!resolvedTarget.startsWith(resolvedRoot)) {
    throw ApiException('Invalid path: path is not safe');
  }
  return resolvedTarget;
}

/// Create the four PARA root folders (idempotent). Called before every
/// directory listing so the Library grid is never empty/unusable.
Future<void> ensureParaRoots() async {
  try {
    final userId = await UserStorage.getUserId();
    if (userId == null) return;
    final pkmRoot = _fileSystemService.getPkmPath(userId);
    for (final root in pkmParaRoots) {
      final dir = Directory(p.join(pkmRoot, root));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }
  } catch (e) {
    _logger.warning('ensureParaRoots failed: $e');
  }
}

/// Create a folder or a markdown note under [parentPath] (relative to PKM).
Future<Map<String, dynamic>> createPkmEntry({
  required String parentPath,
  required String name,
  required bool isFolder,
  String? content,
}) async {
  final userId = await UserStorage.getUserId();
  if (userId == null) {
    throw ApiException('User not logged in, cannot create PKM entry');
  }
  if (!_isValidSegment(name)) {
    throw ApiException('Invalid name');
  }
  final pkmRoot = _fileSystemService.getPkmPath(userId);
  final parent = _resolveSafePkmPath(pkmRoot, parentPath);
  final target = p.join(parent, name.trim());

  if (await FileSystemEntity.isDirectory(target) ||
      await FileSystemEntity.isFile(target)) {
    throw ApiException('An item with this name already exists');
  }

  if (isFolder) {
    await Directory(target).create(recursive: true);
  } else {
    final fileName = name.trim().endsWith('.md') ? name.trim() : '${name.trim()}.md';
    final file = File(p.join(parent, fileName));
    if (await file.exists()) {
      throw ApiException('An item with this name already exists');
    }
    await file.writeAsString(content ?? '# ${name.trim()}\n');
  }

  final relative = p.relative(target, from: pkmRoot);
  _logger.info('Created PKM entry: $relative (folder=$isFolder)');
  return {'path': relative, 'is_directory': isFolder, 'name': name.trim()};
}

/// Delete a file or a folder (recursive) inside the PKM.
/// PARA root folders themselves are protected.
Future<bool> deletePkmEntry({required String entryPath}) async {
  final userId = await UserStorage.getUserId();
  if (userId == null) {
    throw ApiException('User not logged in, cannot delete PKM entry');
  }
  final pkmRoot = _fileSystemService.getPkmPath(userId);
  final target = _resolveSafePkmPath(pkmRoot, entryPath);

  // Protect the PARA roots themselves.
  final rel = p.relative(target, from: p.absolute(pkmRoot));
  if (pkmParaRoots.contains(rel) ||
      _paraCategoryMapping.values.contains(rel)) {
    throw ApiException('Cannot delete a PARA root folder');
  }

  final entity = FileSystemEntity.type(target) == FileSystemEntityType.directory
      ? Directory(target)
      : File(target);
  if (await entity.exists()) {
    await entity.delete(recursive: true);
    _logger.info('Deleted PKM entry: $rel');
    return true;
  }
  return false;
}

/// Move a file/folder to another folder inside the PKM (no overwrite).
Future<String> movePkmEntry({
  required String entryPath,
  required String newParentPath,
}) async {
  final userId = await UserStorage.getUserId();
  if (userId == null) {
    throw ApiException('User not logged in, cannot move PKM entry');
  }
  final pkmRoot = _fileSystemService.getPkmPath(userId);
  final source = _resolveSafePkmPath(pkmRoot, entryPath);
  final newParent = _resolveSafePkmPath(pkmRoot, newParentPath);

  final rel = p.relative(source, from: p.absolute(pkmRoot));
  if (pkmParaRoots.contains(rel)) {
    throw ApiException('Cannot move a PARA root folder');
  }

  final target = p.join(newParent, p.basename(source));
  if (await FileSystemEntity.isDirectory(target) ||
      await FileSystemEntity.isFile(target)) {
    throw ApiException('An item with this name already exists in the target');
  }

  // Source must exist.
  final sourceType = FileSystemEntity.type(source);
  if (sourceType == FileSystemEntityType.notFound) {
    throw ApiException('Source entry does not exist');
  }

  final FileSystemEntity moved;
  if (sourceType == FileSystemEntityType.directory) {
    moved = await Directory(source).rename(target);
  } else {
    moved = await File(source).rename(target);
  }
  _logger.info('Moved PKM entry $rel → ${p.relative(moved.path, from: pkmRoot)}');
  return p.relative(moved.path, from: p.absolute(pkmRoot));
}
