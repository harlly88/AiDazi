import 'package:flutter/material.dart';

import 'environment_provider.dart';
import 'i18n.dart';
import 'storage.dart';

/// 我的设定（15.9：用户画像）
///
/// 称呼/职业/年龄/生日/其他 → prompt 注入（utils.dart buildContextInjections）；
/// 称呼非空时替换 {{user}} 宏取值来源（storage.getUserName）。
/// 位置感知开关（15.10/15.11：定位 + 天气注入）也放在本页。
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final _nameController = TextEditingController();
  final _occupationController = TextEditingController();
  final _ageController = TextEditingController();
  final _birthdayController = TextEditingController();
  final _otherController = TextEditingController();
  bool _locationEnabled = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await getUserProfile();
    final locationEnabled = await EnvironmentProvider.isEnabled();
    if (!mounted) return;
    setState(() {
      _nameController.text = profile.name;
      _occupationController.text = profile.occupation;
      _ageController.text = profile.age;
      _birthdayController.text = profile.birthday;
      _otherController.text = profile.other;
      _locationEnabled = locationEnabled;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _occupationController.dispose();
    _ageController.dispose();
    _birthdayController.dispose();
    _otherController.dispose();
    super.dispose();
  }

  /// 生日选择器（存 MM-dd）
  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _parseBirthday(now.year) ?? DateTime(now.year, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
      helpText: I18n.t('profile_birthday'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _birthdayController.text =
          '${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    });
  }

  DateTime? _parseBirthday(int year) {
    final parts = _birthdayController.text.split('-');
    if (parts.length != 2) return null;
    final month = int.tryParse(parts[0]);
    final day = int.tryParse(parts[1]);
    if (month == null || day == null) return null;
    return DateTime(year, month, day);
  }

  Future<void> _save() async {
    await setUserProfile(UserProfile(
      name: _nameController.text.trim(),
      occupation: _occupationController.text.trim(),
      age: _ageController.text.trim(),
      birthday: _birthdayController.text.trim(),
      other: _otherController.text.trim(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(I18n.t('profile_saved'))),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(I18n.t('my_profile')),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: I18n.t('confirm'),
            onPressed: _save,
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text(
                  I18n.t('my_profile_hint'),
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: I18n.t('profile_nickname'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _occupationController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: I18n.t('profile_occupation'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: I18n.t('profile_age'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _birthdayController,
                  readOnly: true,
                  onTap: _pickBirthday,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: I18n.t('profile_birthday'),
                    hintText: I18n.t('profile_birthday_hint'),
                    suffixIcon: const Icon(Icons.calendar_month),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _otherController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: I18n.t('profile_other'),
                  ),
                ),
                const Divider(height: 32),
                SwitchListTile(
                  title: Text(I18n.t('location_awareness')),
                  subtitle: Text(
                    I18n.t('location_awareness_hint'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  value: _locationEnabled,
                  onChanged: (value) async {
                    await EnvironmentProvider.setEnabled(value);
                    if (!mounted) return;
                    setState(() => _locationEnabled = value);
                  },
                ),
              ],
            ),
    );
  }
}
