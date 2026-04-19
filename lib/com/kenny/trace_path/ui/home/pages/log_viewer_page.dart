import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/error_logger_service.dart';

/// 日志查看页面
class LogViewerPage extends StatefulWidget {
  const LogViewerPage({super.key});

  @override
  State<LogViewerPage> createState() => _LogViewerPageState();
}

class _LogViewerPageState extends State<LogViewerPage> with WidgetsBindingObserver {
  final ErrorLoggerService _errorLogger = ErrorLoggerService();
  final ScrollController _scrollController = ScrollController();
  final _spKeySelectedTags = 'log_viewer_selected_tags';

  List<LogLine> _allLogs = []; // 所有日志（用于统计各tag数量）
  List<LogLine> _filteredLogs = []; // 过滤后的日志（用于显示）
  Map<String, int> _tagCounts = {}; // 各tag的日志数量
  Set<String> _availableTags = {};
  Set<String> _selectedTags = {};
  bool _showAll = true; // true=显示全部，false=按tag过滤
  bool _isLoading = true;
  bool _tagsInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTagsAndLoadLogs();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSelectedTags();
    }
  }

  Future<void> _initTagsAndLoadLogs() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      await _errorLogger.init();

      // 首次进入时扫描Tag
      if (!_tagsInitialized) {
        final allTags = await _errorLogger.getUniqueTags();
        _availableTags = allTags;
        _selectedTags = await _loadSelectedTags();
        _tagsInitialized = true;
      }

      // 加载所有日志用于统计
      _allLogs = await _errorLogger.readLogsWithFilter(null);
      _computeTagCounts();

      // 根据当前筛选状态过滤
      _applyFilter();

      if (!mounted) return;

      setState(() => _isLoading = false);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _computeTagCounts() {
    final counts = <String, int>{};
    for (final log in _allLogs) {
      if (log.tag != null) {
        counts[log.tag!] = (counts[log.tag!] ?? 0) + 1;
      }
    }
    _tagCounts = counts;
  }

  void _applyFilter() {
    if (!_showAll && _selectedTags.isNotEmpty) {
      // 非 showAll 模式且有选中 tag 时才过滤
      _filteredLogs = _allLogs.where((log) {
        return log.tag != null && _selectedTags.contains(log.tag);
      }).toList();
    } else {
      // showAll 模式或无选中 tag：显示全部
      _filteredLogs = List.from(_allLogs);
    }
  }

  Future<Set<String>> _loadSelectedTags() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final list = sp.getStringList(_spKeySelectedTags);
      if (list != null) {
        return list.toSet();
      }
    } catch (_) {}
    return {};
  }

  Future<void> _saveSelectedTags() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_spKeySelectedTags, _selectedTags.toList());
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTagChanged(String tag, bool selected) {
    final newTags = Set<String>.from(_selectedTags);
    if (selected) {
      newTags.add(tag);
    } else {
      newTags.remove(tag);
    }
    setState(() {
      _selectedTags = newTags;
      // 如果有选中tag则退出showAll模式
      if (newTags.isNotEmpty) {
        _showAll = false;
      }
    });
    _saveSelectedTags();
    _applyFilter();
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  void _toggleAll() {
    // All chip 点击切换：
    // - 当前 showAll 模式 → 进入过滤模式，选中所有 tag
    // - 当前过滤模式 → 退出过滤，回到 showAll 模式
    setState(() {
      if (_showAll) {
        _showAll = false;
        _selectedTags = {..._availableTags};
      } else {
        _showAll = true;
        _selectedTags = {};
      }
    });
    _saveSelectedTags();
    _applyFilter();
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  Future<void> _refreshFilteredLogs() async {
    _allLogs = await _errorLogger.readLogsWithFilter(null);
    _computeTagCounts();
    _applyFilter();
    if (mounted) {
      setState(() {});
      _scrollToBottom();
    }
  }

  Future<void> _loadLogs() async {
    await _refreshFilteredLogs();
  }

  Future<void> _copyAllLogs() async {
    if (_filteredLogs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志为空')),
      );
      return;
    }

    final buffer = StringBuffer();
    String? currentFile;
    for (final line in _filteredLogs) {
      if (line.fileName != currentFile) {
        currentFile = line.fileName;
        buffer.writeln('=== $currentFile ===');
      }
      buffer.writeln(line.content);
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('日志已复制到剪贴板')),
      );
    }
  }

  Future<void> _clearCurrentLog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要清空当前日志文件吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _errorLogger.clearCurrentLogs();
      await _loadLogs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('日志已清空')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('日志'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyAllLogs,
            tooltip: '复制全部',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearCurrentLog,
            tooltip: '清空当前',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  List<Widget> _buildTagChips() {
    final sortedTags = _availableTags.toList()..sort();
    return sortedTags.map((tag) {
      final count = _tagCounts[tag] ?? 0;
      // showAll模式下全部为selected；否则按_selectedTags判断
      final isSelected = _showAll || _selectedTags.contains(tag);
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: FilterChip(
          label: Text('$tag ($count)', style: const TextStyle(fontSize: 11)),
          selected: isSelected,
          onSelected: (selected) => _onTagChanged(tag, selected),
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }).toList();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('加载失败: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLogs,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Row 1: All chip + tag chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              FilterChip(
                label: const Text('All', style: TextStyle(fontSize: 11)),
                selected: _showAll,
                onSelected: (_) => _toggleAll(),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              ..._buildTagChips(),
            ],
          ),
        ),
        // Row 2: log count left, tag filter count right
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.grey[200],
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                '共 ${_filteredLogs.length} 行日志',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              Text(
                'Tag筛选: (${_selectedTags.length}/${_availableTags.length})',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
        // Row 3: log content or empty state
        Expanded(
          child: _filteredLogs.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.article_outlined, size: 48, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('暂无日志', style: TextStyle(fontSize: 14, color: Colors.grey)),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    _filteredLogs.map((l) => l.content).join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
        ),
      ],
    );
  }
}
