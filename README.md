<div align="center">
  <img src="web/favicon.png" width="128" height="128" alt="AI搭子 Logo">
</div>

<h1 align="center">AI搭子 (aiDazi)</h1>

**将你最喜欢的角色带入现实！**

AI搭子是一款使用 Flutter 构建的、注重隐私的开源 AI 伙伴应用。全链路国产化 API：大语言模型对话、角色专属语音（复刻或文字设计）、语音识别、文生图、文生视频，一个阿里云百炼 API Key 即可全部打通。

## ✨ 核心功能

- **🤖 智能聊天:** 支持阿里千问（**推荐**）、DeepSeek、火山引擎豆包、智谱 GLM、Kimi 及任意自定义 OpenAI 兼容端点
- **🎭 角色管理:** 创建、编辑、导入导出 AI 角色；兼容 SillyTavern V2 角色卡；支持声音复刻（参考音频 URL）和声音设计（文字描述）两种方式为角色创建专属音色；样貌描述自动生成参考图作为角色头像和聊天背景
- **🔊 角色专属语音:** 阿里百炼 CosyVoice 模型，两种创建方式——上传公网参考音频 URL 复刻音色，或用一段自然语言描述设计全新音色；开启「自动发声」后 AI 回复自动播报
- **🎤 语音输入:** 长按麦克风说话，松手即识别发送（阿里百炼 qwen3-asr-flash，支持中/英/日/韩/粤语），最长 55 秒自动停止
- **🎨 文生图:** 阿里万相（默认），支持参考图保持角色一致性；选中消息一键生成配图；9:16 竖屏适配
- **🎬 文生视频:** 阿里万相（默认）/ 火山 Seedance / 可灵 / MiniMax
- **🖼️ 自动换背景:** 每个角色拥有专属背景图库，开启自动背景后每 2-5 次对话自动轮换
- **📍 时间/位置/天气注入:** 当前日期时间、GPS 定位和实时天气自动注入对话，让 AI 回复更有场景感
- **📁 媒体库:** 按角色浏览、预览、删除所有生成的图片与视频
- **💾 本地备份与恢复:** 所有数据保存在设备本地，支持一键导出配置/角色/聊天记录为 JSON 文件
- **🔒 隐私优先:** 所有数据存储在你的设备上，本应用不收集任何个人信息

## 🚀 快速开始

1. 注册阿里云账号并开通[百炼大模型服务](https://bailian.console.aliyun.com/?tab=model#/api-key)
2. 打开应用，欢迎页面会引导你进入 **设置 → 模型配置**，填入阿里云百炼 API Key
3. 本软件基于阿里模型设计，**推荐优先选择 qwen 模型**，一个 Key 即可打通对话 / 语音 / 生图 / 生视频全链路
4. （可选）在模型配置页面点击「申请 XX API Key」按钮，可直接跳转到对应服务商的申请页面

## 🛠️ 构建

```sh
git clone <仓库地址>
cd aiDazi
flutter pub get
flutter run
```

打包：

```sh
flutter build apk      # Android
flutter build web      # Web
flutter build windows  # Windows
```

## 📱 平台支持

| 平台      | 状态    | 说明                               |
| ------- | ----- | -------------------------------- |
| Android | ✅ 主平台 | 包名 `com.aidazi.app`，Android 8.0+ |
| Windows | ✅ 可用  | Windows 10+                      |
| Web     | ✅ 可用  | 浏览器直接访问                          |

## 🤝 联系作者

<div align="center">
  <img src="assets/wechat_qr.jpg" width="200" alt="作者微信二维码"><br>
  <sub>扫描二维码加作者微信</sub>
</div>

提供**复刻专属人物**，定制减脂搭子、健身搭子、瑜伽搭子、育儿搭子、亲密搭子等服务。

## 💖 感谢

本软件基于 [MoeTalk](https://github.com/shinnpuru/MoeTalk)（及其上游 [MisonoTalk](https://github.com/k96e/MisonoTalk)）二次开发，面向国内用户做了全面国产化改造。

## 📄 许可证

该项目根据 [MIT](LICENSE) 许可证的条款进行许可。
