import 'dart:async';

import 'package:cinder/cinder.dart';

enum ChatRole { user, assistant, system, tool }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.timestamp,
    this.streaming = false,
    this.title,
  });

  final Object id;
  final ChatRole role;
  final String content;
  final DateTime? timestamp;
  final bool streaming;
  final String? title;

  ChatMessage copyWith({String? content, bool? streaming, String? title}) {
    return ChatMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      timestamp: timestamp,
      streaming: streaming ?? this.streaming,
      title: title ?? this.title,
    );
  }
}

/// Owns a chat transcript and coalesces streaming deltas to frame cadence.
class ChatViewController extends ChangeNotifier {
  ChatViewController({
    Iterable<ChatMessage> messages = const [],
    this.maxMessages = 10000,
    this.streamBatchInterval = const Duration(milliseconds: 16),
  }) : _messages = List.of(messages);

  final int maxMessages;
  final Duration streamBatchInterval;
  final List<ChatMessage> _messages;
  final Map<Object, StringBuffer> _pendingDeltas = {};
  Timer? _flushTimer;

  List<ChatMessage> get messages => List.unmodifiable(_messages);

  void add(ChatMessage message) {
    flushPendingDeltas();
    _messages.removeWhere((item) => item.id == message.id);
    _messages.add(message);
    _trim();
    notifyListeners();
  }

  void replace(ChatMessage message) {
    flushPendingDeltas();
    final index = _messages.indexWhere((item) => item.id == message.id);
    if (index < 0) {
      add(message);
      return;
    }
    _messages[index] = message;
    notifyListeners();
  }

  void appendDelta(Object id, String delta) {
    if (delta.isEmpty) return;
    (_pendingDeltas[id] ??= StringBuffer()).write(delta);
    _flushTimer ??= Timer(streamBatchInterval, flushPendingDeltas);
  }

  void finishStreaming(Object id) {
    flushPendingDeltas();
    final index = _messages.indexWhere((item) => item.id == id);
    if (index < 0) return;
    _messages[index] = _messages[index].copyWith(streaming: false);
    notifyListeners();
  }

  void remove(Object id) {
    _pendingDeltas.remove(id);
    final before = _messages.length;
    _messages.removeWhere((item) => item.id == id);
    if (_messages.length != before) notifyListeners();
  }

  void clear() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _pendingDeltas.clear();
    if (_messages.isEmpty) return;
    _messages.clear();
    notifyListeners();
  }

  void flushPendingDeltas() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pendingDeltas.isEmpty) return;
    var changed = false;
    for (final entry in _pendingDeltas.entries) {
      final index = _messages.indexWhere((item) => item.id == entry.key);
      if (index < 0) continue;
      final message = _messages[index];
      _messages[index] = message.copyWith(
        content: '${message.content}${entry.value}',
        streaming: true,
      );
      changed = true;
    }
    _pendingDeltas.clear();
    if (changed) notifyListeners();
  }

  void _trim() {
    if (_messages.length <= maxMessages) return;
    _messages.removeRange(0, _messages.length - maxMessages);
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _pendingDeltas.clear();
    super.dispose();
  }
}

/// Virtualized, selectable chat transcript suitable for LLM applications.
class ChatView extends StatefulWidget {
  const ChatView({
    super.key,
    required this.controller,
    this.followTail = true,
    this.showTimestamps = true,
    this.emptyMessage = 'Start a conversation',
    this.messageBuilder,
    this.onMessageSelected,
  });

  final ChatViewController controller;
  final bool followTail;
  final bool showTimestamps;
  final String emptyMessage;
  final Widget Function(BuildContext context, ChatMessage message, int index)?
  messageBuilder;
  final ValueChanged<ChatMessage>? onMessageSelected;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(ChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (widget.followTail && widget.controller.messages.isNotEmpty) {
      _scrollController.ensureIndexVisible(
        index: widget.controller.messages.length - 1,
      );
    }
    if (mounted) setState(() {});
  }

  String _roleLabel(ChatRole role) {
    switch (role) {
      case ChatRole.user:
        return 'You';
      case ChatRole.assistant:
        return 'Assistant';
      case ChatRole.system:
        return 'System';
      case ChatRole.tool:
        return 'Tool';
    }
  }

  Color _roleColor(ChatRole role) {
    switch (role) {
      case ChatRole.user:
        return Colors.blue;
      case ChatRole.assistant:
        return Colors.cyan;
      case ChatRole.system:
        return Colors.yellow;
      case ChatRole.tool:
        return Colors.green;
    }
  }

