import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_dfu/SecureDfuImpl.dart';

import 'package:modern_dfu/modern_dfu.dart';

class FakeCharacteristic implements UserCharacteristic {

  final String name;
  final StreamController<List<int>> controller = new StreamController<List<int>>.broadcast();

  FakeCharacteristic(this.name);

  @override
  Future<void> writeData(List<int> data) async {

    debugPrint("Writing ${data} to ${name} char.");

    await Future.delayed(Duration(milliseconds: 400));

    List<int> rsp = [ 0, 0, 0, 0, 0];
    controller.add(rsp);
  }

  @override
  Future<List<int>> getResponse(int timeout_ms) {
    return controller.stream.first;
  }

  // Stream<List<int>> getStream() {
  //   return controller.stream;
  // }

}

void main() {
  test('adds one to input values', () async {

    final FakeCharacteristic controlChar = FakeCharacteristic('controlChar');
    final FakeCharacteristic packetChar = FakeCharacteristic('packetChar');

    SecureDfuImpl dfuImpl = SecureDfuImpl(
      mControlPointCharacteristic: controlChar,
      mPacketCharacteristic: packetChar,
    );

    Uint8List initContent = Uint8List.fromList([ 1, 2, 3, 4, 5, 6]);
    Uint8List fwContent = Uint8List.fromList([ 1, 2, 3, 4, 5, 6]);

    await dfuImpl.startDfu(initContent, fwContent);

    final calculator = Calculator();
    expect(calculator.addOne(2), 3);
    expect(calculator.addOne(-7), -6);
    expect(calculator.addOne(0), 1);
  });
}
