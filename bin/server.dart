import 'dart:io';
import 'package:be_core/be_core.dart';
import 'package:kpi_app/kpi_service.dart';

void main(List<String> args) async {
  final storagePath = args.isNotEmpty ? args[0] : '${Directory.current.path}/kpi_data.json';
  final service = await KpiService.init(storagePath);
  final server = StandardAppServer(schema: service.schema, store: service.store);
  await server.start();
}
