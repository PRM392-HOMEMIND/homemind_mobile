typedef FamilyRequest = Future<Map<String, Object?>> Function(
  String method,
  String path, {
  Map<String, Object?>? body,
  String? idempotencyKey,
});

abstract interface class FamilySource {
  FamilyGateway? get family;
}

/// Uses the authenticated client and its immutable workspace scope.
class FamilyGateway {
  const FamilyGateway({
    required this.workspaceId,
    required this.userId,
    required this.request,
    required this.refreshContext,
    required this.newKey,
  });
  final String workspaceId, userId;
  final FamilyRequest request;
  final Future<void> Function() refreshContext;
  final String Function() newKey;
  String get root => '/workspaces/$workspaceId';
  Future<Map<String, Object?>> overview() => request('GET', '$root/family');
  Future<Map<String, Object?>> workspaces() => request('GET', '/me/workspaces');
  Future<Map<String, Object?>> invitations({
    bool outgoing = false,
    String? cursor,
  }) {
    final query = Uri(queryParameters: {'limit': '20', if (cursor != null) 'cursor': cursor})
        .query;
    return request(
      'GET',
      '${outgoing ? '$root/invitations' : '/me/workspace-invitations'}?$query',
    );
  }

  Future<Map<String, Object?>> invitation(String id) =>
      request('GET', '/me/workspace-invitations/${Uri.encodeComponent(id)}');
  Future<Map<String, Object?>> validate(String emails) =>
      request('POST', '$root/invitations/validate', body: {'emails': emails});
  Future<Map<String, Object?>> invite(
    String emails,
    String token,
    String key,
  ) => request(
    'POST',
    '$root/invitations/batch',
    body: {'emails': emails, 'validationToken': token},
    idempotencyKey: key,
  );
  Future<void> select(String id) async {
    await request('POST', '/me/workspace-context', body: {'workspaceId': id});
    await refreshContext();
  }

  Future<void> respond(
    String id, {
    required bool accept,
    required String key,
  }) async {
    await request(
      'POST',
      '/me/workspace-invitations/${Uri.encodeComponent(id)}/${accept ? 'accept' : 'decline'}',
      idempotencyKey: key,
    );
    if (accept) await refreshContext();
  }

  Future<void> cancel(String id, String key) async {
    await request(
      'POST',
      '$root/invitations/${Uri.encodeComponent(id)}/cancel',
      idempotencyKey: key,
    );
  }

  Future<void> remove(String id, String key) async {
    await request(
      'DELETE',
      '$root/family/members/${Uri.encodeComponent(id)}',
      idempotencyKey: key,
    );
  }

  Future<void> leave(String key) async {
    await request('POST', '$root/family/leave', idempotencyKey: key);
    await refreshContext();
  }

  Future<void> end(String key) async {
    await request('POST', '$root/family/end', idempotencyKey: key);
    await refreshContext();
  }
}

List<Map<String, Object?>> familyRows(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .toList()
    : const [];
