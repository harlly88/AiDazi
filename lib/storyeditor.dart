import 'package:flutter/material.dart';

import 'i18n.dart';

/// 15.4 故事背景编辑器：单个多行文本编辑框（标题只读展示 + 正文）
///
/// 用于「新增故事」与「修改故事」：用户直接书写故事背景/世界观，
/// 保存时正文包装为单条 system Message 存入故事池（与导入故事结构一致）。
/// 通过 Navigator.pop(context, text) 返回正文文本，取消返回 null。
class StoryTextEditor extends StatefulWidget {
  final String title;
  final String initialText;

  const StoryTextEditor({
    super.key,
    required this.title,
    this.initialText = "",
  });

  @override
  State<StoryTextEditor> createState() => _StoryTextEditorState();
}

class _StoryTextEditorState extends State<StoryTextEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title,
            style: const TextStyle(color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(color: Color(0xfff2a0ac)),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(_controller.text.trim());
            },
            child:
                Text(I18n.t('save'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              I18n.t('story_background_edit'),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                autofocus: widget.initialText.isEmpty,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: I18n.t('story_background_hint'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
