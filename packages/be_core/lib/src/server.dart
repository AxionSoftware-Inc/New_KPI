import 'dart:convert';
import 'dart:io';
import 'protocol.dart';
import 'store.dart';

/// Har bir dastur uchun standart HTTP API server
class StandardAppServer {
  StandardAppServer({
    required this.schema,
    required this.store,
    this.apiKey,
  });

  final AppSchema schema;
  final StandardStore store;
  final String? apiKey;
  HttpServer? _server;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, schema.port);
    stdout.writeln('🚀 [${schema.app.toUpperCase()}] API server ishga tushdi: http://localhost:${schema.port}');

    _server!.listen((HttpRequest request) async {
      final response = request.response;

      // CORS va JSON headers
      response.headers.add('Access-Control-Allow-Origin', '*');
      response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      response.headers.add('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-API-KEY');
      response.headers.contentType = ContentType.json;

      if (request.method == 'OPTIONS') {
        response.statusCode = HttpStatus.ok;
        await response.close();
        return;
      }

      final path = request.uri.path;

      // Xavfsizlik: agar apiKey kiritilgan bo'lsa, /execute va /export tekshiriladi
      if (apiKey != null && apiKey!.isNotEmpty && path != '/health' && path != '/schema') {
        final authHeader = request.headers.value('authorization');
        final keyHeader = request.headers.value('x-api-key');
        final bearerMatch = RegExp(r'^Bearer\s+(.*)$', caseSensitive: false).firstMatch(authHeader ?? '');
        final token = bearerMatch?.group(1) ?? keyHeader;

        if (token != apiKey) {
          response.statusCode = HttpStatus.unauthorized;
          response.write(jsonEncode(ToolResult.err(
            error: "Avtorizatsiya xatosi: API-Key noto'g'ri yoki kiritilmadi.",
            code: 'UNAUTHORIZED',
          ).toJson()));
          await response.close();
          return;
        }
      }

      try {
        // 1. GET /schema -> Barcha funksiyalar va parametrlar
        if (request.method == 'GET' && path == '/schema') {
          response.statusCode = HttpStatus.ok;
          response.write(jsonEncode(schema.toJson()));
        }
        // 2. GET /health -> Server holati
        else if (request.method == 'GET' && path == '/health') {
          response.statusCode = HttpStatus.ok;
          response.write(jsonEncode({
            'status': 'ok',
            'app': schema.app,
            'port': schema.port,
            'total_items': store.all.length,
          }));
        }
        // 3. GET /export -> Barcha ma'lumotlar eksporti
        else if (request.method == 'GET' && path == '/export') {
          response.statusCode = HttpStatus.ok;
          response.write(jsonEncode(store.all.map((e) => e.toJson()).toList()));
        }
        // 4. POST /execute -> Funksiya (tool) bajarish
        else if (request.method == 'POST' && (path == '/execute' || path == '/call')) {
          final bodyStr = await utf8.decoder.bind(request).join();
          Map<String, dynamic> body = {};
          if (bodyStr.trim().isNotEmpty) {
            body = jsonDecode(bodyStr) as Map<String, dynamic>;
          }

          final actionName = (body['action'] ?? body['tool']) as String?;
          final params = Map<String, dynamic>.from(body['params'] ?? body['args'] ?? {});

          if (actionName == null || actionName.isEmpty) {
            response.statusCode = HttpStatus.badRequest;
            response.write(jsonEncode(ToolResult.err(
              error: "'action' yoki 'tool' nomi ko'rsatilmadi.",
              code: 'INVALID_REQUEST',
            ).toJson()));
          } else {
            final tool = schema.tools.where((t) => t.name == actionName).firstOrNull;
            if (tool == null) {
              response.statusCode = HttpStatus.notFound;
              response.write(jsonEncode(ToolResult.err(
                action: actionName,
                error: "'$actionName' funksiyasi [${schema.app}] dasturida mavjud emas.",
                code: 'TOOL_NOT_FOUND',
              ).toJson()));
            } else {
              final result = await tool.handler(params);
              response.statusCode = result.success ? HttpStatus.ok : HttpStatus.badRequest;
              response.write(jsonEncode(result.toJson()));
            }
          }
        } else {
          response.statusCode = HttpStatus.notFound;
          response.write(jsonEncode({
            'error': "Bunday endpoint mavjud emas: $path",
            'available': ['/schema', '/execute', '/export', '/health'],
          }));
        }
      } catch (e, st) {
        response.statusCode = HttpStatus.internalServerError;
        response.write(jsonEncode(ToolResult.err(
          error: "Ichki xatolik: $e",
          code: 'INTERNAL_ERROR',
        ).toJson()));
        stderr.writeln("Server xatosi: $e\n$st");
      }

      await response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close(force: true);
  }
}
