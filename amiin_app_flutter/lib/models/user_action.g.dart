// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'user_action.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class UserActionAdapter extends TypeAdapter<UserAction> {
  @override
  final int typeId = 0;

  @override
  UserAction read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return UserAction(
      type: fields[0] as String,
      objectId: fields[1] as String,
      summary: fields[2] as String,
      timestamp: fields[3] as DateTime,
      context: fields[4] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, UserAction obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.type)
      ..writeByte(1)
      ..write(obj.objectId)
      ..writeByte(2)
      ..write(obj.summary)
      ..writeByte(3)
      ..write(obj.timestamp)
      ..writeByte(4)
      ..write(obj.context);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserActionAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
