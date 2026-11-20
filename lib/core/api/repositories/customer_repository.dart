import 'package:dio/dio.dart';
import 'package:thingsboard_democloud_app/core/api/client/tb_api_client.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/core/models/customer_models.dart';
import 'package:thingsboard_democloud_app/core/models/pagination.dart';
import 'package:thingsboard_democloud_app/core/models/tb_failure.dart';

/// Customer listing and detail boundary.
abstract interface class CustomerRepository {
  Future<PageData<TbCustomerInfo>> getCustomers(
    PageQuery query, {
    CancelToken? cancelToken,
  });

  Future<TbCustomerInfo> getCustomerInfo(String customerId);
}

final class RestCustomerRepository implements CustomerRepository {
  RestCustomerRepository({required TbApiClient client}) : _client = client;

  final TbApiClient _client;

  @override
  Future<PageData<TbCustomerInfo>> getCustomers(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final params = <String, dynamic>{
      ...query.toQueryParameters(),
      'includeCustomers': true,
    };

    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/customerInfos/all',
        queryParameters: params,
        cancelToken: cancelToken,
      );
      return PageData<TbCustomerInfo>.fromJson(
        response.data ?? const <String, dynamic>{},
        TbCustomerInfo.fromJson,
      );
    } on TbFailure catch (e) {
      // Only fall back on HTTP 404 (pre-PE hierarchy endpoint); never mask 403.
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/customers',
        queryParameters: query.toQueryParameters(),
        cancelToken: cancelToken,
      );
      return PageData<TbCustomerInfo>.fromJson(
        fallback.data ?? const <String, dynamic>{},
        TbCustomerInfo.fromJson,
      );
    }
  }

  @override
  Future<TbCustomerInfo> getCustomerInfo(String customerId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/customer/info/$customerId',
      );
      return TbCustomerInfo.fromJson(
        response.data ?? const <String, dynamic>{},
      );
    } on TbFailure catch (e) {
      if (e.type != TbFailureType.notFound) rethrow;
      final fallback = await _client.get<Map<String, dynamic>>(
        '/api/customer/$customerId',
      );
      return TbCustomerInfo.fromJson(
        fallback.data ?? const <String, dynamic>{},
      );
    }
  }
}

final class DemoCustomerRepository implements CustomerRepository {
  DemoCustomerRepository(List<MockCustomer> customers)
    : _customers = [
        for (final c in customers)
          TbCustomerInfo(
            id: c.id,
            title: c.title,
            country: c.country,
            state: c.state,
            city: c.city,
            address: c.address,
            address2: c.address2,
            zip: c.zip,
            phone: c.phone,
            email: c.email,
            createdTime: c.createdTime.millisecondsSinceEpoch,
          ),
      ];

  final List<TbCustomerInfo> _customers;

  @override
  Future<PageData<TbCustomerInfo>> getCustomers(
    PageQuery query, {
    CancelToken? cancelToken,
  }) async {
    final search = query.textSearch?.trim().toLowerCase() ?? '';
    final filtered = _customers
        .where(
          (c) =>
              search.isEmpty ||
              c.title.toLowerCase().contains(search) ||
              c.city.toLowerCase().contains(search) ||
              c.country.toLowerCase().contains(search),
        )
        .toList(growable: false);

    final start = query.page * query.pageSize;
    if (start >= filtered.length) {
      return PageData<TbCustomerInfo>(
        data: const [],
        totalPages: (filtered.length / query.pageSize).ceil(),
        totalElements: filtered.length,
        hasNext: false,
      );
    }
    final end = (start + query.pageSize).clamp(0, filtered.length);
    return PageData<TbCustomerInfo>(
      data: filtered.sublist(start, end),
      totalPages: (filtered.length / query.pageSize).ceil(),
      totalElements: filtered.length,
      hasNext: end < filtered.length,
    );
  }

  @override
  Future<TbCustomerInfo> getCustomerInfo(String customerId) async {
    return _customers.firstWhere(
      (c) => c.id == customerId,
      orElse: () => throw const TbFailure(
        type: TbFailureType.notFound,
        message: 'Customer not found',
      ),
    );
  }
}