  Widget _defaultMessage(BuildContext context, ChatMessage message) {
    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onMessageSelected == null
            ? null
            : () => widget.onMessageSelected!(message),
        child: Container(
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: const Color.fromRGB(22, 25, 34),
            border: BoxBorder.all(color: _roleColor(message.role)),
            title: BorderTitle(
              text:
                  ' ${TerminalTextSanitizer.sanitize(message.title ?? _roleLabel(message.role))} ',
            ),
          ),
          padding: const EdgeInsets.all(1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectionArea(
                child: StreamingMessage(
                  data: message.content,
                  streaming: message.streaming,
                ),
              ),
              if (widget.showTimestamps && message.timestamp != null)
                Align(
                  alignment: Alignment.bottomRight,
                  child: TerminalText.safe(
                    message.timestamp!.toIso8601String(),
                    style: const TextStyle(color: Colors.grey),
                    softWrap: false,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.controller.messages;
    if (messages.isEmpty) {
      return Center(child: TerminalText.safe(widget.emptyMessage));
    }
    return VirtualListView.builder(
      controller: _scrollController,
      itemCount: messages.length,
      cacheExtent: 6,
      itemBuilder: (context, index) {
        final message = messages[index];
        return widget.messageBuilder?.call(context, message, index) ??
            _defaultMessage(context, message);
      },
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scrollController.dispose();
    super.dispose();
  }
}

/// A repaint-isolated Markdown message with an optional streaming cursor.
class StreamingMessage extends StatelessWidget {
  const StreamingMessage({
    super.key,
    required this.data,
    this.streaming = false,
    this.cursor = '▋',
    this.styleSheet,
  });

  final String data;
  final bool streaming;
  final String cursor;
  final MarkdownStyleSheet? styleSheet;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MarkdownText(data, styleSheet: styleSheet),
          if (streaming)
            Text(cursor, style: const TextStyle(color: Colors.cyan)),
        ],
      ),
    );
  }
}

enum ToolCallStatus { queued, running, succeeded, failed, cancelled }

