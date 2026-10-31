// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sale_model.dart';

class SaleModelAdapter extends TypeAdapter<SaleModel> {
  @override
  final int typeId = 3;

  @override
  SaleModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SaleModel(
      id: fields[0] as String,
      soldAt: fields[1] as DateTime,
      total: fields[2] as double,
      linesJson: fields[5] == null ? '[]' : fields[5] as String,
      currencyCode: fields[6] == null ? 'USD' : fields[6] as String,
      customerId: fields[3] as String?,
      customerName: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, SaleModel obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.soldAt)
      ..writeByte(2)
      ..write(obj.total)
      ..writeByte(3)
      ..write(obj.customerId)
      ..writeByte(4)
      ..write(obj.customerName)
      ..writeByte(5)
      ..write(obj.linesJson)
      ..writeByte(6)
      ..write(obj.currencyCode);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaleModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
