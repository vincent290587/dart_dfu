library dart_dfu;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import 'utils.dart';
import 'constants.dart';

///////////////////////////////////////////////////////////

abstract class UserCharacteristic {

  Future<void> writeData(List<int> data);

  Future<List<int>> getResponse(int timeout_ms);

}

///////////////////////////////////////////////////////////

class SecureDfuImpl {

  final UserCharacteristic mPacketCharacteristic;
  final UserCharacteristic mControlPointCharacteristic;

  final StreamController<String>? mController;
  String currentText = '';

  SecureDfuImpl(this.mController, {required this.mPacketCharacteristic, required this.mControlPointCharacteristic});

  Future<int> startDfu(Uint8List initContent, Uint8List fwContent) async {

    int ret;

    ret = await sendInitPacket(initContent);
    if (ret != 0) return ret;

    await Future.delayed(Duration(milliseconds: 200));

    ret = await sendFirmware(fwContent);

    return ret;
  }

  void _controllerSet(String text) {

    currentText = text;
    mController?.add(text);
  }

  void _controllerAppend(String text) {

    currentText += text;
    mController?.add(text);
  }

  Future<int> sendInitPacket(Uint8List initContent) async {

    _controllerSet('Sending init packet...');

    debugPrint("Setting object to Command (Op Code = 6, Type = 1)");
    ObjectResponse status = await retryBlock(3, () => selectObject(OBJECT_COMMAND));
    if (status.success == false) {
      return 1;
    }
    final ObjectInfo info = status.payload;
    debugPrint("Command object info received (Max size = ${info.maxSize}, Offset = ${info.offset}, CRC = ${info.CRC32})");

    // Create the Init object
    debugPrint("Creating Init packet object (Op Code = 1, Type = 1, Size = ${initContent.length})");
    status = await retryBlock(3, () => writeCreateRequest(OBJECT_COMMAND, initContent.length));
    if (status.success == false) {
      return 2;
    }
    debugPrint("Command object created");

    status = await retryBlock(3, () => setPacketReceiptNotifications(0));
    if (status.success == false) {
      return 3;
    }
    debugPrint("Packet Receipt Notif disabled (Op Code = 2, Value = 0)");

    List<int> buffer = List<int>.from(initContent); // TODO check

    await writeData(mPacketCharacteristic, buffer, 0);

    // Calculate Checksum
    debugPrint("Sending Calculate Checksum command (Op Code = 3)");
    status = await retryBlock(3, () => readChecksum());
    if (status.success == false) {
      return 4;
    }
    ObjectChecksum checksum = status.payload;
    debugPrint("Checksum received (Offset = ${checksum.offset}, CRC = ${checksum.CRC32})");

    int crc32 = CRC32.compute(buffer);

    if (checksum.offset == buffer.length &&
        crc32 == checksum.CRC32) {

      debugPrint("Length do match: ${checksum.offset} / ${buffer.length}");
      debugPrint("Checksum match ${crc32} / ${checksum.CRC32}");

      debugPrint("Executing init packet (Op Code = 4)");
      status = await retryBlock(3, () => writeExecute());
      if (status.success == false) {
        return 5;
      }

    } else {

      debugPrint("Length DON'T match: ${checksum.offset} / ${buffer.length}");
      debugPrint("Checksum DON'T match ${crc32} / ${checksum.CRC32}");
      return 10;

    }

    _controllerAppend('Init packet success');

    return 0;
  }

