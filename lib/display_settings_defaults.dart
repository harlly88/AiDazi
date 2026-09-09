// 17.11：配色改为自己 / 对方独立两套，名字不再独立配置（跟随角色文字颜色）
const double defaultDisplayFontSize = 20.0;
const String defaultUserTextColorHex = ''; // 空 = 硬编码深蓝 primaryBlueDark
const String defaultAiTextColorHex = '';   // 空 = 硬编码默认色 baseColor
const bool defaultDisplayTextOutline = true;
const double defaultDisplayOutlineWidth = 1.0;
const String defaultDisplayOutlineColorHex = 'FFFFFF';

const Map<String, Object> displaySettingsBackupDefaults = {
  'display_font_size': defaultDisplayFontSize,
  'user_text_color': defaultUserTextColorHex,
  'ai_text_color': defaultAiTextColorHex,
  'display_text_outline': defaultDisplayTextOutline,
  'display_outline_width': defaultDisplayOutlineWidth,
  'display_outline_color': defaultDisplayOutlineColorHex,
};
