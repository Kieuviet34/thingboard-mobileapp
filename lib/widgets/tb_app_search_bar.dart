import 'package:flutter/material.dart';

class TbAppSearchBar extends StatefulWidget implements PreferredSizeWidget {
  TbAppSearchBar({
    super.key,
    this.elevation = 8,
    this.shadowColor,
    this.showLoadingIndicator = false,
    this.searchHint,
    this.onSearch,
    this.leading,
  }) : preferredSize = Size.fromHeight(
         kToolbarHeight + (showLoadingIndicator ? 4 : 0),
       );

  final double? elevation;
  final Color? shadowColor;
  final bool showLoadingIndicator;
  final String? searchHint;
  final void Function(String searchText)? onSearch;
  final Widget? leading;

  @override
  final Size preferredSize;

  @override
  State<StatefulWidget> createState() => _TbAppSearchBarState();
}

class _TbAppSearchBarState extends State<TbAppSearchBar> {
  final TextEditingController _filter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filter.addListener(() {
      widget.onSearch?.call(_filter.text);
    });
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          centerTitle: true,
          elevation: widget.elevation ?? 8,
          shadowColor:
              widget.shadowColor ?? const Color(0xFFFFFFFF).withAlpha(150),
          title: TextField(
            controller: _filter,
            autofocus: true,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintStyle: TextStyle(
                color: const Color(0xFF282828).withAlpha((255 * 0.38).ceil()),
              ),
              contentPadding: const EdgeInsets.only(
                left: 15,
                bottom: 11,
                top: 15,
                right: 15,
              ),
              hintText: widget.searchHint ?? 'Search',
            ),
          ),
          leading: widget.leading,
          actions: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _filter,
              builder: (context, value, child) {
                if (_filter.text.isNotEmpty) {
                  return IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _filter.text = '';
                    },
                  );
                } else {
                  return const SizedBox.shrink();
                }
              },
            ),
          ],
        ),
        if (widget.showLoadingIndicator) const LinearProgressIndicator(),
      ],
    );
  }
}
