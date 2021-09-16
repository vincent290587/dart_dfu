
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:modern_dfu/utils.dart';

import 'constants.dart';

///////////////////////////////////////////////////////////

abstract class UserCharacteristic {

  Future<void> writeData(List<int> data);

  Future<List<int>> getResponse(int timeout_ms);

  Stream<List<int>> getStream();
}

///////////////////////////////////////////////////////////

class SecureDfuImpl {

  final UserCharacteristic mPacketCharacteristic;
  final UserCharacteristic mControlPointCharacteristic;

  SecureDfuImpl({required this.mPacketCharacteristic, required this.mControlPointCharacteristic});

  Future<int> startDfu() async {

    int ret;

    ret = await sendInitPacket();

    return ret;
  }

  Future<int> sendInitPacket() async {

    debugPrint("Setting object to Command (Op Code = 6, Type = 1)");

    final ObjectInfo info = await selectObject(OBJECT_COMMAND);

    debugPrint("Command object info received (Max size = ${info.maxSize}, Offset = ${info.offset}, CRC = ${info.CRC32})");

    File mInitPacketStream = File('sample_file');
    Uint8List initContent = mInitPacketStream.readAsBytesSync();

    List<int> buffer = initContent.sublist(0, info.offset);

    // Calculate the CRC32
    //final int crc = CRC32.compute(buffer);

    setPacketReceiptNotifications(0);
    debugPrint("Packet Receipt Notif disabled (Op Code = 2, Value = 0)");

    // Create the Init object
    debugPrint("Creating Init packet object (Op Code = 1, Type = 1, Size = ${initContent.length})");
    writeCreateRequest(OBJECT_COMMAND, initContent.length);
    debugPrint("Command object created");

    while (initContent.length > 0) {
      writeInitData(mPacketCharacteristic, crc32);

      int crc = (int) (crc32.getValue() & 0xFFFFFFFFL);

      // Calculate Checksum
      debugPrint("Sending Calculate Checksum command (Op Code = 3)");
      checksum = readChecksum();
      debugPrint("Checksum received (Offset = %d, CRC = %08X)", checksum.offset, checksum.CRC32);
    }

    logi("Executing init packet (Op Code = 4)");
    writeExecute();

    return 0;
  }

  Future<ObjectInfo> selectObject(int type) async {

    List<int> opCode = OP_CODE_SELECT_OBJECT;
    opCode[1] = type;
    writeOpCode(mControlPointCharacteristic, opCode);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic); // TODO check char
    int status = getStatusCode(response, OP_CODE_SELECT_OBJECT_KEY);

    if (status == EXTENDED_ERROR)
      throw new Exception("Selecting object failed ${response}");
    if (status != DFU_STATUS_SUCCESS)
      throw new Exception("Selecting object failed ${status}");

    final ObjectInfo info = new ObjectInfo();
    info.maxSize = unsignedBytesToInt(response!, 3);
    info.offset = unsignedBytesToInt(response!, 3 + 4);
    info.CRC32  = unsignedBytesToInt(response!, 3 + 8);
    return info;
  }

  Future<void> writeOpCode(UserCharacteristic char, List<int> opCode) async {
    char.writeData(opCode);
  }

  Future<List<int>?> readNotificationResponse(UserCharacteristic char) async {
    await char.getResponse(1000);
  }

  int getStatusCode(List<int>? response, int request) {
    if (response == null || response.length < 3 || response[0] != OP_CODE_RESPONSE_CODE_KEY || response[1] != request ||
        (response[2] != DFU_STATUS_SUCCESS &&
            response[2] != OP_CODE_NOT_SUPPORTED &&
            response[2] != INVALID_PARAM &&
            response[2] != INSUFFICIENT_RESOURCES &&
            response[2] != INVALID_OBJECT &&
            response[2] != UNSUPPORTED_TYPE &&
            response[2] != OPERATION_NOT_PERMITTED &&
            response[2] != OPERATION_FAILED &&
            response[2] != EXTENDED_ERROR))
      throw new Exception("Invalid response received, ${response} ${request}");
    return response[2];
  }

  Future<void> setPacketReceiptNotifications(final int number) async {

    // Send the number of packets of firmware before receiving a receipt notification
    debugPrint("Sending the number of packets before notifications (Op Code = 2, Value = ${number}");
    setNumberOfPackets(OP_CODE_PACKET_RECEIPT_NOTIF_REQ, number);
    writeOpCode(mControlPointCharacteristic, OP_CODE_PACKET_RECEIPT_NOTIF_REQ);

    // Read response
    List<int>? response = await readNotificationResponse(mControlPointCharacteristic); // TODO check
    final int status = getStatusCode(response, OP_CODE_PACKET_RECEIPT_NOTIF_REQ_KEY);
    if (status == EXTENDED_ERROR)
      throw new Exception("Sending the number of packets failed ${response}");
    if (status != DFU_STATUS_SUCCESS)
      throw new Exception("Sending the number of packets failed ${status}");
  }

}

///////////////////////////////////////////////////////////

class ObjectInfo extends ObjectChecksum {
  late int maxSize;
}

class ObjectChecksum {
  late int offset;
  late int CRC32;
}