
final int DFU_STATUS_SUCCESS = 1;
final int MAX_ATTEMPTS = 3;

// Object types
final int OBJECT_COMMAND = 0x01;
final int OBJECT_DATA = 0x02;
// Operation codes and packets
final int OP_CODE_CREATE_KEY = 0x01;
final int OP_CODE_PACKET_RECEIPT_NOTIF_REQ_KEY = 0x02;
final int OP_CODE_CALCULATE_CHECKSUM_KEY = 0x03;
final int OP_CODE_EXECUTE_KEY = 0x04;
final int OP_CODE_SELECT_OBJECT_KEY = 0x06;
final int OP_CODE_RESPONSE_CODE_KEY = 0x60;
final List<int> OP_CODE_CREATE_COMMAND = [OP_CODE_CREATE_KEY, OBJECT_COMMAND, 0x00, 0x00, 0x00, 0x00];
final List<int> OP_CODE_CREATE_DATA = [OP_CODE_CREATE_KEY, OBJECT_DATA, 0x00, 0x00, 0x00, 0x00];
final List<int> OP_CODE_PACKET_RECEIPT_NOTIF_REQ = [OP_CODE_PACKET_RECEIPT_NOTIF_REQ_KEY, 0x00, 0x00 /* param PRN uint16 in Little Endian */];
final List<int> OP_CODE_CALCULATE_CHECKSUM = [OP_CODE_CALCULATE_CHECKSUM_KEY];
final List<int> OP_CODE_EXECUTE = [OP_CODE_EXECUTE_KEY];
final List<int> OP_CODE_SELECT_OBJECT = [OP_CODE_SELECT_OBJECT_KEY, 0x00 /* type */];


// class SecureDfuError {
//   // DFU status values
//   // SUCCESS = 1; // that's not an error
final int OP_CODE_NOT_SUPPORTED = 2;
final int INVALID_PARAM = 3;
final int INSUFFICIENT_RESOURCES = 4;
final int INVALID_OBJECT = 5;
final int UNSUPPORTED_TYPE = 7;
final int OPERATION_NOT_PERMITTED = 8;
final int OPERATION_FAILED = 10; // 0xA
final int EXTENDED_ERROR = 11; // 0xB
//
//   // EXT_ERROR_NO_ERROR = 0x00; // that's not an error
//   final int EXT_ERROR_WRONG_COMMAND_FORMAT = 0x02;
//   final int EXT_ERROR_UNKNOWN_COMMAND = 0x03;
//   final int EXT_ERROR_INIT_COMMAND_INVALID = 0x04;
//   final int EXT_ERROR_FW_VERSION_FAILURE = 0x05;
//   final int EXT_ERROR_HW_VERSION_FAILURE = 0x06;
//   final int EXT_ERROR_SD_VERSION_FAILURE = 0x07;
//   final int EXT_ERROR_SIGNATURE_MISSING = 0x08;
//   final int EXT_ERROR_WRONG_HASH_TYPE = 0x09;
//   final int EXT_ERROR_HASH_FAILED = 0x0A;
//   final int EXT_ERROR_WRONG_SIGNATURE_TYPE = 0x0B;
//   final int EXT_ERROR_VERIFICATION_FAILED = 0x0C;
//   final int EXT_ERROR_INSUFFICIENT_SPACE = 0x0D;
//
//   // BUTTONLESS_SUCCESS = 1;
//   final int BUTTONLESS_ERROR_OP_CODE_NOT_SUPPORTED = 2;
//   final int BUTTONLESS_ERROR_OPERATION_FAILED = 4;
//
// }