import 'package:file_picker_web/file_picker_web.dart';

/// Wait for the chosen file however long the browser takes to hand it over.
/// By default the plugin treats the window regaining focus as "cancelled" if
/// no file arrived within 0.5 s. On iPhone Safari the window regains focus as
/// soon as the Files sheet closes, while a PDF (above all one in iCloud
/// Drive) is still being copied, so picking a PDF did nothing. Cancelling
/// still works through the input's own `cancel` event.
const pickerWebOptions = FilePickerWebOptions(cancelUploadOnWindowBlur: false);
