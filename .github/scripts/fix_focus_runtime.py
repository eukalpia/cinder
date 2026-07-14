#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[2] / 'lib/src/components/focus.dart'
text = path.read_text(encoding='utf-8')
old = """  void _scheduleAutofocus() {
    if (!widget.autofocus || _autofocusScheduled) return;
    _autofocusScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _node.attached && !_node.hasFocus) {
        _node.requestFocus();
      }
    });
  }
"""
new = """  void _scheduleAutofocus() {
    if (!widget.autofocus || _autofocusScheduled) return;
    _autofocusScheduled = true;

    // The node is already attached when didChangeDependencies reaches here.
    // Requesting focus synchronously makes the first key event deterministic
    // and avoids requiring an extra frame after pumpWidget/runApp.
    if (_node.attached && !_node.hasFocus) {
      _node.requestFocus();
    }
  }
"""
if old in text:
    path.write_text(text.replace(old, new, 1), encoding='utf-8')
elif new not in text:
    raise RuntimeError('Expected autofocus implementation not found')
