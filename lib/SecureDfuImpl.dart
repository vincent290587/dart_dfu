
import 'package:flutter/cupertino.dart';

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

    return 0;
  }

  Future<ObjectInfo> selectObject(int type) async {

    List<int> opCode = OP_CODE_SELECT_OBJECT;
    opCode[1] = type;
    writeOpCode(mControlPointCharacteristic, opCode);

    List<int> response = await readNotificationResponse();
    int status = getStatusCode(response, OP_CODE_SELECT_OBJECT_KEY);

    final ObjectInfo info = new ObjectInfo();
    info.maxSize = unsignedBytesToInt(response, 3);
    info.offset = unsignedBytesToInt(response, 3 + 4);
    info.CRC32  = unsignedBytesToInt(response, 3 + 8);
    return info;
  }

  Future<void> writeOpCode(UserCharacteristic char, List<int> opCode) async {
    char.writeData(opCode);
  }

  Future<List<int>> readNotificationResponse(UserCharacteristic char, List<int> opCode) async {
    await char.getResponse(1000);
  }

  int getStatusCode(List<int> response, int request) {
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
}

///////////////////////////////////////////////////////////

class ObjectInfo extends ObjectChecksum {
  late int maxSize;
}

class ObjectChecksum {
  late int offset;
  late int CRC32;
}