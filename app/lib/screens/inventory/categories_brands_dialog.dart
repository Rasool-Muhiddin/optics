import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/strings/app_strings.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../models/catalog.dart';
import '../../widgets/common.dart';
import 'inventory_providers.dart';

/// Owner: add / rename / (de)activate categories (tree) and brands.
class CategoriesBrandsDialog extends ConsumerWidget {
  const CategoriesBrandsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: const Text(AppStrings.categoriesAndBrands),
      content: SizedBox(
        width: 560,
        height: 460,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                tabs: [
                  Tab(text: AppStrings.categories),
                  Tab(text: AppStrings.brands),
                ],
              ),
              Expanded(child: TabBarView(children: [_CategoriesTab(), _BrandsTab()])),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.close),
        ),
      ],
    );
  }
}

class _CategoriesTab extends ConsumerWidget {
  const _CategoriesTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, List<Category> all, [Category? c]) async {
    final result = await showDialog<({String name, int? parent, bool active})>(
      context: context,
      builder: (_) => _NameDialog(
        initialName: c?.name ?? '',
        parents: [
          for (final p in all)
            if (p.id != c?.id) p,
        ],
        initialParent: c?.parentId,
        initialActive: c?.isActive ?? true,
        showParent: true,
      ),
    );
    if (result == null) return;
    try {
      await ref.read(catalogRepositoryProvider).saveCategory(c?.id, {
        'name': result.name,
        'parent': result.parent,
        'is_active': result.active,
      });
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(categoriesProvider),
      onRetry: () => ref.invalidate(categoriesProvider),
      builder: (categories) {
        final byId = {for (final c in categories) c.id: c};
        String path(Category c) {
          final parts = <String>[c.name];
          var parent = c.parentId == null ? null : byId[c.parentId];
          var guard = 0;
          while (parent != null && guard++ < 10) {
            parts.insert(0, parent.name);
            parent = parent.parentId == null ? null : byId[parent.parentId];
          }
          return parts.join(' › ');
        }

        final sorted = [...categories]..sort((a, b) => path(a).compareTo(path(b)));
        return Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('add-category'),
                icon: const Icon(Icons.add),
                label: const Text(AppStrings.add),
                onPressed: () => _edit(context, ref, categories),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in sorted)
                    ListTile(
                      dense: true,
                      title: Text(path(c)),
                      subtitle: c.isActive ? null : const Text(AppStrings.inactive),
                      trailing: const Icon(Icons.edit_outlined, size: 18),
                      onTap: () => _edit(context, ref, categories, c),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BrandsTab extends ConsumerWidget {
  const _BrandsTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, [Brand? b]) async {
    final result = await showDialog<({String name, int? parent, bool active})>(
      context: context,
      builder: (_) => _NameDialog(initialName: b?.name ?? '', initialActive: b?.isActive ?? true),
    );
    if (result == null) return;
    try {
      await ref.read(catalogRepositoryProvider).saveBrand(b?.id, {
        'name': result.name,
        'is_active': result.active,
      });
      ref.invalidate(brandsProvider);
    } catch (e) {
      if (context.mounted) showErrorSnack(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView(
      value: ref.watch(brandsProvider),
      onRetry: () => ref.invalidate(brandsProvider),
      builder: (brands) => Column(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              key: const Key('add-brand'),
              icon: const Icon(Icons.add),
              label: const Text(AppStrings.add),
              onPressed: () => _edit(context, ref),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final b in brands)
                  ListTile(
                    dense: true,
                    title: Text(b.name),
                    subtitle: b.isActive ? null : const Text(AppStrings.inactive),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => _edit(context, ref, b),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initialName,
    this.parents = const [],
    this.initialParent,
    this.initialActive = true,
    this.showParent = false,
  });

  final String initialName;
  final List<Category> parents;
  final int? initialParent;
  final bool initialActive;
  final bool showParent;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initialName);
  late int? _parent = widget.initialParent;
  late bool _active = widget.initialActive;
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormDialog(
      title: widget.initialName.isEmpty ? AppStrings.add : AppStrings.edit,
      width: 380,
      onSave: () {
        if (!_formKey.currentState!.validate()) return;
        Navigator.of(context).pop((name: _name.text.trim(), parent: _parent, active: _active));
      },
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('name-field'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: AppStrings.name),
              validator: Inputs.requiredText,
            ),
            if (widget.showParent) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                isExpanded: true,
                initialValue: widget.parents.any((p) => p.id == _parent) ? _parent : null,
                decoration: const InputDecoration(labelText: AppStrings.parentCategory),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text(AppStrings.none)),
                  for (final p in widget.parents)
                    DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _parent = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.active),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          ],
        ),
      ),
    );
  }
}
