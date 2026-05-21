import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/debug_config.dart';
import '../../models/chat_message.dart';
import '../../services/api_service.dart';
import '../../services/location_service.dart';
import '../../tools/python_command.dart';
import '../../tools/python_runner.dart';
import '../../tools/tool_result.dart';

// ── Test case definition ──────────────────────────────────────────────────────

enum _ResultKind { text, image, html }

class _TestCase {
  const _TestCase({
    required this.id,
    required this.name,
    required this.description,
    this.directCode,
    this.e2ePrompt,
    required this.expectedKind,
    this.mustContain = const [],
  }) : assert(directCode != null || e2ePrompt != null,
            'Must supply directCode or e2ePrompt');

  final String id;
  final String name;
  final String description;

  /// Pre-written Python injected straight into Pyodide (deterministic).
  final String? directCode;

  /// Natural-language prompt routed through the LLM then Pyodide (E2E).
  final String? e2ePrompt;

  final _ResultKind expectedKind;

  /// Strings that must all appear in the result text / HTML.
  final List<String> mustContain;

  bool get isE2E => e2ePrompt != null;
}

// ── Test result (mutable state) ───────────────────────────────────────────────

enum _Status { pending, running, passed, failed }

class _TestResult {
  _TestResult(this.testCase);

  final _TestCase testCase;
  _Status status = _Status.pending;
  String detail = '';
  Duration? elapsed;
}

// ── Test case registry ────────────────────────────────────────────────────────
//
// Direct tests: pre-written Python snippets — fast, deterministic, verify that
//   Pyodide, each library, and the GPS preamble all work correctly.
//
// E2E smoke tests: natural-language prompts through the LLM → Pyodide pipeline,
//   verifying prompt quality and end-to-end code generation.

