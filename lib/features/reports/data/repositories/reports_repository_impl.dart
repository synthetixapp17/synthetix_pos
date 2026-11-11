import 'package:fpdart/fpdart.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/error/failure.dart';
import '../../../product/data/models/product_model.dart';
import '../../../product/domain/entities/product.dart';
import '../../domain/entities/sale_record.dart';
import '../../domain/repositories/reports_repository.dart';
import '../models/sale_model.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  @override
  Future<Either<Failure, List<SaleRecord>>> getSales({
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final sales =
          HiveDatabase.salesBox.values
              .where(
                (sale) =>
                    !sale.soldAt.isBefore(from) && !sale.soldAt.isAfter(to),
              )
              .map((sale) => sale.toEntity())
              .toList()
            ..sort((a, b) => a.soldAt.compareTo(b.soldAt));
      return Right(sales);
    } catch (error) {
      return Left(CacheFailure(error.toString()));
    }
  }

  @override
  Future<Either<Failure, void>> recordSale(SaleRecord sale) async {
    final productsBox = HiveDatabase.productBox;
    final salesBox = HiveDatabase.salesBox;
    final isNewSale = !salesBox.containsKey(sale.id);
    final productsToUpdate = <String, ProductModel>{};
    final previousProducts = <String, ProductModel>{};

    try {
      if (isNewSale) {
        for (final line in sale.lines) {
          if (!line.inventoryTracked) continue;
          final product =
              productsToUpdate[line.productId] ??
              productsBox.get(line.productId);
          if (product == null) {
            return Left(
              CacheFailure(
                'No se encontró "${line.productName}" en el inventario; '
                'no se registró la venta.',
              ),
            );
          }
          final variant = line.variantId == null
              ? null
              : product.variants.where((item) => item.id == line.variantId);
          if (line.variantId != null && (variant == null || variant.isEmpty)) {
            return Left(
              CacheFailure(
                'No se encontró la variación de "${line.productName}"; '
                'no se registró la venta.',
              ),
            );
          }
          final availableStock = variant == null
              ? product.stock
              : variant.first.stock;
          if (availableStock < line.quantity) {
            return Left(
              CacheFailure(
                'Existencia insuficiente para "${line.productName}". '
                'Disponible: $availableStock; solicitado: ${line.quantity}.',
              ),
            );
          }
          previousProducts.putIfAbsent(line.productId, () => product);
          final updatedVariants = variant == null
              ? null
              : product.variants
                    .map(
                      (item) => item.id == line.variantId
                          ? ProductVariant(
                              id: item.id,
                              attributes: item.attributes,
                              price: item.price,
                              stock: item.stock - line.quantity,
                              barcode: item.barcode,
                              unitLabel: item.unitLabel,
                            )
                          : item,
                    )
                    .toList();
          productsToUpdate[line.productId] = product.copyWith(
            stock: product.stock - line.quantity,
            variants: updatedVariants,
          );
        }
        await productsBox.putAll(productsToUpdate);
      }

      await salesBox.put(sale.id, SaleModel.fromEntity(sale));
      return const Right(null);
    } catch (error) {
      if (isNewSale && previousProducts.isNotEmpty) {
        try {
          await productsBox.putAll(previousProducts);
          await salesBox.delete(sale.id);
        } catch (rollbackError) {
          return Left(
            CacheFailure(
              'No se pudo completar la venta ($error) y tampoco restaurar '
              'el inventario ($rollbackError). Revisa las existencias antes '
              'de continuar.',
            ),
          );
        }
      }
      return Left(CacheFailure(error.toString()));
    }
  }
}
