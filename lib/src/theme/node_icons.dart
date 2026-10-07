import 'package:flutter/material.dart';

/// Iconos disponibles por defecto para `NodeStyle.icon`, por clave.
///
/// Los nodos guardan la clave (texto) para poder serializarse; el tema la
/// traduce a un icono. Añade los tuyos con
/// `theme.copyWith(icons: {...NodeIcons.all, 'mi_icono': Icons.abc})`.
abstract final class NodeIcons {
  static const Map<String, IconData> all = {
    // Personas y organización
    'person': Icons.person_outline,
    'group': Icons.groups_outlined,
    'badge': Icons.badge_outlined,
    'business': Icons.business,
    'store': Icons.storefront,
    'home': Icons.home_outlined,
    'public': Icons.public,
    'place': Icons.place_outlined,
    // Inventario y logística
    'inventory': Icons.inventory_2_outlined,
    'warehouse': Icons.warehouse_outlined,
    'truck': Icons.local_shipping_outlined,
    'factory': Icons.factory_outlined,
    'build': Icons.build_outlined,
    'settings': Icons.settings_outlined,
    'cart': Icons.shopping_cart_outlined,
    'box': Icons.all_inbox_outlined,
    'qr': Icons.qr_code_2,
    'money': Icons.attach_money,
    // Proceso
    'play': Icons.play_arrow_rounded,
    'stop': Icons.stop_rounded,
    'flag': Icons.flag_outlined,
    'check': Icons.check_rounded,
    'close': Icons.close_rounded,
    'help': Icons.help_outline,
    'warning': Icons.warning_amber_rounded,
    'info': Icons.info_outline,
    'schedule': Icons.schedule,
    'event': Icons.event_outlined,
    'sync': Icons.sync,
    'bolt': Icons.bolt,
    // Información
    'star': Icons.star_outline,
    'favorite': Icons.favorite_border,
    'lightbulb': Icons.lightbulb_outline,
    'note': Icons.sticky_note_2_outlined,
    'description': Icons.description_outlined,
    'folder': Icons.folder_outlined,
    'database': Icons.storage_outlined,
    'cloud': Icons.cloud_outlined,
    'email': Icons.mail_outline,
    'phone': Icons.phone_outlined,
    'lock': Icons.lock_outline,
    'label': Icons.label_outline,
  };
}