const _cases = <_TestCase>[
  // ── Direct: NumPy ─────────────────────────────────────────────────────────
  _TestCase(
    id: 'numpy_sqrt_sum',
    name: 'NumPy — sqrt sum',
    description: 'sqrt([1,4,9,16,25]).sum() == 15.0',
    expectedKind: _ResultKind.text,
    mustContain: ['15'],
    directCode: '''
import numpy as np
arr = np.array([1, 4, 9, 16, 25])
result = str(round(float(np.sqrt(arr).sum()), 4))
''',
  ),

  // ── Direct: SciPy ────────────────────────────────────────────────────────
  _TestCase(
    id: 'scipy_norm_pdf',
    name: 'SciPy — normal PDF',
    description: 'stats.norm.pdf(0) ≈ 0.3989',
    expectedKind: _ResultKind.text,
    mustContain: ['0.3989'],
    directCode: '''
from scipy import stats
result = str(round(float(stats.norm.pdf(0)), 4))
''',
  ),

  // ── Direct: Pandas ────────────────────────────────────────────────────────
  _TestCase(
    id: 'pandas_mean',
    name: 'Pandas — DataFrame mean',
    description: 'Mean of [1,2,3,4,5] == 3.0',
    expectedKind: _ResultKind.text,
    mustContain: ['3.0'],
    directCode: '''
import pandas as pd
df = pd.DataFrame({'values': [1, 2, 3, 4, 5]})
result = str(float(df['values'].mean()))
''',
  ),

  // ── Direct: Matplotlib ───────────────────────────────────────────────────
  _TestCase(
    id: 'matplotlib_sine',
    name: 'Matplotlib — sine wave PNG',
    description: 'sin(x) 0→2π → PNG image result',
    expectedKind: _ResultKind.image,
    directCode: '''
import numpy as np
import matplotlib.pyplot as plt
x = np.linspace(0, 2 * 3.14159265, 200)
plt.figure(figsize=(6, 3))
plt.plot(x, np.sin(x), color='steelblue')
plt.title('Sine Wave')
plt.xlabel('x')
plt.ylabel('sin(x)')
''',
  ),

  // ── Direct: Plotly Express ───────────────────────────────────────────────
  _TestCase(
    id: 'plotly_express_bar',
    name: 'Plotly Express — bar chart',
    description: 'Bar chart → interactive HTML',
    expectedKind: _ResultKind.html,
    directCode: '''
import plotly.express as px
fig = px.bar(
    x=['Alpha', 'Beta', 'Gamma', 'Delta', 'Epsilon'],
    y=[10, 25, 15, 30, 20],
    title='Test Bar Chart')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
''',
  ),

  // ── Direct: Plotly Graph Objects ─────────────────────────────────────────
  _TestCase(
    id: 'plotly_go_scatter',
    name: 'Plotly GO — scatter chart',
    description: 'Scatter via graph_objects → interactive HTML',
    expectedKind: _ResultKind.html,
    directCode: '''
import plotly.graph_objects as go
fig = go.Figure(go.Scatter(
    x=[1, 2, 3, 4, 5],
    y=[2, 4, 1, 5, 3],
    mode='markers+lines'))
fig.update_layout(title='Test Scatter')
result = fig.to_html(include_plotlyjs='cdn', full_html=True)
''',
  ),

  // ── Direct: Astral sunrise / sunset ──────────────────────────────────────
  _TestCase(
    id: 'astral_sunrise',
    name: 'Astral — sunrise / sunset',
    description: 'Sunrise & sunset at Swisher IA today (uses GPS preamble)',
    expectedKind: _ResultKind.text,
    mustContain: [':'],
    directCode: '''
import datetime
from astral import LocationInfo
from astral.sun import sun

location = LocationInfo(
    name='Swisher', region='IA', timezone='UTC',
    latitude=user_latitude, longitude=user_longitude)
today = datetime.date.today()
s = sun(location.observer, date=today, tzinfo=user_timezone)
result = (
    f"Sunrise: {s['sunrise'].strftime('%I:%M %p')}\\n"
    f"Sunset:  {s['sunset'].strftime('%I:%M %p')}\\n"
    f"Noon:    {s['noon'].strftime('%I:%M %p')}"
)
''',
  ),

  // ── Direct: Astral moon phase ─────────────────────────────────────────────
  _TestCase(
    id: 'astral_moon',
    name: 'Astral — moon phase',
    description: 'Moon phase today as float 0–28 with phase name',
    expectedKind: _ResultKind.text,
    mustContain: ['/28'],
    directCode: '''
import datetime
from astral.moon import phase

today = datetime.date.today()
p = phase(today)
names = ['New Moon', 'Waxing Crescent', 'First Quarter', 'Waxing Gibbous',
         'Full Moon', 'Waning Gibbous', 'Last Quarter', 'Waning Crescent']
idx = int(p / 3.5) % 8
result = f"Moon phase: {p:.1f}/28 — {names[idx]}"
''',
  ),

  // ── Direct: Folium map ────────────────────────────────────────────────────
  _TestCase(
    id: 'folium_map',
    name: 'Folium — interactive map',
    description: 'Map centred on Swisher IA with marker → HTML',
    expectedKind: _ResultKind.html,
    directCode: '''
import folium
m = folium.Map(location=[user_latitude, user_longitude], zoom_start=13)
folium.Marker(
    [user_latitude, user_longitude],
    tooltip='Swisher, IA'
).add_to(m)
result = m.get_root().render()
''',
  ),

  // ── Direct: Shapely ───────────────────────────────────────────────────────
  _TestCase(
    id: 'shapely_area',
    name: 'Shapely — polygon area',
    description: 'Unit square Polygon.area == 1.0',
    expectedKind: _ResultKind.text,
    mustContain: ['1.0'],
    directCode: '''
from shapely.geometry import Polygon
square = Polygon([(0, 0), (1, 0), (1, 1), (0, 1)])
result = str(float(square.area))
''',
  ),

  // ── Direct: Haversine distance (pure math) ────────────────────────────────
  _TestCase(
    id: 'haversine_distance',
    name: 'Haversine — Swisher IA → NYC',
    description: 'GPS distance ≈ 1,440 km using GPS preamble coords',
    expectedKind: _ResultKind.text,
    mustContain: ['km'],
    directCode: '''
import math

def haversine(lat1, lon1, lat2, lon2):
    R = 6371
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * R * math.asin(math.sqrt(a))

dist = haversine(user_latitude, user_longitude, 40.7128, -74.0060)
result = f"Swisher IA → New York City: {dist:.1f} km"
''',
  ),

  // ── Direct: GPS preamble ──────────────────────────────────────────────────
  _TestCase(
    id: 'gps_preamble',
    name: 'GPS — preamble injection',
    description:
        'Verifies user_latitude, user_longitude, user_timezone are set',
    expectedKind: _ResultKind.text,
    mustContain: ['41.'],
    directCode: '''
result = (
    f"lat={user_latitude:.4f}, "
    f"lon={user_longitude:.4f}, "
    f"tz=UTC{user_timezone_offset:+.1f}"
)
''',
  ),

  // ── E2E smoke: basic arithmetic ───────────────────────────────────────────
  _TestCase(
    id: 'e2e_math',
    name: 'E2E — basic arithmetic',
    description: '"12 × 12" → result contains 144',
    expectedKind: _ResultKind.text,
    mustContain: ['144'],
    e2ePrompt: 'what is 12 multiplied by 12',
  ),


  // ── E2E smoke: sine wave plot ─────────────────────────────────────────────
  _TestCase(
    id: 'e2e_sine_plot',
    name: 'E2E — sine wave plot',
    description: '"plot a sine wave" → image or interactive HTML',
    expectedKind: _ResultKind.html,
    e2ePrompt: 'plot a sine wave from 0 to 2 pi',
  ),

  // ── E2E smoke: Plotly chart ───────────────────────────────────────────────
  _TestCase(
    id: 'e2e_bar_chart',
    name: 'E2E — interactive bar chart',
    description: '"bar chart of 10,20,30,40,50" → HTML',
    expectedKind: _ResultKind.html,
    e2ePrompt: 'show an interactive bar chart of the values 10, 20, 30, 40, 50',
  ),

  // ── E2E smoke: moon phase ─────────────────────────────────────────────────
  _TestCase(
    id: 'e2e_moon_phase',
    name: 'E2E — moon phase',
    description: '"moon phase today at my location" → text',
    expectedKind: _ResultKind.text,
    e2ePrompt: 'what is the moon phase today at my location',
  ),
];

