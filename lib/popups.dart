import 'package:flutter/material.dart';
import 'i18n.dart';

// 15.2 长按消息菜单：灵感 / 绘图 / 视频 / 删除（删除需二次确认）
void assistantPopup(BuildContext context, String msg, LongPressStartDetails details,
                    String stuName, Function(String) onEdited) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
  showMenu(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: 1, child: Text(I18n.t('inspire'))),
      PopupMenuItem(value: 3, child: Text(I18n.t('draw'))),
      PopupMenuItem(value: 4, child: Text(I18n.t('video'))),
      PopupMenuItem(value: 2, child: Text(I18n.t('delete'))),
    ],
  ).then((value) {
    if (value == 1) {
      onEdited("INSPIRE");
    } else if (value == 2) {
      _confirmDeleteMessage(context, () => onEdited("DELETE"));
    } else if (value == 3) {
      onEdited("DRAW");
    } else if (value == 4) {
      onEdited("VIDEO");
    }
  });
}

void userPopup(BuildContext context, String msg, LongPressStartDetails details, Function(String,bool) onEdited) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
  showMenu(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: 1, child: Text(I18n.t('inspire'))),
      PopupMenuItem(value: 3, child: Text(I18n.t('draw'))),
      PopupMenuItem(value: 4, child: Text(I18n.t('video'))),
      PopupMenuItem(value: 2, child: Text(I18n.t('delete'))),
    ],
  ).then((value) {
    if (value == 1) {
      onEdited("INSPIRE", false);
    } else if (value == 2) {
      _confirmDeleteMessage(context, () => onEdited("DELETE", false));
    } else if (value == 3) {
      onEdited("DRAW", false);
    } else if (value == 4) {
      onEdited("VIDEO", false);
    }
  });
}

/// 15.2 删除消息二次确认
void _confirmDeleteMessage(BuildContext context, VoidCallback onConfirmed) {
  showDialog(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Text(I18n.t('delete_msg_confirm')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(I18n.t('cancel')),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onConfirmed();
          },
          child: Text(I18n.t('delete')),
        ),
      ],
    ),
  );
}

void systemPopup(BuildContext context, String msg, Function(String,bool) onEdited) {
  TextEditingController controller = TextEditingController(text: msg);
  showDialog(context: context, builder: (context) {
    return AlertDialog(
      title: Text(I18n.t('edit_system_instruction')),
      content: TextField(
        maxLines: null,
        minLines: 1,
        controller: controller,
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.clear();
          },
          child: Text(I18n.t('clear')),
        ),
        TextButton(
          onPressed: () {
            onEdited(controller.text,false);
            Navigator.of(context).pop();
          },
          child: Text(I18n.t('confirm')),
        ),
        TextButton(
          onPressed: () {
            onEdited("DRAW", false);
            Navigator.of(context).pop();
          },
          child: Text(I18n.t('draw')),
        ),
      ],
    );
  });
}

// bool: true for transfer to system instruction, false for not
void timePopup(BuildContext context, int oldTime, LongPressStartDetails details, Function(bool,DateTime?) onEdited) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
  showMenu(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: 1, child: Text(I18n.t('edit'))),
      PopupMenuItem(value: 2, child: Text(I18n.t('turn_to_system_instruction')))
    ],
  ).then((value) {
    if (value == 1) {
      showDatePicker(
        context: context,
        initialDate: DateTime.fromMillisecondsSinceEpoch(oldTime),
        firstDate: DateTime(2021),
        lastDate: DateTime(2099),
      ).then((date) {
        if (date != null) {
          showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(oldTime)),
          ).then((time) {
            if (time != null) {
              DateTime newTime = DateTime(
                date.year,
                date.month,
                date.day,
                time.hour,
                time.minute,
              );
              onEdited(false, newTime);
            }
          });
        }
      });
    } else if (value == 2) {
      onEdited(true, null);
    }
  });
}

void imagePopup(BuildContext context, LongPressStartDetails details, Function(int) onEdited) {
  final RenderBox overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromLTWH(details.globalPosition.dx, details.globalPosition.dy, 0, 0),
    Offset.zero & overlay.size,
  );
  showMenu(
    context: context,
    position: position,
    items: [
      PopupMenuItem(value: 1, child: Text(I18n.t('remove'))),
      PopupMenuItem(value: 2, child: Text(I18n.t('save'))),
      PopupMenuItem(value: 0, child: Text(I18n.t('set_background')))
    ],
  ).then((value) {
    onEdited(value!);
  });
}
