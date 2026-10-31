import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WebAppShell extends StatelessWidget {
  final String location;
  final Widget child;

  const WebAppShell({super.key, required this.location, required this.child});

  static const _navigation = <_NavigationItem>[
    _NavigationItem(
      label: 'Resumen',
      path: '/',
      icon: Icons.space_dashboard_outlined,
      selectedIcon: Icons.space_dashboard_rounded,
    ),
    _NavigationItem(
      label: 'Punto de venta',
      path: '/new-sale',
      icon: Icons.point_of_sale_outlined,
      selectedIcon: Icons.point_of_sale_rounded,
    ),
    _NavigationItem(
      label: 'Inventario',
      path: '/products',
      icon: Icons.inventory_2_outlined,
      selectedIcon: Icons.inventory_2_rounded,
    ),
    _NavigationItem(
      label: 'Clientes',
      path: '/customers',
      icon: Icons.people_outline_rounded,
      selectedIcon: Icons.people_rounded,
    ),
    _NavigationItem(
      label: 'Reportes',
      path: '/reports',
      icon: Icons.bar_chart_outlined,
      selectedIcon: Icons.bar_chart_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 800) return child;

    final expanded = width >= 1120;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(
        children: [
          Container(
            width: expanded ? 252 : 76,
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(right: BorderSide(color: colors.outlineVariant)),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 22 : 12,
                      18,
                      expanded ? 22 : 12,
                      28,
                    ),
                    child: expanded
                        ? Row(
                            children: [
                              _BrandIcon(color: colors.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Synthetix POS',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          )
                        : _BrandIcon(color: colors.primary),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(
                        horizontal: expanded ? 12 : 8,
                      ),
                      children: [
                        for (final item in _navigation)
                          _NavigationButton(
                            item: item,
                            expanded: expanded,
                            selected: _isSelected(location, item.path),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      expanded ? 12 : 8,
                      8,
                      expanded ? 12 : 8,
                      16,
                    ),
                    child: _NavigationButton(
                      item: const _NavigationItem(
                        label: 'Configuración',
                        path: '/settings',
                        icon: Icons.settings_outlined,
                        selectedIcon: Icons.settings_rounded,
                      ),
                      expanded: expanded,
                      selected:
                          location.startsWith('/settings') ||
                          location == '/shop',
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final contentWidth = constraints.maxWidth
                      .clamp(0.0, 1600.0)
                      .toDouble();
                  return Center(
                    child: SizedBox(width: contentWidth, child: child),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSelected(String currentLocation, String path) {
    if (path == '/') return currentLocation == '/';
    return currentLocation == path || currentLocation.startsWith('$path/');
  }
}

class _BrandIcon extends StatelessWidget {
  final Color color;

  const _BrandIcon({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Icon(Icons.storefront_rounded, color: color),
  );
}

class _NavigationButton extends StatelessWidget {
  final _NavigationItem item;
  final bool expanded;
  final bool selected;

  const _NavigationButton({
    required this.item,
    required this.expanded,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final button = Material(
      color: selected ? colors.primaryContainer : Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () => context.go(item.path),
        child: SizedBox(
          height: 48,
          child: Row(
            mainAxisAlignment: expanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              SizedBox(
                width: expanded ? 48 : 56,
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 21,
                  color: selected
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              if (expanded)
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    if (expanded) {
      return Padding(padding: const EdgeInsets.only(bottom: 6), child: button);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Tooltip(message: item.label, child: button),
    );
  }
}

class _NavigationItem {
  final String label;
  final String path;
  final IconData icon;
  final IconData selectedIcon;

  const _NavigationItem({
    required this.label,
    required this.path,
    required this.icon,
    required this.selectedIcon,
  });
}
