import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Sort direction for ThingsBoard paginated queries.
enum SortOrder {
  asc('ASC'),
  desc('DESC');

  const SortOrder(this.wireValue);

  /// Wire string sent in `sortOrder` query/body fields.
  final String wireValue;
}

/// Standard pagination and search parameters for ThingsBoard REST endpoints.
@immutable
class PageQuery {
  const PageQuery({
    this.page = 0,
    this.pageSize = 20,
    this.textSearch,
    this.sortProperty = 'createdTime',
    this.sortOrder = SortOrder.desc,
  });

  final int page;
  final int pageSize;
  final String? textSearch;
  final String sortProperty;
  final SortOrder sortOrder;

  Map<String, dynamic> toQueryParameters() {
    return <String, dynamic>{
      'page': page,
      'pageSize': pageSize,
      if (textSearch != null && textSearch!.trim().isNotEmpty)
        'textSearch': textSearch!.trim(),
      'sortProperty': sortProperty,
      'sortOrder': sortOrder.wireValue,
    };
  }

  PageQuery copyWith({
    int? page,
    int? pageSize,
    String? textSearch,
    bool clearTextSearch = false,
    String? sortProperty,
    SortOrder? sortOrder,
  }) {
    return PageQuery(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      textSearch: clearTextSearch ? null : (textSearch ?? this.textSearch),
      sortProperty: sortProperty ?? this.sortProperty,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageQuery &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          pageSize == other.pageSize &&
          textSearch == other.textSearch &&
          sortProperty == other.sortProperty &&
          sortOrder == other.sortOrder;

  @override
  int get hashCode =>
      Object.hash(page, pageSize, textSearch, sortProperty, sortOrder);
}

/// Paginated response envelope returned by ThingsBoard list and query APIs.
@immutable
class PageData<T> {
  const PageData({
    required this.data,
    required this.totalPages,
    required this.totalElements,
    required this.hasNext,
  });

  factory PageData.empty() => PageData<T>(
    data: const [],
    totalPages: 0,
    totalElements: 0,
    hasNext: false,
  );

  factory PageData.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic> itemJson) itemFromJson,
  ) {
    final rawList = json['data'] as List<dynamic>? ?? const [];
    return PageData<T>(
      data: rawList
          .whereType<Map<String, dynamic>>()
          .map(itemFromJson)
          .toList(growable: false),
      totalPages: (json['totalPages'] as num?)?.toInt() ?? 0,
      totalElements: (json['totalElements'] as num?)?.toInt() ?? 0,
      hasNext: json['hasNext'] as bool? ?? false,
    );
  }

  final List<T> data;
  final int totalPages;
  final int totalElements;
  final bool hasNext;
}

/// Controller state for paginated infinite-scroll lists.
@immutable
class PagedListState<T> {
  const PagedListState({
    this.items = const [],
    this.page = 0,
    this.hasNext = false,
    this.totalElements = 0,
    this.isLoadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;
  final int page;
  final bool hasNext;
  final int totalElements;
  final bool isLoadingMore;
  final TbFailure? loadMoreError;

  PagedListState<T> copyWith({
    List<T>? items,
    int? page,
    bool? hasNext,
    int? totalElements,
    bool? isLoadingMore,
    TbFailure? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return PagedListState<T>(
      items: items ?? this.items,
      page: page ?? this.page,
      hasNext: hasNext ?? this.hasNext,
      totalElements: totalElements ?? this.totalElements,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}
