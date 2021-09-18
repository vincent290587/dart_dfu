
This package allows you to do a secure Device Firmware Update (DFU) nRF52 chip from Nordic Semiconductor.  
It is only compatible with the recent SDKs (Version > 14.0, tested up to 17.2), using the secure implementation without bond sharing.

## Features

- Secure firmware updates,
- BLE library agnostic,
- Almost NO dependency,
- Robust to packet loss,

## Getting started

First, put your device in bootloader mode by writing a 0x01 to its DFU control characteristic.  
After that, use the following code to scan, connect and update your device.

## Usage

```dart

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:modern_dfu/SecureDfuImpl.dart';
import 'package:skommander/util/constants.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;

Uuid DFU_UUID = Uuid.parse(dfuServiceUUID);
Uuid DFU_BTNLSS_RX = Uuid.parse(dfuCharUUID);
Uuid DFU_CHAR_CTL = Uuid.parse(dfuCtlUUID);
Uuid DFU_CHAR_DTA = Uuid.parse(dfuPcktUUID);

class DfuSupport2 {

  final flutterReactiveBle = FlutterReactiveBle();
  Stream<ConnectionStateUpdate>? _currentConnectionStream;
  StreamSubscription<ConnectionStateUpdate>? _connection;
  DiscoveredDevice? mDevice;

  CharWrapper? dfuCTL;
  CharWrapper? dfuPCKT;

  Future<void> startDfu() async {

    StreamSubscription<DiscoveredDevice>? scanStream = null;
    scanStream = flutterReactiveBle.scanForDevices(
      scanMode: ScanMode.lowLatency,
      withServices: [],
    ).listen((device) {

      debugPrint("Scanned : " + device.name);
      if (device.name == 'DfuTarg') {
        scanStream?.cancel();
        _currentConnectionStream = flutterReactiveBle.connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: {
            DFU_UUID: [DFU_CHAR_CTL, DFU_CHAR_DTA],
          },
          connectionTimeout: const Duration(seconds: 6),
        );
        _connection = _currentConnectionStream?.listen((event) {
          var id = event.deviceId.toString();
          switch (event.connectionState) {
            case DeviceConnectionState.connecting:
              {
                debugPrint("Connecting to $id\n");
                break;
              }
            case DeviceConnectionState.connected:
              {
                debugPrint("Connected to $id\n");
                mDevice = device;
                _handleDevice();
                break;
              }
            case DeviceConnectionState.disconnecting:
              {
                debugPrint("Disconnecting from $id\n");
                break;
              }
            case DeviceConnectionState.disconnected:
              {
                debugPrint("Disconnected from $id\n");
                break;
              }
          }
        });
      }

    });
  }

  Future<void> _handleDevice() async {

    List<DiscoveredService> services = await flutterReactiveBle.discoverServices(mDevice!.id);

    int mtu = await flutterReactiveBle.requestMtu(deviceId: mDevice!.id, mtu: 247);
    mtu = (mtu - 3) & 0xFC; // !!! IMPORTANT: multiple of 4 for nrf_fstorage_write !!!

    debugPrint("DiscoveredService $services ");
    for (var element in services) {

      String shortUUID = element.serviceId.toString();
      if (shortUUID.length > 4) {
        shortUUID = element.serviceId.toString().substring(4, 8);
      }
      if (dfuServiceUUID.substring(4, 8) == shortUUID) {

        for (var char in element.characteristicIds) {
          shortUUID = char.toString();
          if (shortUUID.length > 4) {
            shortUUID = shortUUID.substring(4, 8);
          }
          if (dfuCtlUUID.substring(4, 8) == shortUUID) {

            debugPrint("dfuCTL found");
            var ctlChar = QualifiedCharacteristic(
              serviceId: element.serviceId,
              characteristicId: char,
              deviceId: mDevice!.id,
            );
            Stream<List<int>> receivedDataStream = flutterReactiveBle.subscribeToCharacteristic(ctlChar);
            // receivedDataStream.listen((event) {
            //   debugPrint("RECV CTL ${event}");
            // });
            dfuCTL = CharWrapper(
                receivedDataStream,
                char: ctlChar,
                MTU: mtu
            );

            await Future.delayed(Duration(milliseconds: 200));

          } else
          if (dfuPcktUUID.substring(4, 8) == shortUUID) {

            debugPrint("dfuPCKT found");
            dfuPCKT = CharWrapper(
                null,
                char: QualifiedCharacteristic(
                  serviceId: element.serviceId,
                  characteristicId: char,
                  deviceId: mDevice!.id,
                ),
                MTU: mtu
            );

            await Future.delayed(Duration(milliseconds: 200));
          }
        }
      }
    }

    await Future.delayed(Duration(milliseconds: 2000));

    if (dfuCTL != null && dfuPCKT != null) {

      debugPrint("Configuring DFU...");
      SecureDfuImpl dfuImpl = SecureDfuImpl(
        null,
        mControlPointCharacteristic: dfuCTL!,
        mPacketCharacteristic: dfuPCKT!,
      );

      ByteData initPack = await rootBundle.load('assets/Firmware.dat');
      Uint8List initContent = initPack.buffer.asUint8List();

      ByteData fwPack = await rootBundle.load('assets/Firmware.bin');
      Uint8List fwContent = fwPack.buffer.asUint8List();

      //await Future.delayed(Duration(seconds: 15));

      debugPrint("Starting DFU...");
      int ret = await dfuImpl.startDfu(initContent, fwContent);
      debugPrint("DFU ret=$ret");

      // disconnect
      await _connection?.cancel();
    }
  }

}

class CharWrapper implements UserCharacteristic {

  final flutterReactiveBle = FlutterReactiveBle();

  final int MTU;
  final QualifiedCharacteristic char;
  late Stream<List<int>>? receivedDataStream;
  Queue<List<int>> packets = Queue<List<int>>();

  CharWrapper(this.receivedDataStream, {required this.char, required this.MTU}) {

    // receivedDataStream = flutterReactiveBle.subscribeToCharacteristic(char);
    receivedDataStream?.listen((event) {
      debugPrint("RECV ${char.characteristicId.toString()} ${event}");
      packets.addFirst(event);
    });

  }

  Future<void> _atomicWrites(List<int> data) async {

    packets.clear();

    if (data.length <= MTU) {
      return flutterReactiveBle.writeCharacteristicWithResponse(char, value: data);
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

      bytesSent += toSend.length;

      if (bytesSent >= data.length) {
        return flutterReactiveBle.writeCharacteristicWithoutResponse(char, value: toSend);
      }

      // sending toSend
      await flutterReactiveBle.writeCharacteristicWithoutResponse(char, value: toSend);
    }
  }

  @override
  Future<List<int>> getResponse(int timeout_ms) async {
    //debugPrint("getResponse start $timeout_ms");
    int curTimeout = 0;
    while (packets.isEmpty) {
      await Future.delayed(Duration(milliseconds: 25));
      curTimeout += 25;
      if (curTimeout >= timeout_ms) {
        debugPrint("getResponse timeout");
        return [];
      }
    }
    return packets.single;
  }

  @override
  Future<void> writeData(List<int> data) {
    if (data.length < 10) {
      debugPrint("Writing ${data} to ${char.characteristicId.toString()} char.");
    } else {
      debugPrint("Writing ${data.length} bytes to ${char.characteristicId.toString()} char.");
    }
    return _atomicWrites(data);
  }

}

```

