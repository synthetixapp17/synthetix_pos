import 'package:flutter/material.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/utils/payment_methods.dart';

class PaymentMethodsSettingsPage extends StatefulWidget {
  const PaymentMethodsSettingsPage({super.key});

  @override
  State<PaymentMethodsSettingsPage> createState() =>
      _PaymentMethodsSettingsPageState();
}

class _PaymentMethodsSettingsPageState
    extends State<PaymentMethodsSettingsPage> {
  late List<String> _methods = loadPaymentMethods();

  Future<void> _editMethod({String? existingMethod}) async {
    final controller = TextEditingController(text: existingMethod ?? '');
    final formKey = GlobalKey<FormState>();
    final method = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          existingMethod == null
              ? 'Agregar forma de pago'
              : 'Editar forma de pago',
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Nombre',
              hintText: 'Ej. Pago móvil',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            validator: (value) {
              final candidate = (value ?? '').trim();
              if (candidate.isEmpty) return 'Escribe un nombre.';
              if (_methods.any(
                (item) =>
                    item.toLowerCase() == candidate.toLowerCase() &&
                    item != existingMethod,
              )) {
                return 'Esta forma de pago ya existe.';
              }
              return null;
            },
            onFieldSubmitted: (_) {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (method == null || !mounted) return;

    final updatedMethods = [..._methods];
    if (existingMethod == null) {
      updatedMethods.add(method);
    } else {
      updatedMethods[updatedMethods.indexOf(existingMethod)] = method;
    }
    await _saveMethods(updatedMethods);
  }

  Future<void> _deleteMethod(String method) async {
    if (_methods.length == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe quedar al menos una forma de pago disponible.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar forma de pago'),
        content: Text(
          '¿Quieres eliminar "$method" de las opciones disponibles?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _saveMethods(_methods.where((item) => item != method).toList());
  }

  Future<void> _saveMethods(List<String> methods) async {
    try {
      await HiveDatabase.settingsBox.put(paymentMethodsSettingKey, methods);
      if (mounted) setState(() => _methods = methods);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron guardar los cambios: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Formas de pago')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editMethod(),
        icon: const Icon(Icons.add),
        label: const Text('Agregar'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 100),
        children: [
          Card(
            color: colors.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Personaliza las opciones que tu negocio acepta. '
                      'Se mostrarán al registrar ventas y abonos.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (final method in _methods)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colors.secondaryContainer,
                  child: Icon(
                    Icons.account_balance_wallet_outlined,
                    color: colors.onSecondaryContainer,
                  ),
                ),
                title: Text(
                  method,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editMethod(existingMethod: method);
                    } else {
                      _deleteMethod(method);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'edit',
                      child: ListTile(
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Editar'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_outline),
                        title: Text('Eliminar'),
                        contentPadding: EdgeInsets.zero,
                      ),
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