/// Collapsible presentation for an agent tool call.
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({
    super.key,
    required this.toolName,
    required this.status,
    this.input,
    this.output,
    this.error,
    this.initiallyExpanded = false,
    this.onCancel,
  });

  final String toolName;
  final ToolCallStatus status;
  final String? input;
  final String? output;
  final String? error;
  final bool initiallyExpanded;
  final VoidCallback? onCancel;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  late bool _expanded = widget.initiallyExpanded;

  String _marker() {
    switch (widget.status) {
      case ToolCallStatus.queued:
        return '○';
      case ToolCallStatus.running:
        return '◐';
      case ToolCallStatus.succeeded:
        return '✓';
      case ToolCallStatus.failed:
        return '✗';
      case ToolCallStatus.cancelled:
        return '■';
    }
  }

  Color _color() {
    switch (widget.status) {
      case ToolCallStatus.queued:
        return Colors.grey;
      case ToolCallStatus.running:
        return Colors.cyan;
      case ToolCallStatus.succeeded:
        return Colors.green;
      case ToolCallStatus.failed:
        return Colors.red;
      case ToolCallStatus.cancelled:
        return Colors.yellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color.fromRGB(20, 23, 31),
        border: BoxBorder.all(color: _color()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text('${_marker()} ', style: TextStyle(color: _color())),
                Expanded(
                  child: TerminalText.safe(
                    widget.toolName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    softWrap: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.status == ToolCallStatus.running &&
                    widget.onCancel != null)
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: const Text('[stop]'),
                  ),
                const SizedBox(width: 1),
                Text(_expanded ? '▴' : '▾'),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(),
            if (widget.input != null) ...[
              const Text(
                'Input',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TerminalText.safe(widget.input!),
            ],
            if (widget.output != null) ...[
              const Text(
                'Output',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SelectionArea(child: TerminalText.safe(widget.output!)),
            ],
            if (widget.error != null) ...[
              const Text(
                'Error',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TerminalText.safe(
                widget.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// Collapsible model reasoning/status block.
class ThinkingBlock extends StatefulWidget {
  const ThinkingBlock({
    super.key,
    required this.content,
    this.label = 'Thinking',
    this.initiallyExpanded = false,
    this.active = false,
  });

  final String content;
  final String label;
  final bool initiallyExpanded;
  final bool active;

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: Colors.grey)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Text(
                  widget.active ? '◐ ' : '◇ ',
                  style: const TextStyle(color: Colors.grey),
                ),
                Expanded(
                  child: TerminalText.safe(
                    widget.label,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(_expanded ? '▴' : '▾'),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(),
            TerminalText.safe(
              widget.content,
              style: const TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum ApprovalRisk { low, medium, high, critical }

/// Explicit, keyboard-friendly approval prompt for agent operations.
class ApprovalDialog extends StatelessWidget {
  const ApprovalDialog({
    super.key,
    required this.title,
    required this.command,
    required this.onApprove,
    required this.onDeny,
    this.description,
    this.scope,
    this.risk = ApprovalRisk.medium,
    this.reversible,
    this.onAlwaysApprove,
  });

  final String title;
  final String command;
  final String? description;
  final String? scope;
  final ApprovalRisk risk;
  final bool? reversible;
  final VoidCallback onApprove;
  final VoidCallback onDeny;
  final VoidCallback? onAlwaysApprove;

  Color _riskColor() {
    switch (risk) {
      case ApprovalRisk.low:
        return Colors.green;
      case ApprovalRisk.medium:
        return Colors.yellow;
      case ApprovalRisk.high:
      case ApprovalRisk.critical:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (event) {
        if (event.logicalKey == LogicalKey.escape ||
            event.logicalKey == LogicalKey.keyN) {
          onDeny();
          return true;
        }
        if (event.logicalKey == LogicalKey.enter ||
            event.logicalKey == LogicalKey.keyY) {
          onApprove();
          return true;
        }
        return false;
      },
      child: Dialog(
        title: title,
        width: 72,
        actions: [
          _ActionButton(label: 'Deny', onPressed: onDeny, color: Colors.red),
          const SizedBox(width: 1),
          if (onAlwaysApprove != null) ...[
            _ActionButton(
              label: 'Always',
              onPressed: onAlwaysApprove!,
              color: Colors.yellow,
            ),
            const SizedBox(width: 1),
          ],
          _ActionButton(
            label: 'Approve',
            onPressed: onApprove,
            color: Colors.green,
          ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TerminalText.safe(
              command,
              style: const TextStyle(
                color: Colors.cyan,
                backgroundColor: Color.fromRGB(16, 18, 24),
              ),
            ),
            const Divider(),
            if (description != null) TerminalText.safe(description!),
            Row(
              children: [
                const SizedBox(width: 12, child: Text('Risk')),
                TerminalText.safe(
                  risk.name.toUpperCase(),
                  style: TextStyle(
                    color: _riskColor(),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (scope != null)
              Row(
                children: [
                  const SizedBox(width: 12, child: Text('Scope')),
                  Expanded(child: TerminalText.safe(scope!)),
                ],
              ),
            if (reversible != null)
              Row(
                children: [
                  const SizedBox(width: 12, child: Text('Reversible')),
                  Text(reversible! ? 'yes' : 'no'),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onPressed,
    required this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        decoration: BoxDecoration(border: BoxBorder.all(color: color)),
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: TerminalText.safe(label),
      ),
    );
  }
}

class FileTreeNode {
  const FileTreeNode({
    required this.path,
    required this.name,
    this.directory = false,
    this.children = const [],
    this.modified = false,
  });

  final String path;
  final String name;
  final bool directory;
  final List<FileTreeNode> children;
  final bool modified;

  TreeNode<FileTreeNode> toTreeNode() {
    return TreeNode<FileTreeNode>(
      id: path,
      label: name,
      value: this,
      leading: Text(directory ? '▸' : '·'),
      children: [for (final child in children) child.toTreeNode()],
    );
  }
}

/// File-system specialization of [TreeView].
class FileTree extends StatelessWidget {
  const FileTree({
    super.key,
    required this.roots,
    this.controller,
    this.onOpen,
    this.autofocus = false,
  });

  final List<FileTreeNode> roots;
  final TreeViewController<FileTreeNode>? controller;
  final ValueChanged<FileTreeNode>? onOpen;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TreeView<FileTreeNode>(
      nodes: [for (final root in roots) root.toTreeNode()],
      controller: controller,
      autofocus: autofocus,
      onActivated: (node) {
        final value = node.value;
        if (value != null && !value.directory) onOpen?.call(value);
      },
      itemBuilder: (context, entry) {
        final value = entry.node.value;
        return Row(
          children: [
            Text(value?.directory == true ? '▸ ' : '  '),
            Expanded(
              child: TerminalText.safe(
                entry.node.label,
                style: TextStyle(
                  color: value?.modified == true ? Colors.yellow : null,
                  fontWeight: entry.selected
                      ? FontWeight.bold
                      : FontWeight.normal,
                ),
                softWrap: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (value?.modified == true)
              const Text('M', style: TextStyle(color: Colors.yellow)),
          ],
        );
      },
    );
  }
}

/// Selectable, virtualized source-code viewer.
class CodeView extends StatelessWidget {
  const CodeView({
    super.key,
    required this.code,
    this.language,
    this.showLineNumbers = true,
    this.highlightedLines = const {},
    this.controller,
  });

  final String code;
  final String? language;
  final bool showLineNumbers;
  final Set<int> highlightedLines;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final sanitized = TerminalTextSanitizer.sanitize(code);
    final lines = sanitized.split('\n');
    final numberWidth = lines.length.toString().length + 1;
    return SelectionArea(
      child: VirtualListView.builder(
        controller: controller,
        itemCount: lines.length,
        itemExtent: 1,
        itemBuilder: (context, index) {
          final lineNumber = index + 1;
          Widget row = Row(
            children: [
              if (showLineNumbers)
                SizedBox(
                  width: numberWidth.toDouble(),
                  child: Text(
                    lineNumber.toString().padLeft(numberWidth - 1),
                    style: const TextStyle(color: Colors.grey),
                    softWrap: false,
                  ),
                ),
              if (showLineNumbers) const Text('│ '),
              Expanded(
                child: TerminalText.safe(
                  lines[index],
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
          if (highlightedLines.contains(lineNumber)) {
            row = Container(color: const Color.fromRGB(48, 44, 28), child: row);
          }
          return row;
        },
      ),
    );
  }
}

/// Framed PTY terminal surface.
class TerminalView extends StatelessWidget {
  const TerminalView({
    super.key,
    required this.controller,
    this.focused = false,
    this.title = 'Terminal',
    this.maxLines = 10000,
    this.autoStart = true,
    this.onKeyEvent,
  });

  final PtyController controller;
  final bool focused;
  final String title;
  final int maxLines;
  final bool autoStart;
  final bool Function(KeyboardEvent)? onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: BoxBorder.all(
          color: focused ? Colors.cyan : TuiTheme.of(context).outline,
          style: BoxBorderStyle.rounded,
        ),
        title: BorderTitle(text: ' ${TerminalTextSanitizer.sanitize(title)} '),
      ),
      padding: const EdgeInsets.all(1),
      child: TerminalXterm(
        controller: controller,
        focused: focused,
        maxLines: maxLines,
        autoStart: autoStart,
        onKeyEvent: onKeyEvent,
      ),
    );
  }
}

enum AgentState {
  idle,
  thinking,
  runningTool,
  waitingApproval,
  succeeded,
  failed,
}

/// Compact live state for an AI agent.
class AgentStatus extends StatelessWidget {
  const AgentStatus({
    super.key,
    required this.name,
    required this.state,
    this.detail,
    this.progress,
    this.onStop,
  });

  final String name;
  final AgentState state;
  final String? detail;
  final double? progress;
  final VoidCallback? onStop;

  Color _color() {
    switch (state) {
      case AgentState.idle:
        return Colors.grey;
      case AgentState.thinking:
      case AgentState.runningTool:
        return Colors.cyan;
      case AgentState.waitingApproval:
        return Colors.yellow;
      case AgentState.succeeded:
        return Colors.green;
      case AgentState.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: BoxBorder.all(color: _color())),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('● ', style: TextStyle(color: _color())),
              Expanded(
                child: TerminalText.safe(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  softWrap: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TerminalText.safe(
                state.name,
                style: TextStyle(color: _color()),
                softWrap: false,
              ),
              if (onStop != null) ...[
                const SizedBox(width: 1),
                GestureDetector(onTap: onStop, child: const Text('■')),
              ],
            ],
          ),
          if (detail != null)
            TerminalText.safe(
              detail!,
              style: const TextStyle(color: Colors.grey),
              softWrap: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          if (progress != null)
            ProgressBar(
              value: progress!.clamp(0, 1),
              minHeight: 1,
              valueColor: _color(),
            ),
        ],
      ),
    );
  }
}

/// Displays used context against the model context window.
class ContextMeter extends StatelessWidget {
  const ContextMeter({
    super.key,
    required this.usedTokens,
    required this.maxTokens,
    this.label = 'Context',
  });

  final int usedTokens;
  final int maxTokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    final value = maxTokens <= 0 ? 0.0 : usedTokens / maxTokens;
    return ProgressBar(
      value: value.clamp(0.0, 1.0),
      label: '$label $usedTokens / $maxTokens',
      showPercentage: true,
      valueColor: value >= 0.9
          ? Colors.red
          : value >= 0.75
          ? Colors.yellow
          : Colors.cyan,
    );
  }
}

/// Shows prompt/completion token usage.
class TokenUsageBar extends StatelessWidget {
  const TokenUsageBar({
    super.key,
    required this.promptTokens,
    required this.completionTokens,
    this.cachedTokens = 0,
    this.maxTokens,
  });

  final int promptTokens;
  final int completionTokens;
  final int cachedTokens;
  final int? maxTokens;

  @override
  Widget build(BuildContext context) {
    final total = promptTokens + completionTokens;
    final limit = maxTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('Prompt $promptTokens')),
            Expanded(child: Text('Completion $completionTokens')),
            Expanded(child: Text('Cached $cachedTokens')),
          ],
        ),
        if (limit != null)
          ProgressBar(
            value: limit <= 0 ? 0 : (total / limit).clamp(0.0, 1.0),
            label: '$total / $limit',
            showPercentage: true,
          ),
      ],
    );
  }
}

enum TaskStatus { pending, running, blocked, succeeded, failed, cancelled }

class TaskNode {
  const TaskNode({
    required this.id,
    required this.title,
    this.status = TaskStatus.pending,
    this.detail,
    this.dependencies = const [],
    this.progress,
  });

  final Object id;
  final String title;
  final TaskStatus status;
  final String? detail;
  final List<Object> dependencies;
  final double? progress;
}

/// Virtualized task/dependency view for multi-agent workflows.
class TaskGraph extends StatelessWidget {
  const TaskGraph({super.key, required this.tasks, this.onSelected});

  final List<TaskNode> tasks;
  final ValueChanged<TaskNode>? onSelected;

  String _marker(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
        return '○';
      case TaskStatus.running:
        return '◐';
      case TaskStatus.blocked:
        return '◇';
      case TaskStatus.succeeded:
        return '●';
      case TaskStatus.failed:
        return '✗';
      case TaskStatus.cancelled:
        return '■';
    }
  }

  Color _color(TaskStatus status) {
    switch (status) {
      case TaskStatus.pending:
      case TaskStatus.blocked:
      case TaskStatus.cancelled:
        return Colors.grey;
      case TaskStatus.running:
        return Colors.cyan;
      case TaskStatus.succeeded:
        return Colors.green;
      case TaskStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VirtualListView.builder(
      itemCount: tasks.length,
      itemExtent: 3,
      itemBuilder: (context, index) {
        final task = tasks[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onSelected == null ? null : () => onSelected!(task),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    '${_marker(task.status)} ',
                    style: TextStyle(color: _color(task.status)),
                  ),
                  Expanded(
                    child: TerminalText.safe(
                      task.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TerminalText.safe(
                    task.status.name,
                    style: TextStyle(color: _color(task.status)),
                    softWrap: false,
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TerminalText.safe(
                      task.detail ??
                          (task.dependencies.isEmpty
                              ? ''
                              : 'depends on ${task.dependencies.join(', ')}'),
                      style: const TextStyle(color: Colors.grey),
                      softWrap: false,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (task.progress != null)
                    SizedBox(
                      width: 20,
                      child: ProgressBar(
                        value: task.progress!.clamp(0.0, 1.0),
                        valueColor: _color(task.status),
                      ),
                    ),
                ],
              ),
              const Divider(),
            ],
          ),
        );
      },
    );
  }
}

/// Safe selectable Markdown surface.
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    this.styleSheet,
    this.selectable = true,
    this.maxLines,
  });

  final String data;
  final MarkdownStyleSheet? styleSheet;
  final bool selectable;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final markdown = MarkdownText(
      data,
      styleSheet: styleSheet,
      maxLines: maxLines,
    );
    return selectable ? SelectionArea(child: markdown) : markdown;
  }
}
