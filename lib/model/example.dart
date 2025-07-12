import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../model.dart';
import '../widgets.dart';

final tasks = ValueNotifier(<Task>[]);
int lastId = 0;

class Example extends StatefulWidget {
  const Example({super.key, required this.apiKey, required this.title});

  final String apiKey, title;

  @override
  State<Example> createState() => _ExampleState();
}

class _ExampleState extends State<Example> {
  final loading = ValueNotifier(false);
  final menu = ValueNotifier('');
  final messages = ValueNotifier<List<(Sender, String)>>([]);
  final controller = TextEditingController();
  late final _history = <Content>[];

  late final model = GenerativeModel(
    model: 'gemini-pro',
    apiKey: widget.apiKey,
    requestOptions: const RequestOptions(apiVersion: 'v1beta'),
    tools: [
      Tool(
        functionDeclarations: <FunctionDeclaration>[
          FunctionDeclaration(
            'add_task',
            'Add a new task to the list',
            Schema(
              SchemaType.object,
              properties: {'name': Schema(SchemaType.string), 'description': Schema(SchemaType.string, nullable: true)},
            ),
          ),
          FunctionDeclaration(
            'get_completed_tasks',
            'Return all the completed tasks in the list',
            Schema(
              SchemaType.object,
              properties: {
                'name': Schema(SchemaType.string, nullable: true, description: 'Search filter for name'),
                'description': Schema(SchemaType.string, nullable: true, description: 'Search filter for description'),
              },
            ),
          ),
          FunctionDeclaration(
            'get_active_tasks',
            'Return all the active tasks in the list',
            Schema(
              SchemaType.object,
              properties: {
                'name': Schema(SchemaType.string, nullable: true, description: 'Search filter for name'),
                'description': Schema(SchemaType.string, nullable: true, description: 'Search filter for description'),
              },
            ),
          ),
          FunctionDeclaration(
            'update_task',
            'Update a task in the list',
            Schema(
              SchemaType.object,
              properties: {
                'name': Schema(SchemaType.string, description: 'Task name'),
                'description': Schema(SchemaType.string, nullable: true, description: 'Task description'),
                'completed': Schema(SchemaType.boolean, nullable: true, description: 'Task status'),
              },
            ),
          ),
        ],
      ),
    ],
  );

  Future<void> sendMessage() async {
    final message = controller.text.trim();
    if (message.isEmpty) return;
    controller.clear();
    addMessage(Sender.user, message);
    loading.value = true;
    try {
      final prompt = StringBuffer();
      prompt.writeln(
        'If the following is not a question assume'
        'it is a new task to be added:',
      );
      prompt.writeln(message);
      final response = await callWithActions([Content.text(prompt.toString())]);
      if (response.text != null) {
        addMessage(Sender.system, response.text!);
      } else {
        addMessage(Sender.system, 'Something went wrong, please try again.');
      }
    } catch (e) {
      addMessage(Sender.system, 'Error sending message: $e');
    } finally {
      loading.value = false;
    }
  }

  Future<GenerateContentResponse> callWithActions(Iterable<Content> prompt) async {
    final response = await model.generateContent(_history.followedBy(prompt));
    if (response.candidates.isNotEmpty) {
      _history.addAll(prompt);
      _history.add(response.candidates.first.content);
    }
    final actions = <FunctionResponse>[];
    for (final fn in response.functionCalls) {
      final current = tasks.value.toList();
      final args = fn.args;
      switch (fn.name) {
        case 'add_task':
          final name = args['name'] as String;
          final description = args['description'] as String?;
          final task = Task(id: ++lastId, name: name, description: description, completed: false);
          current.add(task);
          tasks.value = current;
          actions.add(FunctionResponse(fn.name, task.toJson()));
          break;
        case 'get_completed_tasks':
          var filter = current.toList().where((e) => e.completed == true).toList();
          final name = args['name'] as String?;
          final description = args['description'] as String?;
          if (name != null) {
            filter = filter.where((e) => e.name.contains(name)).toList();
          }
          if (description != null) {
            filter = filter.where((e) => e.description?.contains(description) ?? false).toList();
          }
          actions.add(FunctionResponse(fn.name, {'tasks': filter.map((e) => e.toJson()).toList()}));
          break;
        case 'get_active_tasks':
          var filter = current.toList().where((e) => e.completed == false).toList();
          final name = args['name'] as String?;
          final description = args['description'] as String?;
          if (name != null) {
            filter = filter.where((e) => e.name.contains(name)).toList();
          }
          if (description != null) {
            filter = filter.where((e) => e.description?.contains(description) ?? false).toList();
          }
          actions.add(FunctionResponse(fn.name, {'tasks': filter.map((e) => e.toJson()).toList()}));
          break;
        case 'update_task':
          final name = args['name'] as String?;
          final idx = current.indexWhere((e) => e.name == name);
          if (idx == -1) {
            actions.add(FunctionResponse(fn.name, {"type": "error", 'message': 'Task with "$name" id not found'}));
            continue;
          }
          final task = current[idx];
          current[idx] = Task(
            id: task.id,
            name: args['name'] as String? ?? task.name,
            description: args['description'] as String? ?? task.description,
            completed: args['completed'] as bool? ?? task.completed,
          );
          tasks.value = current;
          actions.add(FunctionResponse(fn.name, current[idx].toJson()));
          break;
        default:
      }
    }
    if (actions.isNotEmpty) {
      return await callWithActions([
        ...prompt,
        if (response.functionCalls.isNotEmpty) Content.model(response.functionCalls),
        for (final res in actions) Content.functionResponse(res.name, res.response),
      ]);
    }
    return response;
  }

  void addMessage(Sender sender, String value, {bool clear = false}) {
    if (clear) {
      _history.clear();
      messages.value = [];
    }
    messages.value = messages.value.toList()..add((sender, value));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: messages,
      builder: (context, child) {
        final reversed = messages.value.reversed;
        return Scaffold(
          appBar: AppBar(title: Text(widget.title)),
          body:
              messages.value.isEmpty
                  ? const Center(child: Text('No tasks found'))
                  : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    reverse: true,
                    itemCount: reversed.length,
                    itemBuilder: (context, index) {
                      final (sender, message) = reversed.elementAt(index);
                      return MessageWidget(isFromUser: sender == Sender.user, text: message);
                    },
                  ),
          bottomNavigationBar: BottomAppBar(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: textFieldDecoration(
                      context,
                      'Try "Add a task for..."'
                      'or "What are my uncompleted tasks?"',
                    ),
                    onEditingComplete: sendMessage,
                    onSubmitted: (value) => sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: loading,
                  builder: (context, _) {
                    if (loading.value) {
                      return const CircularProgressIndicator();
                    }
                    return IconButton(onPressed: sendMessage, icon: const Icon(Icons.send), tooltip: 'Send a message');
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

enum Sender { user, system }
