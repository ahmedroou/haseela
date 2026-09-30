import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'design.dart';
import 'domain.dart';
import 'forms.dart';
import 'screens.dart';
import 'store.dart';

Future<void> copyAccount(BuildContext context, Account account) async {
  try {
    await Clipboard.setData(ClipboardData(text: account.name));
    if (context.mounted) {
      notice(
        context,
        account.isEmail ? 'تم نسخ البريد الإلكتروني' : 'تم نسخ اسم الحساب',
      );
    }
  } catch (_) {
    if (context.mounted) notice(context, 'تعذّر النسخ. حاولي مرة أخرى.');
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.account,
    required this.store,
    required this.onOpen,
  });
  final Account account;
  final AppStore store;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Deletable(
    child: (remove) => Pressable(
      onTap: onOpen,
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  account.isClosed
                      ? Icons.lock_outline_rounded
                      : account.isEmail
                      ? Icons.alternate_email_rounded
                      : Icons.folder_open_rounded,
                  size: 21,
                  color: account.isClosed
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : lilac,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    account.name,
                    textDirection: account.isEmail ? TextDirection.ltr : null,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: ValueKey('copy_account_${account.id}'),
                  tooltip: account.isEmail
                      ? 'نسخ البريد الإلكتروني'
                      : 'نسخ اسم الحساب',
                  onPressed: () => copyAccount(context, account),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 40),
                    padding: const EdgeInsets.all(6),
                  ),
                  icon: const Icon(
                    Icons.content_copy_rounded,
                    size: 17,
                    color: lilac,
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'خيارات الحساب',
                  enabled: !store.busy,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(minWidth: 180),
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (action) async {
                    if (action == 'edit') {
                      await accountSheet(context, store, account: account);
                    } else if (action == 'toggle_closed') {
                      try {
                        await store.mutate(
                          () => store.database.toggleAccountClosed(
                            account.id,
                            !account.isClosed,
                          ),
                        );
                        if (context.mounted) {
                          notice(
                            context,
                            account.isClosed
                                ? 'أُعيد فتح الحساب'
                                : 'تم إغلاق الحساب',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) notice(context, friendlyError(e));
                      }
                    } else if (await confirm(
                      context,
                      'حذف «${account.name}»؟',
                      'سيُحذف الحساب و${account.orderCount} طلب داخله، وتُزال مبالغها من التقرير العام. الأرباح المستلمة المسجّلة تبقى محفوظة في سجلها.',
                    )) {
                      if (!context.mounted) return;
                      await remove(() async {
                        await store.mutate(
                          () => store.database.deleteAccount(account.id),
                        );
                        if (context.mounted) notice(context, 'تم حذف الحساب');
                      });
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('تعديل الحساب'),
                    ),
                    PopupMenuItem(
                      value: 'toggle_closed',
                      child: Text(
                        account.isClosed ? 'إعادة فتح الحساب' : 'إغلاق الحساب',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('حذف الحساب'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 2),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${account.orderCount} طلب · ${account.pieces} قطعة',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (account.pending > 0)
                  _stat(context, '${account.pending} معلّق', lilac),
                if (account.arrived > 0)
                  _stat(context, '${account.arrived} وصل', sage),
                if (account.cancelled > 0)
                  _stat(context, '${account.cancelled} ملغي', rose),
                if (account.isClosed)
                  _stat(
                    context,
                    'مغلق',
                    Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    shortDate(account.createdAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (!account.isClosed)
                  TextButton.icon(
                    key: ValueKey('account_add_order_${account.id}'),
                    onPressed: store.busy
                        ? null
                        : () => orderSheet(context, store, account.id),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      minimumSize: const Size(0, 34),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 17),
                    label: const Text('طلب', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  Widget _stat(BuildContext context, String text, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: color)),
    ],
  );
}
