import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters/formatters.dart';
import '../../core/strings/app_strings.dart';
import '../../models/doctors.dart';
import '../../widgets/common.dart';

/// Doctor ↔ lab links as seen by one [side] (`doctor` / `lab`): this side's link code,
/// a field to request a link with the other side's code, and the links with their actions.
class LinksPanel extends StatefulWidget {
  const LinksPanel({
    super.key,
    required this.side,
    required this.links,
    required this.onRequest,
    required this.onAction,
    this.code,
    this.onRegenerate,
    this.canManage = true,
  });

  final String side;
  final List<DoctorLink> links;
  final String? code;
  final Future<void> Function(String code) onRequest;

  /// `accept` | `reject` | `revoke`.
  final Future<void> Function(DoctorLink link, String action) onAction;
  final VoidCallback? onRegenerate;
  final bool canManage;

  @override
  State<LinksPanel> createState() => _LinksPanelState();
}

class _LinksPanelState extends State<LinksPanel> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (_busy || _code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onRequest(_code.text.trim());
      _code.clear();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDoctor = widget.side == 'doctor';
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.page,
      ),
      children: [
        if (widget.canManage)
          SectionCard(
            title: AppStrings.sectionLinks,
            icon: Icons.qr_code_2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isDoctor ? AppStrings.myLinkCodeHint : AppStrings.labLinkCodeHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.of(context).textMuted,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (widget.code != null)
                      InputDecorator(
                        decoration: InputDecoration(
                          labelText: isDoctor ? AppStrings.myLinkCode : AppStrings.labLinkCode,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelectableText(
                              widget.code!,
                              key: const Key('own-link-code'),
                              style: theme.textTheme.titleLarge?.copyWith(letterSpacing: 2),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () => Clipboard.setData(ClipboardData(text: widget.code!)),
                            ),
                            if (widget.onRegenerate != null)
                              TextButton(
                                onPressed: widget.onRegenerate,
                                child: const Text(AppStrings.regenerateCode),
                              ),
                          ],
                        ),
                      ),
                    SizedBox(
                      width: 220,
                      child: TextField(
                        key: const Key('link-code-input'),
                        controller: _code,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: isDoctor
                              ? AppStrings.enterLabCode
                              : AppStrings.enterDoctorCode,
                        ),
                        onSubmitted: (_) => _request(),
                      ),
                    ),
                    FilledButton.icon(
                      key: const Key('link-request'),
                      icon: const Icon(Icons.link),
                      label: const Text(AppStrings.requestLink),
                      onPressed: _busy ? null : _request,
                    ),
                  ],
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        if (widget.links.isEmpty) const EmptyState(icon: Icons.link_off, title: AppStrings.noLinks),
        for (final link in widget.links)
          Card(
            key: Key('link-row-${link.id}'),
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: IconTile(
                icon: link.status == LinkStatuses.accepted ? Icons.link : Icons.link_off,
                tone: StatusTones.link(link.status),
                size: 38,
              ),
              title: Row(
                children: [
                  Flexible(child: Text(link.otherName, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpacing.sm),
                  StatusBadge(
                    label: AppStrings.label(AppStrings.linkStatuses, link.status),
                    tone: StatusTones.link(link.status),
                    dense: true,
                  ),
                ],
              ),
              subtitle: Text(
                [
                  if (link.status == LinkStatuses.pending)
                    link.requestedBy == widget.side
                        ? AppStrings.requestedByUs
                        : AppStrings.requestedByThem,
                  if (link.otherDetails.isNotEmpty) link.otherDetails,
                  if (link.otherPhone.isNotEmpty) link.otherPhone,
                  Formatters.date(link.requestedAt),
                ].join('   •   '),
              ),
              trailing: !widget.canManage
                  ? null
                  : Wrap(
                      spacing: 4,
                      children: [
                        if (link.canAnswer(widget.side)) ...[
                          FilledButton(
                            key: Key('link-accept-${link.id}'),
                            onPressed: () => widget.onAction(link, 'accept'),
                            child: const Text(AppStrings.acceptLink),
                          ),
                          OutlinedButton(
                            key: Key('link-reject-${link.id}'),
                            onPressed: () => widget.onAction(link, 'reject'),
                            child: const Text(AppStrings.rejectLink),
                          ),
                        ],
                        if (link.canRevoke && !link.canAnswer(widget.side))
                          TextButton(
                            key: Key('link-revoke-${link.id}'),
                            onPressed: () async {
                              if (await confirmDialog(context, '${AppStrings.revokeLink}؟')) {
                                await widget.onAction(link, 'revoke');
                              }
                            },
                            child: const Text(AppStrings.revokeLink),
                          ),
                      ],
                    ),
            ),
          ),
      ],
    );
  }
}