  Future<int> sendFirmware(Uint8List firmwareFile) async {

    _controllerAppend('Sending firmware...');

    // notif every 12 packets
    int notifs = 0; // don't need those
    ObjectResponse status = await retryBlock(3, () => setPacketReceiptNotifications(notifs));
    if (status.success == false) {
      return 1;
    }
    debugPrint("Packet Receipt Notif Req (Op Code = 2) sent (Value = ${notifs})");

    debugPrint("Setting object to Data (Op Code = 6, Type = 2)");
    status = await retryBlock(3, () => selectObject(OBJECT_DATA));
    if (status.success == false) {
      return 2;
    }
    ObjectInfo info = status.payload;
    debugPrint("Command object info received (Max size = ${info.maxSize}, Offset = ${info.offset}, CRC = ${info.CRC32})");

    int availableObjectSizeInBytes = info.maxSize;
    final int chunkCount = ((firmwareFile.length + info.maxSize - 1).toDouble() / info.maxSize).toInt();
    int currentChunk = 0;

    List<int> totBuffer = List<int>.from(firmwareFile);

    int nbRetries = 0;
    int curIndex = 0;
    int validatedIndex = 0;
    while (totBuffer.length > 0) {

      await Future.delayed(Duration(milliseconds: 400));

      // nRF refuses that with error invalid param
      // if (nbRetries >= 2) {
      //   // desperately try smaller chunks
      //   availableObjectSizeInBytes = info.maxSize >> 1;
      // }else if (nbRetries >= 4) {
      //   // desperately try even smaller chunks
      //   availableObjectSizeInBytes = info.maxSize >> 2;
      // }

      List<int> buffer = [];
      if (totBuffer.length >= availableObjectSizeInBytes) {
        buffer = totBuffer.sublist(0, availableObjectSizeInBytes);
      } else {
        buffer = totBuffer;
      }
      if (buffer.length < availableObjectSizeInBytes) {
        availableObjectSizeInBytes = buffer.length;
      }
      debugPrint(
          "Creating Data object (Op Code = 1, Type = 2, Size = ${availableObjectSizeInBytes}) (${currentChunk +
              1}/${chunkCount})");
      _controllerSet('Sending chunk ${availableObjectSizeInBytes}) (${currentChunk + 1}/${chunkCount})');
      status = await retryBlock(3, () => writeCreateRequest(OBJECT_DATA, availableObjectSizeInBytes));
      if (status.success == false) {
        return 3;
      }
      debugPrint("Data object (${currentChunk + 1}/${chunkCount}) created");

      await Future.delayed(Duration(milliseconds: 200));

      debugPrint("Uploading firmware...");
      await writeData(mPacketCharacteristic, buffer, 0);

      // Calculate Checksum
      debugPrint("Sending Calculate Checksum command (Op Code = 3)");
      status = await retryBlock(3, () => readChecksum());
      if (status.success == false) {
        return 4;
      }
      ObjectChecksum checksum = status.payload;
      debugPrint("Checksum received (Offset = ${checksum.offset}, CRC = ${checksum.CRC32})");

      int crc32 = CRC32.compute(firmwareFile.sublist(0, checksum.offset));
      curIndex = validatedIndex + buffer.length;

      if ( checksum.offset == curIndex && crc32 == checksum.CRC32) {

        debugPrint("Length do match: ${checksum.offset} / ${curIndex}");
        debugPrint("Checksum match ${crc32} / ${checksum.CRC32}");

        debugPrint("Executing FW packet (Op Code = 4)");
        status = await retryBlock(5, () => writeExecute());
        if (status.success == false) {
          debugPrint("Execution failed");
          _controllerAppend('Execution failed');
          return 5;
        }

        if (totBuffer.length >= info.maxSize) {
          totBuffer = totBuffer.sublist(info.maxSize);
        } else {
          totBuffer = [];
        }
        currentChunk++;
        validatedIndex += buffer.length;
        nbRetries = 0;
      } else {

        nbRetries++;
        debugPrint("Length DON'T match: ${checksum.offset} / ${curIndex}");
        debugPrint("Checksum DON'T match ${crc32} / ${checksum.CRC32}");

        if (nbRetries < 6) {
          _controllerAppend('CRC fail, retrying chunk...');
          await Future.delayed(Duration(milliseconds: 300));
        } else {
          _controllerAppend('Error: out of retries');
          return 6;
        }
      }
    }

    _controllerAppend('Firmware sent !');

