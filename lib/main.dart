import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

const String baseUrl = 'http://127.0.0.1:8000';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
      ),
      home: const LoginPage(),
    );
  }
}

//////////////////////////////////////////////////////
// LOGIN
//////////////////////////////////////////////////////

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String user = 'Pai';
  final pin = TextEditingController();

  Future<void> login() async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user': user, 'pin': pin.text}),
    );

    final data = jsonDecode(res.body);

    if (data['status'] == 'ok') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => ChatPage(user: user)),
      );
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("PIN inválido")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ['Pai', 'Mãe', 'Filho', 'Filha'];

    return Scaffold(
      body: Center(
        child: Container(
          width: 350,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("English Trainer", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 20),

              DropdownButtonFormField(
                value: user,
                items: users
                    .map((e) =>
                        DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => user = v!),
              ),

              const SizedBox(height: 12),

              TextField(
                controller: pin,
                obscureText: true,
                decoration: const InputDecoration(labelText: "PIN"),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: login,
                  child: const Text("Entrar"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//////////////////////////////////////////////////////
// CHAT
//////////////////////////////////////////////////////

class ChatPage extends StatefulWidget {
  final String user;
  const ChatPage({super.key, required this.user});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final msg = TextEditingController();
  final recorder = AudioRecorder();
  final player = AudioPlayer();
  final scroll = ScrollController();

  List<Map> messages = [];
  bool recording = false;
  String level = "beginner";

  String? lastAIMessage; // 🔥 usado no treino

  void add(String text, bool user, {bool tr = false}) {
    setState(() {
      messages.add({'text': text, 'user': user, 'tr': tr});
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (scroll.hasClients) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
      }
    });
  }

  //////////////////////////////////////////////////////
  // CHAT
  //////////////////////////////////////////////////////

  Future<void> send() async {
    if (msg.text.isEmpty) return;

    add(msg.text, true);

    final res = await http.post(
      Uri.parse('$baseUrl/chat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'user': widget.user,
        'msg': msg.text,
        'level': level
      }),
    );

    msg.clear();

    final reply = jsonDecode(res.body)['resposta'];

    add(reply, false);

    lastAIMessage = reply; // 🔥 guarda última frase

    speak(reply);
  }

  //////////////////////////////////////////////////////
  // AUDIO
  //////////////////////////////////////////////////////

  Future<void> speak(String text) async {
    final res = await http.post(
      Uri.parse('$baseUrl/speak'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );

    await player.stop();
    await player.play(BytesSource(res.bodyBytes));
  }

  //////////////////////////////////////////////////////
  // TRADUZIR
  //////////////////////////////////////////////////////

  Future<void> translate(int i) async {
    final res = await http.post(
      Uri.parse('$baseUrl/translate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': messages[i]['text']}),
    );

    final data = jsonDecode(res.body);
    add("(${data['translation']})", false, tr: true);
  }

  //////////////////////////////////////////////////////
  // TREINO
  //////////////////////////////////////////////////////

  Future<void> trainLast() async {
    if (lastAIMessage == null) {
      add("Sem frase para treinar", false, tr: true);
      return;
    }

    final dir = await getTemporaryDirectory();

    await recorder.start(
      const RecordConfig(),
      path: "${dir.path}/train.m4a",
    );

    add("🎤 Fale agora...", false, tr: true);

    await Future.delayed(const Duration(seconds: 3));

    final path = await recorder.stop();

    if (path == null) return;

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/transcribe'),
    );

    req.files.add(await http.MultipartFile.fromPath('file', path));

    final res = await http.Response.fromStream(await req.send());
    final text = jsonDecode(res.body)['text'];

    add("Você disse: $text", false, tr: true);

    final res2 = await http.post(
      Uri.parse('$baseUrl/pronunciation'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'spoken': text,
        'correct': lastAIMessage,
      }),
    );

    final data = jsonDecode(res2.body);
    add(data['feedback'], false, tr: true);
  }

  //////////////////////////////////////////////////////
  // UI BOLHA
  //////////////////////////////////////////////////////

  Widget bubble(Map m, int i) {
    final isUser = m['user'];
    final text = m['text'];
    final isTr = m['tr'] ?? false;

    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        if (!isUser)
          const CircleAvatar(child: Icon(Icons.smart_toy)),

        Container(
          margin: const EdgeInsets.all(6),
          padding: const EdgeInsets.all(12),
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: isUser
                ? Colors.blue
                : isTr
                    ? Colors.blueGrey
                    : const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(text),

              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                  },
                ),
              ),
            ],
          ),
        ),

        if (isUser)
          const CircleAvatar(child: Icon(Icons.person)),
      ],
    );
  }

  //////////////////////////////////////////////////////
  // BUILD
  //////////////////////////////////////////////////////

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.user),
        actions: [
          DropdownButton(
            value: level,
            items: const [
              DropdownMenuItem(
                  value: "beginner", child: Text("Beginner")),
              DropdownMenuItem(
                  value: "intermediate", child: Text("Inter")),
              DropdownMenuItem(
                  value: "advanced", child: Text("Advanced")),
            ],
            onChanged: (v) => setState(() => level = v.toString()),
          )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: messages.length,
              itemBuilder: (_, i) => Column(
                children: [
                  bubble(messages[i], i),

                  if (!messages[i]['user'] &&
                      !(messages[i]['tr'] ?? false))
                    Row(
                      children: [
                        TextButton(
                            onPressed: () => translate(i),
                            child: const Text("🌍")),
                      ],
                    )
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: msg,
                    decoration: const InputDecoration(
                        hintText: "Digite...",
                        border: OutlineInputBorder()),
                  ),
                ),

                IconButton(
                    icon: Icon(
                        recording ? Icons.stop : Icons.mic),
                    onPressed: () {}),

                // 🎯 BOTÃO TREINAR
                IconButton(
                    icon: const Icon(Icons.school),
                    onPressed: trainLast),

                IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: send),
              ],
            ),
          )
        ],
      ),
    );
  }
}
