import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/error_messages.dart';
import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../data/cache/json_cache_dao.dart';
import '../../data/repositories/users_repository.dart';
import '../../models/users.dart';
import '../../services/auth_controller.dart';
import '../../widgets/common.dart';

final labUsersProvider = FutureProvider.autoDispose<List<LabMember>>(
  (ref) => ref.watch(usersRepositoryProvider).users(),
);

final labDevicesProvider = FutureProvider.autoDispose<List<LabDevice>>(
  (ref) => ref.watch(usersRepositoryProvider).devices(),
);

final labUsageProvider = FutureProvider.autoDispose<LabUsage>(
  (ref) => ref.watch(usersRepositoryProvider).usage(),
);

void invalidateUsers(WidgetRef ref) {
  ref.invalidate(labUsersProvider);
  ref.invalidate(labDevicesProvider);
  ref.invalidate(labUsageProvider);
}

/// Owner only: lab users (add staff, edit, permissions, deactivate) and activated devices
/// (rename, revoke), with the plan's user/device limits.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(labUsageProvider).value;
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: AppStrings.usersTitle,
            cacheTables: const [CacheTables.labUsers, CacheTables.devices],
            actions: [
              FilledButton.icon(
                key: const Key('add-user'),
                icon: const Icon(Icons.person_add_alt),
                label: const Text(AppStrings.addUser),
                onPressed: () async {
                  if (usage != null && usage.usersFull) {
                    showSnack(context, AppStrings.limitReachedUsers, error: true);
                    return;
                  }
                  final saved = await showDialog<LabMember>(
                    context: context,
                    builder: (_) => const UserFormDialog(),
                  );
                  if (saved != null) invalidateUsers(ref);
                },
              ),
            ],
          ),
          if (usage != null) _UsageBar(usage: usage),
          const TabBar(
            tabs: [
              Tab(key: Key('tab-users'), text: AppStrings.usersTab),
              Tab(key: Key('tab-devices'), text: AppStrings.devicesTab),
            ],
          ),
          const SizedBox(height: 8),
          const Expanded(child: TabBarView(children: [_UsersTab(), _DevicesTab()])),
        ],
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});

  final LabUsage usage;

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.errorContainer;
    String limit(int n) => n == 0 ? AppStrings.unlimited : '$n';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              Chip(
                key: const Key('usage-users'),
                backgroundColor: usage.usersFull ? error : null,
                label: Text('${AppStrings.usersUsage}: ${usage.users} / ${limit(usage.maxUsers)}'),
              ),
              Chip(
                key: const Key('usage-devices'),
                backgroundColor: usage.devicesFull ? error : null,
                label: Text(
                  '${AppStrings.devicesUsage}: ${usage.devices} / ${limit(usage.maxDevices)}',
                ),
              ),
            ],
          ),
          if (usage.usersFull) const Text(AppStrings.limitReachedUsers),
          if (usage.devicesFull) const Text(AppStrings.limitReachedDevices),
        ],
      ),
    );
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myId = ref.watch(sessionProvider)?.user.id;
    return AsyncView(
      value: ref.watch(labUsersProvider),
      onRetry: () => ref.invalidate(labUsersProvider),
      builder: (users) => users.isEmpty
          ? const Center(child: Text(AppStrings.noUsers))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                for (final u in users)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      key: Key('user-row-${u.id}'),
                      leading: CircleAvatar(
                        child: Icon(u.isOwner ? Icons.verified_user : Icons.person_outline),
                      ),
                      title: Text(
                        u.displayName,
                        style: u.isActive
                            ? null
                            : const TextStyle(decoration: TextDecoration.lineThrough),
                      ),
                      subtitle: Text(
                        [
                          u.username,
                          u.isOwner ? AppStrings.roleOwner : AppStrings.roleStaff,
                          if (u.phone.isNotEmpty) u.phone,
                          if (!u.isOwner && u.canViewCosts) AppStrings.canViewCostsLabel,
                          if (!u.isOwner && u.canManageInventory) AppStrings.navInventory,
                          if (!u.isActive) AppStrings.inactive,
                          if (u.lastLogin != null)
                            '${AppStrings.lastLogin}: ${Formatters.dateTime(u.lastLogin)}',
                        ].join('   •   '),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            key: Key('edit-user-${u.id}'),
                            tooltip: AppStrings.edit,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final saved = await showDialog<LabMember>(
                                context: context,
                                builder: (_) => UserFormDialog(member: u, isSelf: u.id == myId),
                              );
                              if (saved != null) invalidateUsers(ref);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DevicesTab extends ConsumerWidget {
  const _DevicesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final raw = ref.watch(sessionProvider)?.raw['device'];
    final myDevice = raw is Map ? raw['id'] : null;
    final repo = ref.read(usersRepositoryProvider);

    Future<void> run(Future<Object?> Function() action) async {
      try {
        await action();
        invalidateUsers(ref);
      } catch (e) {
        if (context.mounted) showErrorSnack(context, e);
      }
    }

    return AsyncView(
      value: ref.watch(labDevicesProvider),
      onRetry: () => ref.invalidate(labDevicesProvider),
      builder: (devices) => devices.isEmpty
          ? const Center(child: Text(AppStrings.noDevices))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              children: [
                for (final d in devices)
                  Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    child: ListTile(
                      key: Key('device-row-${d.id}'),
                      leading: Icon(
                        Icons.computer,
                        color: d.isActive ? Colors.green : Theme.of(context).hintColor,
                      ),
                      title: Text(
                        '${d.name.isEmpty ? d.deviceId : d.name}'
                        '${d.id == myDevice ? ' (${AppStrings.thisDevice})' : ''}',
                      ),
                      subtitle: Text(
                        [
                          if (!d.isActive) AppStrings.inactive,
                          if (d.appVersion.isNotEmpty)
                            '${AppStrings.appVersionLabel}: ${d.appVersion}',
                          if (d.lastLoginAt != null)
                            '${AppStrings.lastLogin}: ${Formatters.dateTime(d.lastLoginAt)}',
                        ].join('   •   '),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: AppStrings.edit,
                            icon: const Icon(Icons.drive_file_rename_outline),
                            onPressed: () async {
                              final name = await _askName(context, d.name);
                              if (name != null) {
                                await run(() => repo.saveDevice(d.id, {'name': name}));
                              }
                            },
                          ),
                          if (d.isActive && d.id != myDevice)
                            TextButton(
                              key: Key('revoke-device-${d.id}'),
                              onPressed: () async {
                                if (await confirmDialog(context, AppStrings.revokeDeviceConfirm)) {
                                  await run(() => repo.saveDevice(d.id, {'is_active': false}));
                                }
                              },
                              child: const Text(AppStrings.revokeDevice),
                            ),
                          if (!d.isActive)
                            TextButton(
                              key: Key('reactivate-device-${d.id}'),
                              onPressed: () =>
                                  run(() => repo.saveDevice(d.id, {'is_active': true})),
                              child: const Text(AppStrings.reactivateDevice),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<String?> _askName(BuildContext context, String current) => showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(initial: current),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FormDialog(
    title: AppStrings.deviceName,
    width: 360,
    onSave: () => Navigator.of(context).pop(_name.text.trim()),
    child: TextField(
      key: const Key('device-name'),
      controller: _name,
      autofocus: true,
      decoration: const InputDecoration(labelText: AppStrings.deviceName),
    ),
  );
}

/// Add staff / edit a user: names, phone, password (reset), role, permissions, active.
class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, this.member, this.isSelf = false});

  final LabMember? member;
  final bool isSelf;

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.member?.username ?? '');
  late final _first = TextEditingController(text: widget.member?.firstName ?? '');
  late final _last = TextEditingController(text: widget.member?.lastName ?? '');
  late final _phone = TextEditingController(text: widget.member?.phone ?? '');
  final _password = TextEditingController();
  late String _role = widget.member?.role ?? 'staff';
  late bool _costs = widget.member?.canViewCosts ?? false;
  late bool _inventory = widget.member?.canManageInventory ?? false;
  late bool _active = widget.member?.isActive ?? true;
  bool _busy = false;
  Object? _error;

  bool get _editing => widget.member != null;

  @override
  void dispose() {
    for (final c in [_username, _first, _last, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    if (_editing && widget.member!.isActive && !_active) {
      if (!await confirmDialog(context, AppStrings.deactivateUserConfirm)) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final body = <String, dynamic>{
      if (!_editing) 'username': _username.text.trim(),
      'first_name': _first.text.trim(),
      'last_name': _last.text.trim(),
      'phone': _phone.text.trim(),
      if (_password.text.isNotEmpty) 'password': _password.text,
      if (!widget.isSelf) ...{'role': _role, 'is_active': _active},
      'can_view_costs': _costs,
      'can_manage_inventory': _inventory,
    };
    try {
      final saved = await ref.read(usersRepositoryProvider).saveUser(widget.member?.id, body);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwnerRole = _role == 'owner';
    return FormDialog(
      title: _editing ? AppStrings.editUser : AppStrings.addUser,
      width: 520,
      busy: _busy,
      error: _error == null ? null : errorMessageFor(_error!),
      onSave: _save,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('user-username'),
              controller: _username,
              enabled: !_editing,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(labelText: AppStrings.username),
              validator: Inputs.requiredText,
            ),
            const SizedBox(height: 12),
            FieldGrid(
              children: [
                TextFormField(
                  key: const Key('user-first-name'),
                  controller: _first,
                  decoration: const InputDecoration(labelText: AppStrings.firstName),
                ),
                TextFormField(
                  controller: _last,
                  decoration: const InputDecoration(labelText: AppStrings.lastName),
                ),
                TextFormField(
                  key: const Key('user-phone'),
                  controller: _phone,
                  decoration: const InputDecoration(labelText: AppStrings.phone),
                ),
                TextFormField(
                  key: const Key('user-password'),
                  controller: _password,
                  obscureText: true,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: _editing ? AppStrings.newPassword : AppStrings.password,
                  ),
                  validator: (v) {
                    final text = v ?? '';
                    if (!_editing && text.isEmpty) return AppStrings.passwordRequired;
                    if (text.isNotEmpty && text.length < 8) return AppStrings.passwordMin;
                    return null;
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!widget.isSelf)
              DropdownButtonFormField<String>(
                key: const Key('user-role'),
                isExpanded: true,
                initialValue: _role,
                decoration: const InputDecoration(labelText: AppStrings.role),
                items: const [
                  DropdownMenuItem(value: 'staff', child: Text(AppStrings.roleStaff)),
                  DropdownMenuItem(value: 'owner', child: Text(AppStrings.roleOwner)),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'staff'),
              ),
            if (isOwnerRole)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text(AppStrings.ownerHasAll))
            else ...[
              SwitchListTile(
                key: const Key('user-can-view-costs'),
                contentPadding: EdgeInsets.zero,
                value: _costs,
                title: const Text(AppStrings.canViewCostsLabel),
                onChanged: (v) => setState(() => _costs = v),
              ),
              SwitchListTile(
                key: const Key('user-can-manage-inventory'),
                contentPadding: EdgeInsets.zero,
                value: _inventory,
                title: const Text(AppStrings.canManageInventoryLabel),
                onChanged: (v) => setState(() => _inventory = v),
              ),
            ],
            if (_editing && !widget.isSelf)
              SwitchListTile(
                key: const Key('user-active'),
                contentPadding: EdgeInsets.zero,
                value: _active,
                title: Text(_active ? AppStrings.active : AppStrings.inactive),
                subtitle: Text(_active ? AppStrings.deactivateUser : AppStrings.activateUser),
                onChanged: (v) => setState(() => _active = v),
              ),
          ],
        ),
      ),
    );
  }
}
