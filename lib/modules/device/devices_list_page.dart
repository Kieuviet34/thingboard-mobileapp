import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:thingsboard_democloud_app/constants/assets_path.dart';
import 'package:thingsboard_democloud_app/core/mock/mock_data.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_bar.dart';
import 'package:thingsboard_democloud_app/widgets/tb_app_search_bar.dart';

class DevicesListPage extends ConsumerStatefulWidget {
  const DevicesListPage({
    super.key,
    this.deviceType,
    this.active,
    this.searchMode = false,
  });

  final String? deviceType;
  final bool? active;
  final bool searchMode;

  @override
  ConsumerState<DevicesListPage> createState() => _DevicesListPageState();
}

class _DevicesListPageState extends ConsumerState<DevicesListPage> {
  String _searchText = '';
  static final _dateFormat = DateFormat('yyyy-MM-dd');

  @override
  Widget build(BuildContext context) {
    final allDevices = ref.watch(devicesProvider);
    final filtered =
        allDevices.where((d) {
          if (widget.deviceType != null && d.type != widget.deviceType) {
            return false;
          }
          if (widget.active != null && d.active != widget.active) {
            return false;
          }
          if (_searchText.isNotEmpty) {
            final q = _searchText.toLowerCase();
            return d.name.toLowerCase().contains(q) ||
                d.label.toLowerCase().contains(q) ||
                d.type.toLowerCase().contains(q);
          }
          return true;
        }).toList();

    PreferredSizeWidget appBar;
    if (widget.searchMode) {
      appBar = TbAppSearchBar(
        searchHint: 'Search devices',
        onSearch: (text) => setState(() => _searchText = text),
      );
    } else {
      final String titleText = widget.deviceType ?? 'All devices';
      String? subTitleText;
      if (widget.active != null) {
        subTitleText = widget.active! ? 'Active' : 'Inactive';
      }
      final title = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            titleText,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: subTitleText != null ? 16 : 20,
              height: subTitleText != null ? 20 / 16 : 24 / 20,
            ),
          ),
          if (subTitleText != null)
            Text(
              subTitleText,
              style: TextStyle(
                color: Colors.black.withAlpha((0.38 * 255).ceil()),
                fontSize: 12,
                fontWeight: FontWeight.normal,
                height: 16 / 12,
              ),
            ),
        ],
      );

      appBar = TbAppBar(
        title: title,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              final params = <String>['search=true'];
              if (widget.deviceType != null) {
                params.add(
                  'deviceType=${Uri.encodeComponent(widget.deviceType!)}',
                );
              }
              if (widget.active != null) {
                params.add('active=${widget.active}');
              }
              context.push('/devices/deviceList?${params.join('&')}');
            },
          ),
        ],
      );
    }

    return Scaffold(
      appBar: appBar,
      body:
          filtered.isEmpty
              ? const Center(child: Text('No devices found'))
              : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: filtered.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final device = filtered[index];
                  return Card(
                    margin: EdgeInsets.zero,
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: InkWell(
                      onTap:
                          () => context.push(
                            '/devices/deviceDetails/${device.id}',
                          ),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Container(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 4,
                                decoration: BoxDecoration(
                                  color:
                                      device.active
                                          ? const Color(0xFF008A00)
                                          : const Color(0xFFAFAFAF),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(4),
                                    bottomLeft: Radius.circular(4),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            child: Row(
                              children: [
                                if (widget.deviceType == null) ...[
                                  SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: SvgPicture.asset(
                                      ThingsboardImage.deviceProfilePlaceholder,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                ],
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              device.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF282828),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                height: 20 / 14,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            _dateFormat.format(
                                              device.createdTime,
                                            ),
                                            style: const TextStyle(
                                              color: Color(0xFFAFAFAF),
                                              fontSize: 12,
                                              height: 16 / 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (device.label.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            device.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: Color(0xFFAFAFAF),
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic,
                                              height: 16 / 12,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            device.type,
                                            style: const TextStyle(
                                              color: Color(0xFFAFAFAF),
                                              fontSize: 12,
                                              height: 16 / 12,
                                            ),
                                          ),
                                          Text(
                                            device.active
                                                ? 'Active'
                                                : 'Inactive',
                                            style: TextStyle(
                                              color:
                                                  device.active
                                                      ? const Color(0xFF008A00)
                                                      : const Color(0xFFAFAFAF),
                                              fontSize: 12,
                                              height: 16 / 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Icon(
                                  Icons.chevron_right,
                                  color: Color(0xFFACACAC),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
    );
  }
}
