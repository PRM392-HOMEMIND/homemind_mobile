enum VoiceIntent {
  inventoryAdd('inventory.add'),
  inventoryReceive('inventory.receive'),
  inventoryConsume('inventory.consume'),
  inventoryAdjustQuantity('inventory.adjust_quantity'),
  inventoryMarkOut('inventory.mark_out'),
  inventoryUpdateExpiry('inventory.update_expiry'),
  inventoryUpdateProduct('inventory.update_product'),
  inventoryDelete('inventory.delete'),
  inventorySearch('inventory.search'),
  inventoryGetQuantity('inventory.get_quantity'),
  inventoryExpiring('inventory.expiring'),
  inventoryExpired('inventory.expired'),
  inventoryByCategory('inventory.by_category'),
  inventorySummary('inventory.summary'),
  inventoryPriceLookup('inventory.price_lookup'),
  shoppingAdd('shopping.add'),
  shoppingRemove('shopping.remove'),
  shoppingList('shopping.list'),
  shoppingMarkBought('shopping.mark_bought'),
  shoppingClearCompleted('shopping.clear_completed'),
  navigationGoHome('navigation.go_home'),
  navigationOpenInventory('navigation.open_inventory'),
  navigationOpenShopping('navigation.open_shopping'),
  navigationOpenNotifications('navigation.open_notifications'),
  navigationGoBack('navigation.go_back'),
  uiFilter('ui.filter'),
  uiSort('ui.sort'),
  uiClearFilter('ui.clear_filter'),
  conversationConfirm('conversation.confirm'),
  conversationReject('conversation.reject'),
  conversationRetry('conversation.retry'),
  conversationEditField('conversation.edit_field'),
  conversationSelectOption('conversation.select_option'),
  conversationAnswerSlot('conversation.answer_slot'),
  conversationHelp('conversation.help'),
  reportSummary('report.summary'),
  unknown('unknown');

  const VoiceIntent(this.wireValue);
  final String wireValue;

  static VoiceIntent parse(Object? value) {
    for (final intent in values) {
      if (intent.wireValue == value) return intent;
    }
    throw VoiceCommandFormatException(
      'Intent không nằm trong allowlist: $value',
    );
  }
}

enum OperationType {
  read,
  write,
  navigation,
  conversation;

  static OperationType parse(Object? value) => switch (value) {
    'read' => read,
    'write' => write,
    'navigation' => navigation,
    'conversation' => conversation,
    _ => throw VoiceCommandFormatException('operationType không hợp lệ.'),
  };
}

enum RiskLevel {
  low,
  medium,
  high,
  critical;

  static RiskLevel parse(Object? value) => switch (value) {
    'low' => low,
    'medium' => medium,
    'high' => high,
    'critical' => critical,
    _ => throw VoiceCommandFormatException('riskLevel không hợp lệ.'),
  };
}

enum ConversationState {
  idle('idle'),
  awaitingConfirmation('awaiting_confirmation'),
  awaitingClarification('awaiting_clarification'),
  awaitingSelection('awaiting_selection'),
  answering('answering'),
  cancelled('cancelled');

  const ConversationState(this.wireValue);
  final String wireValue;

  static ConversationState parse(Object? value) => values.firstWhere(
    (state) => state.wireValue == value,
    orElse: () =>
        throw VoiceCommandFormatException('Conversation state không hợp lệ.'),
  );
}

class VoiceCommandFormatException implements Exception {
  const VoiceCommandFormatException(this.message);
  final String message;

  @override
  String toString() => 'VoiceCommandFormatException: $message';
}

class VoiceAction {
  const VoiceAction({
    required this.actionType,
    required this.targetId,
    required this.entities,
    required this.confidence,
    required this.warnings,
  });

  final VoiceIntent actionType;
  final String? targetId;
  final Map<String, Object?> entities;
  final Map<String, double> confidence;
  final List<String> warnings;

  factory VoiceAction.fromJson(Map<String, Object?> json) {
    return VoiceAction(
      actionType: VoiceIntent.parse(json['actionType']),
      targetId: _text(json['targetId']),
      entities: _objectMap(json['entities']),
      confidence: _numberMap(json['confidence']),
      warnings: _strings(json['warnings']),
    );
  }
}

class VoiceQuery {
  const VoiceQuery({
    required this.resource,
    required this.filters,
    required this.sort,
  });

  final String resource;
  final Map<String, Object?> filters;
  final String? sort;

  factory VoiceQuery.fromJson(Map<String, Object?> json) {
    final resource = _text(json['resource']);
    if (resource == null) {
      throw const VoiceCommandFormatException('Query thiếu resource.');
    }
    return VoiceQuery(
      resource: resource,
      filters: _objectMap(json['filters']),
      sort: _text(json['sort']),
    );
  }
}

