// This is the same worker entry point used by the package setup command.
// Direct dart2js compilation avoids webdev subprocess failures on Windows.
import 'package:sqflite_common_ffi_web/src/sw/shared_worker.dart';

void main(List<String> args) => mainSharedWorker(args);
