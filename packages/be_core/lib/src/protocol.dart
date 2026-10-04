/// Dasturlararo standart buyruq va natija protokoli (RPC & Schema)
typedef ToolHandler = Future<ToolResult> Function(Map<String, dynamic> params);

class ParamDef {
  const ParamDef({
    required this.type,
    required this.description,
    this.required = true,
    this.defaultValue,
  });

  final String type; // string, number, boolean, array, object
  final String description;
  final bool required;
  final Object? defaultValue;

  Map<String, dynamic> toJson() => {
        'type': type,
        'description': description,
        'required': required,
        if (defaultValue != null) 'default': defaultValue,
      };
}

class ToolDef {
  const ToolDef({
    required this.name,
    required this.description,
    required this.params,
    required this.handler,
  });

  final String name;
  final String description;
  final Map<String, ParamDef> params;
  final ToolHandler handler;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'params': params.map((k, v) => MapEntry(k, v.toJson())),
      };
}

class ToolResult {
  const ToolResult({
    required this.success,
    this.action,
    this.data,
    this.message,
    this.error,
    this.code,
  });

  final bool success;
  final String? action;
  final Object? data;
  final String? message;
  final String? error;
  final String? code;

  factory ToolResult.ok({
    String? action,
    Object? data,
    String? message,
  }) =>
      ToolResult(
        success: true,
        action: action,
        data: data,
        message: message ?? 'Muvaffaqiyatli bajarildi.',
      );

  factory ToolResult.err({
    String? action,
    required String error,
    String? code,
  }) =>
      ToolResult(
        success: false,
        action: action,
        error: error,
        code: code ?? 'EXECUTION_ERROR',
      );

  Map<String, dynamic> toJson() => {
        'success': success,
        if (action != null) 'action': action,
        if (data != null) 'data': data,
        if (message != null) 'message': message,
        if (error != null) 'error': error,
        if (code != null) 'code': code,
      };
}

class AppSchema {
  const AppSchema({
    required this.app,
    required this.version,
    required this.description,
    required this.port,
    required this.tools,
  });

  final String app;
  final String version;
  final String description;
  final int port;
  final List<ToolDef> tools;

  Map<String, dynamic> toJson() => {
        'app': app,
        'version': version,
        'description': description,
        'port': port,
        'tools': tools.map((t) => t.toJson()).toList(),
      };
}
