// Small helpers shared by the entities' toJson/fromJson.

typedef Json = Map<String, dynamic>;

DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
String? iso(DateTime? d) => d?.toIso8601String();
List<String> strs(Object? v) => [for (final x in (v as List? ?? const [])) x as String];
List<T> objs<T>(Object? v, T Function(Json) f) => [for (final x in (v as List? ?? const [])) f(x as Json)];
int asInt(Object? v, [int d = 0]) => v == null ? d : (v as num).toInt();
double asDouble(Object? v, [double d = 0]) => v == null ? d : (v as num).toDouble();
