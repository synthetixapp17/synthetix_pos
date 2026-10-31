import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/customer.dart';
import '../bloc/customer_bloc.dart';

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({super.key});

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clientes'),
        actions: [
          IconButton(
            tooltip: 'Nuevo cliente',
            onPressed: () => context.push('/customers/new'),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: BlocConsumer<CustomerBloc, CustomerState>(
        listener: (context, state) {
          if (state.status == CustomerStatus.failure && state.message != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message!)),
            );
          }
        },
        builder: (context, state) {
          final customers = state.customers
              .where((customer) =>
                  customer.name.toLowerCase().contains(_query.toLowerCase()) ||
                  customer.phone.contains(_query) ||
                  customer.email.toLowerCase().contains(_query.toLowerCase()))
              .toList();
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: TextField(
                  onChanged: (value) => setState(() => _query = value.trim()),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar por nombre, teléfono o correo',
                  ),
                ),
              ),
              Expanded(
                child: state.status == CustomerStatus.loading &&
                        state.customers.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : customers.isEmpty
                        ? _EmptyCustomers(hasSearch: _query.isNotEmpty)
                        : RefreshIndicator(
                            onRefresh: () async => context
                                .read<CustomerBloc>()
                                .add(const LoadCustomersEvent()),
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              itemCount: customers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) =>
                                  _CustomerCard(customer: customers[index]),
                            ),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  const _CustomerCard({required this.customer});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(customer.name.isEmpty ? '?' : customer.name[0].toUpperCase()),
        ),
        title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text([
            if (customer.phone.isNotEmpty) customer.phone,
            if (customer.email.isNotEmpty) customer.email,
            if (customer.address.isNotEmpty) customer.address,
          ].join('\n')),
        ),
        isThreeLine: customer.email.isNotEmpty || customer.address.isNotEmpty,
        trailing: PopupMenuButton<String>(
          tooltip: 'Acciones del cliente',
          onSelected: (action) async {
            if (action == 'editar') {
              await context.push('/customers/edit', extra: customer);
            } else if (action == 'eliminar') {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Eliminar cliente'),
                  content: Text('¿Deseas eliminar a ${customer.name}?'),
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
              if (confirmed == true && context.mounted) {
                context
                    .read<CustomerBloc>()
                    .add(DeleteCustomerEvent(customer.id));
              }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'eliminar', child: Text('Eliminar')),
          ],
        ),
      ),
    );
  }
}

class _EmptyCustomers extends StatelessWidget {
  final bool hasSearch;
  const _EmptyCustomers({required this.hasSearch});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(hasSearch ? Icons.search_off : Icons.people_outline,
                  size: 52, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                hasSearch ? 'No hay coincidencias' : 'Aún no hay clientes',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                hasSearch
                    ? 'Prueba con otro término de búsqueda.'
                    : 'Registra clientes para agilizar tus ventas.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}
