import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'app_theme.dart';
import 'display_settings_defaults.dart';
import 'i18n.dart';
import 'utils.dart' show Message;

// 全局显示设置（由 main.dart 或 storage 初始化时填充）
// 17.11：拆为自己 / 对方两套独立配色，删除独立的名字配色
class DisplaySettings {
  double fontSize;
  String userTextColorHex; // 自己的文字颜色（空 = 用硬编码默认深蓝）
  String aiTextColorHex;   // 对方的文字颜色（空 = 用硬编码默认色）
  bool textOutline;
  double outlineWidth;
  String outlineColorHex;

  DisplaySettings({
    this.fontSize = defaultDisplayFontSize,
    this.userTextColorHex = defaultUserTextColorHex,
    this.aiTextColorHex = defaultAiTextColorHex,
    this.textOutline = defaultDisplayTextOutline,
    this.outlineWidth = defaultDisplayOutlineWidth,
    this.outlineColorHex = defaultDisplayOutlineColorHex,
  });
}

DisplaySettings displaySettings = DisplaySettings();

/// 应用描边到 TextStyle
TextStyle _applyOutline(TextStyle style, {double? strokeWidth, Color? strokeColor}) {
  if (!displaySettings.textOutline) return style;
  final width = strokeWidth ?? displaySettings.outlineWidth;
  Color color;
  if (displaySettings.outlineColorHex.isNotEmpty) {
    try {
      final hex = displaySettings.outlineColorHex.replaceFirst('#', '');
      color = Color(int.parse('FF${hex.padLeft(6, '0').substring(0, 6)}', radix: 16));
    } catch (_) {
      color = strokeColor ?? Colors.black26;
    }
  } else {
    color = strokeColor ?? Colors.black26;
  }
  return style.copyWith(
    shadows: [
      Shadow(offset: Offset(-width, -width), color: color),
      Shadow(offset: Offset(width, -width), color: color),
      Shadow(offset: Offset(-width, width), color: color),
      Shadow(offset: Offset(width, width), color: color),
    ],
  );
}

/// 17.11：根据角色（isUser）选对应的 hex 颜色或主题默认值
Color _resolveTextColor(Color defaultColor, {required bool isUser}) {
  final hex = isUser ? displaySettings.userTextColorHex : displaySettings.aiTextColorHex;
  if (hex.isNotEmpty) {
    try {
      final c = hex.replaceFirst('#', '');
      if (c.length == 6) {
        return Color(int.parse('FF$c', radix: 16));
      } else if (c.length == 8) {
        return Color(int.parse(c, radix: 16));
      }
    } catch (_) {}
  }
  return defaultColor;
}

/// 16.1：打开视频（系统播放器）
///
/// 本地路径走 OpenFilex（内部经 FileProvider 转 content:// URI，
/// 其他应用可正常读取）；远程 URL 先下载到临时目录再打开（百炼 URL 24h 过期）。
/// 打开失败弹 SnackBar 提示具体原因。
Future<void> openVideoWithSystemPlayer(BuildContext context, String message) async {
  try {
    var path = message;
    if (message.startsWith('http')) {
      // 旧消息可能是远程 URL：下载到临时目录后由系统播放器打开
      final response = await http.get(Uri.parse(message))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode != 200) {
        throw Exception('视频下载失败: HTTP ${response.statusCode}（URL 可能已过期，请重新生成）');
      }
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/video_play_${message.hashCode.toRadixString(16)}.mp4';
      await File(path).writeAsBytes(response.bodyBytes);
    }
    if (!File(path).existsSync()) {
      throw Exception('视频文件不存在');
    }
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      throw Exception(result.message.isEmpty ? '系统未找到可用的视频播放器' : result.message);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text("${I18n.t('video_open_failed')}: $e"),
          showCloseIcon: true,
        ),
      );
    }
  }
}


class ChatElement extends StatelessWidget {
  final String message;
  final int type;
  final String userName;
  final String stuName;
  final bool isBacklog; // true = backlog列表模式(左对齐), false = 单条模式(居中)
  const ChatElement({super.key, required this.message, required this.type, required this.userName, required this.stuName, this.isBacklog = false});

