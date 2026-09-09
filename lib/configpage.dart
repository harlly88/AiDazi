// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:url_launcher/url_launcher.dart';
import 'storage.dart';
import 'i18n.dart';
import 'app_theme.dart' show primaryBlue;
import 'tts_provider.dart' show systemVoices;
import 'voice_input.dart';
import 'environment_provider.dart' show getEnvironmentInjection;

import 'utils.dart'
    show snackBarAlert, Config, DecimalTextInputFormatter, buildTimeInjection;

/// 17.15：Provider → API Key 申请链接映射
const Map<String, Map<String, String>> _apiKeyApplyLinks = {
  'qwen':     {'name': '阿里云百炼', 'url': 'https://bailian.console.aliyun.com/?tab=model#/api-key'},
  'deepseek': {'name': 'DeepSeek',   'url': 'https://platform.deepseek.com/api_keys'},
  'doubao':   {'name': '火山引擎',    'url': 'https://console.volcengine.com/ark/region:ark+cn-beijing/apiKey'},
  'glm':      {'name': '智谱 AI',    'url': 'https://open.bigmodel.cn/usercenter/apikeys'},
  'kimi':     {'name': 'Moonshot',   'url': 'https://platform.moonshot.cn/console/api-keys'},
};

/// 预置 LLM 模板（与 agent.md 第三章 3.1 一致；预设项不可删除，缺失时自动补齐）
final List<Config> _presetConfigs = [
  Config(name: "qwen", baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1", apiKey: "", model: "qwen3.7-flash", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
  Config(name: "deepseek", baseUrl: "https://api.deepseek.com/v1", apiKey: "", model: "deepseek-chat", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
  Config(name: "doubao", baseUrl: "https://ark.cn-beijing.volces.com/api/v3", apiKey: "", model: "doubao-seed-1-6", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
  Config(name: "glm", baseUrl: "https://open.bigmodel.cn/api/paas/v4", apiKey: "", model: "glm-4.6", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
  Config(name: "kimi", baseUrl: "https://api.moonshot.cn/v1", apiKey: "", model: "kimi-k2-turbo-preview", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
  Config(name: "custom", baseUrl: "", apiKey: "", model: "", temperature: "1", frequencyPenalty: "", presencePenalty: "", maxTokens: "8192"),
];

bool _isPresetName(String name) =>
    _presetConfigs.any((c) => c.name == name);

class ConfigPage extends StatefulWidget {
  final Function(Config) updateFunc;
  final Config currentConfig;
  const ConfigPage({super.key, required this.updateFunc, required this.currentConfig});

  @override
  ConfigPageState createState() => ConfigPageState();
}

class ConfigPageState extends State<ConfigPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  String? selectedConfig;
  List<Config> apiConfigs = [];
  TextEditingController nameController = TextEditingController();
  TextEditingController urlController = TextEditingController();
  TextEditingController keyController = TextEditingController();
  TextEditingController modelController = TextEditingController();
  TextEditingController temperatureController = TextEditingController();
  TextEditingController frequencyPenaltyController = TextEditingController();
  TextEditingController presencePenaltyController = TextEditingController();
  TextEditingController maxTokensController = TextEditingController();

  // TTS 兜底音色
  String _fallbackVoice = 'longanhuan_v3';

  // 15.16：TTS / ASR / 生图 / 生视频模型名全部可编辑（官方可能下线/升级模型）
  final _ttsModelController = TextEditingController();
  final _asrModelController = TextEditingController();
  final _wanImageModelController = TextEditingController();
  final _wanVideoModelController = TextEditingController();

  // 16.3：ASR 测试进行中（录 3 秒 → 识别 → 展示结果）
  bool _asrTesting = false;

  // 万相文生图
  String _wanImageSize = '1080*1920';

  // 万相文生视频
  String _wanVideoResolution = '720P';
  String _wanVideoRatio = '9:16';
  int _wanVideoDuration = 5;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    getApiConfigs().then((List<Config> value) async {
      debugPrint("Loaded API configs: $value");
      // 14.4 预设自动补齐：无论列表是否为空，按 name 判重补齐缺失的预置项
      final existingNames = value.map((c) => c.name).toSet();
      for (final preset in _presetConfigs) {
        if (!existingNames.contains(preset.name)) {
          value.add(preset);
        }
      }
      // 预置项排前，自定义项按字母序
      value.sort((a, b) {
        final ap = _isPresetName(a.name) ? 0 : 1;
        final bp = _isPresetName(b.name) ? 0 : 1;
        return ap != bp ? ap - bp : a.name.compareTo(b.name);
      });

      setState(() {
        apiConfigs = value;
        for (Config c in apiConfigs) {
          if (c.name == widget.currentConfig.name) {
            selectedConfig = c.name;
            break;
          }
        }
        nameController.text = widget.currentConfig.name;
        urlController.text = widget.currentConfig.baseUrl;
        keyController.text = widget.currentConfig.apiKey;
        modelController.text = widget.currentConfig.model;
        temperatureController.text = widget.currentConfig.temperature ?? "";
        frequencyPenaltyController.text = widget.currentConfig.frequencyPenalty ?? "";
        presencePenaltyController.text = widget.currentConfig.presencePenalty ?? "";
        maxTokensController.text = widget.currentConfig.maxTokens ?? "";
      });
    });
    // 语音 / 生图 / 生视频配置载入（15.16：模型名可编辑）
    getTtsFallbackVoice().then((v) {
      if (mounted) setState(() => _fallbackVoice = v);
    });
    getTtsModel().then((v) {
      if (mounted) _ttsModelController.text = v;
    });
    getAsrModel().then((v) {
      if (mounted) _asrModelController.text = v;
    });
    getWanImageConfig().then((config) {
      if (mounted) {
        setState(() {
          _wanImageModelController.text = config.$1;
          _wanImageSize = config.$2;
        });
      }
    });
    getVideoModel().then((v) {
      if (mounted) _wanVideoModelController.text = v;
    });
    getWanVideoConfig().then((config) {
      if (mounted) {
        setState(() {
          _wanVideoResolution = config.$1;
          _wanVideoRatio = config.$2;
          _wanVideoDuration = config.$3;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    nameController.dispose();
    urlController.dispose();
    keyController.dispose();
    modelController.dispose();
    temperatureController.dispose();
    frequencyPenaltyController.dispose();
    presencePenaltyController.dispose();
    maxTokensController.dispose();
    _ttsModelController.dispose();
    _asrModelController.dispose();
    _wanImageModelController.dispose();
    _wanVideoModelController.dispose();
    super.dispose();
  }

  Future<void> deleteConfirm(BuildContext context, String config) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(I18n.t('confirm_delete')),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(I18n.t('delete_confirm_msg').replaceFirst('?', config)),
                Text(I18n.t('cannot_undo')),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(I18n.t('cancel')),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: Text(I18n.t('delete')),
              onPressed: () {
                setState(() {
                  for (Config c in apiConfigs) {
                    if (c.name == config) {
                      deleteApiConfig(config);
                      apiConfigs.remove(c);
                      if (selectedConfig == config) {
                        if (apiConfigs.isNotEmpty) {
                          selectedConfig = apiConfigs[0].name;
                        }
                      }
                      break;
                    }
                  }
                });
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void saveConfig() {
    if (apiConfigs.isNotEmpty) {
      for (Config c in apiConfigs) {
        if (c.name == nameController.text) {
          // 删除旧配置
          deleteApiConfig(nameController.text);
          apiConfigs.remove(c);
        }
      }
    }
    Config newConfig = Config(
      name: nameController.text,
      baseUrl: urlController.text,
      apiKey: keyController.text,
      model: modelController.text,
      temperature: temperatureController.text.isEmpty
          ? null
          : temperatureController.text,
      frequencyPenalty: frequencyPenaltyController.text.isEmpty
          ? null
          : frequencyPenaltyController.text,
      presencePenalty: presencePenaltyController.text.isEmpty
          ? null
          : presencePenaltyController.text,
      maxTokens: maxTokensController.text.isEmpty
          ? null
          : maxTokensController.text,
    );
    setApiConfig(newConfig);
    setCurrentApiConfig(nameController.text);
    setState(() {
      apiConfigs.add(newConfig);
      selectedConfig = nameController.text;
    });
  }

  /// 15.16：保存模型名（空值回落默认）
  Future<void> _saveModelName(
      Future<void> Function(String) setter, String value) async {
    await setter(value.trim());
    snackBarAlert(context, I18n.t('save_success'));
  }

  /// 16.3：ASR 一键测试——录 3 秒 → 自动停止 → 调百炼识别 → 展示结果
  /// （不进对话流程；失败时 SnackBar 显示具体错误，便于定位 Key/网络/格式问题）
  Future<void> _runAsrTest() async {
    if (_asrTesting) return;
    setState(() => _asrTesting = true);
    final controller = VoiceInputController();
    try {
      await controller.start();
      if (!mounted) return;
      snackBarAlert(context, I18n.t('asr_test_start'));
      await Future<void>.delayed(const Duration(seconds: 3));
      final text = await controller.stopAndTranscribe();
      if (!mounted) return;
      if (text == null || text.isEmpty) {
        snackBarAlert(
            context, "${I18n.t('asr_test_fail')}: ${I18n.t('recognition_failed')}");
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(I18n.t('asr_test_ok')),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(I18n.t('confirm')),
            ),
          ],
        ),
      );
    } catch (e) {
      await controller.cancel();
      if (mounted) snackBarAlert(context, "${I18n.t('asr_test_fail')}: $e");
    } finally {
      await controller.dispose();
      if (mounted) setState(() => _asrTesting = false);
    }
  }

  /// 16.4：环境信息预览——时间注入（实时生成）+ 定位/天气注入（异步加载）
  Future<void> _showEnvPreview() async {
    final timeText = buildTimeInjection();
    final envFuture = getEnvironmentInjection();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(I18n.t('env_preview')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                I18n.t('env_preview_hint'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Text(timeText),
              const SizedBox(height: 8),
              FutureBuilder<String>(
                future: envFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final env = snapshot.data ?? '';
                  return Text(
                    env.isEmpty ? I18n.t('env_preview_empty') : env,
                    style: TextStyle(
                        fontSize: 13,
                        color: env.isEmpty ? Colors.grey[600] : null),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(I18n.t('confirm')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.t('model_config')),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: I18n.t('llm_chat_model')),
            Tab(text: I18n.t('voice_config')),
            Tab(text: I18n.t('image_model')),
            Tab(text: I18n.t('video_model')),
          ],
        ),
        actions: [
          // 初始化
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                nameController.clear();
                urlController.clear();
                keyController.clear();
                modelController.clear();
                temperatureController.clear();
                frequencyPenaltyController.clear();
                presencePenaltyController.clear();
                maxTokensController.clear();
              });
            },
          ),
          // 保存（当前 LLM 配置）
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              saveConfig();
              // 18.1：保存按钮同步持久化 4 个模型名（输入框仅 onSubmitted 保存，
              // 移动端直接点保存会丢失；空值回落各自默认值）
              final tts = _ttsModelController.text.trim();
              final asr = _asrModelController.text.trim();
              final wanImage = _wanImageModelController.text.trim();
              final wanVideo = _wanVideoModelController.text.trim();
              await setTtsModel(tts.isEmpty ? 'cosyvoice-v3-flash' : tts);
              await setAsrModel(asr.isEmpty ? 'qwen3-asr-flash' : asr);
              await setWanImageConfig(
                  wanImage.isEmpty ? 'wan2.7-image' : wanImage, _wanImageSize);
              await setVideoModel(wanVideo.isEmpty ? 'wan2.7-t2v' : wanVideo);
              widget.updateFunc(Config(
                name: nameController.text,
                baseUrl: urlController.text,
                apiKey: keyController.text,
                model: modelController.text,
                temperature: temperatureController.text.isEmpty
                    ? null
                    : temperatureController.text,
                frequencyPenalty: frequencyPenaltyController.text.isEmpty
                    ? null
                    : frequencyPenaltyController.text,
                presencePenalty: presencePenaltyController.text.isEmpty
                    ? null
                    : presencePenaltyController.text,
                maxTokens: maxTokensController.text.isEmpty
                    ? null
                    : maxTokensController.text,
              ));
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLlmTab(),
          _buildVoiceTab(),
          _buildImageTab(),
          _buildVideoTab(),
        ],
      ),
    );
  }

  // ==================== LLM 对话模型 ====================
  Widget _buildLlmTab() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          children: [
            ListTile(
              title: Text(I18n.t('preset_manage'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  DropdownButton<String>(
                    value: selectedConfig,
                    hint: Text(I18n.t('select_preset')),
                    isExpanded: true,
                    items: apiConfigs.map((Config config) {
                      final isQwen = config.name == 'qwen';
                      return DropdownMenuItem<String>(
                        value: config.name,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(config.name),
                                  if (isQwen) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: primaryBlue.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '推荐',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: primaryBlue,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // 预置项不可删除（14.4），仅自定义项显示删除按钮
                            if (!_isPresetName(config.name))
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () {
                                  deleteConfirm(context, config.name);
                                },
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        selectedConfig = newValue;
                        for (Config c in apiConfigs) {
                          if (c.name == newValue) {
                            nameController.text = c.name;
                            urlController.text = c.baseUrl;
                            keyController.text = c.apiKey;
                            modelController.text = c.model;
                            temperatureController.text = c.temperature ?? "";
                            frequencyPenaltyController.text = c.frequencyPenalty ?? "";
                            presencePenaltyController.text = c.presencePenalty ?? "";
                            maxTokensController.text = c.maxTokens ?? "";
                            widget.updateFunc(c);
                            break;
                          }
                        }
                      });
                      setCurrentApiConfig(selectedConfig!);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              title: Text(I18n.t('config_params'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(labelText: I18n.t('name')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(labelText: I18n.t('api_url')),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keyController,
                    decoration: InputDecoration(labelText: I18n.t('api_key')),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: keyController,
                    builder: (context, value, _) {
                      final isAliyun =
                          urlController.text.contains('dashscope.aliyuncs.com');
                      if (!isAliyun) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '提示：此为阿里云百炼 API Key，语音、识别、文生图、文生视频将复用同一个 Key',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  // 17.15：API Key 申请链接按钮（根据 Provider 动态显示）
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: nameController,
                    builder: (context, value, _) {
                      final applyInfo = _apiKeyApplyLinks[value.text.trim()];
                      if (applyInfo == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final url = Uri.parse(applyInfo['url']!);
                            if (await canLaunchUrl(url)) {
                              await launchUrl(
                                url,
                                mode: LaunchMode.externalApplication,
                              );
                            } else {
                              if (context.mounted) {
                                snackBarAlert(context, '无法打开浏览器');
                              }
                            }
                          },
                          icon: const Icon(Icons.key, size: 18),
                          label: Text('申请 ${applyInfo['name']} API Key'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: modelController,
                    decoration: InputDecoration(labelText: I18n.t('model')),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: temperatureController,
                          decoration: InputDecoration(labelText: I18n.t('temperature')),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalTextInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: frequencyPenaltyController,
                          decoration: InputDecoration(labelText: I18n.t('frequency_penalty')),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalTextInputFormatter()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: presencePenaltyController,
                          decoration: InputDecoration(labelText: I18n.t('presence_penalty')),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalTextInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: maxTokensController,
                          decoration: InputDecoration(labelText: I18n.t('max_output_length')),
                          keyboardType: const TextInputType.numberWithOptions(),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    child: Text(I18n.t('save_preset')),
                    onPressed: () {
                      if (nameController.text.isEmpty ||
                          urlController.text.isEmpty ||
                          keyController.text.isEmpty ||
                          modelController.text.isEmpty) {
                        snackBarAlert(context, I18n.t('please_fill_all'));
                      } else {
                        saveConfig();
                        snackBarAlert(context, I18n.t('save_success'));
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  // 16.4：环境信息预览（时间/位置/天气注入文本）
                  OutlinedButton.icon(
                    onPressed: _showEnvPreview,
                    icon: const Icon(Icons.info_outline),
                    label: Text(I18n.t('env_preview')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 语音（TTS / ASR） ====================
  Widget _buildVoiceTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(I18n.t('voice_config_hint')),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: Text(I18n.t('tts_config'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 15.16：TTS 模型名可编辑（默认 cosyvoice-v3-flash）
              TextField(
                controller: _ttsModelController,
                decoration: InputDecoration(
                  labelText: I18n.t('tts_model_name'),
                  hintText: 'cosyvoice-v3-flash',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) =>
                    _saveModelName(setTtsModel, v.isEmpty ? 'cosyvoice-v3-flash' : v),
              ),
              const SizedBox(height: 12),
              Text(I18n.t('tts_fallback_voice'),
                  style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: _fallbackVoice,
                isExpanded: true,
                items: systemVoices
                    .map((v) => DropdownMenuItem<String>(
                          value: v.id,
                          child: Text(v.label),
                        ))
                    .toList(),
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  await setTtsFallbackVoice(newValue);
                  setState(() => _fallbackVoice = newValue);
                  snackBarAlert(context, I18n.t('save_success'));
                },
              ),
              const SizedBox(height: 4),
              Text(
                I18n.t('tts_fallback_voice_hint'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        const Divider(),
        ListTile(
          title: Text(I18n.t('asr_config'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 15.16：ASR 模型名可编辑（默认 qwen3-asr-flash；sensevoice 已下线）
              TextField(
                controller: _asrModelController,
                decoration: InputDecoration(
                  labelText: I18n.t('asr_model_name'),
                  hintText: 'qwen3-asr-flash',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) =>
                    _saveModelName(setAsrModel, v.isEmpty ? 'qwen3-asr-flash' : v),
              ),
              const SizedBox(height: 4),
              Text(
                I18n.t('asr_config_hint'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              // 16.3：ASR 一键测试（录 3 秒 → 识别 → 显示结果，不进对话流程）
              ElevatedButton.icon(
                onPressed: _asrTesting ? null : _runAsrTest,
                icon: _asrTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mic),
                label: Text(I18n.t('asr_test')),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 生图模型（万相） ====================
  Widget _buildImageTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(I18n.t('wan_image_hint')),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: Text(I18n.t('image_model'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // 15.16：生图模型名可编辑（默认 wan2.7-image；官方下线/升级可自行更换）
              TextField(
                controller: _wanImageModelController,
                decoration: InputDecoration(
                  labelText: I18n.t('model'),
                  hintText: 'wan2.7-image',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) => _saveModelName(
                    (m) => setWanImageConfig(m, _wanImageSize),
                    v.isEmpty ? 'wan2.7-image' : v),
              ),
              const SizedBox(height: 4),
              Text(
                I18n.t('model_editable_hint'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Text(I18n.t('image_resolution'), style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              // 15.6：统一 9:16 竖版档位（适配手机竖屏）
              DropdownButton<String>(
                value: _wanImageSize,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '720*1280', child: Text('720×1280（9:16）')),
                  DropdownMenuItem(value: '1080*1920', child: Text('1080×1920（9:16）')),
                ],
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  await setWanImageConfig(
                      _wanImageModelController.text, newValue);
                  setState(() => _wanImageSize = newValue);
                  snackBarAlert(context, I18n.t('save_success'));
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==================== 生视频模型（万相） ====================
  Widget _buildVideoTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(I18n.t('wan_video_hint')),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          title: Text(I18n.t('video_model'),
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 15.16：生视频模型名可编辑（默认 wan2.7-t2v；图生视频自动切 i2v）
              TextField(
                controller: _wanVideoModelController,
                decoration: InputDecoration(
                  labelText: I18n.t('model'),
                  hintText: 'wan2.7-t2v',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (v) => _saveModelName(
                    setVideoModel, v.isEmpty ? 'wan2.7-t2v' : v),
              ),
              const SizedBox(height: 4),
              Text(
                I18n.t('model_editable_hint'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 12),
              Text(I18n.t('video_resolution'), style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: _wanVideoResolution,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '720P', child: Text('720P')),
                  DropdownMenuItem(value: '1080P', child: Text('1080P')),
                ],
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  await setWanVideoConfig(newValue, _wanVideoRatio, _wanVideoDuration);
                  setState(() => _wanVideoResolution = newValue);
                  snackBarAlert(context, I18n.t('save_success'));
                },
              ),
              const SizedBox(height: 12),
              Text(I18n.t('video_ratio'), style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 4),
              DropdownButton<String>(
                value: _wanVideoRatio,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: '9:16', child: Text('9:16（竖屏）')),
                  DropdownMenuItem(value: '16:9', child: Text('16:9（横屏）')),
                  DropdownMenuItem(value: '1:1', child: Text('1:1（正方形）')),
                  DropdownMenuItem(value: '4:3', child: Text('4:3')),
                  DropdownMenuItem(value: '3:4', child: Text('3:4')),
                ],
                onChanged: (String? newValue) async {
                  if (newValue == null) return;
                  await setWanVideoConfig(_wanVideoResolution, newValue, _wanVideoDuration);
                  setState(() => _wanVideoRatio = newValue);
                  snackBarAlert(context, I18n.t('save_success'));
                },
              ),
              const SizedBox(height: 12),
              Text('${I18n.t('video_duration')}：$_wanVideoDuration ${I18n.t('video_duration_seconds')}',
                  style: const TextStyle(fontSize: 14)),
              Slider(
                value: _wanVideoDuration.toDouble(),
                min: 2,
                max: 15,
                divisions: 13,
                label: '$_wanVideoDuration',
                onChanged: (value) => setState(() => _wanVideoDuration = value.round()),
                onChangeEnd: (value) async {
                  await setWanVideoConfig(_wanVideoResolution, _wanVideoRatio, value.round());
                  snackBarAlert(context, I18n.t('save_success'));
                },
              ),
              Text(
                I18n.t('video_cost_hint'),
                style: TextStyle(fontSize: 12, color: Colors.orange[700]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
