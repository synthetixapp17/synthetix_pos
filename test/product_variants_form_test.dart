import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/presentation/widgets/product_variants_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('preserves custom units and attributes when editing variants', (
    tester,
  ) async {
    final formKey = GlobalKey<ProductVariantsFormState>();
    const variant = ProductVariant(
      id: 'variant-1',
      attributes: {'Color': 'Azul', 'Empaque': 'Bolsa grande'},
      price: 4.5,
      stock: 12,
      unitLabel: 'bolsa grande',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProductVariantsForm(
              key: formKey,
              initialVariants: const [variant],
            ),
          ),
        ),
      ),
    );

    expect(find.text('bolsa grande'), findsOneWidget);
    final variants = formKey.currentState!.readVariants();

    expect(variants, isNotNull);
    expect(variants!.single.unitLabel, 'bolsa grande');
    expect(variants.single.attributes, variant.attributes);
    expect(tester.takeException(), isNull);
  });
}
