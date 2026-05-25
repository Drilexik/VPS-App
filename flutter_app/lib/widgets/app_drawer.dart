import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class DrawerItem {
  final IconData icon;
  final String label;

  const DrawerItem(this.icon, this.label);
}

const _drawerItems = [
  DrawerItem(Icons.dashboard_rounded, 'Dashboard'),
  DrawerItem(Icons.bar_chart_rounded, 'Statistics'),
  DrawerItem(Icons.memory_rounded, 'CPU Monitor'),
  DrawerItem(Icons.storage_rounded, 'RAM Monitor'),
  DrawerItem(Icons.folder_rounded, 'Disk Manager'),
  DrawerItem(Icons.wifi_rounded, 'Network'),
  DrawerItem(Icons.inventory_2_rounded, 'Docker'),
  DrawerItem(Icons.terminal_rounded, 'Terminal'),
];

class AppDrawer extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;
  final VoidCallback onDisconnect;

  const AppDrawer({
    super.key,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                    ),
                    child: const Icon(Icons.dns_rounded, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Drilex VPS',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.text,
                        ),
                      ),
                      Text(
                        'Server Manager',
                        style: TextStyle(fontSize: 12, color: AppColors.textDim),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _drawerItems.length,
                itemBuilder: (ctx, i) {
                  final item = _drawerItems[i];
                  final selected = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    child: ListTile(
                      leading: Icon(
                        item.icon,
                        size: 20,
                        color: selected ? AppColors.primary : AppColors.textDim,
                      ),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                          color: selected ? AppColors.primary : AppColors.text,
                        ),
                      ),
                      selected: selected,
                      selectedTileColor: AppColors.primary.withOpacity(0.12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      onTap: () => onItemSelected(i),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  );
                },
              ),
            ),
            const Divider(color: AppColors.border, height: 1),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, size: 20, color: AppColors.danger),
                title: const Text(
                  'Disconnect',
                  style: TextStyle(fontSize: 14, color: AppColors.danger),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Disconnect'),
                      content: const Text('Clear saved server credentials?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onDisconnect();
                          },
                          child: const Text(
                            'Disconnect',
                            style: TextStyle(color: AppColors.danger),
                          ),
                        ),
                      ],
                    ),
                  );
                },
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
