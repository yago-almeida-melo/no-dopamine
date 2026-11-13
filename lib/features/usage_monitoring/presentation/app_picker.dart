import 'package:flutter/material.dart';

import '../domain/usage_models.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({required this.app, super.key, this.size = 40});
  final TrackedApp app;
  final double size;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * .26),
        child: app.icon != null
            ? Image.memory(app.icon!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback())
            : _fallback(),
      );

  Widget _fallback() => Container(
        width: size,
        height: size,
        color: const Color(0xFFE2EDE6),
        alignment: Alignment.center,
        child: Text(
            app.name.isEmpty ? '?' : app.name.substring(0, 1).toUpperCase(),
            style:
                TextStyle(fontWeight: FontWeight.bold, fontSize: size * .45)),
      );
}

class AppPicker extends StatefulWidget {
  const AppPicker(
      {required this.apps,
      required this.selected,
      required this.onSave,
      super.key});
  final List<TrackedApp> apps;
  final Set<String> selected;
  final Future<void> Function(Set<String>) onSave;

  @override
  State<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<AppPicker> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';
  bool _all = false;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(_selected);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error = 'Não foi possível salvar. Tente novamente.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.apps
        .where(
          (app) =>
              (_all || app.isSocial || _selected.contains(app.id)) &&
              '${app.name} ${app.id}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList()
      ..sort((a, b) {
        if (a.isSocial != b.isSocial) return a.isSocial ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return SafeArea(
      child: Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 16, 8),
              child: Row(children: [
                const Expanded(
                    child: Text('Escolha seus aplicativos',
                        style: TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w700))),
                IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close)),
              ]),
            ),
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text('Selecione as redes que você quer acompanhar. '
                    'Você pode mudar a seleção quando quiser.')),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              child: TextField(
                enabled: !_saving,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Buscar aplicativo',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16))),
                  isDense: true,
                ),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: const Text('Mostrar todos os aplicativos'),
              subtitle: const Text('Inclui apps além das redes sugeridas'),
              value: _all,
              onChanged:
                  _saving ? null : (value) => setState(() => _all = value),
            ),
            const Divider(height: 1),
            Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                                _all
                                    ? 'Nenhum aplicativo encontrado.'
                                    : 'Nenhuma rede encontrada. Ative “Mostrar todos os aplicativos” para ver outros apps.',
                                textAlign: TextAlign.center)))
                    : ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final app = visible[index];
                          return CheckboxListTile(
                            key: ValueKey('app-${app.id}'),
                            secondary: AppAvatar(app: app),
                            title: Text(app.name),
                            subtitle: Text(app.id,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            value: _selected.contains(app.id),
                            onChanged: _saving
                                ? null
                                : (value) => setState(() {
                                      if (value == true) {
                                        _selected.add(app.id);
                                      } else {
                                        _selected.remove(app.id);
                                      }
                                    }),
                          );
                        },
                      )),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            Padding(
                padding: const EdgeInsets.all(20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                      onPressed: _saving ? null : _save,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_saving
                              ? 'Salvando…'
                              : 'Salvar seleção (${_selected.length})'))),
                )),
          ]),
        ),
      ),
    );
  }
}