class VoiceConversation {
  const VoiceConversation({required this.state, required this.expectedIntents});

  final ConversationState state;
  final List<VoiceIntent> expectedIntents;

  factory VoiceConversation.fromJson(Map<String, Object?> json) {
    return VoiceConversation(
      state: ConversationState.parse(json['state']),
      expectedIntents: _list(json['expectedIntents'])
          .map(VoiceIntent.parse)
          .toList(growable: false),
    );
  }
}

class VoiceCommand {
  const VoiceCommand({
    required this.schemaVersion,
    required this.commandId,
    required this.intent,
    required this.operationType,
    required this.riskLevel,
    required this.rawTranscript,
    required this.correctedTranscript,
    required this.assistantReply,
    required this.actions,
    required this.query,
    required this.missingSlots,
    required this.clarification,
    required this.requiresConfirmation,
    required this.suggestedUiTarget,
    required this.conversation,
    this.processingTimeMs = 0,
  });

  final String schemaVersion;
  final String commandId;
  final VoiceIntent intent;
  final OperationType operationType;
  final RiskLevel riskLevel;
  final String rawTranscript;
  final String correctedTranscript;
  final String assistantReply;
  final List<VoiceAction> actions;
  final VoiceQuery? query;
  final List<String> missingSlots;
  final String? clarification;
  final bool requiresConfirmation;
  final String? suggestedUiTarget;
  final VoiceConversation conversation;
  final int processingTimeMs;

  bool get needsClarification =>
      missingSlots.isNotEmpty || clarification != null;

  factory VoiceCommand.fromJson(
    Map<String, Object?> json, {
    required String rawTranscript,
    int processingTimeMs = 0,
  }) {
    if (json['schemaVersion'] != '2.0') {
      throw const VoiceCommandFormatException(
        'Phiên bản command schema không được hỗ trợ.',
      );
    }
    final commandId = _text(json['commandId']);
    if (commandId == null) {
      throw const VoiceCommandFormatException('Command thiếu commandId.');
    }
    final intent = VoiceIntent.parse(json['intent']);
    final operationType = OperationType.parse(json['operationType']);
    final riskLevel = RiskLevel.parse(json['riskLevel']);
    final requiresConfirmation = json['requiresConfirmation'] == true;

    if (operationType == OperationType.write &&
        !requiresConfirmation &&
        _strings(json['missingSlots']).isEmpty) {
      throw const VoiceCommandFormatException(
        'Write command bắt buộc phải xác nhận.',
      );
    }
    if ((riskLevel == RiskLevel.high || riskLevel == RiskLevel.critical) &&
        !requiresConfirmation) {
      throw const VoiceCommandFormatException(
        'High-risk command bắt buộc phải xác nhận.',
      );
    }

    final actions = _list(json['actions'])
        .map((value) {
          if (value is! Map) {
            throw const VoiceCommandFormatException('Action không hợp lệ.');
          }
          return VoiceAction.fromJson(_map(value));
        })
        .toList(growable: false);

    final rawQuery = json['query'];
    final query = rawQuery is Map ? VoiceQuery.fromJson(_map(rawQuery)) : null;
    final rawConversation = json['conversation'];
    if (rawConversation is! Map) {
      throw const VoiceCommandFormatException('Thiếu conversation context.');
    }

    return VoiceCommand(
      schemaVersion: '2.0',
      commandId: commandId,
      intent: intent,
      operationType: operationType,
      riskLevel: riskLevel,
      rawTranscript: rawTranscript.trim(),
      correctedTranscript:
          _text(json['correctedTranscript']) ?? rawTranscript.trim(),
      assistantReply:
          _text(json['assistantReply']) ??
          'Mình chưa tạo được phản hồi phù hợp.',
      actions: actions,
      query: query,
      missingSlots: _strings(json['missingSlots']),
      clarification: _text(json['clarification']),
      requiresConfirmation: requiresConfirmation,
      suggestedUiTarget: _text(json['suggestedUiTarget']),
      conversation: VoiceConversation.fromJson(_map(rawConversation)),
      processingTimeMs: processingTimeMs,
    );
  }
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value.trim();
}

List<Object?> _list(Object? value) => value is List ? value : const [];

List<String> _strings(Object? value) =>
    _list(value)
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);

Map<String, Object?> _map(Map value) =>
    value.map((key, value) => MapEntry(key.toString(), value));

Map<String, Object?> _objectMap(Object? value) =>
    value is Map ? _map(value) : const {};

Map<String, double> _numberMap(Object? value) {
  if (value is! Map) return const {};
  return value.map((key, value) {
    final score = value is num
        ? value.toDouble().clamp(0.0, 1.0).toDouble()
        : 0.0;
    return MapEntry(key.toString(), score);
  });
}
