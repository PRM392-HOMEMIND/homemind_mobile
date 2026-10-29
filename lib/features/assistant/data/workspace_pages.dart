import '../domain/assistant_models.dart';

typedef WorkspacePageRequest = Future<Map<String, Object?>> Function(
  String method,
  String path,
);

abstract interface class WorkspacePagesSource {
  WorkspacePages? get workspacePages;
}

class WorkspacePages {
  const WorkspacePages({required this.workspaceId, required this.request});
  final String workspaceId;
  final WorkspacePageRequest request;
  Future<
    ({
      List<ShoppingItem> items,
      List<Map<String, Object?>> suggestions,
      int total,
      String? nextCursor,
    })
  >
  shopping({required String status, String q = '', String? cursor}) async {
    final query = Uri(
      queryParameters: {
        'status': status,
        'q': q,
        'limit': '30',
        'includeSuggestions': '${status == 'needed'}',
        'cursor': ?cursor,
      },
    ).query;
    final data = await request(
      'GET',
      '/workspaces/$workspaceId/shopping-items?$query',
    );
    return (
      items: [
        for (final row in data['items'] as List)
          ShoppingItem.fromJson(Map<String, Object?>.from(row as Map)),
      ],
      suggestions: [
        for (final row in (data['suggestions'] as List? ?? []))
          Map<String, Object?>.from(row as Map),
      ],
      total: (data['total'] as num).toInt(),
      nextCursor: data['hasMore'] == true
          ? data['nextCursor'] as String?
          : null,
    );
  }

  Future<SpendingSummary> spending({
    required String month,
    required String scope,
    String? cursor,
  }) async {
    final query = Uri(
      queryParameters: {
        'month': month,
        'scope': scope,
        'limit': '20',
        'cursor': ?cursor,
      },
    ).query;
    return SpendingSummary.fromJson(
      await request('GET', '/workspaces/$workspaceId/spending?$query'),
    );
  }
}