// ── Screen ────────────────────────────────────────────────────────────────────

class TestScreen extends StatefulWidget {
  const TestScreen({super.key});

  @override
  State<TestScreen> createState() => _TestScreenState();
}

class _TestScreenState extends State<TestScreen> {
  late final List<_TestResult> _results =
      _cases.map(_TestResult.new).toList();

  bool _running = false;
  int _current = -1;

  // ── Counts ────────────────────────────────────────────────────────────────

  int get _passed => _results.where((r) => r.status == _Status.passed).length;
  int get _failed => _results.where((r) => r.status == _Status.failed).length;

  // ── Run all ───────────────────────────────────────────────────────────────

  Future<void> _runAll() async {
    if (_running) return;
    setState(() {
      _running = true;
      _current = 0;
      for (final r in _results) {
        r.status = _Status.pending;
        r.detail = '';
        r.elapsed = null;
      }
    });

    // Fetch (mock) location once; reused for all tests.
    final location = await LocationService.getLocation();

    for (int i = 0; i < _results.length; i++) {
      if (!mounted) break;
      setState(() => _current = i);
      await _runOne(_results[i], location);
      if (mounted) setState(() {});
    }

    if (mounted) setState(() { _running = false; _current = -1; });
  }

  // ── Run single ────────────────────────────────────────────────────────────

  Future<void> _runOne(_TestResult r, DeviceLocation? location) async {
    r.status = _Status.running;
    if (mounted) setState(() {});

    final sw = Stopwatch()..start();
    try {
      final result = r.testCase.isE2E
          ? await _runE2E(r.testCase, location)
          : await _runDirect(r.testCase, location);
      sw.stop();
      r.elapsed = sw.elapsed;
      _evaluate(r, result);
    } catch (e) {
      sw.stop();
      r.elapsed = sw.elapsed;
      r.status = _Status.failed;
      r.detail = 'Exception: $e';
    }
  }

  // ── Direct execution ──────────────────────────────────────────────────────

  Future<ToolResult> _runDirect(
      _TestCase tc, DeviceLocation? location) async {
    final code = '${location?.pythonPreamble ?? ''}${tc.directCode!}';
    return PythonRunner.instance.execute(code);
  }

  // ── E2E execution ─────────────────────────────────────────────────────────

