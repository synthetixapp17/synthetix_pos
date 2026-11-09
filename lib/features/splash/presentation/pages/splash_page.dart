import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class SplashPage extends StatelessWidget {
  const SplashPage({required this.onContinue, this.imageData, super.key});

  final VoidCallback onContinue;
  final String? imageData;

  static const _background = Color(0xFF101A16);
  static const _accent = Color(0xFF71D9A0);

  @override
  Widget build(BuildContext context) {
    final customImage = imageData == null ? null : _decodeImage(imageData!);
    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          Positioned(
            top: -180,
            right: -120,
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _accent.withValues(alpha: 0.08),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 176,
                              height: 176,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(34),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withValues(alpha: 0.16),
                                    blurRadius: 48,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(24),
                                child: customImage == null
                                    ? Image.asset(
                                        'assets/images/logo.png',
                                        fit: BoxFit.cover,
                                        semanticLabel: 'Logo de Synthetix POS',
                                      )
                                    : Image.memory(
                                        customImage,
                                        fit: BoxFit.cover,
                                        semanticLabel:
                                            'Imagen de bienvenida de Synthetix POS',
                                        errorBuilder: (_, _, _) => Image.asset(
                                          'assets/images/logo.png',
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: _accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: _accent.withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                child: Text(
                                  'GESTIÓN INTELIGENTE PARA TU NEGOCIO',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _accent,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Synthetix POS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 38,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.2,
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Todo tu negocio, en un solo lugar.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 17,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Administra ventas, inventario y clientes de forma '
                              'simple y rápida.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.52),
                                fontSize: 14,
                                height: 1.6,
                              ),
                            ),
                            const SizedBox(height: 32),
                            const Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                _FeatureChip(
                                  icon: Icons.point_of_sale_rounded,
                                  label: 'Ventas',
                                ),
                                _FeatureChip(
                                  icon: Icons.inventory_2_outlined,
                                  label: 'Inventario',
                                ),
                                _FeatureChip(
                                  icon: Icons.bar_chart_rounded,
                                  label: 'Reportes',
                                ),
                              ],
                            ),
                            const SizedBox(height: 36),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: onContinue,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: _background,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('Ingresar a la plataforma'),
                                    SizedBox(width: 10),
                                    Icon(Icons.arrow_forward_rounded, size: 20),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Rápido · Simple · Siempre a tu alcance',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.38),
                                fontSize: 12,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Uint8List? _decodeImage(String data) {
    try {
      return base64Decode(data);
    } on FormatException {
      return null;
    }
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: SplashPage._accent),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.84),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