  @override
  Widget build(BuildContext context) {
    if (type == Message.assistant) {
      return Column(crossAxisAlignment: isBacklog ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
          ChatLineLayout(name: stuName, messages: [message.replaceAll('{{user}}', userName).replaceAll('{{char}}', stuName)], isBacklog: isBacklog, isUser: false),
          const SizedBox(height: 10),
        ]);
    } else if (type == Message.user) {
      return Column(
        crossAxisAlignment: isBacklog ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // 16.8：用户消息深蓝加粗，与 AI 消息区分
          ChatLineLayout(name: userName, messages: [message.replaceAll('{{user}}', userName).replaceAll('{{char}}', stuName)], isBacklog: isBacklog, isUser: true),
          const SizedBox(height: 10),
        ],
      );
    } else if (type == Message.timestamp){
      DateTime t = DateTime.fromMillisecondsSinceEpoch(int.parse(message));
      String timestr = "${t.hour.toString().padLeft(2,'0')}:"
        "${t.minute.toString().padLeft(2,'0')}";
      return centerBubble(timestr);
    } else if (type == Message.system) {
      return centerBubble(message.replaceAll('{{user}}', userName).replaceAll('{{char}}', stuName));
    } else if (type == Message.image) {
      return ChatLineImage(name: stuName, imageUrl: message, isBacklog: isBacklog);
    } else if (type == Message.video) {
      // 14.13 视频消息：点击调用系统播放器播放（约束：视频必须用系统播放器）
      // 16.1：本地路径走 OpenFilex（FileProvider content:// URI），远程 URL 先下载
      return Column(
        crossAxisAlignment: isBacklog ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          InkWell(
            onTap: () => openVideoWithSystemPlayer(context, message),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: const Color(0xCCE8F1FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle_fill, color: primaryBlue),
                  const SizedBox(width: 8),
                  Text(I18n.t('play_video'),
                      style: TextStyle(fontSize: displaySettings.fontSize - 2, color: Colors.black54)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
      );
    }
    else {
      return const SizedBox.shrink();
    }
  }
}

Widget centerBubble(String msg) {
  final fontSize = displaySettings.fontSize - 2;
  TextStyle style = TextStyle(fontSize: fontSize, color: Colors.black54);
  style = _applyOutline(style, strokeColor: Colors.black12);

  return Column(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Container(
        decoration: BoxDecoration(
          color: const Color(0xCCE8F1FA),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        child: MarkdownBody(
          data: msg,
          shrinkWrap: true,
          styleSheet: MarkdownStyleSheet(
            p: style,
          ),
        ),
      ),
      const SizedBox(height: 5),
    ],
  );
}

/// 新的聊天行布局：名字（居中）→ 分割线 → 内容（居中）
class ChatLineLayout extends StatelessWidget {
  final String name;
  final List<String> messages;
  final bool isBacklog;
  final bool isUser; // 16.8：用户消息深蓝加粗，AI 消息默认色

