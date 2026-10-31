import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../domain/entities/shop.dart';
import '../bloc/shop_bloc.dart';

class ShopDetailsPage extends StatefulWidget {
  const ShopDetailsPage({super.key});

  @override
  State<ShopDetailsPage> createState() => _ShopDetailsPageState();
}

class _ShopDetailsPageState extends State<ShopDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address1 = TextEditingController();
  final _address2 = TextEditingController();
  final _phone = TextEditingController();
  final _upi = TextEditingController();
  final _footer = TextEditingController();
  String? _logoData;
  bool _isLoaded = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    context.read<ShopBloc>().add(LoadShopEvent());
  }

  void _fill(Shop shop) {
    if (_isLoaded) return;
    _isLoaded = true;
    _name.text = shop.name;
    _address1.text = shop.addressLine1;
    _address2.text = shop.addressLine2;
    _phone.text = shop.phoneNumber;
    _upi.text = shop.upiId;
    _footer.text = shop.footerText;
    _logoData = shop.logoData;
  }

  @override
  void dispose() {
    _name.dispose();
    _address1.dispose();
    _address2.dispose();
    _phone.dispose();
    _upi.dispose();
    _footer.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    try {
      final selected = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1200,
      );
      if (selected == null || !mounted) return;
      final bytes = await selected.readAsBytes();
      setState(() => _logoData = base64Encode(bytes));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo cargar el logotipo: $error')),
      );
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    context.read<ShopBloc>().add(
      UpdateShopEvent(
        Shop(
          name: _name.text.trim(),
          addressLine1: _address1.text.trim(),
          addressLine2: _address2.text.trim(),
          phoneNumber: _phone.text.trim(),
          upiId: _upi.text.trim(),
          footerText: _footer.text.trim(),
          logoData: _logoData,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Datos de la tienda')),
    body: BlocConsumer<ShopBloc, ShopState>(
      listener: (context, state) {
        if (state is ShopLoaded) _fill(state.shop);
        if (state is ShopOperationSuccess) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Datos de la tienda guardados.')),
          );
          context.pop();
        } else if (state is ShopError) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      builder: (context, state) {
        if (state is ShopLoading && !_isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _LogoCard(imageData: _logoData, onPressed: _pickLogo),
              const SizedBox(height: 22),
              const _FormSection(
                title: 'Identidad del negocio',
                subtitle:
                    'Esta información identifica tu tienda en la aplicación y en los recibos.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nombre de la tienda',
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'El nombre de la tienda es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Dirección',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'La dirección es obligatoria.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _address2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Complemento de dirección (opcional)',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
              ),
              const SizedBox(height: 22),
              const _FormSection(
                title: 'Contacto y pagos',
                subtitle:
                    'Los datos de contacto pueden imprimirse en los comprobantes.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Teléfono',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'El teléfono es obligatorio.'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _upi,
                decoration: const InputDecoration(
                  labelText: 'Identificador de pago UPI (opcional)',
                  prefixIcon: Icon(Icons.qr_code_2),
                ),
              ),
              const SizedBox(height: 22),
              const _FormSection(
                title: 'Personalización del recibo',
                subtitle:
                    'Añade un mensaje breve para tus clientes al finalizar la compra.',
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _footer,
                minLines: 2,
                maxLines: 3,
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Mensaje final',
                  hintText: 'Gracias por tu compra.',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Guardando…' : 'Guardar datos'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _LogoCard extends StatelessWidget {
  final String? imageData;
  final VoidCallback onPressed;
  const _LogoCard({required this.imageData, required this.onPressed});

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: .1),
            backgroundImage: imageData == null
                ? null
                : MemoryImage(base64Decode(imageData!)),
            child: imageData == null
                ? Icon(
                    Icons.storefront_outlined,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Logotipo de la tienda',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Personaliza el perfil visible de tu negocio.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.upload_outlined),
                  label: Text(
                    imageData == null ? 'Subir logotipo' : 'Cambiar logotipo',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FormSection extends StatelessWidget {
  final String title;
  final String subtitle;
  const _FormSection({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
