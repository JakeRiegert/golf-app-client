import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'course_model.dart';
import 'dialog_utils.dart';

// The Course page: a full screen (not a dialog) for entering everything about a course once, at round setup.
//   - the name, and any number of tees (tips, blue, white...), each with its own men's and women's rating and slope;
//   - one row per hole: par, men's and women's hole ranking (HCP), and the selected tee's yards.
// Returns the course in the shape createRound / updateRound take (see course_model.dart), or nothing if cancelled.
// Tap a column heading to paste a whole column from a scorecard (18 numbers separated by spaces or commas).

class CoursePage extends StatefulWidget {
  const CoursePage({super.key, this.initial});

  // The round's current course as stored, or null to start empty.
  final Map? initial;

  @override
  State<CoursePage> createState() => _CoursePageState();
}

class _CoursePageState extends State<CoursePage> {
  late final CourseDraft _draft = CourseDraft.fromStored(widget.initial);
  late final _name = TextEditingController(text: _draft.name);
  int _tee = 0;
  // Bumped when a whole column is pasted, so the cells rebuild with the new numbers.
  int _generation = 0;
  List<String> _problems = const [];
  bool _showWomenPar = false;

  @override
  void initState() {
    super.initState();
    _showWomenPar = _draft.womenParDiffers;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  TeeDraft? get _selectedTee => _draft.tees.isEmpty ? null : _draft.tees[_tee.clamp(0, _draft.tees.length - 1)];

  void _save() {
    _draft.name = _name.text;
    final problems = _draft.problems();
    if (problems.isNotEmpty) {
      setState(() => _problems = problems);
      return;
    }
    popDialog(context, _draft.toPayload());
  }

  Future<void> _addTee() async {
    final name = await _askText('Add a tee', 'Tee name', 'Blue, Tips, White, Red...');
    if (name == null || name.trim().isEmpty) return;
    setState(() {
      _draft.tees.add(TeeDraft(id: _draft.nextTeeId(), name: name.trim()));
      _tee = _draft.tees.length - 1;
    });
  }

  Future<void> _removeTee() async {
    final tee = _selectedTee;
    if (tee == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${tee.name}?'),
        content: const Text('Its yardage and ratings are removed. Players who picked it will pick again.'),
        actions: [
          TextButton(onPressed: () => popDialog(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => popDialog(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      _draft.tees.remove(tee);
      _tee = 0;
    });
  }

  Future<String?> _askText(String title, String label, String hint) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (v) => popDialog(context, v),
        ),
        actions: [
          TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => popDialog(context, controller.text), child: const Text('Add')),
        ],
      ),
    );
  }

  // Paste a whole column ("4 5 3 4 ...") from a scorecard into [target].
  Future<void> _pasteColumn(String title, List<int?> target, {bool allowEmpty = false}) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Paste $title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            hintText: '18 numbers, hole 1 first, separated by spaces',
            helperText: 'Copy a row from the scorecard and paste it here.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => popDialog(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => popDialog(context, controller.text), child: const Text('Fill column')),
        ],
      ),
    );
    if (text == null || !mounted) return;
    final parts = text.split(RegExp(r'[\s,]+')).where((p) => p.isNotEmpty).toList();
    final values = [for (final p in parts) int.tryParse(p)];
    if (parts.isEmpty && allowEmpty) return;
    if (parts.length != holeCount || values.any((v) => v == null)) {
      showErrorMessage(context, 'Paste exactly 18 whole numbers (you pasted ${parts.length}).');
      return;
    }
    setState(() {
      for (var i = 0; i < holeCount; i++) {
        target[i] = values[i];
      }
      _generation++;
    });
  }

  InputDecoration _cell() => const InputDecoration(
    isDense: true,
    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
    border: OutlineInputBorder(),
    counterText: '',
  );

  Widget _numberCell(List<int?> column, int hole, String key, {int maxLength = 3, bool marked = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: TextFormField(
        key: ValueKey('$key-$hole-$_generation-${_selectedTee?.id}'),
        initialValue: column[hole - 1]?.toString() ?? '',
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        textAlign: TextAlign.center,
        maxLength: maxLength,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: _cell().copyWith(
          enabledBorder: marked
              ? OutlineInputBorder(borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2))
              : null,
        ),
        onChanged: (v) {
          column[hole - 1] = int.tryParse(v);
          // Marking duplicates and the par total need a redraw, but not a full rebuild of the cell being typed in.
          setState(() {});
        },
      ),
    );
  }

  Widget _heading(String text, {VoidCallback? onTap, int flex = 1}) {
    final style = Theme.of(context).textTheme.labelMedium;
    final child = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(text, textAlign: TextAlign.center, style: style?.copyWith(decoration: onTap == null ? null : TextDecoration.underline)),
    );
    return Expanded(flex: flex, child: onTap == null ? child : InkWell(onTap: onTap, child: child));
  }

  Widget _teeEditor(TeeDraft tee) {
    Widget field(String label, String initial, void Function(String) onChanged, {bool decimal = false, String key = ''}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextFormField(
            key: ValueKey('tee-${tee.id}-$key-$_generation'),
            initialValue: initial,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
            onChanged: (v) {
              onChanged(v);
              setState(() {});
            },
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TextFormField(
            key: ValueKey('tee-name-${tee.id}'),
            initialValue: tee.name,
            maxLength: 50,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Tee name', isDense: true, border: OutlineInputBorder(), counterText: ''),
            onChanged: (v) {
              tee.name = v;
              setState(() {});
            },
          ),
        ),
        Text("Men's rating and slope (optional)", style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            field('Rating', tee.menRating?.toString() ?? '', (v) => tee.menRating = double.tryParse(v), decimal: true, key: 'mr'),
            field('Slope', tee.menSlope?.toString() ?? '', (v) => tee.menSlope = int.tryParse(v), key: 'ms'),
          ],
        ),
        const SizedBox(height: 12),
        Text("Women's rating and slope (optional)", style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Row(
          children: [
            field('Rating', tee.womenRating?.toString() ?? '', (v) => tee.womenRating = double.tryParse(v), decimal: true, key: 'wr'),
            field('Slope', tee.womenSlope?.toString() ?? '', (v) => tee.womenSlope = int.tryParse(v), key: 'ws'),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tee = _selectedTee;
    final dupMen = CourseDraft.duplicateRankingHoles(_draft.strokeIndex);
    final dupWomen = CourseDraft.duplicateRankingHoles(_draft.strokeIndexWomen);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: () => popDialog(context)),
        title: const Text('Course'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_problems.isNotEmpty)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [for (final p in _problems) Text(p, style: TextStyle(color: theme.colorScheme.onErrorContainer))],
                    ),
                  ),
                ),
              TextField(
                controller: _name,
                maxLength: 100,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Course name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Text('Tees', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'One tee for every set of markers players might use. Each has its own yardage and ratings. Players pick theirs when they check in.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < _draft.tees.length; i++)
                    ChoiceChip(
                      label: Text(_draft.tees[i].name.isEmpty ? 'Tee ${i + 1}' : _draft.tees[i].name),
                      selected: i == _tee.clamp(0, _draft.tees.length - 1),
                      onSelected: (_) => setState(() => _tee = i),
                    ),
                  ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add a tee'), onPressed: _addTee),
                ],
              ),
              if (tee != null) ...[
                const SizedBox(height: 12),
                _teeEditor(tee),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _removeTee,
                    icon: const Icon(Icons.delete_outline),
                    label: Text('Remove ${tee.name.isEmpty ? 'this tee' : tee.name}'),
                  ),
                ),
              ],
              const Divider(height: 32),
              Text('Holes', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                "Par and HCP (the hole's difficulty rank, 1 to 18) for every hole. Leave the women's HCP empty if it is the same as the men's. "
                'Tap a heading to paste a whole column from the scorecard.',
                style: theme.textTheme.bodySmall,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Women's par differs on some holes"),
                value: _showWomenPar,
                onChanged: (v) => setState(() {
                  _showWomenPar = v;
                  if (!v) {
                    for (var i = 0; i < holeCount; i++) {
                      _draft.parWomen[i] = null;
                    }
                    _generation++;
                  }
                }),
              ),
              Row(
                children: [
                  const SizedBox(width: 28),
                  _heading('Par', onTap: () => _pasteColumn('pars', _draft.par)),
                  if (_showWomenPar) _heading('Par W', onTap: () => _pasteColumn("women's pars", _draft.parWomen)),
                  _heading('HCP', onTap: () => _pasteColumn("men's HCP", _draft.strokeIndex)),
                  _heading('HCP W', onTap: () => _pasteColumn("women's HCP", _draft.strokeIndexWomen)),
                  _heading(tee == null ? 'Yards' : '${tee.name.isEmpty ? 'Tee' : tee.name} yds', onTap: tee == null ? null : () => _pasteColumn('${tee.name} yards', tee.yards)),
                ],
              ),
              for (var hole = 1; hole <= holeCount; hole++)
                Row(
                  children: [
                    SizedBox(width: 28, child: Text('$hole', textAlign: TextAlign.center)),
                    Expanded(child: _numberCell(_draft.par, hole, 'par', maxLength: 1)),
                    if (_showWomenPar) Expanded(child: _numberCell(_draft.parWomen, hole, 'parw', maxLength: 1)),
                    Expanded(child: _numberCell(_draft.strokeIndex, hole, 'si', maxLength: 2, marked: dupMen.contains(hole))),
                    Expanded(child: _numberCell(_draft.strokeIndexWomen, hole, 'siw', maxLength: 2, marked: dupWomen.contains(hole))),
                    Expanded(
                      child: tee == null
                          ? const Padding(padding: EdgeInsets.all(2), child: Text('add a tee', textAlign: TextAlign.center, style: TextStyle(fontSize: 11)))
                          : _numberCell(tee.yards, hole, 'yd', maxLength: 3),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                'Par ${_draft.totalPar}'
                '${tee == null ? '' : ' · ${tee.name.isEmpty ? 'this tee' : tee.name}: ${tee.yardsEntered} of 18 yardages, ${tee.totalYards} yds total'}',
                style: theme.textTheme.bodyMedium,
              ),
              if (dupMen.isNotEmpty || dupWomen.isNotEmpty)
                Text('Highlighted HCP numbers are used more than once.', style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _save, child: const Text('Save course')),
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 24 : 0),
            ],
          ),
        ),
      ),
    );
  }
}
