import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/customer.dart';
import '../bloc/customer_bloc.dart';

class CustomerFormPage extends StatefulWidget {
  final Customer? customer;
  final bool quickCreate;
  final String initialPhone;

  const CustomerFormPage({
    super.key,
    this.customer,
    this.quickCreate = false,
    this.initialPhone = '',
  });

  @override
  State<CustomerFormPage> createState() => _CustomerFormPageState();
}

class _CustomerFormPageState extends State<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.customer?.name ?? '');
    _phone = TextEditingController(
      text: widget.customer?.phone ?? widget.initialPhone,
    );
    _email = TextEditingController(text: widget.customer?.email ?? '');
    _address = TextEditingController(text: widget.customer?.address ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CustomerBloc, CustomerState>(
      listenWhen: (_, current) =>
          current.status == CustomerStatus.saved ||
          current.status == CustomerStatus.failure,
      listener: (context, state) {
        if (state.status == CustomerStatus.saved) {
          if (widget.quickCreate) {
            context.pop(state.savedCustomer);
          } else {
            context.pop();
          }
        } else if (state.message != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message!)));
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.customer == null ? 'Nuevo cliente' : 'Editar cliente',
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.quickCreate
                      ? 'Asocia un cliente a esta venta.'
                      : 'Completa los datos de contacto del cliente.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'El nombre es obligatorio.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  validator: (value) =>
                      widget.quickCreate &&
                          (value == null || value.trim().isEmpty)
                      ? 'El teléfono es obligatorio para enviar el comprobante.'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    return RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value.trim())
                        ? null
                        : 'Ingresa un correo válido.';
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _address,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    widget.customer == null
                        ? 'Guardar cliente'
                        : 'Guardar cambios',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    context.read<CustomerBloc>().add(
      SaveCustomerEvent(
        customer: widget.customer == null
            ? null
            : Customer(
                id: widget.customer!.id,
                name: _name.text.trim(),
                phone: _phone.text.trim(),
                email: _email.text.trim(),
                address: _address.text.trim(),
              ),
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        address: _address.text,
      ),
    );
  }
}
