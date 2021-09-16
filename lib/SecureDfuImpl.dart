
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:modern_dfu/utils.dart';

import 'constants.dart';

///////////////////////////////////////////////////////////

abstract class UserCharacteristic {

  Future<void> writeData(List<int> data);

  Future<List<int>> getResponse(int timeout_ms);

  //Stream<List<int>> getStream();
}

///////////////////////////////////////////////////////////

class SecureDfuImpl {

  final UserCharacteristic mPacketCharacteristic;
  final UserCharacteristic mControlPointCharacteristic;

  SecureDfuImpl({required this.mPacketCharacteristic, required this.mControlPointCharacteristic});

  Future<int> startDfu() async {

    int ret;

    File mInitPacketStream = File('data/bin');
    Uint8List initContent = mInitPacketStream.readAsBytesSync();

    ret = await sendInitPacket(initContent);

    File mFirmwareStream = File('firmware');
    Uint8List fwContent = mFirmwareStream.readAsBytesSync();

    ret = await sendFirmware(fwContent);

    return ret;
  }

  Future<int> sendInitPacket(Uint8List initContent) async {

    debugPrint("Setting object to Command (Op Code = 6, Type = 1)");
    final ObjectInfo info = await selectObject(OBJECT_COMMAND);
    debugPrint("Command object info received (Max size = ${info.maxSize}, Offset = ${info.offset}, CRC = ${info.CRC32})");

    // Create the Init object
    debugPrint("Creating Init packet object (Op Code = 1, Type = 1, Size = ${initContent.length})");
    await writeCreateRequest(OBJECT_COMMAND, initContent.length);
    debugPrint("Command object created");

    await setPacketReceiptNotifications(0);
    debugPrint("Packet Receipt Notif disabled (Op Code = 2, Value = 0)");

    List<int> buffer = initContent.sublist(0, info.maxSize); // TODO check

    // Calculate the CRC32
    final int crc = CRC32.compute(initContent);

    await writeData(mPacketCharacteristic, buffer, crc);

    // Calculate Checksum
    debugPrint("Sending Calculate Checksum command (Op Code = 3)");
    ObjectChecksum checksum = await readChecksum();
    debugPrint("Checksum received (Offset = ${checksum.offset}, CRC = ${checksum.CRC32})");

    debugPrint("Executing init packet (Op Code = 4)");
    await writeExecute();

    return 0;
  }

  Future<int> sendFirmware(Uint8List firmwareFile) async {

    // notif every 12 packets
    int notifs = 12;
    setPacketReceiptNotifications(notifs);
    debugPrint("Packet Receipt Notif Req (Op Code = 2) sent (Value = ${notifs})");

    debugPrint("Setting object to Data (Op Code = 6, Type = 2)");
    ObjectInfo info = await selectObject(OBJECT_DATA);
    debugPrint("Command object info received (Max size = ${info.maxSize}, Offset = ${info.offset}, CRC = ${info.CRC32})");

    int availableObjectSizeInBytes = info.maxSize;
    final int chunkCount = ((firmwareFile.length + info.maxSize - 1).toDouble() / info.maxSize).toInt();
    int currentChunk = 0;

    List<int> buffer = firmwareFile.sublist(0, info.offset);

    //

    await Future.delayed(Duration(milliseconds: 400));

    debugPrint("Creating Data object (Op Code = 1, Type = 2, Size = ${availableObjectSizeInBytes}) (${currentChunk + 1}/${chunkCount})");
    writeCreateRequest(OBJECT_DATA, availableObjectSizeInBytes);
    debugPrint("Data object (${currentChunk + 1}/${chunkCount}) created");

    debugPrint("Uploading firmware...");
    await writeData(mPacketCharacteristic, buffer, 0);

    // Calculate Checksum
    debugPrint("Sending Calculate Checksum command (Op Code = 3)");
    ObjectChecksum checksum = await readChecksum();
    debugPrint("Checksum received (Offset = ${checksum.offset}, CRC = ${checksum.CRC32})");

    debugPrint("Executing FW packet (Op Code = 4)");
    await writeExecute();

    //

    await writeExecute();

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
    await char.writeData(opCode);
  }

  Future<List<int>?> readNotificationResponse(UserCharacteristic char) async {
    await char.getResponse(1000);
  }

  Future<void> writeExecute() async {

    writeOpCode(mControlPointCharacteristic, OP_CODE_EXECUTE);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic); // TODO check char
    final int status = getStatusCode(response, OP_CODE_EXECUTE_KEY);
    if (status == EXTENDED_ERROR)
      throw new Exception("Executing object failed ${response}");
    if (status != DFU_STATUS_SUCCESS)
      throw new Exception("Executing object failed ${status}");
  }

  Future<void>  writeCreateRequest(final int type, final int size) async {

    List<int> data = (type == OBJECT_COMMAND) ? OP_CODE_CREATE_COMMAND : OP_CODE_CREATE_DATA;
    setObjectSize(data, size);
    writeOpCode(mControlPointCharacteristic, data);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic); // TODO check char
    final int status = getStatusCode(response, OP_CODE_CREATE_KEY);
    if (status == EXTENDED_ERROR)
      throw new Exception("Creating Command object failed ${response}");
    if (status != DFU_STATUS_SUCCESS)
      throw new Exception("Creating Command object failed ${status}");
  }

  Future<void> writeData(UserCharacteristic char, List<int> buffer, int crc32) async {
    await char.writeData(buffer);
  }

  Future<ObjectChecksum> readChecksum() async {

    writeOpCode(mControlPointCharacteristic, OP_CODE_CALCULATE_CHECKSUM);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic); // TODO check char
    final int status = getStatusCode(response, OP_CODE_CALCULATE_CHECKSUM_KEY);
    if (status == EXTENDED_ERROR)
      throw new Exception("Creating Command object failed ${response}");
    if (status != DFU_STATUS_SUCCESS)
      throw new Exception("Creating Command object failed ${status}");

    final ObjectChecksum checksum = new ObjectChecksum();
    checksum.offset = unsignedBytesToInt(response!, 3);
    checksum.CRC32  = unsignedBytesToInt(response!, 3 + 4);
    return checksum;
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
    List<int> data = List.from(OP_CODE_PACKET_RECEIPT_NOTIF_REQ);
    debugPrint("Sending the number of packets before notifications (Op Code = 2, Value = ${number}");
    setNumberOfPackets(data, number);
    writeOpCode(mControlPointCharacteristic, data);

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