import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_dfu/SecureDfuImpl.dart';
import 'package:modern_dfu/constants.dart';

import 'package:modern_dfu/utils.dart';

class FakeCharacteristic implements UserCharacteristic {

  final String name;
  final StreamController<List<int>> controller = new StreamController<List<int>>.broadcast();

  int counter = 0;

  FakeCharacteristic(this.name);

  @override
  Future<void> writeData(List<int> data) async {

    if (data.length < 10) {

      debugPrint("Writing ${data} to ${name} char.");
    } else {

      debugPrint("Writing ${data.length} bytes to ${name} char.");
    }

    counter += data.length;

    await Future.delayed(Duration(milliseconds: 50));

    if (data.length == 0) {
      debugPrint("!! Zero length data !!");
    } else if (data.length == 2 && data[0] == 6) {

      List<int> rsp = [ OP_CODE_RESPONSE_CODE_KEY, data[0], DFU_STATUS_SUCCESS, 0, 0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      controller.add(rsp);
    } else {

      List<int> rsp = [ OP_CODE_RESPONSE_CODE_KEY, data[0], DFU_STATUS_SUCCESS, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
      controller.add(rsp);
    }

  }

  @override
  Future<List<int>> getResponse(int timeout_ms) {
    //controller.stream.drain();
    return controller.stream.first;
  }

  // Stream<List<int>> getStream() {
  //   return controller.stream;
  // }

}

void main() {
  test('Utils', () async {
    List<int> array = [10, 0, 0, 0];
    expect(unsignedBytesToInt(array, 0), 10);
  });
  test('ObjectInfo', () async {
    List<int> array = [0x60, 0x06, 0x01, 0, 0x02, 0, 0, 0, 0x03, 0, 0, 0, 0, 0, 0, 0];
    final ObjectInfo info = new ObjectInfo();
    info.maxSize = unsignedBytesToInt(array, 3);
    info.offset = unsignedBytesToInt(array, 3 + 4);
    info.CRC32  = unsignedBytesToInt(array, 3 + 8);

    expect(info.maxSize, 512);
    expect(info.offset, 768);
  });
  test('Full DFU', () async {

    final FakeCharacteristic controlChar = FakeCharacteristic('controlChar');
    final FakeCharacteristic packetChar = FakeCharacteristic('packetChar');

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