  Future<ToolResult> _runE2E(_TestCase tc, DeviceLocation? location) async {
    // Phase 1: collect full LLM response (60 s ceiling)
    final buf = StringBuffer();
    final done = Completer<void>();
    ApiService.instance
        .chatCompletionStream(messages: [
          ChatMessage(
            role: MessageRole.user,
            content: PythonCommand.buildToolPrompt(tc.e2ePrompt!),
          ),
        ])
        .listen(
          buf.write,
          onError: (Object e) {
            if (!done.isCompleted) done.completeError(e);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future.timeout(const Duration(seconds: 60));

    // Phase 2: extract + execute
    final code = PythonCommand.extractCode(buf.toString());
    if (code == null || code.trim().isEmpty) {
      return const TextToolResult('E2E: no code extracted from LLM response.');
    }
    final full = '${location?.pythonPreamble ?? ''}$code';
    return PythonRunner.instance.execute(full);
  }

  // ── Evaluate ──────────────────────────────────────────────────────────────

  void _evaluate(_TestResult r, ToolResult result) {
    final String content;
    final _ResultKind actualKind;

    switch (result) {
      case ImageToolResult():
        actualKind = _ResultKind.image;
        content = '[image: ${result.base64DataUrl.length} chars]';
      case HtmlToolResult():
        actualKind = _ResultKind.html;
        content = result.html;
      case TextToolResult():
        actualKind = _ResultKind.text;
        content = result.text;
    }

    // Any error marker → fail immediately
    if (content.startsWith('❌') ||
        content.startsWith('Error') ||
        content.contains('PythonError') ||
        content == 'Cancelled.') {
      r.status = _Status.failed;
      r.detail = content;
      return;
    }

    // Wrong result type → fail
    if (actualKind != r.testCase.expectedKind) {
      r.status = _Status.failed;
      r.detail =
          'Expected ${r.testCase.expectedKind.name}, got ${actualKind.name}.\n'
          '$content';
      return;
    }

    // mustContain checks
    for (final kw in r.testCase.mustContain) {
      if (!content.contains(kw)) {
        r.status = _Status.failed;
        r.detail = 'Missing "$kw" in result.\n$content';
        return;
      }
    }

    r.status = _Status.passed;
    // Store a short preview for the expanded tile
    r.detail = content.length > 200
        ? '${content.substring(0, 200)}…'
        : content;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Python Tool Tests'),
        actions: [
          if (_running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.play_circle_outline),
              tooltip: 'Run all tests',
              onPressed: _runAll,
            ),
        ],
      ),
      body: Column(
        children: [
          _SummaryBar(
            passed: _passed,
            failed: _failed,
            total: _results.length,
            mockGps: kUseMockLocation,
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 16),
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final r = _results[i];
                final isRunning = _running && _current == i;
                return _TestTile(
                  key: ValueKey(r.testCase.id),
                  result: r,
                  isRunning: isRunning,
                  theme: theme,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.passed,
    required this.failed,
    required this.total,
    required this.mockGps,
  });

  final int passed, failed, total;
  final bool mockGps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _Badge('$passed passed', Colors.green),
          const SizedBox(width: 8),
          _Badge('$failed failed', failed > 0 ? Colors.red : Colors.grey),
          const SizedBox(width: 8),
          Text('of $total', style: theme.textTheme.bodySmall),
          const Spacer(),
          if (mockGps)
            Chip(
              label: const Text('Mock GPS'),
              avatar: const Icon(Icons.location_on_outlined, size: 14),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.tertiaryContainer,
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ── Individual test tile ──────────────────────────────────────────────────────

class _TestTile extends StatelessWidget {
  const _TestTile({
    super.key,
    required this.result,
    required this.isRunning,
    required this.theme,
  });

  final _TestResult result;
  final bool isRunning;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final tc = r.testCase;

    final (IconData icon, Color color) = switch (r.status) {
      _Status.pending => (Icons.radio_button_unchecked, Colors.grey),
      _Status.running => (Icons.hourglass_top_outlined, theme.colorScheme.primary),
      _Status.passed  => (Icons.check_circle_outline, Colors.green),
      _Status.failed  => (Icons.cancel_outlined, Colors.red),
    };

    final subtitle = r.elapsed != null
        ? '${tc.description}  ·  ${r.elapsed!.inMilliseconds} ms'
        : tc.description;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: ExpansionTile(
        leading: isRunning
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: theme.colorScheme.primary),
              )
            : Icon(icon, color: color, size: 20),
        title: Row(
          children: [
            if (tc.isE2E)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('E2E',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer)),
              ),
            Expanded(
              child: Text(
                tc.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: r.status == _Status.failed
                      ? theme.colorScheme.error
                      : null,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: [
          if (r.detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  r.detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: r.status == _Status.failed
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