    return 0;
  }

  Future<ObjectResponse> selectObject(int type) async {

    List<int> opCode = List.from(OP_CODE_SELECT_OBJECT);
    opCode[1] = type;
    await writeOpCode(mControlPointCharacteristic, opCode);

    List<int> response = await readNotificationResponse(mControlPointCharacteristic);
    final ObjectResponse status = getStatusCode(response, OP_CODE_SELECT_OBJECT_KEY);
    if (status.success == false) {
      debugPrint("getStatusCode failed");
      return ObjectResponse(null, success: false);
    }
    if (status.payload == EXTENDED_ERROR) {
      debugPrint("Sending the number of packets failed ${response}");
      return ObjectResponse(null, success: false);
    }
    if (status.payload != DFU_STATUS_SUCCESS) {
      debugPrint("Sending the number of packets failed ${status}");
      return ObjectResponse(null, success: false);
    }

    final ObjectInfo info = new ObjectInfo();
    info.maxSize = unsignedBytesToInt(response, 3);
    info.offset = unsignedBytesToInt(response, 3 + 4);
    info.CRC32  = unsignedBytesToInt(response, 3 + 8);
    return ObjectResponse(info, success: true);
  }

  Future<void> writeOpCode(UserCharacteristic char, List<int> opCode) {
    return char.writeData(opCode);
  }

  Future<List<int>> readNotificationResponse(UserCharacteristic char) {
    return char.getResponse(8000);
  }

  Future<ObjectResponse> writeExecute() async {

    writeOpCode(mControlPointCharacteristic, OP_CODE_EXECUTE);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic);
    final ObjectResponse status = getStatusCode(response, OP_CODE_EXECUTE_KEY);
    if (status.success == false) {
      debugPrint("getStatusCode failed");
      return ObjectResponse(null, success: false);
    }
    if (status.payload == EXTENDED_ERROR) {
      _controllerAppend('EXTENDED_ERROR ${response.last}');
      debugPrint("Sending the number of packets failed ${response}");
      return ObjectResponse(null, success: false);
    }
    if (status.payload != DFU_STATUS_SUCCESS) {
      debugPrint("Sending the number of packets failed ${status}");
      return ObjectResponse(null, success: false);
    }

    return ObjectResponse(null, success: true);
  }

  Future<ObjectResponse> writeCreateRequest(final int type, final int size) async {

    List<int> data = List.from((type == OBJECT_COMMAND) ? OP_CODE_CREATE_COMMAND : OP_CODE_CREATE_DATA);
    setObjectSize(data, size);
    writeOpCode(mControlPointCharacteristic, data);

    List<int>? response = await readNotificationResponse(mControlPointCharacteristic);
    final ObjectResponse status = getStatusCode(response, OP_CODE_CREATE_KEY);
    if (status.success == false) {
      debugPrint("getStatusCode failed");
      return ObjectResponse(null, success: false);
    }
    if (status.payload == EXTENDED_ERROR) {
      debugPrint("Sending the number of packets failed ${response}");
      return ObjectResponse(null, success: false);
    }
    if (status.payload != DFU_STATUS_SUCCESS) {
      debugPrint("Sending the number of packets failed ${status}");
      return ObjectResponse(null, success: false);
    }

    return ObjectResponse(null, success: true);
  }

  Future<void> writeData(UserCharacteristic char, List<int> buffer, int crc32) {
    return char.writeData(buffer);
  }

  Future<ObjectResponse> readChecksum() async {

    writeOpCode(mControlPointCharacteristic, OP_CODE_CALCULATE_CHECKSUM);

    List<int> response = await readNotificationResponse(mControlPointCharacteristic);
    final ObjectResponse status = getStatusCode(response, OP_CODE_CALCULATE_CHECKSUM_KEY);
    if (status.success == false) {
      debugPrint("getStatusCode failed");
      return ObjectResponse(null, success: false);
    }
    if (status.payload == EXTENDED_ERROR) {
      debugPrint("Sending the number of packets failed ${response}");
      return ObjectResponse(null, success: false);
    }
    if (status.payload != DFU_STATUS_SUCCESS) {
      debugPrint("Sending the number of packets failed ${status}");
      return ObjectResponse(null, success: false);
    }

    final ObjectChecksum checksum = new ObjectChecksum();
    checksum.offset = unsignedBytesToInt(response, 3);
    checksum.CRC32  = unsignedBytesToInt(response, 3 + 4);
    return ObjectResponse(checksum, success: true);
  }

  ObjectResponse getStatusCode(List<int> response, int request) {
    if (response == null || response.length < 3 || response[0] != OP_CODE_RESPONSE_CODE_KEY || response[1] != request ||
        (response[2] != DFU_STATUS_SUCCESS &&
        response[2] != OP_CODE_NOT_SUPPORTED &&
        response[2] != INVALID_PARAM &&
        response[2] != INSUFFICIENT_RESOURCES &&
        response[2] != INVALID_OBJECT &&
        response[2] != UNSUPPORTED_TYPE &&
        response[2] != OPERATION_NOT_PERMITTED &&
        response[2] != OPERATION_FAILED &&
        response[2] != EXTENDED_ERROR)) {

      debugPrint("Invalid response received, ${response} ${request}");
      return ObjectResponse(null, success: false);
    }
    return ObjectResponse(response[2], success: true);
  }

  Future<ObjectResponse> setPacketReceiptNotifications(final int number) async {

    // Send the number of packets of firmware before receiving a receipt notification
    List<int> data = List.from(OP_CODE_PACKET_RECEIPT_NOTIF_REQ);
    debugPrint("Sending the number of packets before notifications (Op Code = 2, Value = ${number}");
    setNumberOfPackets(data, number);
    writeOpCode(mControlPointCharacteristic, data);

    // Read response
    List<int> response = await readNotificationResponse(mControlPointCharacteristic); // TODO check
    final ObjectResponse status = getStatusCode(response, OP_CODE_PACKET_RECEIPT_NOTIF_REQ_KEY);
    if (status.success == false) {
      debugPrint("getStatusCode failed");
      return ObjectResponse(null, success: false);
    }
    if (status.payload == EXTENDED_ERROR) {
      debugPrint("Sending the number of packets failed ${response}");
      return ObjectResponse(null, success: false);
    }
    if (status.payload != DFU_STATUS_SUCCESS) {
      debugPrint("Sending the number of packets failed ${status}");
      return ObjectResponse(null, success: false);
    }

    return ObjectResponse(status, success: true);
  }

}

///////////////////////////////////////////////////////////

class ObjectResponse {

  bool success;
  dynamic payload;

  ObjectResponse(this.payload, {required this.success});
}

class ObjectInfo extends ObjectChecksum {
  late int maxSize;
}

class ObjectChecksum {
  late int offset;
  late int CRC32;
}