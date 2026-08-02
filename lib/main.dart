import 'package:flutter/material.dart';

void main() {
  runApp(const VillagerTranslatorApp());
}

class VillagerTranslatorApp extends StatelessWidget {
  const VillagerTranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Villager Translator',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7D32)),
        useMaterial3: true,
      ),
      home: const ProjectHomePage(),
    );
  }
}

class ProjectHomePage extends StatelessWidget {
  const ProjectHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Villager Translator')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: const Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Minecraft MOD 翻訳',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Text(
                  '仕様駆動開発で再構築中です。最初の機能仕様を確定後、'
                  'MOD、クエスト、Patchouli ガイドブックの翻訳機能を実装します。',
                  style: TextStyle(fontSize: 16, height: 1.6),
                ),
                SizedBox(height: 24),
                Chip(label: Text('Windows デスクトップ版')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
