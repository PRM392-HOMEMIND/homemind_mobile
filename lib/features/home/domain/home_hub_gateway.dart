typedef HubRequest = Future<Map<String, Object?>> Function(
  String method,
  String path,
);

abstract interface class HomeHubSource {
  HomeHubGateway? get homeHub;
}

class HubTarget {
  const HubTarget(this.type, this.id);
  final String type, id;
  static const types = {
    'feature',
    'plan',
    'inventory',
    'shopping',
    'profile',
    'billing',
    'notification',
    'family',
    'family_invitation',
  };
  factory HubTarget.fromJson(Map value) {
    final type = value['type'], id = value['id'];
    if (type is! String ||
        !types.contains(type) ||
        id is! String ||
        id.length > 160 ||
        id.isEmpty) {
      throw const FormatException('Invalid target');
    }
    return HubTarget(type, id);
  }
}

/// No payment reconciliation and no AI requests are part of this gateway.
class HomeHubGateway {
  const HomeHubGateway({
    required this.request,
    required this.scope,
    required this.workspaceId,
    this.write,
  });
  final HubRequest request;
  final Future<Map<String, Object?>> Function(
    String path,
    Map<String, Object?> body,
  )?
  write;
  Future<Map<String, Object?>> readBatch({String? cutoff}) {
    final send = write;
    if (send == null) throw UnsupportedError('Notification batch unavailable');
    return send('$_root/notifications/read-all', {'cutoff': ?cutoff});
  }

  final String scope, workspaceId;
  String get _root => '/workspaces/$workspaceId';
  Future<Map<String, Object?>> notifications({
    int limit = 5,
    String? cursor,
    bool unread = false,
  }) {
    if (limit < 1 || limit > 50) throw RangeError.range(limit, 1, 50);
    final query = Uri(
      queryParameters: {
        'limit': '$limit',
        'cursor': ?cursor,
        'unread': '$unread',
      },
    ).query;
    return request('GET', '$_root/notifications?$query');
  }

  Future<Map<String, Object?>> notification(String id) =>
      request('GET', '$_root/notifications/${Uri.encodeComponent(id)}');
  Future<Map<String, Object?>> read(String id) =>
      request('PATCH', '$_root/notifications/${Uri.encodeComponent(id)}/read');
  Future<Map<String, Object?>> search(
    String q, {
    String? cursor,
    String filter = 'all',
  }) {
    if (q.runes.length > 120) throw RangeError('Query exceeds 120 characters');
    final query = Uri(
      queryParameters: {
        'q': q,
        'limit': '20',
        'filter': filter,
        'cursor': ?cursor,
      },
    ).query;
    return request('GET', '$_root/search?$query');
  }

  Future<HubTarget> resolve(HubTarget target) async {
    if (target.type == 'family_invitation') {
      await request(
        'GET',
        '/me/workspace-invitations/${Uri.encodeComponent(target.id)}',
      );
      return target;
    }
    if (target.type == 'family') {
      if (target.id != workspaceId) {
        throw StateError('Workspace no longer selected');
      }
      await request('GET', '$_root/family');
      return target;
    }
    final query = Uri(
      queryParameters: {'type': target.type, 'target': target.id},
    ).query;
    return HubTarget.fromJson(
      await request('GET', '$_root/search/resolve?$query'),
    );
  }

  Future<Map<String, Object?>> entity(HubTarget target) {
    if (!{'inventory', 'shopping'}.contains(target.type)) {
      throw ArgumentError('Not an entity');
    }
    final module = target.type == 'inventory' ? 'inventory' : 'shopping-items';
    return request('GET', '$_root/$module/${Uri.encodeComponent(target.id)}');
  }
}