  const ChatLineLayout({
    super.key,
    required this.name,
    required this.messages,
    this.isBacklog = false,
    this.isUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    // 16.8：用户消息用主题深蓝，AI 消息保持默认（显示设置 hex 覆盖优先）
    final textColor = _resolveTextColor(
      isUser ? primaryBlueDark : baseColor,
      isUser: isUser,
    );
    final dividerColor = isDark ? Colors.white38 : Colors.black26;
    // 17.11：名字颜色跟随对应角色的文字颜色（加粗），不再独立配置
    final nameColor = textColor;
    final fontSize = displaySettings.fontSize;
    final outlineWidth = displaySettings.outlineWidth;

    final crossAlign = isBacklog ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = isBacklog ? TextAlign.left : TextAlign.center;
    final contentAlign = isBacklog ? Alignment.centerLeft : Alignment.center;

    // 带描边的基础 TextStyle
    TextStyle baseTextStyle = TextStyle(
      fontSize: fontSize,
      color: textColor,
      fontWeight: isUser ? FontWeight.bold : FontWeight.normal,
    );
    baseTextStyle = _applyOutline(baseTextStyle, strokeWidth: outlineWidth);

    TextStyle boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.bold);
    TextStyle italicTextStyle = baseTextStyle.copyWith(fontStyle: FontStyle.italic);

    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        // 名字（backlog左对齐，单条模式居中）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            name,
            textAlign: textAlign,
            style: _applyOutline(TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: nameColor,
            ), strokeWidth: outlineWidth),
          ),
        ),
        // 分割线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(
            color: dividerColor,
            height: 1,
            thickness: 1,
          ),
        ),
        const SizedBox(height: 8),
        // 内容（backlog左对齐，单条模式居中）
        ...messages.asMap().entries.map((entry) {
          String message = entry.value;
          if (message.isEmpty) {
            return const SizedBox.shrink();
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: contentAlign,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44, maxWidth: 600),
                child: MarkdownBody(
                  data: message,
                  shrinkWrap: true,
                  styleSheet: MarkdownStyleSheet(
                    p: baseTextStyle,
                    strong: boldTextStyle,
                    em: italicTextStyle,
                    a: TextStyle(fontSize: fontSize, color: Colors.blue, decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class ChatLineImage extends StatelessWidget {
  final String name;
  final String imageUrl;
  final bool isBacklog;

  const ChatLineImage({
    super.key,
    required this.name,
    required this.imageUrl,
    this.isBacklog = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? Colors.white38 : Colors.black26;
    // 17.11：ChatLineImage 默认 AI 消息风格，名字颜色跟随 AI 文字颜色
    final nameColor = _resolveTextColor(
      isDark ? Colors.white70 : Colors.black54,
      isUser: false,
    );
    final outlineWidth = displaySettings.outlineWidth;

    final crossAlign = isBacklog ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = isBacklog ? TextAlign.left : TextAlign.center;
    final contentAlign = isBacklog ? Alignment.centerLeft : Alignment.center;

    return Column(
      crossAxisAlignment: crossAlign,
      children: [
        // 名字（backlog左对齐，单条模式居中）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            name,
            textAlign: textAlign,
            style: _applyOutline(TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: nameColor,
            ), strokeWidth: outlineWidth),
          ),
        ),
        // 分割线
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(
            color: dividerColor,
            height: 1,
            thickness: 1,
          ),
        ),
        const SizedBox(height: 8),
        // 图片内容（backlog左对齐，单条模式居中）
        // 16.2：点击弹出全屏预览（InteractiveViewer 支持缩放）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: contentAlign,
            child: GestureDetector(
              onTap: () => _previewImage(context),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: FractionallySizedBox(
                      widthFactor: 0.8,
                      // 15.12：生成产物已下载本地，消息存本地路径；旧消息仍可能是远程 URL
                      child: _buildImage(imageUrl),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 16.2：全屏图片预览（点击空白处关闭，双指/滚轮缩放）
  void _previewImage(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullScreenImagePreview(imageUrl: imageUrl);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  /// 本地路径用 Image.file，远程 URL 用 Image.network（15.12）
  Widget _buildImage(String imageUrl) {
    if (imageUrl.startsWith('http')) {
      return Image.network(
        imageUrl,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          } else {
            return Center(
              child: CircularProgressIndicator(
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            );
          }
        },
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.error);
        },
      );
    }
    return Image.file(
      File(imageUrl),
      errorBuilder: (context, error, stackTrace) {
        return const Icon(Icons.error);
      },
    );
  }
}

/// 16.2：全屏图片预览页（点击任意处关闭，双指缩放/拖动）
class _FullScreenImagePreview extends StatelessWidget {
  final String imageUrl;

  const _FullScreenImagePreview({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final bool isRemote = imageUrl.startsWith('http');
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: InteractiveViewer(
            maxScale: 5.0,
            child: isRemote
                ? Image.network(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.error, color: Colors.white, size: 48),
                  )
                : Image.file(
                    File(imageUrl),
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        const Icon(Icons.error, color: Colors.white, size: 48),
                  ),
          ),
        ),
      ),
    );
  }
}
