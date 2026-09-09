// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'storage.dart';
import 'utils.dart' show snackBarAlert;
import 'i18n.dart';
import 'dart:io';

// 17.12：统一内部存储 backups/ 目录，恢复用自定义 Dialog 列表（不再走 file_picker）
class BackupPage extends StatefulWidget {
  final String currentMessages;
  final Function(String) onRefresh;
  final Future<void> Function() onConfigRestored;
  const BackupPage({
    super.key,
    required this.currentMessages,
    required this.onRefresh,
    required this.onConfigRestored,
  });
  @override
  BackupPageState createState() => BackupPageState();
}

class BackupPageState extends State<BackupPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.t('backup_config')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            ListTile(
              title: Text(I18n.t('local_backup_restore'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey)),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  child: const Text('保存到本地'),
                  onPressed: () async {
                    try {
                      String j = await convertToJson();
                      final path = await saveBackupLocally(j);
                      if (mounted) {
                        snackBarAlert(context, '备份已保存');
                      }
                      debugPrint('Backup saved to: $path');
                    } catch (e) {
                      if (mounted) {
                        snackBarAlert(context, '保存失败: $e');
                      }
                    }
                  },
                ),
                ElevatedButton(
                  child: const Text('从本地恢复'),
                  onPressed: () async {
                    await _showBackupListDialog();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 17.12：列出内部存储 backups/ 目录下的 JSON 备份文件
  Future<void> _showBackupListDialog() async {
    if (!mounted) return;
    List<Map<String, dynamic>> files = await listBackupFiles();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          return AlertDialog(
            title: const Text('本地备份'),
            content: SizedBox(
              width: double.maxFinite,
              child: files.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('暂无备份文件，请先保存一次'),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: files.length,
                      itemBuilder: (context, index) {
                        final file = files[index];
                        final name = file['name'] as String;
                        final size = file['size'] as int;
                        final modified = file['modified'] as DateTime;
                        final path = file['path'] as String;
                        final sizeStr = size < 1024
                            ? '${size} B'
                            : size < 1024 * 1024
                                ? '${(size / 1024).toStringAsFixed(1)} KB'
                                : '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
                        return ListTile(
                          leading: const Icon(Icons.backup),
                          title: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${_formatDate(modified)}  ·  $sizeStr',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.play_arrow,
                                    color: Colors.blue),
                                tooltip: '加载',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      title: const Text('确认恢复'),
                                      content: const Text(
                                          '此操作将覆盖当前配置，是否继续？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: Text(I18n.t('cancel')),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: Text(I18n.t('confirm')),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true) return;

                                  final jsonString =
                                      await readBackupFile(path);
                                  if (jsonString == null) {
                                    if (ctx.mounted) {
                                      snackBarAlert(ctx, '文件读取失败');
                                    }
                                    return;
                                  }
                                  try {
                                    await restoreFromJson(jsonString);
                                    if (!ctx.mounted) return;
                                    snackBarAlert(ctx, '恢复成功');
                                    Navigator.pop(ctx);
                                    await widget.onConfigRestored();
                                  } catch (e) {
                                    if (ctx.mounted) {
                                      snackBarAlert(ctx,
                                          '恢复失败: $e');
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red),
                                tooltip: '删除',
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      title: const Text('确认删除'),
                                      content:
                                          const Text('确定要删除这个备份吗？'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, false),
                                          child: Text(I18n.t('cancel')),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(c, true),
                                          child: Text(I18n.t('confirm')),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await deleteBackupFile(path);
                                    if (ctx2.mounted) {
                                      // 刷新列表
                                      final updated =
                                          await listBackupFiles();
                                      setDialogState(() {
                                        files = updated;
                                      });
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(I18n.t('cancel')),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }
}
