import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_dfu/SecureDfuImpl.dart';
import 'package:modern_dfu/constants.dart';

import 'package:modern_dfu/utils.dart';

class FakeCharacteristic implements UserCharacteristic {

  final int MTU;
  final String name;
  final StreamController<List<int>> controller = new StreamController<List<int>>.broadcast();

  int counter = 0;

  FakeCharacteristic({required this.name, required this.MTU});

  Future<void> _atomicWrites(List<int> data) async {

    if (data.length <= MTU) {
      counter += data.length;
      return;
    }

    int index = 0;
    int bytesSent = 0;
    while (bytesSent < data.length) {

      int length = MTU;
      if (index + MTU > data.length) {
        length = data.length - index;
      }
      List<int> toSend = data.sublist(index, index + length);
      index += length;

      // sending toSend

      bytesSent += toSend.length;
      counter += toSend.length;
    }
  }

  @override
  Future<void> writeData(List<int> data) async {

    if (data.length < 10) {

      debugPrint("Writing ${data} to ${name} char.");
    } else {

      debugPrint("Writing ${data.length} bytes to ${name} char.");
    }

    Future.delayed(Duration(milliseconds: 50)).then((value) {

      if (data.length == 0) {
        debugPrint("!! Zero length data !!");
      } else if (data.length == 2 && data[0] == 6) {

        List<int> rsp = [ OP_CODE_RESPONSE_CODE_KEY, data[0], DFU_STATUS_SUCCESS, 0, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        controller.add(rsp);
      } else {

        List<int> rsp = [ OP_CODE_RESPONSE_CODE_KEY, data[0], DFU_STATUS_SUCCESS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
        controller.add(rsp);
      }
    });

    return _atomicWrites(data);
  }

  @override
  Future<List<int>> getResponse(int timeout_ms) {
    //controller.stream.drain();
    // return controller.stream.first;
    Future<List<int>> ret = controller.stream.first.timeout(
      Duration(milliseconds: timeout_ms),
      onTimeout : () => [],
    );
    return ret;
  }

}

class RetryTest {

  int nbRetries = 0;

  Future<ObjectResponse> getResponse() {
    nbRetries++;
    debugPrint("Retrying... count=$nbRetries");
    // return Future.value(ObjectResponse(null, success: false));
    return Future.delayed(Duration(milliseconds: 10), () => ObjectResponse(null, success: false));
  }
}

void main() {
  test('Utils', () async {
    List<int> array = [10, 0, 0, 0];
    expect(unsignedBytesToInt(array, 0), 10);
  });
  test('Retries', () async {
    RetryTest rTest = RetryTest();
    ObjectResponse resp = await retryBlock(3, () => rTest.getResponse());
    expect(resp.success, false);
    expect(rTest.nbRetries, 3);
  });
  test('ObjectInfo', () async {
    List<int> array = [0x60, 0x06, 0x01, 0, 0x02, 0, 0, 0, 0x03, 0, 0, 0, 0, 0, 0, 0];
    ObjectInfo info = new ObjectInfo();
    info.maxSize = unsignedBytesToInt(array, 3);
    info.offset = unsignedBytesToInt(array, 3 + 4);
    info.CRC32  = unsignedBytesToInt(array, 3 + 8);

    expect(info.maxSize, 512);
    expect(info.offset, 768);
  });
  test('Full DFU', () async {

    final FakeCharacteristic controlChar = FakeCharacteristic(
      MTU: 20,
      name: 'controlChar',
    );
    final FakeCharacteristic packetChar = FakeCharacteristic(
      MTU: 20,
      name: 'packetChar',
    );

    SecureDfuImpl dfuImpl = SecureDfuImpl(
      mControlPointCharacteristic: controlChar,
      mPacketCharacteristic: packetChar,
    );

    Uint8List initContent = Uint8List.fromList([ 1, 2, 3, 4, 5, 6]);
    Uint8List fwContent = Uint8List.fromList(List<int>.filled(44*1024, 255));

    await dfuImpl.startDfu(initContent, fwContent);

    expect(packetChar.counter, initContent.length + fwContent.length);
  });
}
